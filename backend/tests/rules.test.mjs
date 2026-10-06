// API rule tests against a throwaway PocketBase instance. See docs/adr/0009-data-model-and-api-rules.md.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

let h
before(async () => { h = await startPocketBase() })
after(() => h?.stop())
const test = (name, fn) => nodeTest(name, async () => { await h.world(); await fn() })
const people = new Proxy({}, { get: (_, k) => h.people[k] })
const as = (name) => h.as(name)
const api = (...a) => h.api(...a)
const create = (...a) => h.create(...a)
// Clients must send base_updated (ADR 0011); like the sync engine, fetch it first unless given.
const update = async (who, collection, rid, body) => {
  if (body.base_updated === undefined) {
    const current = await h.get(who, collection, rid)
    if (current.status === 200) body = { ...body, base_updated: current.body.updated }
  }
  return h.update(who, collection, rid, body)
}
const get = (...a) => h.get(...a)
const list = (...a) => h.list(...a)

const mkPlan = async (owner, extra = {}) => {
  const r = await create(owner, "plans", { id: id(), owner: people[owner].id, title: "10k", visibility: "private", ...extra })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}
const mkWorkout = async (owner, plan, extra = {}) => {
  const r = await create(owner, "workouts", { id: id(), plan: plan.id, day_index: 0, title: "Easy", kind: "easy", ...extra })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}
const grant = async (athlete, coach) => {
  const r = await create(athlete, "coach_grants", { id: id(), athlete: people[athlete].id, coach: people[coach].id })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}
const mkActivity = async (owner, extra = {}) => {
  const r = await create(owner, "activities", {
    id: id(), owner: people[owner].id, source: "fit", started_at: "2026-10-01 07:00:00.000Z", sport: "run", distance_m: 10000, ...extra,
  })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}

test("client-generated IDs are kept", async () => {
  const plan = await mkPlan("alice")
  assert.equal((await get("alice", "plans", plan.id)).body.id, plan.id)
})

test("plans: private to owner, public to signed-in users, anonymous sees nothing", async () => {
  const priv = await mkPlan("alice")
  const pub = await mkPlan("alice", { visibility: "public" })
  assert.equal((await get("bob", "plans", priv.id)).status, 404)
  assert.equal((await get("bob", "plans", pub.id)).status, 200)
  assert.equal((await get(null, "plans", pub.id)).status, 404)
})

test("plans: cannot create for someone else, cannot change owner, cannot edit others' plans", async () => {
  const bad = await create("bob", "plans", { id: id(), owner: people.alice.id, title: "x", visibility: "private" })
  assert.equal(bad.status, 400)
  const pub = await mkPlan("alice", { visibility: "public" })
  assert.equal((await update("bob", "plans", pub.id, { title: "hacked" })).status, 404)
  assert.equal((await update("alice", "plans", pub.id, { owner: people.bob.id })).status, 404)
  assert.equal((await update("alice", "plans", pub.id, { title: "renamed" })).status, 200)
})

test("plans: clients cannot hard-delete", async () => {
  const plan = await mkPlan("alice")
  assert.equal((await api("DELETE", `collections/plans/records/${plan.id}`, { token: as("alice") })).status, 403)
  assert.equal((await update("alice", "plans", plan.id, { deleted: true })).status, 200)
})

test("plan_shares: the owner shares a plan with a user, who can read it and its workouts", async () => {
  const plan = await mkPlan("alice")
  const workout = await mkWorkout("alice", plan)
  assert.equal((await get("bob", "plans", plan.id)).status, 404)
  assert.equal((await get("bob", "workouts", workout.id)).status, 404)
  const share = await create("alice", "plan_shares", { id: id(), plan: plan.id, user: people.bob.id })
  assert.equal(share.status, 200, JSON.stringify(share.body))
  assert.equal((await get("bob", "plans", plan.id)).status, 200)
  assert.equal((await get("bob", "workouts", workout.id)).status, 200)
  assert.equal((await get("carol", "plans", plan.id)).status, 404)
  assert.equal((await update("bob", "plans", plan.id, { title: "x" })).status, 404)
  // a non-owner cannot share someone else's plan
  assert.equal((await create("bob", "plan_shares", { id: id(), plan: plan.id, user: people.carol.id })).status, 400)
  // revoking hides it again
  assert.equal((await update("alice", "plan_shares", share.body.id, { deleted: true })).status, 200)
  assert.equal((await get("bob", "plans", plan.id)).status, 404)
})

test("workouts: only the plan owner can write", async () => {
  const plan = await mkPlan("alice", { visibility: "public" })
  const bad = await create("bob", "workouts", { id: id(), plan: plan.id, day_index: 0, title: "x", kind: "easy" })
  assert.equal(bad.status, 400)
  const w = await mkWorkout("alice", plan)
  assert.equal((await update("bob", "workouts", w.id, { title: "x" })).status, 404)
  assert.equal((await update("alice", "workouts", w.id, { plan: (await mkPlan("alice")).id })).status, 404)
})

