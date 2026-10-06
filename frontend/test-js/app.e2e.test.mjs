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

// Driving the plans screens through the DOM ---------------------------------------------------------

const waitFor = async (what, check, ms = 8000) => {
  const end = Date.now() + ms
  let last
  while (Date.now() < end) {
    try { last = await check(); if (last) return last } catch {}
    await sleep(50)
  }
  assert.fail(`timed out waiting for: ${what}`)
}
const click = (w, el) => el.dispatchEvent(new w.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }))
const typeInto = (w, el, value) => { el.value = value; el.dispatchEvent(new w.Event("input", { bubbles: true })) }
const submit = (w, form) => form.dispatchEvent(new w.Event("submit", { bubbles: true, cancelable: true }))
const button = (w, text) => [...w.document.querySelectorAll("button")].find((b) => b.textContent.trim() === text)

test("a user creates, edits and deletes a plan on the plans screens and the server follows", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const w = startApp("/plans", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const onServer = async () => (await h.api("GET", "collections/plans/records?perPage=50", { token: alice.token })).body.items

  await waitFor("the empty list", () => d.body.textContent.includes("You have no plans yet"))

  // Create
  click(w, button(w, "New plan"))
  await waitFor("the form", () => d.querySelector("#plan-title"))
  submit(w, d.querySelector("form"))
  await waitFor("a title error", () => d.querySelector(".error")?.textContent === "Give the plan a title.")
  assert.deepEqual(await onServer(), [], "an empty title is not sent")
  typeInto(w, d.querySelector("#plan-title"), "Autumn 10k")
  typeInto(w, d.querySelector("#plan-description"), "Eight weeks, three runs a week")
  submit(w, d.querySelector("form"))
  const link = await waitFor("the plan in the list", () => [...d.querySelectorAll(".cards a")].find((a) => a.textContent === "Autumn 10k"))
  const created = await waitFor("the plan on the server", async () => (await onServer()).find((p) => p.title === "Autumn 10k"))
  assert.equal(created.owner, alice.id)
  assert.equal(created.description, "Eight weeks, three runs a week")
  assert.equal(created.visibility, "private")
  assert.equal(link.getAttribute("href"), `/plans/${created.id}`)
  await waitFor("the synced marker", () => !d.body.textContent.includes("Not synced yet"))

  // Edit, on the plan's own screen
  click(w, link)
  await waitFor("the plan screen", () => d.querySelector("h2")?.textContent === "Autumn 10k" && button(w, "Edit"))
  assert.equal(w.location.pathname, `/plans/${created.id}`)
  click(w, button(w, "Edit"))
  await waitFor("the edit form", () => d.querySelector("#plan-title")?.value === "Autumn 10k")
  typeInto(w, d.querySelector("#plan-title"), "Autumn half marathon")
  submit(w, d.querySelector("form"))
  await waitFor("the new title on screen", () => d.querySelector("h2")?.textContent === "Autumn half marathon")
  await waitFor("the new title on the server", async () => (await onServer()).some((p) => p.title === "Autumn half marathon"))
  assert.equal((await onServer()).find((p) => p.id === created.id).description, "Eight weeks, three runs a week", "unchanged fields stay")

  // Delete, with the question first
  click(w, button(w, "Delete"))
  await waitFor("the question", () => d.body.textContent.includes("Delete this plan?"))
  assert.equal((await onServer()).find((p) => p.id === created.id).deleted, false, "asking does not delete")
  click(w, button(w, "Yes, delete it"))
  await waitFor("the plan marked deleted on the server", async () => (await onServer()).find((p) => p.id === created.id)?.deleted === true)
  click(w, [...d.querySelectorAll("a")].find((a) => a.textContent.includes("All plans")))
  await waitFor("an empty list again", () => d.body.textContent.includes("You have no plans yet"))
  w.close()
})

