// Strava helpers shared by the hooks in ../strava.pb.js. See docs/adr/0012-strava-integration-hooks.md.
// Hook handlers run in isolated scopes, so they load this file with require() inside the handler.

const SPORTS = {
  Run: "run", VirtualRun: "run", TrailRun: "trail_run", Walk: "walk", Hike: "hike",
  Ride: "ride", VirtualRide: "ride", EBikeRide: "ride", GravelRide: "ride", MountainBikeRide: "ride", EMountainBikeRide: "ride",
  Swim: "swim", WeightTraining: "strength", Workout: "strength", Crossfit: "strength",
}

function config() {
  return {
    scope: "activity:read_all",
    clientId: $os.getenv("STRAVA_CLIENT_ID"),
    clientSecret: $os.getenv("STRAVA_CLIENT_SECRET"),
    verifyToken: $os.getenv("STRAVA_VERIFY_TOKEN"),
    subscriptionId: $os.getenv("STRAVA_SUBSCRIPTION_ID"),
    publicUrl: ($os.getenv("ATLAS_PUBLIC_URL") || "").replace(/\/+$/, ""),
    base: ($os.getenv("STRAVA_BASE") || "https://www.strava.com").replace(/\/+$/, ""),
  }
}

function requireConfigured() {
  const c = config()
  if (!c.clientId || !c.clientSecret) {
    throw new ApiError(503, "Strava is not configured on this server.", {})
  }
  return c
}

const toDate = (epochSeconds) => new Date(epochSeconds * 1000).toISOString().replace("T", " ")
const form = (obj) => Object.keys(obj).map((k) => encodeURIComponent(k) + "=" + encodeURIComponent(obj[k])).join("&")

function send(method, url, opts) {
  opts = opts || {}
  const headers = {}
  if (opts.token) headers["Authorization"] = "Bearer " + opts.token
  if (opts.form) headers["Content-Type"] = "application/x-www-form-urlencoded"
  return $http.send({ url: url, method: method, headers: headers, body: opts.form ? form(opts.form) : undefined, timeout: 20 })
}

function exchangeCode(code) {
  const c = requireConfigured()
  const res = send("POST", c.base + "/oauth/token", {
    form: { client_id: c.clientId, client_secret: c.clientSecret, code: code, grant_type: "authorization_code" },
  })
  if (res.statusCode !== 200) throw new BadRequestError("Strava refused the authorization code.")
  return res.json
}

// Returns a valid access token for the connection, refreshing it when it is about to expire.
function accessToken(conn) {
  const expires = new Date(conn.getString("expires_at").replace(" ", "T")).getTime()
  if (expires - Date.now() > 120 * 1000) return conn.getString("access_token")
  const c = requireConfigured()
  const res = send("POST", c.base + "/oauth/token", {
    form: { client_id: c.clientId, client_secret: c.clientSecret, grant_type: "refresh_token", refresh_token: conn.getString("refresh_token") },
  })
  if (res.statusCode !== 200) throw new Error("Strava token refresh failed: " + res.statusCode)
  conn.set("access_token", res.json.access_token)
  conn.set("refresh_token", res.json.refresh_token)
  conn.set("expires_at", toDate(res.json.expires_at))
  $app.save(conn)
  return res.json.access_token
}

function apiGet(conn, path) {
  const res = send("GET", config().base + "/api/v3" + path, { token: accessToken(conn) })
  if (res.statusCode === 404) return null
  if (res.statusCode !== 200) throw new Error("Strava API " + path + " answered " + res.statusCode)
  return res.json
}

function mapLaps(laps) {
  if (!laps || !laps.length) return null
  return laps.map((l) => ({
    index: l.lap_index, name: l.name, distance_m: l.distance, moving_time_s: l.moving_time, elapsed_time_s: l.elapsed_time,
    elevation_gain_m: l.total_elevation_gain, avg_hr: l.average_heartrate ? Math.round(l.average_heartrate) : null,
    max_hr: l.max_heartrate ? Math.round(l.max_heartrate) : null,
  }))
}

