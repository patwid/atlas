// The whole stack: the built app (jsdom) with a device IndexedDB (fake-indexeddb) against a real
// PocketBase. Needs the built frontend in backend/pb_public: scripts/test-frontend-js.sh builds it.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { toList } from "../build/dev/javascript/atlas/gleam.mjs"
import * as store from "../build/dev/javascript/atlas/atlas/store.ffi.mjs"
import { startPocketBase } from "../../backend/tests/harness.mjs"
import {
  appRunner, built, button, byLabel, call, location, choose, click, daysFromNow, dialogButton, openDialog, pick, pub, setup, sleep, submit, typeInto,
  utcOf, waitFor, ymd,
} from "./support.mjs"


let h
before(async () => { if (built) h = await startPocketBase({}, { publicDir: pub }) })
after(() => h?.stop())

const startApp = appRunner(() => h)

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
  submit(w, d.querySelector(".plan-form"))
  await waitFor("a title error", () => d.querySelector("[role=alert]")?.textContent === "Give the plan a title.")
  assert.deepEqual(await onServer(), [], "an empty title is not sent")
  typeInto(w, d.querySelector("#plan-title"), "Autumn 10k")
  typeInto(w, d.querySelector("#plan-description"), "Eight weeks, three runs a week")
  assert.equal(d.querySelector("#plan-base-weeks").value, "4", "phases start at 4 weeks each")
  typeInto(w, d.querySelector("#plan-competition-weeks"), "2")
  typeInto(w, d.querySelector("#plan-goal"), "35")
  submit(w, d.querySelector(".plan-form"))
  const link = await waitFor("the plan in the list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Autumn 10k"))
  const created = await waitFor("the plan on the server", async () => (await onServer()).find((p) => p.title === "Autumn 10k"))
  assert.equal(created.owner, alice.id)
  assert.equal(created.description, "Eight weeks, three runs a week")
  assert.equal(created.visibility, "private")
  assert.deepEqual([created.base_weeks, created.pre_competition_weeks, created.competition_weeks, created.weekly_distance_m], [4, 4, 2, 35000])
  assert.equal(link.getAttribute("href"), `/plans/${created.id}`)
  await waitFor("the synced marker", () => !d.body.textContent.includes("Not synced yet"))

  // Edit, on the plan's own screen
  click(w, link)
  await waitFor("the plan screen", () => d.querySelector(".bar h1")?.textContent === "Autumn 10k" && byLabel(w, "Edit plan"))
  assert.equal(w.location.pathname, `/plans/${created.id}`)
  click(w, byLabel(w, "Edit plan"))
  await waitFor("the edit form", () => d.querySelector("#plan-title")?.value === "Autumn 10k")
  typeInto(w, d.querySelector("#plan-title"), "Autumn half marathon")
  submit(w, d.querySelector(".plan-form"))
  await waitFor("the new title on screen", () => d.querySelector(".bar h1")?.textContent === "Autumn half marathon")
  await waitFor("the new title on the server", async () => (await onServer()).some((p) => p.title === "Autumn half marathon"))
  assert.equal((await onServer()).find((p) => p.id === created.id).description, "Eight weeks, three runs a week", "unchanged fields stay")

  // Delete: back to the list at once, with Undo; nothing is written until the snackbar goes (ADR 0056).
  click(w, button(w, "Delete"))
  await waitFor("the list with Undo", () => location(w) === "/plans" && d.body.textContent.includes("Plan deleted") && byLabel(w, "Close"))
  assert.equal((await onServer()).find((p) => p.id === created.id).deleted, false, "not yet deleted while Undo lasts")
  click(w, byLabel(w, "Close"))
  await waitFor("the plan marked deleted on the server", async () => (await onServer()).find((p) => p.id === created.id)?.deleted === true)
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
  click(w, [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Alice's public plan"))
  await waitFor("the shared plan's screen", () => d.body.textContent.includes("Only its owner can change it"))
  assert.equal(byLabel(w, "Edit plan"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  w.close()
})

// Workouts inside a plan ------------------------------------------------------------------------------


test("the owner builds a plan's workouts: add, add to the same day, move, delete, and the server follows", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "baseplan0000001", owner: alice.id, title: "Base building", visibility: "private" })
  const w = startApp("/plans/baseplan0000001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const workouts = async () => (await h.api("GET", "collections/workouts/records?perPage=50&sort=day_index,position", { token: alice.token })).body.items

  await waitFor("the empty workouts", () => d.body.textContent.includes("Add the first one with Add workout."))

  // First workout: week 1, day 2, typed the way people type.
  click(w, button(w, "Add workout"))
  await waitFor("the form", () => d.querySelector("#workout-title"))
  choose(w, d.querySelector("#workout-day"), "2")
  submit(w, d.querySelector(".workout-form"))
  await waitFor("a title error", () => d.querySelector("[role=alert]")?.textContent === "Give the workout a title.")
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
  await waitFor("the workout on screen with its targets", () => d.body.textContent.includes("Easy run") && d.body.textContent.includes("8.5 km · 1:15:00"))
  await waitFor("the week total", () => d.querySelector(".week-distance")?.textContent.includes("8.5 km"))

  // A second workout on the same day, from that day's own "+ Add".
  click(w, byLabel(w, "Add a workout to week 1, day 2"))
  await waitFor("the form for day 2", () => d.querySelector("#workout-title") && d.querySelector("#workout-day").value === "2")
  typeInto(w, d.querySelector("#workout-title"), "Core session")
  pick(w, "kind", "strength")
  submit(w, d.querySelector(".workout-form"))
  const second = await waitFor("the second workout", async () => (await workouts()).find((x) => x.title === "Core session"))
  assert.equal(second.kind, "strength")
  assert.equal(second.day_index, 1)
  assert.equal(second.position, 1, "it goes after the first one on that day")

  // Move the first workout to day 4 and rename it: the owner opens it straight in its form (ADR 0080).
  click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Easy run")))
  await waitFor("the edit form", () => d.querySelector("#workout-title")?.value === "Easy run")
  assert.equal(d.querySelector("#workout-dialog[open]"), null, "no details dialog under it")
  assert.equal(d.querySelector("#workout-distance").value, "8.5")
  assert.equal(d.querySelector("#workout-duration").value, "1:15")
  choose(w, d.querySelector("#workout-day"), "4")
  typeInto(w, d.querySelector("#workout-title"), "Steady run")
  submit(w, d.querySelector(".workout-form"))
  const moved = await waitFor("the move on the server", async () => (await workouts()).find((x) => x.id === first.id && x.title === "Steady run"))
  assert.equal(moved.day_index, 3)
  assert.equal(moved.position, 0)
  assert.equal(moved.distance_m, 8500, "unchanged targets stay")

  // Delete the second one; Undo brings it back, and the next delete is written when its snackbar is closed.
  const deleteCore = async () => {
    click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Core session")))
    await waitFor("the second workout in its form", () => d.querySelector("#workout-title")?.value === "Core session")
    click(w, byLabel(w, "Delete workout"))
    await waitFor("the Undo snackbar", () => d.body.textContent.includes("Workout deleted") && !d.querySelector(".calendar").textContent.includes("Core session"))
  }
  await deleteCore()
  click(w, button(w, "Undo"))
  await waitFor("back on the calendar", () => d.querySelector(".calendar").textContent.includes("Core session"))
  assert.equal((await workouts()).find((x) => x.id === second.id).deleted, false, "Undo wrote nothing")
  await deleteCore()
  click(w, byLabel(w, "Close"))
  await waitFor("the delete on the server", async () => (await workouts()).find((x) => x.id === second.id)?.deleted === true)
  await waitFor("gone from the screen", () => !d.body.textContent.includes("Core session"))
  w.close()
})

