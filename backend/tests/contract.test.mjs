// The HTTP shapes the Gleam client (frontend/src/atlas/api.gleam and auth.gleam) depends on.
// If PocketBase changes any of them, the client's parsing needs to change too. See ADR 0017.
import { test as nodeTest, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase, id } from "./harness.mjs"

let h
before(async () => { h = await startPocketBase() })
after(() => h?.stop())
const test = (name, fn) => nodeTest(name, async () => { await h.world(); await fn() })
const plan = (who, extra = {}) => ({ id: id(), owner: h.people[who].id, title: "t", visibility: "private", ...extra })
const jwtPayload = (token) => JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString())

test("sign-in: 200 with token and a record holding id, name and e-mail; the token carries an `exp` claim", async () => {
  const r = await h.api("POST", "collections/users/auth-with-password", { body: { identity: h.people.alice.email, password: "password123" } })
  assert.equal(r.status, 200)
  assert.equal(typeof r.body.token, "string")
  assert.equal(r.body.record.id, h.people.alice.id)
  assert.equal(r.body.record.name, "alice")
  assert.equal(r.body.record.email, h.people.alice.email)
  const claims = jwtPayload(r.body.token)
  assert.equal(typeof claims.exp, "number")
  assert.ok(claims.exp > Date.now() / 1000)
  assert.equal(claims.id, h.people.alice.id)
})

test("sign-in: a wrong password is 400 with a message; blank fields are 400 with field errors", async () => {
  const bad = await h.api("POST", "collections/users/auth-with-password", { body: { identity: h.people.alice.email, password: "nope" } })
  assert.equal(bad.status, 400)
  assert.equal(bad.body.message, "Failed to authenticate.")
  const blank = await h.api("POST", "collections/users/auth-with-password", { body: { identity: "", password: "" } })
  assert.equal(blank.status, 400)
  assert.ok(blank.body.data.identity)
})

test("refresh: 200 with a new token for a valid one, 401 without or with a bad one", async () => {
  const ok = await h.api("POST", "collections/users/auth-refresh", { token: h.as("alice") })
  assert.equal(ok.status, 200)
  assert.equal(typeof ok.body.token, "string")
  assert.equal((await h.api("POST", "collections/users/auth-refresh", {})).status, 401)
  assert.equal((await h.api("POST", "collections/users/auth-refresh", { token: "garbage" })).status, 401)
})

test("an invalid token is treated as anonymous: lists are empty (200), writes look like rejections", async () => {
  const list = await h.api("GET", "collections/plans/records", { token: "garbage" })
  assert.equal(list.status, 200)
  assert.deepEqual(list.body.items, [])
  const p = plan("alice")
  assert.equal((await h.create("alice", "plans", p)).status, 200)
  const created = await h.api("POST", "collections/plans/records", { token: "garbage", body: plan("alice") })
  assert.equal(created.status, 400)
  const current = (await h.get("alice", "plans", p.id)).body
  const updated = await h.api("PATCH", `collections/plans/records/${p.id}`, { token: "garbage", body: { title: "x", base_updated: current.updated } })
  assert.equal(updated.status, 404)
})

test("create: 200 returns the record with `updated`; the same ID again is 400 with data.id.code = validation_not_unique", async () => {
  const p = plan("alice")
  const first = await h.create("alice", "plans", p)
  assert.equal(first.status, 200)
  assert.match(first.body.updated, /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}Z$/)
  assert.equal(first.body.deleted, false)
  const again = await h.create("alice", "plans", p)
  assert.equal(again.status, 400)
  assert.equal(again.body.data.id.code, "validation_not_unique")
  // validation errors elsewhere do not look like that
  const invalid = await h.create("alice", "plans", plan("alice", { visibility: "weird" }))
  assert.equal(invalid.status, 400)
  assert.equal(invalid.body.data.id, undefined)
})

test("update: 200 returns `updated`; a missing base is 400, a stale base 409, a foreign record 404", async () => {
  const p = (await h.create("alice", "plans", plan("alice"))).body
  assert.equal((await h.update("alice", "plans", p.id, { title: "x" })).status, 400)
  assert.equal((await h.update("alice", "plans", p.id, { title: "x", base_updated: "2020-01-01 00:00:00.000Z" })).status, 409)
  assert.equal((await h.update("bob", "plans", p.id, { title: "x", base_updated: p.updated })).status, 404)
  const ok = await h.update("alice", "plans", p.id, { title: "x", base_updated: p.updated })
  assert.equal(ok.status, 200)
  assert.notEqual(ok.body.updated, p.updated)
})

test("list: a page object with items, page and totalPages; `updated >= cursor` sorted by updated includes the cursor record", async () => {
  const a = (await h.create("alice", "plans", plan("alice"))).body
  await new Promise((r) => setTimeout(r, 5))
  const b = (await h.create("alice", "plans", plan("alice"))).body
  const filter = encodeURIComponent(`updated >= "${a.updated}"`)
  const r = await h.api("GET", `collections/plans/records?perPage=1&page=1&sort=updated&filter=${filter}`, { token: h.as("alice") })
  assert.equal(r.status, 200)
  assert.equal(r.body.page, 1)
  assert.equal(r.body.totalPages, 2)
  assert.equal(r.body.items.length, 1)
  assert.equal(r.body.items[0].id, a.id)
  const second = await h.api("GET", `collections/plans/records?perPage=1&page=2&sort=updated&filter=${filter}`, { token: h.as("alice") })
  assert.equal(second.body.items[0].id, b.id)
})

test("soft-deleted records stay in lists for their owner (tombstones for sync)", async () => {
  const p = (await h.create("alice", "plans", plan("alice"))).body
  await h.update("alice", "plans", p.id, { deleted: true, base_updated: p.updated })
  const r = await h.api("GET", `collections/plans/records?filter=${encodeURIComponent(`id = "${p.id}"`)}`, { token: h.as("alice") })
  assert.equal(r.body.items[0].deleted, true)
})