test("workouts: deleted plans and workouts are hidden from readers but kept for the owner's sync", async () => {
  const plan = await mkPlan("alice", { visibility: "public" })
  const w = await mkWorkout("alice", plan)
  await update("alice", "workouts", w.id, { deleted: true })
  assert.equal((await get("bob", "workouts", w.id)).status, 404)
  assert.equal((await get("alice", "workouts", w.id)).body.deleted, true)
})

test("coach_grants: athlete grants, coach can read, others cannot, coach cannot grant for the athlete", async () => {
  const g = await grant("alice", "bob")
  assert.equal((await get("bob", "coach_grants", g.id)).status, 200)
  assert.equal((await get("carol", "coach_grants", g.id)).status, 404)
  assert.equal((await create("bob", "coach_grants", { id: id(), athlete: people.alice.id, coach: people.carol.id })).status, 400)
  assert.equal((await create("alice", "coach_grants", { id: id(), athlete: people.alice.id, coach: people.alice.id })).status, 400)
  assert.equal((await update("bob", "coach_grants", g.id, { deleted: true })).status, 404)
})

test("users: visible only to oneself and linked users", async () => {
  assert.equal((await get("dave", "users", people.alice.id)).status, 404)
  assert.equal((await get("dave", "users", people.dave.id)).status, 200)
  await grant("alice", "carol")
  assert.equal((await get("carol", "users", people.alice.id)).status, 200)
  assert.equal((await get("alice", "users", people.carol.id)).status, 200)
  assert.equal((await get("dave", "users", people.alice.id)).status, 404)
})

test("activities: owner and coach read; strangers do not; revoked coach loses access", async () => {
  const a = await mkActivity("alice")
  assert.equal((await get("alice", "activities", a.id)).status, 200)
  assert.equal((await get("bob", "activities", a.id)).status, 404)
  const g = await grant("alice", "bob")
  assert.equal((await get("bob", "activities", a.id)).status, 200)
  assert.equal((await get("carol", "activities", a.id)).status, 404)
  await update("alice", "coach_grants", g.id, { deleted: true })
  assert.equal((await get("bob", "activities", a.id)).status, 404)
})

test("activities: a coach grant for one athlete does not expose another", async () => {
  await grant("alice", "dave")
  const other = await mkActivity("carol")
  assert.equal((await get("dave", "activities", other.id)).status, 404)
})

test("activities: clients cannot create strava or garmin rows; the server can", async () => {
  for (const source of ["strava", "garmin"]) {
    const r = await create("alice", "activities", { id: id(), owner: people.alice.id, source, started_at: "2026-10-01 07:00:00.000Z", sport: "run" })
    assert.equal(r.status, 400, source)
  }
  const server = await create(null, "activities", { id: id(), owner: people.alice.id, source: "strava", external_id: "42", started_at: "2026-10-01 07:00:00.000Z", sport: "run" })
  assert.equal(server.status, 400) // anonymous is rejected
  const r = await api("POST", "collections/activities/records", {
    token: h.admin, body: { id: id(), owner: people.alice.id, source: "strava", external_id: "42", started_at: "2026-10-01 07:00:00.000Z", sport: "run" },
  })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  assert.equal((await update("alice", "activities", r.body.id, { name: "mine now" })).status, 404)
})

test("activities: Strava activities are visible to a granted coach (ADR 0005)", async () => {
  const r = await api("POST", "collections/activities/records", {
    token: h.admin, body: { id: id(), owner: people.alice.id, source: "strava", external_id: "99", started_at: "2026-10-01 07:00:00.000Z", sport: "run" },
  })
  assert.equal((await get("bob", "activities", r.body.id)).status, 404)
  await grant("alice", "bob")
  assert.equal((await get("bob", "activities", r.body.id)).status, 200)
})

test("activities: owner and source cannot change; external ids are unique per owner and source", async () => {
  const a = await mkActivity("alice", { external_id: "hash1" })
  assert.equal((await update("alice", "activities", a.id, { source: "manual" })).status, 404)
  assert.equal((await update("alice", "activities", a.id, { owner: people.bob.id })).status, 404)
  assert.equal((await update("alice", "activities", a.id, { name: "Morning run" })).status, 200)
  const dup = await create("alice", "activities", { id: id(), owner: people.alice.id, source: "fit", external_id: "hash1", started_at: "2026-10-01 07:00:00.000Z", sport: "run" })
  assert.equal(dup.status, 400)
  assert.equal((await mkActivity("bob", { external_id: "hash1" })).source, "fit")
})