test("the owner sets a week's intensity in its dialog and the plan's phases and goal with Edit (ADR 0043, 0066)", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "phaseplan000001", owner: alice.id, title: "Season", visibility: "private", base_weeks: 2, pre_competition_weeks: 1, competition_weeks: 1 })
  await h.create("alice", "workouts", { id: "phasework000001", plan: "phaseplan000001", day_index: 7, position: 0, title: "Long run", kind: "long", distance_m: 20000 })
  const w = startApp("/plans/phaseplan000001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const onServer = async () => (await h.get("alice", "plans", "phaseplan000001")).body

  await waitFor("the phases as bands", () => ["Base phase", "Pre-competition phase", "Competition phase"].every((t) => d.body.textContent.includes(t)))
  assert.equal(d.querySelectorAll(".calendar-week").length, 4, "every phase week is there, also the empty ones")

  // Select week 2 and make it a hard week.
  click(w, [...d.querySelectorAll(".week-label")].find((b) => b.textContent.startsWith("Week 2")))
  await waitFor("week 2 in its dialog", () => d.querySelector("#week-dialog[open]")?.textContent.includes("Week 2 · Base 2"))
  assert.equal(d.querySelector("#week-intensity").type, "range")
  choose(w, d.querySelector("#week-intensity"), "0.8")
  await waitFor("the intensity on the server", async () => (await onServer()).week_intensity?.[1] === 0.8)
  await waitFor("the intensity in the calendar", () => d.querySelector(".calendar-week.selected .intensity-high")?.textContent === "Intensity 80%")

  // Set a 40 km goal and a longer base phase.
  // The phases and goal are part of the plan, changed with its Edit (ADR 0066).
  click(w, byLabel(w, "Edit plan"))
  await waitFor("the plan form", () => d.querySelector("#plan-goal"))
  typeInto(w, d.querySelector("#plan-goal"), "40")
  typeInto(w, d.querySelector("#plan-base-weeks"), "3")
  submit(w, d.querySelector(".plan-form"))
  await waitFor("the settings on the server", async () => {
    const p = await onServer()
    return p.weekly_distance_m === 40000 && p.base_weeks === 3
  })
  // Week 2 is at 80%, so it aims for 80% of 40 km (ADR 0064).
  await waitFor("the week against its goal, in its row", () => d.querySelector(".calendar")?.textContent.includes("20 / 32 km"))
  click(w, [...d.querySelectorAll(".week-label")].find((b) => b.textContent.startsWith("Week 2")))
  await waitFor("and in its dialog", () => d.querySelector("#week-dialog[open]")?.textContent.includes("20 km of 32 km (63%)"))
  await waitFor("five weeks now", () => d.querySelectorAll(".calendar-week").length === 5)
  assert.equal((await onServer()).week_intensity[1], 0.8, "the intensity stays")
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
  await waitFor("the shared workout", () => d.body.textContent.includes("Hill repeats") && d.body.textContent.includes("6 km · 40:00"))
  assert.equal(button(w, "Add workout"), undefined)
  assert.equal(byLabel(w, "Add a workout to week 1, day 1"), undefined)
  assert.equal(byLabel(w, "Edit plan"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  // A workout opens read-only in its dialog.
  click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Hill repeats")))
  await waitFor("the workout in its dialog", () => d.querySelector("#workout-dialog[open]")?.textContent.includes("Week 1 · day 1"))
  assert.equal(d.querySelector("#workout-title"), null)
  assert.equal(byLabel(w, "Delete workout"), undefined)
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

  await waitFor("the empty schedule", () => d.body.textContent.includes("Use Start this plan to begin."))
  click(w, button(w, "Start this plan"))
  await waitFor("the form", () => d.querySelector("#assign-start"))
  assert.equal(d.querySelector("#assign-athlete"), null, "with no coaching relationships there is nobody else to choose")
  typeInto(w, d.querySelector("#assign-start"), "")
  submit(w, d.querySelector(".schedule-form"))
  await waitFor("a date error", () => d.querySelector("[role=alert]")?.textContent === "Pick a start date.")
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

  // Remove it, from its menu; it is written when the Undo snackbar is closed.
  click(w, button(w, "Remove"))
  await waitFor("the Undo snackbar", () => d.body.textContent.includes("Removed from the schedule"))
  assert.equal((await assignments())[0].deleted, false)
  click(w, byLabel(w, "Close"))
  await waitFor("deleted on the server", async () => (await assignments())[0]?.deleted === true)
  await waitFor("an empty schedule again", () => d.body.textContent.includes("Nobody is following this plan yet"))
  w.close()
})

test("a public plan of someone else can be started, and so can a private one that is shared with you", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await h.create("alice", "plans", { id: "publicplan00001", owner: alice.id, title: "Public plan", visibility: "public" })
  await h.create("alice", "plans", { id: "privateplan0001", owner: alice.id, title: "Private plan", visibility: "private" })
  await h.create("alice", "plan_shares", { id: "share0000000001", plan: "privateplan0001", user: bob.id })

  const w = startApp("/plans/publicplan00001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the public plan", () => d.querySelector(".bar h1")?.textContent === "Public plan" && button(w, "Start this plan"))
  click(w, button(w, "Start this plan"))
  await waitFor("the form", () => d.querySelector("#assign-start"))
  typeInto(w, d.querySelector("#assign-start"), "2026-12-07")
  submit(w, d.querySelector(".schedule-form"))
  const started = await waitFor("the assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items[0])
  assert.equal(started.athlete, bob.id)
  assert.equal(started.plan, "publicplan00001")

  // The private plan that is shared with Bob can be started too (ADR 0029): a share is enough.
  click(w, d.querySelector('a[aria-label="All plans"]'))
  const privateLink = await waitFor("the private plan in the list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Private plan"))
  click(w, privateLink)
  await waitFor("the private plan's screen", () => d.querySelector(".bar h1")?.textContent === "Private plan")
  click(w, await waitFor("the start button", () => button(w, "Start this plan")))
  await waitFor("the start form", () => d.querySelector("#assign-start"))
  typeInto(w, d.querySelector("#assign-start"), "2026-12-14")
  submit(w, d.querySelector(".schedule-form"))
  await waitFor("the second assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items.some((a) => a.plan === "privateplan0001"))
  w.close()
})


// Training zones -------------------------------------------------------------------------------------

test("training zones start as the defaults, are saved under the athlete's ID, and a second device's offline save updates the same row", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const settings = async () => (await h.api("GET", "collections/athlete_settings/records?perPage=50", { token: alice.token })).body.items
  const zones = (row) => [row.max_hr, row.hr_zone1_min, row.hr_zone2_min, row.hr_zone3_min, row.hr_zone4_min, row.hr_zone5_min]
  const lactate = (row) => [1, 2, 3, 4, 5].map((n) => row[`lactate_zone${n}_min`])
  const pace = (row) => [row.threshold_pace_s, ...[1, 2, 3, 4, 5].map((n) => row[`pace_zone${n}_start_s`])]

  // 1. Nothing saved: the form shows the defaults. Change zone 2 and save.
  let w = startApp("/settings/zones", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  let d = w.document
  await waitFor("the default zones", () => d.body.textContent.includes("These are the default zones"))
  assert.equal(d.querySelector("#hr-max").value, "190")
  assert.deepEqual([1, 2, 3, 4, 5].map((n) => d.querySelector(`#hr-zone-${n}`).value), ["95", "114", "133", "152", "171"])
  assert.deepEqual([1, 2, 3, 4, 5].map((n) => d.querySelector(`#lactate-zone-${n}`).value), ["1.0", "1.5", "2.5", "4.0", "6.0"])
  typeInto(w, d.querySelector("#hr-zone-2"), "120")
  typeInto(w, d.querySelector("#lactate-zone-3"), "2,8")
  assert.equal(d.querySelector("#pace-threshold").value, "5:00")
  assert.deepEqual([1, 2, 3, 4, 5].map((n) => d.querySelector(`#pace-zone-${n}`).value), ["7:00", "6:27", "5:42", "5:18", "4:57"])
  typeInto(w, d.querySelector("#pace-threshold"), "4:00")
  click(w, button(w, "Calculate pace zones"))
  await waitFor("the pace zones worked out", () => d.querySelector("#pace-zone-1").value === "5:36")
  submit(w, d.querySelector(".zones-form"))
  const row = await waitFor("the zones on the server", async () => (await settings())[0])
  assert.equal(row.id, alice.id)
  assert.equal(row.owner, alice.id)
  assert.deepEqual(zones(row), [190, 95, 120, 133, 152, 171])
  assert.deepEqual(lactate(row), [1, 1.5, 2.8, 4, 6])
  assert.deepEqual(pace(row), [240, 336, 309, 273, 254, 237])
  w.close()

  // 2. Another device that never pulled the row saved its own zones offline: its create becomes an update.
  await call(store.open, "atlas")
  await call(store.clearAll)
  await call(store.putMeta, "owner", alice.id)
  const fields = { owner: JSON.stringify(alice.id), max_hr: "200", hr_zone1_min: "100", hr_zone2_min: "120", hr_zone3_min: "140", hr_zone4_min: "160", hr_zone5_min: "180", lactate_zone1_min: "0.8", lactate_zone2_min: "1.6", lactate_zone3_min: "2.6", lactate_zone4_min: "4.2", lactate_zone5_min: "6.5", threshold_pace_s: "270", pace_zone1_start_s: "420", pace_zone2_start_s: "360", pace_zone3_start_s: "315", pace_zone4_start_s: "285", pace_zone5_start_s: "260" }
  await call(store.mergeJson, "athlete_settings", alice.id, JSON.stringify(Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, JSON.parse(v)]))))
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 2,
    entries: [{ seq: 1, collection: "athlete_settings", id: alice.id, kind: "create", fields, base_updated: null, in_flight: false, attempts: 0 }],
  }))
  w = startApp("/settings/zones", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  d = w.document
  await waitFor("the second device's zones on the server", async () => (await settings())[0]?.max_hr === 200)
  const rows = await settings()
  assert.equal(rows.length, 1, "still one row")
  assert.deepEqual(zones(rows[0]), [200, 100, 120, 140, 160, 180])
  assert.deepEqual(lactate(rows[0]), [0.8, 1.6, 2.6, 4.2, 6.5])
  assert.deepEqual(pace(rows[0]), [270, 420, 360, 315, 285, 260])
  await waitFor("the outbox empty", async () => JSON.parse((await call(store.getMeta, "outbox")).value).entries.length === 0)
  assert.equal(d.querySelectorAll(".problems li").length, 0, "no problems shown")
  assert.equal(d.querySelector("#hr-max").value, "200")
  assert.equal(d.querySelector("#lactate-zone-5").value, "6.5")
  assert.equal(d.querySelector("#pace-zone-5").value, "4:20")
  w.close()
})

