// One kind for every run: the migration that makes easy, long, tempo, cross-training and strength workouts runs, and
// the hook that saves those kinds from an app not yet updated as a run. See docs/adr/0114-one-kind-for-every-run.md.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

const MIGRATION = "1760001100_workout_kind_run.js"

let h
before(async () => { h = await startPocketBase({}, { migrationsBefore: MIGRATION }) })
after(() => h?.stop())

const ok = async (response) => {
  const r = await response
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}

test("every dropped or combined kind becomes a run, and nothing else changes", async () => {
  await h.world()
  const { alice } = h.people
  const plan = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "10k" }))
  const kinds = ["easy", "long", "tempo", "interval", "race", "rest", "cross", "strength"]
  const made = []
  // As superuser: the hook would already save the old kinds as a run.
  for (const kind of kinds) made.push(await ok(h.create("admin", "workouts", { id: id(), plan: plan.id, title: kind, kind })))

  await h.upgrade()

  const after = await Promise.all(made.map((w) => h.get("admin", "workouts", w.id).then((r) => r.body)))
  assert.deepEqual(after.map((w) => w.kind), ["run", "run", "run", "interval", "race", "rest", "run", "run"])
  // Not moved forward: devices are not made to pull them again, and their changes are not conflicts.
  assert.deepEqual(after.map((w) => w.updated), made.map((w) => w.updated))
  const edited = await ok(h.update("alice", "workouts", made[0].id, { title: "Easy", base_updated: made[0].updated }))
  assert.equal(edited.kind, "run")
})

test("an old kind sent by an app not yet updated is saved as a run; an unknown kind is refused", async () => {
  await h.world()
  const { alice } = h.people
  const plan = await ok(h.create("alice", "plans", { id: id(), owner: alice.id, title: "10k" }))
  const created = await ok(h.create("alice", "workouts", { id: id(), plan: plan.id, title: "Long", kind: "long" }))
  assert.equal(created.kind, "run")
  const interval = await ok(h.create("alice", "workouts", { id: id(), plan: plan.id, title: "Track", kind: "interval" }))
  const updated = await ok(h.update("alice", "workouts", interval.id, { kind: "tempo", base_updated: interval.updated }))
  assert.equal(updated.kind, "run")
  assert.equal((await h.create("alice", "workouts", { id: id(), plan: plan.id, title: "x", kind: "swim" })).status, 400)
})
