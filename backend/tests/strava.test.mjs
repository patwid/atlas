// Strava hooks against a fake Strava. See docs/adr/0012-strava-integration-hooks.md.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"
import { startFakeStrava } from "./fake_strava.mjs"

let h, strava
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
before(async () => {
  strava = await startFakeStrava({ webhookUrl: true })
  h = await startPocketBase({
    STRAVA_CLIENT_ID: "client-1", STRAVA_CLIENT_SECRET: "secret-1", STRAVA_VERIFY_TOKEN: "verify-1",
    STRAVA_SUBSCRIPTION_ID: "777", STRAVA_BASE: strava.base,
  })
})
after(() => { h?.stop(); strava?.stop() })
const test = (name, fn) => nodeTest(name, async () => {
  await h.world()
  strava.state.calls.length = 0
  strava.state.activities.clear()
  strava.state.laps.clear()
  strava.state.athleteId = 1000 + h.run
  strava.state.rejectCode = false
  strava.state.expiresIn = undefined
  await fn()
})

const get = (path, who, opts = {}) => h.api("GET", path, { token: who && h.as(who), ...opts })
const stateFor = async (who) => new URL((await get("atlas/strava/connect", who)).body.url).searchParams.get("state")
const callback = (state, extra = "") => get(`atlas/strava/callback?code=good-code&scope=read,activity:read_all&state=${encodeURIComponent(state)}${extra}`, null)
const connect = async (who) => {
  const r = await callback(await stateFor(who))
  assert.equal(r.status, 302, JSON.stringify(r.body))
  return r
}
const webhook = (event) => h.api("POST", "atlas/strava/webhook", { body: { subscription_id: 777, ...event } })
const activitiesOf = async (who, filter = "") => (await h.list(who, "activities", `source = "strava"${filter}`)).body.items
const connections = async () => (await h.api("GET", "collections/strava_connections/records?perPage=200", { token: h.admin })).body.items

test("connect: returns a Strava authorize URL with the client id, scope and a signed state", async () => {
  const r = await get("atlas/strava/connect", "alice")
  assert.equal(r.status, 200)
  const u = new URL(r.body.url)
  assert.equal(u.origin, strava.base)
  assert.equal(u.pathname, "/oauth/authorize")
  assert.equal(u.searchParams.get("client_id"), "client-1")
  assert.equal(u.searchParams.get("scope"), "activity:read_all")
  assert.match(u.searchParams.get("redirect_uri"), /\/api\/atlas\/strava\/callback$/)
  assert.equal((await get("atlas/strava/connect", null)).status, 401)
})

test("callback: stores the connection, imports the last 30 days and redirects", async () => {
  strava.state.activities.set(1, strava.activity(1))
  strava.state.activities.set(2, strava.activity(2, { sport_type: "TrailRun", name: "Hills" }))
  const r = await connect("alice")
  assert.match(r.headers.get("location"), /\/settings\?strava=connected$/)
  const conns = await connections()
  const mine = conns.find((c) => c.user === h.people.alice.id)
  assert.equal(mine.strava_athlete_id, strava.state.athleteId)
  assert.match(mine.access_token, /^access-/)
  const rows = await activitiesOf("alice")
  assert.equal(rows.length, 2)
  const hills = rows.find((a) => a.external_id === "2")
  assert.equal(hills.sport, "trail_run")
  assert.equal(hills.owner, h.people.alice.id)
  assert.equal(rows.find((a) => a.external_id === "1").avg_hr, 150)
  assert.equal(rows.find((a) => a.external_id === "1").distance_m, 10234.5)
})

test("callback: rejects a bad or expired state, a missing scope, a denied request and a bad code", async () => {
  assert.equal((await callback("garbage")).status, 400)
  const s = await stateFor("alice")
  const r = await get(`atlas/strava/callback?code=good-code&scope=read&state=${encodeURIComponent(s)}`, null)
  assert.equal(r.status, 302)
  assert.match(r.headers.get("location"), /strava=scope/)
  const denied = await get(`atlas/strava/callback?error=access_denied&state=${encodeURIComponent(s)}`, null)
  assert.match(denied.headers.get("location"), /strava=denied/)
  strava.state.rejectCode = true
  assert.equal((await callback(s)).status, 400)
  assert.equal((await connections()).filter((c) => c.user === h.people.alice.id).length, 0)
})