// Coaching -------------------------------------------------------------------------------------------

test("an athlete adds a coach by e-mail, the coach assigns a plan, and the athlete finds it on her schedule", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  const grants = async () => (await h.api("GET", "collections/coach_grants/records?perPage=50", { token: alice.token })).body.items

  // 1. Alice gives Bob access. Looking him up and confirming are separate steps.
  let w = startApp("/settings/coaches", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  let d = w.document
  await waitFor("the coaches section", () => d.body.textContent.includes("Nobody can see your training"))
  typeInto(w, d.querySelector("#coach-email"), "nobody@example.com")
  submit(w, d.querySelector(".coach-form"))
  await waitFor("a not-found message", () => d.body.textContent.includes("Nobody with this e-mail address uses Atlas."))
  typeInto(w, d.querySelector("#coach-email"), bob.email)
  submit(w, d.querySelector(".coach-form"))
  await waitFor("the person found", () => d.body.textContent.includes("Found bob. Let them see your training?"))
  assert.deepEqual(await grants(), [], "finding someone gives no access yet")
  click(w, button(w, "Give access"))
  const grant = await waitFor("the grant on the server", async () => (await grants())[0])
  assert.equal(grant.athlete, alice.id)
  assert.equal(grant.coach, bob.id)
  assert.equal(grant.athlete_name, "alice")
  assert.equal(grant.coach_name, "bob")
  await waitFor("bob in her list", () => d.querySelector(".coaches .list")?.textContent.includes("bob"))
  w.close()

  // 2. Bob, who owns a plan, starts it for Alice.
  await setup(h.create("bob", "plans", { id: "coachplan000001", owner: bob.id, title: "Coach's base plan", visibility: "private" }))
  await setup(h.create("bob", "workouts", { id: "coachwork000001", plan: "coachplan000001", day_index: 0, position: 0, title: "Easy run", kind: "easy", distance_m: 5000 }))
  w = startApp("/plans/coachplan000001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  d = w.document
  await waitFor("the assign button, which needs the grant on his device", () => button(w, "Start or assign"))
  click(w, button(w, "Start or assign"))
  await waitFor("the form with athletes", () => d.querySelector("#assign-athlete"))
  const options = [...d.querySelectorAll("#assign-athlete option")].map((o) => o.textContent)
  assert.deepEqual(options, ["Myself", "alice"])
  choose(w, d.querySelector("#assign-athlete"), alice.id)
  typeInto(w, d.querySelector("#assign-start"), "2026-11-02")
  submit(w, d.querySelector(".schedule-form"))
  const assignment = await waitFor("the assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items[0])
  assert.equal(assignment.athlete, alice.id)
  assert.equal(assignment.assigned_by, bob.id)
  await waitFor("alice by name on his schedule", () => d.body.textContent.includes("alice") && d.body.textContent.includes("Starts Mon 2 Nov 2026"))
  w.close()

  // 3. Alice opens the app and finds the plan on her schedule.
  w = startApp("/plans", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  d = w.document
  const link = await waitFor("the coach's plan in her list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Coach's base plan"))
  click(w, link)
  await waitFor("the plan screen with its schedule", () => d.body.textContent.includes("Assigned by bob") && d.body.textContent.includes("Starts Mon 2 Nov 2026"))
  assert.ok(d.body.textContent.includes("Easy run"), "the coach's workouts are readable through the assignment")
  assert.equal(button(w, "Start this plan"), undefined, "a private plan of someone else cannot be started")
  assert.equal(byLabel(w, "Edit plan"), undefined, "and its workouts cannot be changed")
  assert.ok(button(w, "Change date"), "but the athlete can move her own start date")
  w.close()

  // 4. Taking access back removes it for the coach.
  w = startApp("/settings/coaches", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  d = w.document
  await waitFor("the coach in the list", () => d.querySelector(".coaches .list")?.textContent.includes("bob"))
  click(w, button(w, "Remove access"))
  await waitFor("the question", () => openDialog(w)?.textContent.includes("bob can no longer see your training."))
  click(w, dialogButton(w, "Remove"))
  await waitFor("the grant deleted on the server", async () => (await grants())[0]?.deleted === true)
  await waitFor("nobody listed", () => d.body.textContent.includes("Nobody can see your training"))
  const bobsView = await h.api("GET", `collections/coach_grants/records/${grant.id}`, { token: bob.token })
  assert.equal(bobsView.status, 404, "the coach can no longer see the grant")
  w.close()
})

// Entering an activity by hand ----------------------------------------------------------------------------

test("a user adds, edits and deletes an activity by hand; the start is stored in UTC and shown in local time; Strava rows are read-only", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await setup(h.create("admin", "activities", {
    id: "stravarow000001", owner: alice.id, source: "strava", external_id: "42",
    started_at: "2026-09-20 06:00:00.000Z", sport: "run", name: "Lunch run", distance_m: 5000, moving_time_s: 1500,
  }))
  const w = startApp("/activities", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const activities = async () => (await h.api("GET", "collections/activities/records?perPage=50&sort=started_at", { token: alice.token })).body.items

  await waitFor("the Strava activity", () => d.body.textContent.includes("Lunch run"))
  const stravaCard = [...d.querySelectorAll(".list li")].find((li) => li.textContent.includes("Lunch run"))
  assert.ok(stravaCard.textContent.includes("Strava"))
  assert.equal([...stravaCard.querySelectorAll("button")].length, 0, "Strava activities cannot be changed here")

  click(w, button(w, "Add activity"))
  await waitFor("the form", () => d.querySelector("#activity-date"))
  typeInto(w, d.querySelector("#activity-date"), "2026-10-05")
  typeInto(w, d.querySelector("#activity-time"), "07:30")
  submit(w, d.querySelector(".activity-form"))
  await waitFor("a distance or time error", () => d.querySelector("[role=alert]")?.textContent === "Enter a distance or a duration, or both.")
  assert.equal((await activities()).length, 1, "nothing is sent for an invalid form")
  pick(w, "sport", "trail_run")
  typeInto(w, d.querySelector("#activity-name"), "Morning loop")
  typeInto(w, d.querySelector("#activity-distance"), "8,5")
  typeInto(w, d.querySelector("#activity-duration"), "1:05")
  typeInto(w, d.querySelector("#activity-elevation"), "120")
  typeInto(w, d.querySelector("#activity-hr"), "152")
  submit(w, d.querySelector(".activity-form"))
  const created = await waitFor("the activity on the server", async () => (await activities()).find((a) => a.name === "Morning loop"))
  assert.equal(created.owner, alice.id)
  assert.equal(created.source, "manual")
  assert.equal(created.sport, "trail_run")
  assert.equal(created.distance_m, 8500)
  assert.equal(created.moving_time_s, 3900)
  assert.equal(created.elevation_gain_m, 120)
  assert.equal(created.avg_hr, 152)
  // 07:30 local time on 5 October 2026, converted by the browser's own time zone rules.
  const expectedUtc = new Date(2026, 9, 5, 7, 30).toISOString().replace("T", " ")
  assert.equal(created.started_at, expectedUtc)
  await waitFor("it on screen in local time", () => d.body.textContent.includes("Mon 5 Oct 2026, 07:30") && d.body.textContent.includes("8.50 km"))

  // Edit: only the name changes. The row opens the form (ADR 0080).
  const card = () => [...d.querySelectorAll(".list li")].find((li) => li.textContent.includes("Morning loop") || li.textContent.includes("Easy loop"))
  click(w, card().querySelector(".row-link"))
  await waitFor("the edit form with local values", () => d.querySelector("#activity-time")?.value === "07:30" && d.querySelector("#activity-date")?.value === "2026-10-05")
  assert.equal(d.querySelector("#activity-distance").value, "8.5")
  assert.equal(d.querySelector("#activity-duration").value, "1:05")
  typeInto(w, d.querySelector("#activity-name"), "Easy loop")
  submit(w, d.querySelector(".activity-form"))
  await waitFor("the new name on the server", async () => (await activities()).some((a) => a.id === created.id && a.name === "Easy loop"))
  const after = (await activities()).find((a) => a.id === created.id)
  assert.equal(after.started_at, expectedUtc, "the start is untouched")
  assert.equal(after.distance_m, 8500)

  // Delete, from its form; it is written when the Undo snackbar is closed.
  click(w, card().querySelector(".row-link"))
  await waitFor("the form again", () => d.querySelector("#activity-name")?.value === "Easy loop")
  click(w, byLabel(w, "Delete activity"))
  await waitFor("the Undo snackbar", () => d.body.textContent.includes("Activity deleted"))
  assert.equal((await activities()).find((a) => a.id === created.id).deleted, false)
  click(w, byLabel(w, "Close"))
  await waitFor("deleted on the server", async () => (await activities()).find((a) => a.id === created.id)?.deleted === true)
  await waitFor("gone from the list", () => !d.body.textContent.includes("Easy loop"))
  assert.ok(d.body.textContent.includes("Lunch run"), "the Strava activity is still there")
  w.close()
})

// The Today screen ------------------------------------------------------------------------------------


test("Today shows missed, looks-done and rest days; the user confirms, unlinks, re-links and links by hand", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const yesterday = daysFromNow(-1)
  const today = daysFromNow(0)
  await setup(h.create("alice", "plans", { id: "todayplan000001", owner: alice.id, title: "Tempo block", visibility: "private" }))
  await setup(h.create("alice", "workouts", { id: "todaywork000001", plan: "todayplan000001", day_index: 0, position: 0, title: "Easy shake-out", kind: "easy", distance_m: 5000 }))
  await setup(h.create("alice", "workouts", { id: "todaywork000002", plan: "todayplan000001", day_index: 1, position: 0, title: "Tempo intervals", kind: "tempo", distance_m: 8000, duration_s: 2700 }))
  await setup(h.create("alice", "workouts", { id: "todaywork000003", plan: "todayplan000001", day_index: 2, position: 0, title: "Recovery day", kind: "rest" }))
  // The plan started yesterday: day 0 is yesterday (missed), day 1 today, day 2 tomorrow.
  await setup(h.create("alice", "assignments", { id: "todayasg0000001", plan: "todayplan000001", athlete: alice.id, assigned_by: alice.id, start_date: ymd(yesterday) }))
  const activity = (id, day, hour, name) => setup(h.create("alice", "activities", {
    id, owner: alice.id, source: "manual", started_at: utcOf(day, hour, 0), sport: "run", name, distance_m: 8000, moving_time_s: 2700,
  }))
  await activity("todayact0000001", today, 7, "Morning tempo")
  const matches = async () => (await h.api("GET", "collections/matches/records?perPage=50", { token: alice.token })).body.items

  const w = startApp("/", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const card = (title) => [...d.querySelectorAll(".item")].find((li) => li.textContent.includes(title))
  const inCard = (title, text) => [...card(title).querySelectorAll("button")].find((b) => b.textContent.trim() === text)

  await waitFor("today's tempo workout as a suggestion", () => card("Tempo intervals")?.textContent.includes("Looks done") && card("Tempo intervals").textContent.includes("07:00 · Run · 8.00 km · 45:00"))
  assert.ok(card("Easy shake-out").textContent.includes("Missed"), "yesterday's workout without a run is missed")
  assert.ok(card("Recovery day").textContent.includes("Rest day"))
  assert.deepEqual(await matches(), [], "a suggestion is not stored")

  // Confirm the suggestion: now it is a stored match.
  click(w, inCard("Tempo intervals", "Confirm"))
  const first = await waitFor("the match on the server", async () => (await matches())[0])
  assert.equal(first.owner, alice.id)
  assert.equal(first.activity, "todayact0000001")
  assert.equal(first.workout, "todaywork000002")
  assert.equal(first.assignment, "todayasg0000001")
  await waitFor("done, confirmed", () => card("Tempo intervals").querySelector(".status-done")?.textContent === "Done" && card("Tempo intervals").textContent.includes("07:00") && inCard("Tempo intervals", "Unlink"))

  // Unlink it: the row is removed on the server and the suggestion returns.
  click(w, inCard("Tempo intervals", "Unlink"))
  await waitFor("the Undo snackbar", () => d.body.textContent.includes("Activity unlinked") && button(w, "Undo"))
  await waitFor("the row removed", async () => (await matches())[0]?.deleted === true)
  await waitFor("the suggestion again", () => card("Tempo intervals").textContent.includes("Looks done"))

  // Link the same activity again: the removed row is reused, not duplicated.
  click(w, inCard("Tempo intervals", "Confirm"))
  await waitFor("the same row live again", async () => { const all = await matches(); return all.length === 1 && all[0].id === first.id && all[0].deleted === false })

  // Yesterday's run is not on the device until it is added; then link it to the missed workout by hand.
  await activity("todayact0000002", yesterday, 18, "Evening jog")
  w.dispatchEvent(new w.Event("offline"))
  w.dispatchEvent(new w.Event("online"))
  await waitFor("the missed workout to offer activities", () => inCard("Easy shake-out", "Link activity"))
  click(w, inCard("Easy shake-out", "Link activity"))
  await waitFor("the list with yesterday's run", () => d.body.textContent.includes("Which activity was it?") && d.body.textContent.includes("18:00 · Run"))
  click(w, d.querySelector(".choice-dialog[open] .choice-row"))
  await waitFor("the second match on the server", async () => (await matches()).some((m) => m.activity === "todayact0000002" && m.workout === "todaywork000001"))
  await waitFor("done by hand", () => card("Easy shake-out").querySelector(".status-done")?.textContent === "Done" && card("Easy shake-out").textContent.includes("18:00"))
  assert.equal((await matches()).length, 2)
  w.close()
})

test("Today without a plan points to the plans", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const bob = h.people.bob
  const w = startApp("/", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  await waitFor("the empty state", () => w.document.body.textContent.includes("You are not following a plan yet"))
  assert.equal(w.document.querySelector('a[href="/plans"]')?.textContent, "Go to plans")
  w.close()
})

// Copying a plan --------------------------------------------------------------------------------------

test("a user copies someone else's public plan with its workouts, then edits the copy; the original is untouched", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await setup(h.create("alice", "plans", { id: "copysrcplan0001", owner: alice.id, title: "Autumn 10k", description: "Eight weeks", visibility: "public" }))
  await setup(h.create("alice", "workouts", { id: "copysrcwork0001", plan: "copysrcplan0001", day_index: 3, position: 0, title: "Tempo", kind: "tempo", description: "3 x 10 min", distance_m: 8000, duration_s: 2700 }))
  await setup(h.create("alice", "workouts", { id: "copysrcwork0002", plan: "copysrcplan0001", day_index: 0, position: 0, title: "Easy run", kind: "easy", distance_m: 5000 }))

  const w = startApp("/plans/copysrcplan0001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  const mine = async () => (await h.api("GET", "collections/plans/records?perPage=50", { token: bob.token })).body.items.filter((p) => p.owner === bob.id)
  const workoutsOf = async (planId) =>
    (await h.api("GET", `collections/workouts/records?perPage=50&sort=day_index&filter=${encodeURIComponent(`plan = "${planId}"`)}`, { token: bob.token })).body.items

  await waitFor("the plan with its workouts", () => d.querySelector(".bar h1")?.textContent === "Autumn 10k" && d.body.textContent.includes("Easy run") && d.body.textContent.includes("Tempo"))
  assert.equal(byLabel(w, "Edit plan"), undefined, "someone else's plan cannot be edited")
  click(w, byLabel(w, "Copy to my plans"))
  await waitFor("the confirmation with a link", () => d.body.textContent.includes("Copied to your plans.") && [...d.querySelectorAll("a")].some((a) => a.textContent === "Open your copy"))
  assert.equal(byLabel(w, "Copy to my plans"), undefined, "a second click is not possible while the copy is shown")

  const copy = await waitFor("the copy on the server", async () => (await mine())[0])
  assert.equal(copy.title, "Copy of Autumn 10k")
  assert.equal(copy.description, "Eight weeks")
  assert.equal(copy.visibility, "private", "a copy of a public plan starts private")
  assert.equal(copy.source_plan, "copysrcplan0001")
  const copied = await waitFor("both workouts on the server", async () => { const ws = await workoutsOf(copy.id); return ws.length === 2 && ws })
  assert.deepEqual(copied.map((x) => [x.title, x.day_index, x.kind]), [["Easy run", 0, "easy"], ["Tempo", 3, "tempo"]])
  assert.equal(copied[1].description, "3 x 10 min")
  assert.equal(copied[1].distance_m, 8000)
  assert.equal(copied[1].duration_s, 2700)

  // The original has not changed.
  const original = (await h.api("GET", "collections/plans/records/copysrcplan0001", { token: alice.token })).body
  assert.equal(original.title, "Autumn 10k")
  assert.equal((await workoutsOf("copysrcplan0001")).length, 2)

  // The copy is Bob's: he opens it and can change it.
  click(w, [...d.querySelectorAll("a")].find((a) => a.textContent === "Open your copy"))
  await waitFor("the copy's screen with edit", () => d.querySelector(".bar h1")?.textContent === "Copy of Autumn 10k" && byLabel(w, "Edit plan"))
  assert.ok(d.body.textContent.includes("Tempo") && d.body.textContent.includes("Easy run"), "the workouts came along")
  click(w, byLabel(w, "Edit plan"))
  await waitFor("the edit form", () => d.querySelector("#plan-title")?.value === "Copy of Autumn 10k")
  typeInto(w, d.querySelector("#plan-title"), "My autumn 10k")
  submit(w, d.querySelector(".plan-form"))
  await waitFor("the rename on the server", async () => (await mine()).some((p) => p.title === "My autumn 10k"))
  assert.equal((await h.api("GET", "collections/plans/records/copysrcplan0001", { token: alice.token })).body.title, "Autumn 10k")
  w.close()
})

// Sharing a plan with named people -------------------------------------------------------------------------

test("an owner shares a private plan by e-mail, the recipient reads and starts it, and stopping and sharing again reuses the row", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  const carol = h.people.carol
  await setup(h.create("alice", "plans", { id: "winterplan00001", owner: alice.id, title: "Winter base", visibility: "private" }))
  await setup(h.create("alice", "workouts", { id: "winterwork00001", plan: "winterplan00001", day_index: 0, position: 0, title: "Easy hour", kind: "easy", duration_s: 3600 }))
  const shares = async () => (await h.api("GET", "collections/plan_shares/records?perPage=50", { token: alice.token })).body.items
  const seesPlan = async (who) => (await h.api("GET", "collections/plans/records/winterplan00001", { token: who.token })).status === 200

  // Alice shares with Bob. Finding him gives him nothing until she confirms.
  let w = startApp("/plans/winterplan00001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  let d = w.document
  await waitFor("the sharing section", () => d.body.textContent.includes("Not shared with anyone"))
  assert.equal(await seesPlan(bob), false, "private to start with")
  typeInto(w, d.querySelector("#share-email"), bob.email)
  submit(w, d.querySelector(".share-form"))
  await waitFor("the person found", () => d.body.textContent.includes("Found bob. Share this plan with them?"))
  assert.deepEqual(await shares(), [], "finding someone shares nothing")
  click(w, button(w, "Share plan"))
  const bobShare = await waitFor("the share on the server", async () => (await shares())[0])
  assert.equal(bobShare.plan, "winterplan00001")
  assert.equal(bobShare.user, bob.id)
  assert.equal(bobShare.user_name, "bob")
  assert.equal(bobShare.shared_by_name, "alice")
  await waitFor("bob in the list", () => d.querySelector(".sharing .list")?.textContent.includes("bob"))
  assert.equal(await seesPlan(bob), true)
  // Sharing with someone who already has it is refused before anything is sent.
  typeInto(w, d.querySelector("#share-email"), bob.email)
  submit(w, d.querySelector(".share-form"))
  await waitFor("the refusal", () => d.body.textContent.includes("bob already has this plan."))
  w.close()

  // Bob finds it under "Shared with you", read-only, can start it and cannot share it on.
  w = startApp("/plans", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  d = w.document
  const link = await waitFor("the plan in his list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Winter base"))
  // Plans arrive one step before the shares that say who shared them, so the label follows a moment later.
  await waitFor("who shared it", () => d.body.textContent.includes("Shared by alice"))
  click(w, link)
  await waitFor("the plan screen", () => d.body.textContent.includes("Shared with you by alice.") && d.body.textContent.includes("Easy hour"))
  assert.equal(byLabel(w, "Edit plan"), undefined)
  assert.equal(d.querySelector("#share-email"), null, "only the owner sees the sharing section")
  click(w, await waitFor("the start button", () => button(w, "Start this plan")))
  await waitFor("the start form", () => d.querySelector("#assign-start"))
  typeInto(w, d.querySelector("#assign-start"), "2026-12-07")
  submit(w, d.querySelector(".schedule-form"))
  const started = await waitFor("the assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items[0])
  assert.equal(started.athlete, bob.id)
  assert.equal(started.plan, "winterplan00001", "a shared private plan can be started")
  w.close()

  // Carol: shared, then stopped, then shared again through the same row.
  w = startApp("/plans/winterplan00001", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  d = w.document
  await waitFor("bob still listed", () => d.querySelector(".sharing .list")?.textContent.includes("bob"))
  typeInto(w, d.querySelector("#share-email"), carol.email)
  submit(w, d.querySelector(".share-form"))
  await waitFor("carol found", () => d.body.textContent.includes("Found carol. Share this plan with them?"))
  click(w, button(w, "Share plan"))
  const carolShare = await waitFor("carol's share", async () => (await shares()).find((s) => s.user === carol.id))
  assert.equal(await seesPlan(carol), true)
  const carolCard = () => [...d.querySelectorAll(".sharing .list li")].find((li) => li.textContent.includes("carol"))
  await waitFor("carol listed", () => carolCard())
  click(w, [...carolCard().querySelectorAll("button")].find((b) => b.textContent === "Stop sharing"))
  await waitFor("the question", () => openDialog(w)?.textContent.includes("Stop sharing with carol?"))
  assert.equal(await seesPlan(carol), true, "asking does not stop it")
  click(w, dialogButton(w, "Stop sharing"))
  await waitFor("the share removed on the server", async () => (await shares()).find((s) => s.id === carolShare.id)?.deleted === true)
  assert.equal(await seesPlan(carol), false, "Carol no longer sees the plan")
  assert.equal(await seesPlan(bob), true, "Bob still does")
  await waitFor("carol gone from the list", () => !carolCard())

  typeInto(w, d.querySelector("#share-email"), carol.email)
  submit(w, d.querySelector(".share-form"))
  await waitFor("carol found again", () => d.body.textContent.includes("Found carol. Share this plan with them?"))
  click(w, button(w, "Share plan"))
  await waitFor("the same row live again", async () => {
    const all = (await shares()).filter((s) => s.user === carol.id)
    return all.length === 1 && all[0].id === carolShare.id && all[0].deleted === false
  })
  assert.equal(await seesPlan(carol), true)
  w.close()
})

// Access that is taken away reaches the other person's device (ADR 0030) -------------------------------------

const flipOnline = (w) => { w.dispatchEvent(new w.Event("offline")); w.dispatchEvent(new w.Event("online")) }
const onDevice = async (collection) => {
  await call(store.open, "atlas")
  return (await call(store.getAll, collection)).value.toArray().map((r) => r.id)
}

test("a plan whose share was removed disappears from the recipient's device at the next sync", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const carol = h.people.carol
  await setup(h.create("alice", "plans", { id: "sweepplan000001", owner: alice.id, title: "Shared for a while", visibility: "private" }))
  await setup(h.create("alice", "plans", { id: "sweepplan000002", owner: alice.id, title: "Stays shared", visibility: "private" }))
  const share1 = (await setup(h.create("alice", "plan_shares", { id: "sweepshare00001", plan: "sweepplan000001", user: carol.id }))).body
  await setup(h.create("alice", "plan_shares", { id: "sweepshare00002", plan: "sweepplan000002", user: carol.id }))

  const w = startApp("/plans", { token: carol.token, user_id: carol.id, name: "carol", email: carol.email })
  const d = w.document
  await waitFor("both plans", () => d.body.textContent.includes("Shared for a while") && d.body.textContent.includes("Stays shared"))

  // The owner stops sharing the first one. The server hides it at once.
  await setup(h.update("alice", "plan_shares", share1.id, { deleted: true, base_updated: share1.updated }))
  assert.equal((await h.get("carol", "plans", "sweepplan000001")).status, 404)
  assert.ok(d.body.textContent.includes("Shared for a while"), "until the device syncs it still shows it")

  flipOnline(w)
  await waitFor("the plan gone from the screen", () => !d.body.textContent.includes("Shared for a while"))
  assert.ok(d.body.textContent.includes("Stays shared"), "what is still shared stays")
  assert.ok(!(await onDevice("plans")).includes("sweepplan000001"), "and it is gone from the device database too")
  assert.ok((await onDevice("plans")).includes("sweepplan000002"))
  w.close()
})

test("the date and time pickers fill the activity form's fields", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const w = startApp("/activities", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  click(w, await waitFor("the add button", () => button(w, "Add activity")))
  await waitFor("the form", () => d.querySelector("#activity-date"))
  typeInto(w, d.querySelector("#activity-date"), "2026-10-05")

  // The date picker opens on the field's month, moves a month on, and OK writes the day chosen.
  click(w, byLabel(w, "Choose a date"))
  await waitFor("the date picker", () => openDialog(w)?.textContent.includes("October 2026"))
  assert.equal(openDialog(w).querySelector('[aria-selected="true"]').textContent, "5")
  click(w, byLabel(w, "Next month"))
  await waitFor("November", () => openDialog(w)?.textContent.includes("November 2026"))
  click(w, [...openDialog(w).querySelectorAll(".date-picker-day")].find((b) => b.textContent === "17"))
  await waitFor("the headline", () => openDialog(w).textContent.includes("Tue, 17 Nov"))
  click(w, dialogButton(w, "OK"))
  await waitFor("the date in the field", () => d.querySelector("#activity-date").value === "2026-11-17")
  assert.equal(d.querySelector(".date-picker[open]"), null, "the picker closed")
  assert.ok(d.querySelector(".form-dialog[open]"), "the form's dialog is still open")

  // Cancel leaves the field as it was.
  click(w, byLabel(w, "Choose a date"))
  await waitFor("the date picker again", () => openDialog(w)?.textContent.includes("November 2026"))
  click(w, [...openDialog(w).querySelectorAll(".date-picker-day")].find((b) => b.textContent === "3"))
  click(w, dialogButton(w, "Cancel"))
  await waitFor("closed", () => d.querySelector(".date-picker[open]") === null)
  assert.equal(d.querySelector("#activity-date").value, "2026-11-17")

  // The time picker: an hour, then the minutes, then OK.
  click(w, byLabel(w, "Choose a time"))
  await waitFor("the time picker", () => openDialog(w)?.querySelector(".time-picker-dial"))
  click(w, byLabel(w, "18 hours"))
  await waitFor("the minutes", () => byLabel(w, "45 minutes"))
  click(w, byLabel(w, "45 minutes"))
  click(w, dialogButton(w, "OK"))
  await waitFor("the time in the field", () => d.querySelector("#activity-time").value === "18:45")
  w.close()
})

test("an athlete who removes a coach's access also removes her activities from his device", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  const started = utcOf(daysFromNow(-1), 7, 0)
  await setup(h.create("alice", "activities", { id: "sweepact0000001", owner: alice.id, source: "manual", started_at: started, sport: "run", distance_m: 8000, moving_time_s: 2700 }))
  await setup(h.create("bob", "activities", { id: "sweepact0000002", owner: bob.id, source: "manual", started_at: started, sport: "run", distance_m: 5000, moving_time_s: 1500 }))
  const grant = (await setup(h.create("alice", "coach_grants", { id: "sweepgrant00001", athlete: alice.id, coach: bob.id, athlete_name: "alice", coach_name: "bob" }))).body

  const w = startApp("/settings", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  await waitFor("the coach's device to hold the athlete's activity", async () => (await onDevice("activities")).includes("sweepact0000001"))
  assert.ok((await onDevice("activities")).includes("sweepact0000002"), "and his own")

  await setup(h.update("alice", "coach_grants", grant.id, { deleted: true, base_updated: grant.updated }))
  assert.equal((await h.get("bob", "activities", "sweepact0000001")).status, 404, "the server hides it at once")
  flipOnline(w)
  await waitFor("the athlete's activity gone from the coach's device", async () => !(await onDevice("activities")).includes("sweepact0000001"))
  assert.ok((await onDevice("activities")).includes("sweepact0000002"), "his own activity is untouched")
  assert.ok(!(await onDevice("coach_grants")).includes("sweepgrant00001"), "the grant itself is gone too")
  w.close()
})

// The coach's view of an athlete's progress ------------------------------------------------------------------

test("a coach sees an athlete's weeks, plans and activities read-only, and loses the view when access is removed", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  const start = daysFromNow(-10)
  await setup(h.create("alice", "coach_grants", { id: "cvgrant00000001", athlete: alice.id, coach: bob.id, athlete_name: "alice", coach_name: "bob" }))
  await setup(h.create("bob", "plans", { id: "coachview000001", owner: bob.id, title: "Spring base", visibility: "private" }))
  // Day 0 is ten days ago (missed), day 5 five days ago (done), day 10 is today (still to do).
  const workout = (id, day, title, kind, distance) =>
    setup(h.create("bob", "workouts", { id, plan: "coachview000001", day_index: day, position: 0, title, kind, distance_m: distance }))
  await workout("cvworkout000001", 0, "Missed easy run", "easy", 5000)
  await workout("cvworkout000002", 5, "Tempo they did", "tempo", 8000)
  await workout("cvworkout000003", 10, "Today's long run", "long", 10000)
  await setup(h.create("bob", "assignments", { id: "cvassign0000001", plan: "coachview000001", athlete: alice.id, assigned_by: bob.id, start_date: ymd(start) }))
  await setup(h.create("alice", "activities", {
    id: "cvactivity00001", owner: alice.id, source: "manual", started_at: utcOf(daysFromNow(-5), 7, 0),
    sport: "run", name: "Tempo morning", distance_m: 8000, moving_time_s: 2400,
  }))

  const w = startApp("/athletes", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  const link = await waitFor("the athlete in the list", () => [...d.querySelectorAll(".athletes .list a")].find((a) => a.textContent === "alice"))
  assert.ok([...d.querySelectorAll("nav a")].some((a) => a.textContent === "Athletes"), "the tab is there for a coach")
  click(w, link)
  await waitFor("the athlete's page", () => d.querySelector("table.progress") && d.body.textContent.includes("Tempo morning"))

  // The weekly figures, added up over the weeks shown, do not depend on the weekday the test runs on.
  const rows = [...d.querySelectorAll("tr.week-row")].map((tr) => [...tr.querySelectorAll("td")].map((td) => td.textContent))
  const sum = (column) => rows.reduce((total, cells) => total + Number(cells[column]), 0)
  assert.equal(rows.length, 6)
  assert.equal(sum(0), 3, "three workouts planned")
  assert.equal(sum(1), 1, "one done")
  assert.equal(sum(2), 1, "one missed")
  assert.equal(sum(3), 23, "23 km planned")
  assert.equal(sum(4), 8, "8 km trained")
  assert.ok(d.body.textContent.includes("Spring base"), "the plan they follow, which the coach can read")
  assert.ok(d.body.textContent.includes("Recent activities") && d.body.textContent.includes("Tempo morning"))
  assert.ok(d.body.textContent.includes("You can see this because alice gave you access. It is read-only."))
  assert.equal(d.querySelectorAll(".athlete button").length, 0, "nothing can be changed here")
  assert.match(d.body.textContent, /Missed in the last 6 weeks: 1\./)

  // The athlete takes access away: the page, the tab and the data leave the coach's device.
  const grant = (await h.api("GET", "collections/coach_grants/records/cvgrant00000001", { token: alice.token })).body
  await setup(h.update("alice", "coach_grants", grant.id, { deleted: true, base_updated: grant.updated }))
  flipOnline(w)
  await waitFor("the page to lose the athlete", () => d.body.textContent.includes("You do not coach this person"))
  assert.ok(![...d.querySelectorAll("nav a")].some((a) => a.textContent === "Athletes"), "the tab goes away")
  assert.ok(!(await onDevice("activities")).includes("cvactivity00001"), "and her activity is gone from his device")
  w.close()
})