test("plans shared with the user show up read-only, and a pulled new plan appears without a reload", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  const w = startApp("/plans", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the empty list", () => d.body.textContent.includes("You have no plans yet"))
  // Alice publishes a plan while Bob has the app open; Bob's next sync brings it in.
  await h.create("alice", "plans", { id: "alicepublic0001", owner: alice.id, title: "Alice's public plan", visibility: "public" })
  w.dispatchEvent(new w.Event("offline"))
  w.dispatchEvent(new w.Event("online"))
  await waitFor("the shared plan", () => d.body.textContent.includes("Shared with you") && d.body.textContent.includes("Alice's public plan"))
  click(w, [...d.querySelectorAll(".cards a")].find((a) => a.textContent === "Alice's public plan"))
  await waitFor("the shared plan's screen", () => d.body.textContent.includes("Only its owner can change it"))
  assert.equal(button(w, "Edit"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  w.close()
})

// Workouts inside a plan ------------------------------------------------------------------------------

const choose = (w, select, value) => { select.value = value; select.dispatchEvent(new w.Event("change", { bubbles: true })) }
const byLabel = (w, label) => [...w.document.querySelectorAll("button")].find((b) => b.getAttribute("aria-label") === label)

test("the owner builds a plan's workouts: add, add to the same day, move, delete, and the server follows", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "baseplan0000001", owner: alice.id, title: "Base building", visibility: "private" })
  const w = startApp("/plans/baseplan0000001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const workouts = async () => (await h.api("GET", "collections/workouts/records?perPage=50&sort=day_index,position", { token: alice.token })).body.items

  await waitFor("the empty workouts", () => d.body.textContent.includes("This plan has no workouts yet. Add the first one."))

  // First workout: week 1, day 2, typed the way people type.
  click(w, button(w, "Add workout"))
  await waitFor("the form", () => d.querySelector("#workout-title"))
  choose(w, d.querySelector("#workout-day"), "2")
  submit(w, d.querySelector(".workout-form"))
  await waitFor("a title error", () => d.querySelector(".error")?.textContent === "Give the workout a title.")
  assert.deepEqual(await workouts(), [], "nothing is sent for an invalid form")
  typeInto(w, d.querySelector("#workout-title"), "Easy run")
  typeInto(w, d.querySelector("#workout-distance"), "8,5")
  typeInto(w, d.querySelector("#workout-duration"), "1:15")
  submit(w, d.querySelector(".workout-form"))
  const first = await waitFor("the workout on the server", async () => (await workouts())[0])
  assert.equal(first.plan, "baseplan0000001")
  assert.equal(first.title, "Easy run")
  assert.equal(first.kind, "easy")
  assert.equal(first.day_index, 1)
  assert.equal(first.position, 0)
  assert.equal(first.distance_m, 8500)
  assert.equal(first.duration_s, 4500)
  await waitFor("the workout on screen with its targets", () => d.body.textContent.includes("Easy run") && d.body.textContent.includes("8.50 km · 1:15:00"))
  await waitFor("the week total", () => d.querySelector(".totals")?.textContent.includes("8.50 km"))

  // A second workout on the same day, from that day's own "+ Add".
  click(w, byLabel(w, "Add a workout to week 1, day 2"))
  await waitFor("the form for day 2", () => d.querySelector("#workout-title") && d.querySelector("#workout-day").value === "2")
  typeInto(w, d.querySelector("#workout-title"), "Core session")
  choose(w, d.querySelector("#workout-kind"), "strength")
  submit(w, d.querySelector(".workout-form"))
  const second = await waitFor("the second workout", async () => (await workouts()).find((x) => x.title === "Core session"))
  assert.equal(second.kind, "strength")
  assert.equal(second.day_index, 1)
  assert.equal(second.position, 1, "it goes after the first one on that day")

  // Move the first workout to day 4 and rename it.
  click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Easy run")).querySelector("button"))
  await waitFor("the edit form", () => d.querySelector("#workout-title")?.value === "Easy run")
  assert.equal(d.querySelector("#workout-distance").value, "8.5")
  assert.equal(d.querySelector("#workout-duration").value, "1:15")
  choose(w, d.querySelector("#workout-day"), "4")
  typeInto(w, d.querySelector("#workout-title"), "Steady run")
  submit(w, d.querySelector(".workout-form"))
  const moved = await waitFor("the move on the server", async () => (await workouts()).find((x) => x.id === first.id && x.title === "Steady run"))
  assert.equal(moved.day_index, 3)
  assert.equal(moved.position, 0)
  assert.equal(moved.distance_m, 8500, "unchanged targets stay")

  // Delete the second one, after the question.
  const coreCard = () => [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Core session"))
  click(w, [...coreCard().querySelectorAll("button")].find((b) => b.textContent === "Delete"))
  await waitFor("the question", () => d.body.textContent.includes("Delete this workout?"))
  assert.equal((await workouts()).find((x) => x.id === second.id).deleted, false)
  click(w, button(w, "Yes, delete it"))
  await waitFor("the delete on the server", async () => (await workouts()).find((x) => x.id === second.id)?.deleted === true)
  await waitFor("gone from the screen", () => !d.body.textContent.includes("Core session"))
  w.close()
})

test("someone else's plan shows its workouts but offers no way to change them", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await h.create("alice", "plans", { id: "sharedplan00001", owner: alice.id, title: "Coach's plan", visibility: "public" })
  await h.create("alice", "workouts", { id: "sharedwork00001", plan: "sharedplan00001", day_index: 0, position: 0, title: "Hill repeats", kind: "interval", distance_m: 6000, duration_s: 2400 })
  const w = startApp("/plans/sharedplan00001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the shared workout", () => d.body.textContent.includes("Hill repeats") && d.body.textContent.includes("6.00 km · 40:00"))
  assert.equal(button(w, "Add workout"), undefined)
  assert.equal(byLabel(w, "Add a workout to week 1, day 1"), undefined)
  assert.equal(button(w, "Edit"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  w.close()
})

// Starting a plan -------------------------------------------------------------------------------------

test("a user starts a plan on a date, moves the date and removes it, and the server follows", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "sched0plan00001", owner: alice.id, title: "Base building", visibility: "private" })
  await h.create("alice", "workouts", { id: "sched0work00001", plan: "sched0plan00001", day_index: 27, position: 0, title: "Long run", kind: "long" })
  const w = startApp("/plans/sched0plan00001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const assignments = async () => (await h.api("GET", "collections/assignments/records?perPage=50", { token: alice.token })).body.items

  await waitFor("the empty schedule", () => d.body.textContent.includes("Nobody is following this plan yet. Pick a start date to begin."))
  click(w, button(w, "Start this plan"))
  await waitFor("the form", () => d.querySelector("#assign-start"))
  assert.equal(d.querySelector("#assign-athlete"), null, "with no coaching relationships there is nobody else to choose")
  typeInto(w, d.querySelector("#assign-start"), "")
  submit(w, d.querySelector(".schedule-form"))
  await waitFor("a date error", () => d.querySelector(".error")?.textContent === "Pick a start date.")
  assert.deepEqual(await assignments(), [])
  typeInto(w, d.querySelector("#assign-start"), "2026-11-02")
  submit(w, d.querySelector(".schedule-form"))
  const created = await waitFor("the assignment on the server", async () => (await assignments())[0])
  assert.equal(created.plan, "sched0plan00001")
  assert.equal(created.athlete, alice.id)
  assert.equal(created.assigned_by, alice.id)
  assert.equal(created.start_date, "2026-11-02")
  await waitFor("start and end with weekdays", () => d.body.textContent.includes("Starts Mon 2 Nov 2026") && d.body.textContent.includes("ends Sun 29 Nov 2026"))

  // Move it a week later.
  click(w, button(w, "Change date"))
  await waitFor("the date form", () => d.querySelector("#assign-start")?.value === "2026-11-02")
  typeInto(w, d.querySelector("#assign-start"), "2026-11-09")
  submit(w, d.querySelector(".schedule-form"))
  await waitFor("the new date on the server", async () => (await assignments())[0]?.start_date === "2026-11-09")
  await waitFor("the new dates on screen", () => d.body.textContent.includes("Starts Mon 9 Nov 2026") && d.body.textContent.includes("ends Sun 6 Dec 2026"))

  // Remove it, after the question.
  click(w, button(w, "Remove"))
  await waitFor("the question", () => d.body.textContent.includes("Remove this from the schedule?"))
  assert.equal((await assignments())[0].deleted, false)
  click(w, button(w, "Yes, remove it"))
  await waitFor("deleted on the server", async () => (await assignments())[0]?.deleted === true)
  await waitFor("an empty schedule again", () => d.body.textContent.includes("Nobody is following this plan yet"))
  w.close()
})