test("callback: one Strava athlete cannot be linked to two users; reconnecting the same user updates", async () => {
  await connect("alice")
  const taken = await callback(await stateFor("bob"))
  assert.match(taken.headers.get("location"), /strava=taken/)
  await connect("alice")
  assert.equal((await connections()).filter((c) => c.user === h.people.alice.id).length, 1)
})

test("connection tokens are never reachable through the API", async () => {
  await connect("alice")
  assert.notEqual((await get("collections/strava_connections/records", "alice")).status, 200)
})

test("webhook GET: validates the subscription with the verify token", async () => {
  const ok = await get("atlas/strava/webhook?hub.mode=subscribe&hub.verify_token=verify-1&hub.challenge=xyz", null)
  assert.deepEqual(ok.body, { "hub.challenge": "xyz" })
  assert.equal((await get("atlas/strava/webhook?hub.mode=subscribe&hub.verify_token=nope&hub.challenge=xyz", null)).status, 403)
})

test("webhook: a created activity is fetched with laps; an update changes it; a delete scrubs it", async () => {
  await connect("alice")
  strava.state.activities.set(50, strava.activity(50, { name: "Tempo" }))
  strava.state.laps.set("50", [{ lap_index: 1, name: "Lap 1", distance: 1000, moving_time: 300, elapsed_time: 300, total_elevation_gain: 5, average_heartrate: 160.2, max_heartrate: 170 }])
  const ev = { object_type: "activity", object_id: 50, owner_id: strava.state.athleteId, aspect_type: "create" }
  assert.equal((await webhook(ev)).status, 200)
  let [row] = await activitiesOf("alice", ` && external_id = "50"`)
  assert.equal(row.name, "Tempo")
  assert.equal(row.laps.length, 1)
  assert.equal(row.laps[0].avg_hr, 160)

  strava.state.activities.set(50, strava.activity(50, { name: "Tempo 2" }))
  await webhook({ ...ev, aspect_type: "update" })
  const rows = await activitiesOf("alice", ` && external_id = "50"`)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].name, "Tempo 2")

  // a match on it disappears with it
  const plan = (await h.create("alice", "plans", { id: id(), owner: h.people.alice.id, title: "p", visibility: "private" })).body
  const w = (await h.create("alice", "workouts", { id: id(), plan: plan.id, title: "w", kind: "easy" })).body
  const asg = (await h.create("alice", "assignments", { id: id(), plan: plan.id, athlete: h.people.alice.id, assigned_by: h.people.alice.id, start_date: "2026-10-01" })).body
  const m = (await h.create("alice", "matches", { id: id(), owner: h.people.alice.id, activity: rows[0].id, assignment: asg.id, workout: w.id })).body
  await webhook({ ...ev, aspect_type: "delete" })
  const gone = (await h.get("alice", "activities", rows[0].id)).body
  assert.equal(gone.deleted, true)
  assert.equal(gone.name, "")
  assert.equal(gone.external_id, "")
  assert.equal(gone.distance_m, 0)
  assert.equal(gone.laps, null)
  assert.equal((await h.get("alice", "matches", m.id)).body.deleted, true)
})

test("webhook: unknown athletes, wrong subscription and bad events change nothing and still answer 200", async () => {
  await connect("alice")
  strava.state.activities.set(60, strava.activity(60))
  assert.equal((await webhook({ object_type: "activity", object_id: 60, owner_id: 999999, aspect_type: "create" })).status, 200)
  const wrongSub = await h.api("POST", "atlas/strava/webhook", { body: { subscription_id: 1, object_type: "activity", object_id: 60, owner_id: strava.state.athleteId, aspect_type: "create" } })
  assert.equal(wrongSub.status, 200)
  assert.equal((await webhook({ object_type: "activity", object_id: 404, owner_id: strava.state.athleteId, aspect_type: "create" })).status, 200)
  assert.equal((await activitiesOf("alice", ` && external_id = "60"`)).length, 0)
})

test("webhook: a deauthorization removes the connection and scrubs every Strava activity", async () => {
  strava.state.activities.set(1, strava.activity(1))
  await connect("alice")
  assert.equal((await activitiesOf("alice", " && deleted = false")).length, 1)
  await webhook({ object_type: "athlete", object_id: strava.state.athleteId, owner_id: strava.state.athleteId, aspect_type: "update", updates: { authorized: "false" } })
  assert.equal((await connections()).filter((c) => c.user === h.people.alice.id).length, 0)
  assert.equal((await activitiesOf("alice", " && deleted = false")).length, 0)
})

