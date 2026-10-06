// Strava: OAuth connection, activity import and webhook. See docs/adr/0012-strava-integration-hooks.md.
// Configuration comes from the environment: STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, STRAVA_VERIFY_TOKEN,
// ATLAS_PUBLIC_URL, optionally STRAVA_SUBSCRIPTION_ID and STRAVA_BASE (for tests).

// Note: handlers run in isolated scopes, so shared values live in lib/strava.js.

// 1. The signed-in user asks where to send the browser to connect Strava.
routerAdd("GET", "/api/atlas/strava/connect", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const c = strava.requireConfigured()
  const state = $security.createJWT({ uid: e.auth.id, purpose: "strava-connect" }, c.clientSecret, 600)
  const redirectUri = (c.publicUrl || "http://" + e.request.host) + "/api/atlas/strava/callback"
  const url = c.base + "/oauth/authorize?client_id=" + encodeURIComponent(c.clientId) +
    "&redirect_uri=" + encodeURIComponent(redirectUri) + "&response_type=code&approval_prompt=auto" +
    "&scope=" + encodeURIComponent(c.scope) + "&state=" + encodeURIComponent(state)
  return e.json(200, { url: url })
}, $apis.requireAuth("users"))

// 2. Strava sends the browser back here. The signed state says which user started the flow.
routerAdd("GET", "/api/atlas/strava/callback", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const c = strava.requireConfigured()
  const q = e.request.url.query()
  const home = c.publicUrl || ""
  if (q.get("error")) return e.redirect(302, home + "/?strava=denied")
  let claims
  try {
    claims = $security.parseJWT(q.get("state") || "", c.clientSecret)
  } catch (_) {
    throw new BadRequestError("The Strava connection request expired. Start again.")
  }
  if (claims.purpose !== "strava-connect") throw new BadRequestError("Invalid state.")
  if (String(q.get("scope") || "").indexOf("activity:read") === -1) return e.redirect(302, home + "/?strava=scope")

  const token = strava.exchangeCode(q.get("code") || "")
  const athleteId = token.athlete.id
  const taken = strava.findConnectionByAthlete(athleteId)
  if (taken && taken.getString("user") !== claims.uid) return e.redirect(302, home + "/?strava=taken")

  const conn = strava.findConnection(claims.uid) || new Record($app.findCollectionByNameOrId("strava_connections"))
  conn.set("user", claims.uid)
  conn.set("strava_athlete_id", athleteId)
  conn.set("access_token", token.access_token)
  conn.set("refresh_token", token.refresh_token)
  conn.set("expires_at", strava.toDate(token.expires_at))
  conn.set("scope", q.get("scope"))
  $app.save(conn)
  try {
    strava.backfill(conn, 30)
  } catch (err) {
    $app.logger().error("strava backfill failed", "error", String(err))
  }
  return e.redirect(302, home + "/?strava=connected")
})

// 3. Re-import the last 30 days on request.
routerAdd("POST", "/api/atlas/strava/sync", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const conn = strava.findConnection(e.auth.id)
  if (!conn) throw new NotFoundError("Strava is not connected.")
  return e.json(200, { imported: strava.backfill(conn, 30) })
}, $apis.requireAuth("users"))

// 4. Disconnect: tell Strava, forget the tokens and remove the athlete's Strava data.
routerAdd("DELETE", "/api/atlas/strava/connection", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const conn = strava.findConnection(e.auth.id)
  if (!conn) throw new NotFoundError("Strava is not connected.")
  try {
    strava.send("POST", strava.config().base + "/oauth/deauthorize", { token: strava.accessToken(conn) })
  } catch (err) {
    $app.logger().warn("strava deauthorize failed", "error", String(err))
  }
  return e.json(200, { removed: strava.removeConnection(conn) })
}, $apis.requireAuth("users"))

// 5. Webhook validation, called by Strava when the subscription is created.
routerAdd("GET", "/api/atlas/strava/webhook", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const q = e.request.url.query()
  const expected = strava.config().verifyToken
  if (!expected || q.get("hub.mode") !== "subscribe" || q.get("hub.verify_token") !== expected) {
    throw new ForbiddenError("Invalid verify token.")
  }
  return e.json(200, { "hub.challenge": q.get("hub.challenge") })
})

// 6. Webhook events. Always answer 200 quickly: Strava retries otherwise. Event content is never trusted;
// data is fetched from Strava with the athlete's own token.
routerAdd("POST", "/api/atlas/strava/webhook", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const ev = e.requestInfo().body || {}
  const sub = strava.config().subscriptionId
  if (sub && String(ev.subscription_id) !== sub) return e.json(200, { ignored: true })
  try {
    const conn = strava.findConnectionByAthlete(ev.owner_id)
    if (!conn) return e.json(200, { ignored: true })
    if (ev.object_type === "athlete") {
      if (ev.updates && String(ev.updates.authorized) === "false") strava.removeConnection(conn)
    } else if (ev.object_type === "activity") {
      if (ev.aspect_type === "delete") {
        const rows = $app.findRecordsByFilter("activities", "owner = {:o} && source = 'strava' && external_id = {:e}", "", 1, 0,
          { o: conn.getString("user"), e: String(ev.object_id) })
        for (const r of rows) strava.scrub(r)
      } else {
        strava.importOne(conn, ev.object_id)
      }
    }
  } catch (err) {
    $app.logger().error("strava webhook failed", "error", String(err), "event", JSON.stringify(ev))
  }
  return e.json(200, {})
})

// 7. One-time setup by the owner: create the push subscription at Strava.
routerAdd("POST", "/api/atlas/strava/subscribe", (e) => {
  const strava = require(`${__hooks}/lib/strava.js`)
  const c = strava.requireConfigured()
  if (!c.verifyToken || !c.publicUrl) throw new BadRequestError("STRAVA_VERIFY_TOKEN and ATLAS_PUBLIC_URL are required.")
  const res = strava.send("POST", c.base + "/api/v3/push_subscriptions", {
    form: { client_id: c.clientId, client_secret: c.clientSecret, callback_url: c.publicUrl + "/api/atlas/strava/webhook", verify_token: c.verifyToken },
  })
  return e.json(res.statusCode === 200 || res.statusCode === 201 ? 200 : 502, res.json || {})
}, $apis.requireSuperuserAuth())