test("a public plan of someone else can be started, a private one shared with you cannot", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await h.create("alice", "plans", { id: "publicplan00001", owner: alice.id, title: "Public plan", visibility: "public" })
  await h.create("alice", "plans", { id: "privateplan0001", owner: alice.id, title: "Private plan", visibility: "private" })
  await h.create("alice", "plan_shares", { id: "share0000000001", plan: "privateplan0001", user: bob.id })

  const w = startApp("/plans/publicplan00001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the public plan", () => d.querySelector("h2")?.textContent === "Public plan" && button(w, "Start this plan"))
  click(w, button(w, "Start this plan"))
  await waitFor("the form", () => d.querySelector("#assign-start"))
  typeInto(w, d.querySelector("#assign-start"), "2026-12-07")
  submit(w, d.querySelector(".schedule-form"))
  const started = await waitFor("the assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items[0])
  assert.equal(started.athlete, bob.id)
  assert.equal(started.plan, "publicplan00001")

  // The private plan shared with Bob is readable, but the server would refuse a start, so none is offered.
  click(w, [...d.querySelectorAll("a")].find((a) => a.textContent.includes("All plans")))
  const privateLink = await waitFor("the private plan in the list", () => [...d.querySelectorAll(".cards a")].find((a) => a.textContent === "Private plan"))
  click(w, privateLink)
  await waitFor("the private plan's screen", () => d.querySelector("h2")?.textContent === "Private plan")
  await waitFor("the schedule section", () => d.body.textContent.includes("Nobody is following this plan yet."))
  assert.equal(button(w, "Start this plan"), undefined)
  w.close()
})