test("tokens near expiry are refreshed before use and the new tokens are stored", async () => {
  await connect("alice")
  const conn = (await connections()).find((c) => c.user === h.people.alice.id)
  await h.update("admin", "strava_connections", conn.id, { expires_at: "2020-01-01 00:00:00.000Z" })
  strava.state.activities.set(70, strava.activity(70))
  await webhook({ object_type: "activity", object_id: 70, owner_id: strava.state.athleteId, aspect_type: "create" })
  assert.ok(strava.state.calls.some((c) => c.form.grant_type === "refresh_token" && c.form.refresh_token === conn.refresh_token))
  const after = (await connections()).find((c) => c.user === h.people.alice.id)
  assert.notEqual(after.access_token, conn.access_token)
  const used = strava.state.calls.filter((c) => c.path.startsWith("/api/v3/activities/70")).map((c) => c.auth)
  assert.ok(used.every((a) => a === `Bearer ${after.access_token}`), used.join())
  assert.equal((await activitiesOf("alice", ` && external_id = "70"`)).length, 1)
})

test("sync and disconnect: sync imports again; disconnect tells Strava, drops tokens and scrubs data", async () => {
  await connect("alice")
  strava.state.activities.set(80, strava.activity(80))
  const s = await h.api("POST", "atlas/strava/sync", { token: h.as("alice") })
  assert.equal(s.body.imported, 1)
  assert.equal((await h.api("POST", "atlas/strava/sync", { token: h.as("bob") })).status, 404)
  const d = await h.api("DELETE", "atlas/strava/connection", { token: h.as("alice") })
  assert.equal(d.status, 200, JSON.stringify(d.body))
  assert.equal(d.body.removed, 1)
  assert.ok(strava.state.calls.some((c) => c.path === "/oauth/deauthorize"))
  assert.equal((await connections()).filter((c) => c.user === h.people.alice.id).length, 0)
  assert.equal((await activitiesOf("alice", " && deleted = false")).length, 0)
})

test("coach access: a granted coach sees imported Strava activities (ADR 0005)", async () => {
  strava.state.activities.set(90, strava.activity(90))
  await connect("alice")
  const row = (await activitiesOf("alice"))[0]
  assert.equal((await h.get("bob", "activities", row.id)).status, 404)
  await h.create("alice", "coach_grants", { id: id(), athlete: h.people.alice.id, coach: h.people.bob.id })
  assert.equal((await h.get("bob", "activities", row.id)).status, 200)
})

test("subscribe: only superusers; Strava validates the webhook during the call", async () => {
  assert.equal((await h.api("POST", "atlas/strava/subscribe", { token: h.as("alice") })).status, 403)
  const r = await h.api("POST", "atlas/strava/subscribe", { token: h.admin })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  assert.equal(r.body.id, 777)
})

test("unconfigured server: Strava endpoints answer 503 instead of failing obscurely", async () => {
  const bare = await startPocketBase({ STRAVA_CLIENT_ID: "", STRAVA_CLIENT_SECRET: "" })
  try {
    await bare.world()
    assert.equal((await bare.api("GET", "atlas/strava/connect", { token: bare.as("alice") })).status, 503)
    assert.equal((await bare.api("GET", "atlas/strava/webhook?hub.mode=subscribe&hub.verify_token=&hub.challenge=x")).status, 403)
  } finally { bare.stop() }
})

test("status: says whether Strava is set up and whether the user is connected, to signed-in users only", async () => {
  assert.equal((await get("atlas/strava/status", null)).status, 401)
  assert.deepEqual((await get("atlas/strava/status", "alice")).body, { configured: true, connected: false })
  await connect("alice")
  assert.deepEqual((await get("atlas/strava/status", "alice")).body, { configured: true, connected: true })
  assert.deepEqual((await get("atlas/strava/status", "bob")).body, { configured: true, connected: false })
  await h.api("DELETE", "atlas/strava/connection", { token: h.as("alice") })
  assert.deepEqual((await get("atlas/strava/status", "alice")).body, { configured: true, connected: false })
})

test("status: an unconfigured server says so", async () => {
  const bare = await startPocketBase({ STRAVA_CLIENT_ID: "", STRAVA_CLIENT_SECRET: "" })
  try {
    await bare.world()
    const r = await bare.api("GET", "atlas/strava/status", { token: bare.as("alice") })
    assert.deepEqual(r.body, { configured: false, connected: false })
  } finally { bare.stop() }
})
