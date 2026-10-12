// The migration that gives every plan one athlete, and removes sharing and public plans.
// See docs/adr/0110-one-athlete-per-plan.md.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

const MIGRATION = "1760001000_one_athlete_per_plan.js"

let h
before(async () => { h = await startPocketBase({}, { migrationsBefore: MIGRATION }) })
after(() => h?.stop())

const ok = async (response) => {
  const r = await response
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}

test("existing plans are split, one athlete each, and their matches move with them", async () => {
  await h.world()
  const { alice, bob, carol, dave } = h.people
  const plan = (who, extra = {}) =>
    ok(h.create(who, "plans", { id: id(), owner: h.people[who].id, title: "10k", visibility: "private", start_date: "2026-11-02", ...extra }))
  const assignment = (who, p, athlete, extra = {}) =>
    ok(h.create(who, "assignments", { id: id(), plan: p.id, athlete: h.people[athlete].id, assigned_by: h.people[who].id, start_date: "", ...extra }))
  await ok(h.create("carol", "coach_grants", { id: id(), athlete: carol.id, coach: alice.id }))
  await ok(h.create("dave", "coach_grants", { id: id(), athlete: dave.id, coach: bob.id }))

  // Alice's public plan: her own, one for carol (as her coach), bob started it himself, and he assigned it to dave.
  const shared = await plan("alice", { visibility: "public", description: "Eight weeks", base_weeks: 2 })
  const easy = await ok(h.create("alice", "workouts", { id: id(), plan: shared.id, day_index: 2, title: "Easy", kind: "interval" }))
  const gone = await ok(h.create("alice", "workouts", { id: id(), plan: shared.id, day_index: 4, title: "Gone", kind: "interval" }))
  await ok(h.update("alice", "workouts", gone.id, { deleted: true, base_updated: gone.updated }))
  const own = await assignment("alice", shared, "alice")
  const forCarol = await assignment("alice", shared, "carol", { start_date: "2026-11-09" })
  const bobs = await assignment("bob", shared, "bob", { start_date: "2026-11-11" })
  const forDave = await assignment("bob", shared, "dave")
  const removed = await assignment("alice", shared, "alice", { start_date: "2026-12-07" })
  await ok(h.update("alice", "assignments", removed.id, { deleted: true, base_updated: removed.updated }))
  await ok(h.create("alice", "plan_shares", { id: id(), plan: shared.id, user: dave.id }))
  // Bob ran the easy workout of his start and linked it.
  const run = await ok(h.create("bob", "activities", { id: id(), owner: bob.id, source: "manual", started_at: "2026-11-11 07:00:00.000Z", sport: "run" }))
  const match = await ok(h.create("bob", "matches", { id: id(), owner: bob.id, activity: run.id, assignment: bobs.id, workout: easy.id }))
  const removedRun = await ok(h.create("alice", "activities", { id: id(), owner: alice.id, source: "manual", started_at: "2026-12-09 07:00:00.000Z", sport: "run" }))
  const removedMatch = await ok(h.create("alice", "matches", { id: id(), owner: alice.id, activity: removedRun.id, assignment: removed.id, workout: easy.id }))

  // Nobody follows this one.
  const draft = await plan("carol", { start_date: "" })
  // Dave's plan that only Alice started for herself (it was public): it stays dave's, with one for him.
  const davesPublic = await plan("dave", { visibility: "public" })
  const alicesStart = await assignment("alice", davesPublic, "alice")

  await h.upgrade()

  const read = (collection, rid) => h.get("admin", collection, rid).then((r) => r.body)
  const all = (collection, filter) => h.list("admin", collection, filter).then((r) => r.body.items)
  const assignmentsOf = (p) => all("assignments", `plan = "${p}"`)

  // The original keeps Alice's own, on its date.
  assert.deepEqual((await assignmentsOf(shared.id)).map((a) => a.id), [own.id])
  assert.equal((await read("assignments", own.id)).start_date, "")
  assert.equal((await read("plans", shared.id)).start_date, "2026-11-02")
  assert.equal((await read("plans", shared.id)).visibility, undefined)
  assert.equal((await read("assignments", removed.id)).id, undefined, "a removed assignment is gone")
  assert.equal((await read("matches", removedMatch.id)).id, undefined, "with its matches")

  // Every other start became a copy of the plan, owned by whoever made it, on that start's date.
  const copyOf = async (a, owner, startDate) => {
    const moved = await read("assignments", a.id)
    assert.notEqual(moved.plan, shared.id)
    assert.equal(moved.start_date, "")
    const copy = await read("plans", moved.plan)
    assert.equal(copy.owner, owner.id)
    assert.equal(copy.source_plan, shared.id)
    assert.equal(copy.title, "10k")
    assert.equal(copy.description, "Eight weeks")
    assert.equal(copy.base_weeks, 2)
    assert.equal(copy.start_date, startDate)
    const workouts = await all("workouts", `plan = "${copy.id}"`)
    assert.deepEqual(workouts.map((w) => [w.title, w.day_index, w.deleted]).sort(), [["Easy", 2, false], ["Gone", 4, true]])
    return { copy, workouts }
  }
  await copyOf(forCarol, alice, "2026-11-09")
  const bobsCopy = await copyOf(bobs, bob, "2026-11-11")
  await copyOf(forDave, bob, "2026-11-02")
  const movedMatch = await read("matches", match.id)
  assert.equal(movedMatch.assignment, bobs.id)
  assert.equal(movedMatch.workout, bobsCopy.workouts.find((w) => w.title === "Easy").id, "the match points at the copy's workout")
  // Bob can now change his own plan, and Carol reads hers.
  assert.equal((await h.get("bob", "plans", bobsCopy.copy.id)).status, 200)
  assert.equal((await h.get("bob", "plans", shared.id)).status, 404, "the original is no longer his to read")
  const carolsPlan = (await read("assignments", forCarol.id)).plan
  assert.equal((await h.get("carol", "plans", carolsPlan)).status, 200)

  // A plan nobody followed is its owner's, and so is one that only a stranger had started.
  const draftAssignments = await assignmentsOf(draft.id)
  assert.equal(draftAssignments.length, 1)
  assert.equal(draftAssignments[0].athlete, carol.id)
  assert.equal(draftAssignments[0].assigned_by, carol.id)
  const davesAssignments = await assignmentsOf(davesPublic.id)
  assert.deepEqual(davesAssignments.map((a) => a.athlete), [dave.id])
  const alicesCopy = await read("plans", (await read("assignments", alicesStart.id)).plan)
  assert.equal(alicesCopy.owner, alice.id)

  // Sharing is gone.
  assert.equal((await h.list("admin", "plan_shares")).status, 404)
})
