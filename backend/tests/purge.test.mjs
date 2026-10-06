// Purge job. See docs/adr/0014-purge-soft-deleted-rows.md.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

let h
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
// Retention of about 2 seconds, so the tests do not have to fake the clock.
before(async () => { h = await startPocketBase({ ATLAS_PURGE_RETENTION_DAYS: String(2 / 86400) }) })
after(() => h?.stop())
const test = (name, fn) => nodeTest(name, async () => { await h.world(); await fn() })
const exists = async (collection, rid) => (await h.get("admin", collection, rid)).status === 200
// The cron endpoint answers before the job has finished, so wait until a row that must be purged
// is gone, then give the job a moment to finish the rest.
const runPurge = async ([collection, rid]) => {
  const r = await h.api("POST", "crons/atlas_purge_deleted", { token: h.admin })
  assert.equal(r.status, 204, JSON.stringify(r.body))
  for (let i = 0; i < 100 && (await exists(collection, rid)); i++) await sleep(50)
  await sleep(300)
}
const softDelete = async (collection, rid) => {
  const r = await h.update("admin", collection, rid, { deleted: true })
  assert.equal(r.status, 200, JSON.stringify(r.body))
}
const mkPlan = async (extra = {}) => (await h.create("alice", "plans", { id: id(), owner: h.people.alice.id, title: "p", visibility: "private", ...extra })).body

test("purge: the cron job is registered and only superusers can run it", async () => {
  assert.equal((await h.api("POST", "crons/atlas_purge_deleted", { token: h.as("alice") })).status, 403)
  const list = await h.api("GET", "crons", { token: h.admin })
  assert.ok(list.body.some((j) => j.id === "atlas_purge_deleted"), JSON.stringify(list.body))
})

test("purge: removes old soft-deleted rows, keeps recent tombstones and live rows", async () => {
  const old = await mkPlan()
  const live = await mkPlan()
  await softDelete("plans", old.id)
  await sleep(2500)
  const fresh = await mkPlan()
  await softDelete("plans", fresh.id)
  await runPurge(["plans", old.id])
  assert.equal(await exists("plans", old.id), false)
  assert.equal(await exists("plans", fresh.id), true, "a tombstone younger than the retention stays")
  assert.equal(await exists("plans", live.id), true, "live rows are never purged")
})

test("purge: children go with their purged parent and tombstones of every synced collection are removed", async () => {
  const plan = await mkPlan()
  const w = (await h.create("alice", "workouts", { id: id(), plan: plan.id, title: "w", kind: "easy" })).body
  const asg = (await h.create("alice", "assignments", { id: id(), plan: plan.id, athlete: h.people.alice.id, assigned_by: h.people.alice.id, start_date: "2026-10-01" })).body
  const act = (await h.create("alice", "activities", { id: id(), owner: h.people.alice.id, source: "manual", started_at: "2026-10-01 07:00:00.000Z", sport: "run" })).body
  const m = (await h.create("alice", "matches", { id: id(), owner: h.people.alice.id, activity: act.id, assignment: asg.id, workout: w.id })).body
  const grant = (await h.create("alice", "coach_grants", { id: id(), athlete: h.people.alice.id, coach: h.people.bob.id })).body
  const share = (await h.create("alice", "plan_shares", { id: id(), plan: plan.id, user: h.people.carol.id })).body
  for (const [c, r] of [["matches", m], ["activities", act], ["assignments", asg], ["workouts", w], ["plan_shares", share], ["plans", plan], ["coach_grants", grant]]) {
    await softDelete(c, r.id)
  }
  await sleep(2500)
  await runPurge(["coach_grants", grant.id]) // the last collection the job handles
  for (const [c, r] of [["matches", m], ["activities", act], ["assignments", asg], ["workouts", w], ["plan_shares", share], ["plans", plan], ["coach_grants", grant]]) {
    assert.equal(await exists(c, r.id), false, c)
  }
  assert.equal(await exists("users", h.people.alice.id), true)
})

test("purge: a live child of a purged plan is removed with it (cascade), other plans are untouched", async () => {
  const gone = await mkPlan()
  const kept = await mkPlan()
  const child = (await h.create("alice", "workouts", { id: id(), plan: gone.id, title: "w", kind: "easy" })).body
  const keptChild = (await h.create("alice", "workouts", { id: id(), plan: kept.id, title: "w", kind: "easy" })).body
  await softDelete("plans", gone.id)
  await sleep(2500)
  await runPurge(["plans", gone.id])
  assert.equal(await exists("workouts", child.id), false)
  assert.equal(await exists("workouts", keptChild.id), true)
})

test("purge: a scrubbed Strava tombstone is purged like any other", async () => {
  const a = (await h.create("admin", "activities", { id: id(), owner: h.people.alice.id, source: "strava", external_id: "", deleted: true, started_at: "1970-01-01 00:00:00.000Z", sport: "run" })).body
  await sleep(2500)
  await runPurge(["activities", a.id])
  assert.equal(await exists("activities", a.id), false)
})

test("purge: a cursor pull still sees a tombstone until it is purged", async () => {
  const plan = await mkPlan()
  await softDelete("plans", plan.id)
  const pulled = await h.list("alice", "plans", `deleted = true && id = "${plan.id}"`)
  assert.equal(pulled.body.items.length, 1)
})
