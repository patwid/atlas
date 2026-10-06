// Sync conflict guard. See docs/adr/0011-sync-conflict-guard.md.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

let h
before(async () => { h = await startPocketBase() })
after(() => h?.stop())
const test = (name, fn) => nodeTest(name, async () => { await h.world(); await fn() })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const mkPlan = async () => {
  const r = await h.create("alice", "plans", { id: id(), owner: h.people.alice.id, title: "10k", visibility: "private" })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  return r.body
}

test("guard: an update with the current base_updated succeeds and moves `updated` forward", async () => {
  const plan = await mkPlan()
  await sleep(5)
  const r = await h.update("alice", "plans", plan.id, { title: "half", base_updated: plan.updated })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  assert.notEqual(r.body.updated, plan.updated)
})

test("guard: a stale base_updated is refused with 409, and nothing is written", async () => {
  const plan = await mkPlan()
  await sleep(5)
  const first = await h.update("alice", "plans", plan.id, { title: "from device A", base_updated: plan.updated })
  assert.equal(first.status, 200)
  const stale = await h.update("alice", "plans", plan.id, { title: "from device B", base_updated: plan.updated })
  assert.equal(stale.status, 409, JSON.stringify(stale.body))
  assert.ok(stale.body.data.base_updated, JSON.stringify(stale.body))
  assert.equal((await h.get("alice", "plans", plan.id)).body.title, "from device A")
})

test("guard: a missing base_updated is refused", async () => {
  const plan = await mkPlan()
  assert.equal((await h.update("alice", "plans", plan.id, { title: "x" })).status, 400)
  assert.equal((await h.update("alice", "plans", plan.id, { title: "x", base_updated: "" })).status, 400)
})

test("guard: replaying an update that already took effect is not a conflict", async () => {
  const plan = await mkPlan()
  await sleep(5)
  const body = { title: "renamed", base_updated: plan.updated }
  assert.equal((await h.update("alice", "plans", plan.id, body)).status, 200)
  assert.equal((await h.update("alice", "plans", plan.id, body)).status, 200)
  // ...but a different change on a stale base still conflicts
  assert.equal((await h.update("alice", "plans", plan.id, { title: "other", base_updated: plan.updated })).status, 409)
})

test("guard: a soft delete on a stale base conflicts with an edit made elsewhere", async () => {
  const plan = await mkPlan()
  await sleep(5)
  await h.update("alice", "plans", plan.id, { description: "edited", base_updated: plan.updated })
  assert.equal((await h.update("alice", "plans", plan.id, { deleted: true, base_updated: plan.updated })).status, 409)
})

test("guard: the rule layer still applies first for other users", async () => {
  const plan = await mkPlan()
  assert.equal((await h.update("bob", "plans", plan.id, { title: "x", base_updated: plan.updated })).status, 404)
})

test("guard: superusers can edit without base_updated; every synced collection is guarded", async () => {
  const plan = await mkPlan()
  assert.equal((await h.update("admin", "plans", plan.id, { title: "admin edit" })).status, 200)
  const w = await h.create("alice", "workouts", { id: id(), plan: plan.id, title: "Easy", kind: "easy" })
  assert.equal((await h.update("alice", "workouts", w.body.id, { title: "x" })).status, 400)
  assert.equal((await h.update("alice", "workouts", w.body.id, { title: "x", base_updated: w.body.updated })).status, 200)
})
