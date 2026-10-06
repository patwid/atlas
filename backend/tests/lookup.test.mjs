// User lookup hook. See docs/adr/0010-user-lookup-by-email.md.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

let h
before(async () => { h = await startPocketBase() })
after(() => h?.stop())
const test = (name, fn) => nodeTest(name, async () => { await h.world(); await fn() })

test("lookup: signed-in users find another user by exact e-mail and get only id and name", async () => {
  const r = await h.api("GET", `atlas/users/lookup?email=${encodeURIComponent(h.people.bob.email.toUpperCase())}`, { token: h.as("alice") })
  assert.equal(r.status, 200, JSON.stringify(r.body))
  assert.deepEqual(r.body, { id: h.people.bob.id, name: "bob" })
})

test("lookup: anonymous users, unknown addresses, partial addresses and oneself are refused", async () => {
  const q = (email, who) => h.api("GET", `atlas/users/lookup?email=${encodeURIComponent(email)}`, { token: who && h.as(who) })
  assert.equal((await q(h.people.bob.email)).status, 401)
  assert.equal((await q("nobody@example.com", "alice")).status, 404)
  assert.equal((await q(h.people.bob.email.split("@")[0], "alice")).status, 400)
  assert.equal((await q("%@example.com", "alice")).status, 404)
  assert.equal((await q(h.people.alice.email, "alice")).status, 400)
})

test("lookup: the found user can then be granted coach access and assigned to", async () => {
  const found = (await h.api("GET", `atlas/users/lookup?email=${encodeURIComponent(h.people.bob.email)}`, { token: h.as("alice") })).body
  const g = await h.create("alice", "coach_grants", { id: id(), athlete: h.people.alice.id, coach: found.id })
  assert.equal(g.status, 200, JSON.stringify(g.body))
  assert.equal((await h.get("alice", "users", found.id)).status, 200)
})

test("lookup: limited to 30 requests per user per 10 minutes", async () => {
  const q = (who) => h.api("GET", `atlas/users/lookup?email=${encodeURIComponent("nobody@example.com")}`, { token: h.as(who) })
  for (let i = 0; i < 30; i++) assert.equal((await q("carol")).status, 404)
  assert.equal((await q("carol")).status, 429)
  assert.equal((await q("dave")).status, 404) // other users are not affected
})