test("assignments: athletes assign to themselves; coaches assign to granted athletes; strangers cannot", async () => {
  const coachPlan = await mkPlan("bob")
  const w = await mkWorkout("bob", coachPlan)
  const mine = (athlete, by, plan = coachPlan) => ({ id: id(), plan: plan.id, athlete: people[athlete].id, assigned_by: people[by].id, start_date: "2026-11-01" })
  assert.equal((await create("alice", "assignments", mine("alice", "alice"))).status, 400) // bob's private plan is not readable
  assert.equal((await create("bob", "assignments", mine("alice", "bob"))).status, 400) // no grant yet
  await grant("alice", "bob")
  const given = await create("bob", "assignments", mine("alice", "bob"))
  assert.equal(given.status, 200, JSON.stringify(given.body))
  // the athlete now reads the coach's private plan and its workouts through the assignment
  assert.equal((await get("alice", "plans", coachPlan.id)).status, 200)
  assert.equal((await get("alice", "workouts", w.id)).status, 200)
  assert.equal((await get("alice", "assignments", given.body.id)).status, 200)
  assert.equal((await get("carol", "assignments", given.body.id)).status, 404)
  assert.equal((await create("carol", "assignments", mine("alice", "carol"))).status, 400)
  assert.equal((await create("carol", "assignments", { ...mine("alice", "bob") })).status, 400) // assigned_by must be oneself
  assert.equal((await update("alice", "assignments", given.body.id, { start_date: "2026-11-08" })).status, 200)
  assert.equal((await update("alice", "assignments", given.body.id, { athlete: people.carol.id })).status, 404)
})

test("assignments: a self-assignment of a public plan", async () => {
  const plan = await mkPlan("carol", { visibility: "public" })
  const r = await create("alice", "assignments", { id: id(), plan: plan.id, athlete: people.alice.id, assigned_by: people.alice.id, start_date: "2026-12-01" })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  assert.equal((await create("alice", "assignments", { id: id(), plan: plan.id, athlete: people.alice.id, assigned_by: people.alice.id, start_date: "01.12.2026" })).status, 400)
})

test("matches: the owner links own activity to own assignment; coach reads; others cannot", async () => {
  const plan = await mkPlan("alice")
  const w = await mkWorkout("alice", plan)
  const asg = (await create("alice", "assignments", { id: id(), plan: plan.id, athlete: people.alice.id, assigned_by: people.alice.id, start_date: "2026-10-01" })).body
  const act = await mkActivity("alice")
  const bobAct = await mkActivity("bob")
  const m = await create("alice", "matches", { id: id(), owner: people.alice.id, activity: act.id, assignment: asg.id, workout: w.id })
  assert.equal(m.status, 200, JSON.stringify(m.body))
  assert.equal((await create("alice", "matches", { id: id(), owner: people.alice.id, activity: bobAct.id, assignment: asg.id, workout: w.id })).status, 400)
  assert.equal((await create("bob", "matches", { id: id(), owner: people.bob.id, activity: bobAct.id, assignment: asg.id, workout: w.id })).status, 400)
  assert.equal((await get("bob", "matches", m.body.id)).status, 404)
  await grant("alice", "bob")
  assert.equal((await get("bob", "matches", m.body.id)).status, 200)
  assert.equal((await update("bob", "matches", m.body.id, { deleted: true })).status, 404)
  assert.equal((await update("alice", "matches", m.body.id, { activity: bobAct.id })).status, 404)
  // one match per activity
  assert.equal((await create("alice", "matches", { id: id(), owner: people.alice.id, activity: act.id, assignment: asg.id, workout: w.id })).status, 400)
})

test("strava_connections: no access through the API for users", async () => {
  for (const who of ["alice", null]) {
    assert.notEqual((await api("GET", "collections/strava_connections/records", { token: who && as(who) })).status, 200)
    const c = await create(who, "strava_connections", { user: people.alice.id, strava_athlete_id: 1, access_token: "a", refresh_token: "b", expires_at: "2026-10-01 07:00:00.000Z" })
    assert.ok([400, 403].includes(c.status), String(c.status))
  }
})

test("sync: records changed since a cursor can be pulled, including soft deletes", async () => {
  const plan = await mkPlan("alice")
  const cursor = (await get("alice", "plans", plan.id)).body.updated
  await new Promise((r) => setTimeout(r, 20))
  await update("alice", "plans", plan.id, { deleted: true })
  const pulled = await list("alice", "plans", `updated > "${cursor}"`)
  assert.ok(pulled.body.items.some((p) => p.id === plan.id && p.deleted))
})

test("coach_grants: carry display names for both people, as labels only", async () => {
  const g = await create("alice", "coach_grants", {
    id: id(), athlete: people.alice.id, coach: people.bob.id, athlete_name: "Alice", coach_name: "Coach Bob",
  })
  assert.equal(g.status, 200, JSON.stringify(g.body))
  const seen = (await get("bob", "coach_grants", g.body.id)).body
  assert.equal(seen.athlete_name, "Alice")
  assert.equal(seen.coach_name, "Coach Bob")
  // Names have a length limit like other text.
  const long = await create("alice", "coach_grants", {
    id: id(), athlete: people.alice.id, coach: people.carol.id, athlete_name: "x".repeat(201),
  })
  assert.equal(long.status, 400)
  // Only the athlete changes a grant, names included, and with the guard's base.
  assert.equal((await update("bob", "coach_grants", g.body.id, { coach_name: "Hacked" })).status, 404)
  assert.equal((await update("alice", "coach_grants", g.body.id, { coach_name: "Bob C." })).status, 200)
})
