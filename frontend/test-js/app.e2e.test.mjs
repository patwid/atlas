// The whole stack: the built app (jsdom) with a device IndexedDB (fake-indexeddb) against a real
// PocketBase. Needs the built frontend in backend/pb_public: scripts/test-frontend-js.sh builds it.
import "fake-indexeddb/auto"
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { JSDOM } from "jsdom"
import { toList } from "../build/dev/javascript/atlas/gleam.mjs"
import * as store from "../build/dev/javascript/atlas/atlas/store.ffi.mjs"
import { startPocketBase } from "../../backend/tests/harness.mjs"

const pub = join(dirname(fileURLToPath(import.meta.url)), "../../backend/pb_public")
const built = existsSync(join(pub, "atlas.js"))
const call = (fn, ...a) => new Promise((resolve) => fn(...a, (ok, value) => resolve({ ok, value })))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

let h
before(async () => { if (built) h = await startPocketBase({}, { publicDir: pub }) })
after(() => h?.stop())

const startApp = (path, session) => {
  const html = readFileSync(join(pub, "index.html"), "utf8").replace(/<script[^>]*src="\/atlas.js"[^>]*><\/script>/, "")
  const dom = new JSDOM(html, { url: h.url + path, runScripts: "outside-only", pretendToBeVisual: true })
  const w = dom.window
  // jsdom's AbortSignal is not Node's, so the signal is left out of the shim.
  w.fetch = (url, opts) => { const { signal, ...rest } = opts; return fetch(new URL(url, h.url), rest) }
  w.indexedDB = globalThis.indexedDB
  if (session) w.localStorage.setItem("atlas.session", JSON.stringify(session))
  w.eval(readFileSync(join(pub, "atlas.js"), "utf8"))
  return w
}

test("signed in with unsent offline work: pushes it, pulls the rest, keeps a conflicted copy, ends in sync", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const me = h.people.alice.id
  const token = h.people.alice.token
  const server = (method, path, body) => h.api(method, path, { token, body })
  const plan = (id, title) => server("POST", "collections/plans/records", { id, owner: me, title, visibility: "private" })

  await plan("serverplan00001", "Made on another device")
  const v1 = (await plan("conflictplan001", "Server title v1")).body
  await sleep(20)
  await server("PATCH", "collections/plans/records/conflictplan001", { title: "Server title v2", base_updated: v1.updated })

  // What the app would have left on this device after working offline.
  await call(store.open, "atlas")
  await call(store.putMeta, "owner", me)
  await call(store.mergeJson, "plans", "offlineplan0001", JSON.stringify({ title: "Made offline", owner: me, visibility: "private" }))
  await call(store.putRecords, "plans", toList([{ ...v1 }]))
  await call(store.mergeJson, "plans", "conflictplan001", JSON.stringify({ title: "My offline edit" }))
  const entry = (seq, id, kind, fields, base) => ({ seq, collection: "plans", id, kind, fields, base_updated: base, in_flight: false, attempts: 0 })
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 3,
    entries: [
      entry(1, "offlineplan0001", "create", { title: '"Made offline"', owner: JSON.stringify(me), visibility: '"private"' }, null),
      entry(2, "conflictplan001", "update", { title: '"My offline edit"' }, v1.updated),
    ],
  }))

  const w = startApp("/settings", { token, user_id: me, name: "alice", email: h.people.alice.email })
  let titles = []
  for (let i = 0; i < 60 && titles.length < 4; i++) {
    await sleep(100)
    titles = (await server("GET", "collections/plans/records?perPage=50&sort=title")).body.items.map((p) => p.title)
  }
  await sleep(500)

  const expected = ["Made offline", "Made on another device", "My offline edit (conflicted copy)", "Server title v2"]
  assert.deepEqual(titles, expected, "server")
  const local = (await call(store.getAll, "plans")).value.toArray()
  assert.deepEqual(local.map((p) => p.title).sort(), expected, "device")
  assert.ok(local.every((p) => p.updated), "every local record carries the server's `updated`")
  assert.deepEqual(JSON.parse((await call(store.getMeta, "outbox")).value).entries, [], "outbox is empty")
  assert.notEqual((await call(store.getMeta, "cursor:plans")).value, "", "cursor saved")
  const problems = [...w.document.querySelectorAll(".problems li")].map((li) => li.textContent)
  assert.equal(problems.length, 1)
  assert.match(problems[0], /Your version was kept as "My offline edit \(conflicted copy\)"/)
  w.close()
})

test("a different user on the same device starts with an empty database and cannot upload the first user's work", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const bob = h.people.bob
  await call(store.open, "atlas")
  await call(store.putMeta, "owner", "someone-else")
  await call(store.mergeJson, "plans", "leftoverplan001", JSON.stringify({ title: "Previous user's plan" }))
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 2,
    entries: [{ seq: 1, collection: "plans", id: "leftoverplan001", kind: "create", fields: { title: '"Previous user\'s plan"', owner: '"someone-else"', visibility: '"private"' }, base_updated: null, in_flight: false, attempts: 0 }],
  }))
  const w = startApp("/settings", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  await sleep(2500)
  assert.equal((await call(store.getMeta, "owner")).value, bob.id)
  assert.equal((await call(store.getRecord, "plans", "leftoverplan001")).value, null)
  const onServer = (await h.api("GET", "collections/plans/records?perPage=50", { token: bob.token })).body.items
  assert.deepEqual(onServer, [])
  w.close()
})

test("an expired session on the server signs the user out and keeps the device data", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const carol = h.people.carol
  await call(store.open, "atlas")
  await call(store.putMeta, "owner", carol.id)
  await call(store.mergeJson, "plans", "carolplan00001", JSON.stringify({ title: "Unsent plan", owner: carol.id, visibility: "private" }))
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 2,
    entries: [{ seq: 1, collection: "plans", id: "carolplan00001", kind: "create", fields: { title: '"Unsent plan"', owner: JSON.stringify(carol.id), visibility: '"private"' }, base_updated: null, in_flight: false, attempts: 0 }],
  }))
  // A token the server does not accept (it is anonymous to PocketBase) but that has not expired by its own clock.
  const forged = carol.token.split(".").slice(0, 2).join(".") + ".invalidsignature"
  const w = startApp("/settings", { token: forged, user_id: carol.id, name: "carol", email: carol.email })
  await sleep(2500)
  assert.ok(w.document.querySelector(".signin"), "back at the sign-in page")
  assert.match(w.document.querySelector(".error").textContent, /session expired/i)
  assert.equal(w.localStorage.getItem("atlas.session"), null)
  const stillQueued = JSON.parse((await call(store.getMeta, "outbox")).value).entries
  assert.equal(stillQueued.length, 1, "the unsent plan is still queued")
  assert.equal((await call(store.getRecord, "plans", "carolplan00001")).value.title, "Unsent plan")
  const onServer = (await h.api("GET", "collections/plans/records?perPage=50", { token: carol.token })).body.items
  assert.deepEqual(onServer, [], "and nothing reached the server")
  w.close()
})
