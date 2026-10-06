// The IndexedDB glue (src/atlas/store.ffi.mjs) against fake-indexeddb. Run with scripts/test-frontend-js.sh.
import "fake-indexeddb/auto"
import { test, before } from "node:test"
import assert from "node:assert/strict"
import { toList } from "../build/dev/javascript/atlas/gleam.mjs"
import * as store from "../build/dev/javascript/atlas/atlas/store.ffi.mjs"

const call = (fn, ...args) => new Promise((resolve) => fn(...args, (ok, value) => resolve({ ok, value })))
const list = (xs) => toList(xs)
const plan = (id, extra = {}) => ({ id, title: `Plan ${id}`, updated: "2026-10-06 08:00:00.100Z", deleted: false, ...extra })

before(async () => {
  assert.equal((await call(store.open, "atlas-test")).ok, true)
})

test("records are stored per collection and read back whole", async () => {
  assert.equal((await call(store.putRecords, "plans", list([plan("a"), plan("b")]))).ok, true)
  assert.equal((await call(store.putRecords, "workouts", list([{ id: "a", title: "same id, other collection" }]))).ok, true)
  const plans = (await call(store.getAll, "plans")).value.toArray()
  assert.deepEqual(plans.map((p) => p.id).sort(), ["a", "b"])
  assert.equal((await call(store.getRecord, "workouts", "a")).value.title, "same id, other collection")
  assert.equal((await call(store.getRecord, "plans", "a")).value.title, "Plan a")
})

test("a missing record is null, an empty collection an empty list", async () => {
  assert.equal((await call(store.getRecord, "plans", "nope")).value, null)
  assert.deepEqual((await call(store.getAll, "matches")).value.toArray(), [])
})

test("putting a record again replaces it", async () => {
  await call(store.putRecords, "plans", list([plan("r", { title: "old" })]))
  await call(store.putRecords, "plans", list([plan("r", { title: "new" })]))
  assert.equal((await call(store.getRecord, "plans", "r")).value.title, "new")
})

test("merging changes only the given fields and keeps the rest", async () => {
  await call(store.putRecords, "plans", list([plan("m", { description: "keep me" })]))
  assert.equal((await call(store.mergeJson, "plans", "m", '{"title":"edited","deleted":true}')).ok, true)
  const merged = (await call(store.getRecord, "plans", "m")).value
  assert.equal(merged.title, "edited")
  assert.equal(merged.deleted, true)
  assert.equal(merged.description, "keep me")
  assert.equal(merged.updated, "2026-10-06 08:00:00.100Z")
})

test("merging into a record that does not exist creates it with its ID", async () => {
  await call(store.mergeJson, "plans", "fresh", '{"title":"offline"}')
  assert.deepEqual((await call(store.getRecord, "plans", "fresh")).value, { title: "offline", id: "fresh" })
})

test("merging cannot change a record's ID", async () => {
  await call(store.mergeJson, "plans", "idfixed", '{"id":"other","title":"t"}')
  assert.equal((await call(store.getRecord, "plans", "idfixed")).value.id, "idfixed")
  assert.equal((await call(store.getRecord, "plans", "other")).value, null)
})

test("deleting a record removes only it", async () => {
  await call(store.putRecords, "plans", list([plan("d1"), plan("d2")]))
  await call(store.deleteRecord, "plans", "d1")
  assert.equal((await call(store.getRecord, "plans", "d1")).value, null)
  assert.equal((await call(store.getRecord, "plans", "d2")).value.id, "d2")
})

test("delete-missing keeps listed and protected records and only touches its collection", async () => {
  await call(store.clearAll)
  await call(store.putRecords, "plans", list([plan("keep"), plan("gone"), plan("local-edit")]))
  await call(store.putRecords, "workouts", list([{ id: "gone" }]))
  const result = await call(store.deleteMissing, "plans", list(["keep"]), list(["local-edit"]))
  assert.equal(result.value, 1)
  const left = (await call(store.getAll, "plans")).value.toArray().map((p) => p.id).sort()
  assert.deepEqual(left, ["keep", "local-edit"])
  assert.equal((await call(store.getRecord, "workouts", "gone")).value.id, "gone")
})

test("meta values round trip; a missing key reads as an empty string", async () => {
  assert.equal((await call(store.getMeta, "outbox")).value, "")
  await call(store.putMeta, "outbox", '{"entries":[]}')
  assert.equal((await call(store.getMeta, "outbox")).value, '{"entries":[]}')
  await call(store.putMeta, "outbox", "second")
  assert.equal((await call(store.getMeta, "outbox")).value, "second")
})

test("clear removes records and meta", async () => {
  await call(store.putRecords, "plans", list([plan("x")]))
  await call(store.putMeta, "owner", "u1")
  assert.equal((await call(store.clearAll)).ok, true)
  assert.deepEqual((await call(store.getAll, "plans")).value.toArray(), [])
  assert.equal((await call(store.getMeta, "owner")).value, "")
})

test("many records in one write are all stored", async () => {
  await call(store.clearAll)
  const many = Array.from({ length: 500 }, (_, i) => plan(`id${i}`))
  assert.equal((await call(store.putRecords, "plans", list(many))).ok, true)
  assert.equal((await call(store.getAll, "plans")).value.toArray().length, 500)
})

test("a failure is reported as ok=false, not thrown", async () => {
  // Open a throwaway database, then delete it from under the store: its connection closes
  // (onversionchange) and every later call must fail cleanly.
  assert.equal((await call(store.open, "atlas-doomed")).ok, true)
  await new Promise((resolve) => {
    const request = indexedDB.deleteDatabase("atlas-doomed")
    request.onsuccess = request.onerror = request.onblocked = resolve
  })
  const result = await call(store.getMeta, "k")
  assert.equal(result.ok, false)
  assert.equal(result.value, undefined)
})

test("record fields come out as names with JSON text, ready for the outbox", async () => {
  const pairs = store.recordFields({ id: "p1", title: 'A "q" plan', n: 3, flag: false, nothing: null, list: [1, 2] }).toArray()
  assert.deepEqual(pairs, [
    ["id", '"p1"'],
    ["title", '"A \\"q\\" plan"'],
    ["n", "3"],
    ["flag", "false"],
    ["nothing", "null"],
    ["list", "[1,2]"],
  ])
})