// Creates or updates the activity row for a Strava activity summary (and laps, when known).
function upsertActivity(userId, s, laps) {
  const externalId = String(s.id)
  let record
  try {
    record = $app.findFirstRecordByFilter("activities", "owner = {:o} && source = 'strava' && external_id = {:e}", { o: userId, e: externalId })
  } catch (_) {
    record = new Record($app.findCollectionByNameOrId("activities"))
    record.set("owner", userId)
    record.set("source", "strava")
    record.set("external_id", externalId)
  }
  record.set("deleted", false)
  record.set("started_at", String(s.start_date).replace("T", " "))
  record.set("sport", SPORTS[s.sport_type || s.type] || "other")
  record.set("name", s.name || "")
  record.set("distance_m", s.distance || 0)
  record.set("moving_time_s", Math.round(s.moving_time || 0))
  record.set("elapsed_time_s", Math.round(s.elapsed_time || 0))
  record.set("elevation_gain_m", s.total_elevation_gain || 0)
  record.set("avg_hr", s.average_heartrate ? Math.round(s.average_heartrate) : 0)
  record.set("max_hr", s.max_heartrate ? Math.round(s.max_heartrate) : 0)
  if (laps !== undefined) record.set("laps", mapLaps(laps))
  $app.save(record)
  return record
}

// Strava data must go when the athlete leaves or Strava asks. Rows stay as empty tombstones so that
// syncing clients see the deletion, and the matches that point at them are removed.
function scrub(record) {
  record.set("deleted", true)
  record.set("external_id", "")
  record.set("name", "")
  record.set("started_at", "1970-01-01 00:00:00.000Z")
  for (const f of ["distance_m", "moving_time_s", "elapsed_time_s", "elevation_gain_m", "avg_hr", "max_hr"]) record.set(f, 0)
  record.set("laps", null)
  $app.save(record)
  const matches = $app.findRecordsByFilter("matches", "activity = {:a} && deleted = false", "", 0, 0, { a: record.id })
  for (const m of matches) {
    m.set("deleted", true)
    $app.save(m)
  }
}

function scrubAll(userId) {
  const rows = $app.findRecordsByFilter("activities", "owner = {:o} && source = 'strava' && deleted = false", "", 0, 0, { o: userId })
  for (const r of rows) scrub(r)
  return rows.length
}

// Imports summaries of the last `days` days (no laps, to stay within Strava's rate limits).
function backfill(conn, days) {
  const after = Math.floor(Date.now() / 1000) - days * 86400
  let imported = 0
  for (let page = 1; page <= 3; page++) {
    const items = apiGet(conn, "/athlete/activities?after=" + after + "&per_page=100&page=" + page) || []
    for (const s of items) {
      upsertActivity(conn.getString("user"), s)
      imported++
    }
    if (items.length < 100) break
  }
  return imported
}

function importOne(conn, activityId) {
  const s = apiGet(conn, "/activities/" + activityId)
  if (!s) return null
  const laps = apiGet(conn, "/activities/" + activityId + "/laps") || []
  return upsertActivity(conn.getString("user"), s, laps)
}

function removeConnection(conn) {
  const userId = conn.getString("user")
  $app.delete(conn)
  return scrubAll(userId)
}

function findConnection(userId) {
  try {
    return $app.findFirstRecordByFilter("strava_connections", "user = {:u}", { u: userId })
  } catch (_) {
    return null
  }
}

function findConnectionByAthlete(athleteId) {
  try {
    return $app.findFirstRecordByFilter("strava_connections", "strava_athlete_id = {:a}", { a: athleteId })
  } catch (_) {
    return null
  }
}

module.exports = {
  config, requireConfigured, send, exchangeCode, accessToken, apiGet, upsertActivity, scrub, scrubAll,
  backfill, importOne, removeConnection, findConnection, findConnectionByAthlete, toDate,
}
