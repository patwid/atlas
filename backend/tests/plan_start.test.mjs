// A plan's start date and assignments that follow it, and the migration that gives existing plans one.
// See docs/adr/0108-plan-start-date.md.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

const MIGRATION = "1760000900_plan_start_date.js"
// The rules as this migration left them; 1760001000 changed them again (ADR 0110), see one_athlete_per_plan.test.mjs.
const NEXT = "1760001000_one_athlete_per_plan.js"

let h
before(async () => { h = await startPocketBase({}, { migrationsBefore: MIGRATION }) })
after(() => h?.stop())

const ok = async (response) => {
  const r = await response
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}
const update = async (who, collection, rid, body) => {
  const current = await h.get(who, collection, rid)
  return h.update(who, collection, rid, { ...body, base_updated: current.body.updated })
}

test("existing plans keep their dates; the owner's assignments follow the plan from then on", async () => {
  await h.world()
  const { alice, bob } = h.people
  // Followed from Wednesday 4 Nov by alice herself and by bob (a public plan), on another day by a coach's athlete.
  const plan = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "10k", visibility: "public" }))
  const unused = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "Draft", visibility: "private" }))
  const w0 = await ok(h.create("alice", "workouts", { id: id(), plan: plan.id, day_index: 0, title: "Easy", kind: "easy" }))
  const w9 = await ok(h.create("alice", "workouts", { id: id(), plan: plan.id, day_index: 9, title: "Long", kind: "long" }))
  const draftWorkout = await ok(h.create("alice", "workouts", { id: id(), plan: unused.id, day_index: 2, title: "Easy", kind: "easy" }))
  const own = await ok(h.create("alice", "assignments", { id: id(), plan: plan.id, athlete: alice.id, assigned_by: alice.id, start_date: "2026-11-04" }))
  const older = await ok(h.create("alice", "assignments", { id: id(), plan: plan.id, athlete: alice.id, assigned_by: alice.id, start_date: "2026-09-02" }))
  const bobs = await ok(h.create("bob", "assignments", { id: id(), plan: plan.id, athlete: bob.id, assigned_by: bob.id, start_date: "2026-11-04" }))

  await h.upgrade(NEXT)

  const read = (collection, rid) => h.get("admin", collection, rid).then((r) => r.body)
  assert.equal((await read("plans", plan.id)).start_date, "2026-11-04")
  assert.equal((await read("plans", unused.id)).start_date, "")
  // Wednesday is two days after Monday: day 0 (Wed 4 Nov) is now day 2 from Monday 2 Nov.
  assert.equal((await read("workouts", w0.id)).day_index, 2)
  assert.equal((await read("workouts", w9.id)).day_index, 11)
  assert.equal((await read("workouts", draftWorkout.id)).day_index, 2)
  assert.equal((await read("assignments", own.id)).start_date, "")
  assert.equal((await read("assignments", older.id)).start_date, "2026-09-02")
  assert.equal((await read("assignments", bobs.id)).start_date, "2026-11-04", "someone else's start stays their own")
})

test("an assignment may follow its plan's date only when the plan has one, and a plan's date cannot be emptied", async () => {
  await h.world()
  const { alice } = h.people
  const undated = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "Old", visibility: "private" }))
  const dated = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "New", visibility: "private", start_date: "2026-11-02" }))
  const start = (plan, start_date) =>
    h.create("alice", "assignments", { id: id(), plan: plan.id, athlete: alice.id, assigned_by: alice.id, start_date })
  assert.equal((await start(undated, "")).status, 400)
  assert.equal((await start(undated, "2026-11-02")).status, 200)
  const following = await ok(start(dated, ""))
  assert.equal((await h.create("alice", "plans", { id: id(), owner: alice.id, title: "x", visibility: "private", start_date: "2.11.2026" })).status, 400)

  assert.equal((await update("alice", "plans", dated.id, { start_date: "2026-11-09" })).status, 200)
  assert.equal((await update("alice", "plans", dated.id, { title: "Renamed" })).status, 200)
  assert.equal((await update("alice", "plans", dated.id, { start_date: "" })).status, 404)
  assert.equal((await update("alice", "plans", undated.id, { title: "Still undated" })).status, 200)

  assert.equal((await update("alice", "assignments", following.id, { start_date: "2026-12-07" })).status, 200)
  assert.equal((await update("alice", "assignments", following.id, { start_date: "" })).status, 200)
})
