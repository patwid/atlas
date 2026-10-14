// The whole stack: the built app (jsdom) with a device IndexedDB (fake-indexeddb) against a real
// PocketBase. Needs the built frontend in backend/pb_public: scripts/test-frontend-js.sh builds it.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { toList } from "../build/dev/javascript/atlas/gleam.mjs"
import * as store from "../build/dev/javascript/atlas/atlas/store.ffi.mjs"
import { startPocketBase } from "../../backend/tests/harness.mjs"
import {
  appRunner, built, button, byLabel, call, location, choose, click, daysFromNow, dialogButton, openDialog, pick, pub, setup, sleep, submit, typeInto,
  utcOf, waitFor, weekdayOf, ymd,
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
  const plan = (id, title) => server("POST", "collections/plans/records", { id, owner: me, title })

  await plan("serverplan00001", "Made on another device")
  const v1 = (await plan("conflictplan001", "Server title v1")).body
  await sleep(20)
  await server("PATCH", "collections/plans/records/conflictplan001", { title: "Server title v2", base_updated: v1.updated })

  // What the app would have left on this device after working offline.
  await call(store.open, "atlas")
  await call(store.putMeta, "owner", me)
  await call(store.mergeJson, "plans", "offlineplan0001", JSON.stringify({ title: "Made offline", owner: me }))
  await call(store.putRecords, "plans", toList([{ ...v1 }]))
  await call(store.mergeJson, "plans", "conflictplan001", JSON.stringify({ title: "My offline edit" }))
  const entry = (seq, id, kind, fields, base) => ({ seq, collection: "plans", id, kind, fields, base_updated: base, in_flight: false, attempts: 0 })
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 3,
    entries: [
      entry(1, "offlineplan0001", "create", { title: '"Made offline"', owner: JSON.stringify(me) }, null),
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
    entries: [{ seq: 1, collection: "plans", id: "leftoverplan001", kind: "create", fields: { title: '"Previous user\'s plan"', owner: '"someone-else"' }, base_updated: null, in_flight: false, attempts: 0 }],
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
  await call(store.mergeJson, "plans", "carolplan00001", JSON.stringify({ title: "Unsent plan", owner: carol.id }))
  await call(store.putMeta, "outbox", JSON.stringify({
    next_seq: 2,
    entries: [{ seq: 1, collection: "plans", id: "carolplan00001", kind: "create", fields: { title: '"Unsent plan"', owner: JSON.stringify(carol.id) }, base_updated: null, in_flight: false, attempts: 0 }],
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
  // The new plan opens at once.
  await waitFor("the new plan's screen", () => d.querySelector(".bar h1")?.textContent === "Autumn 10k" && byLabel(w, "Edit plan"))
  const created = await waitFor("the plan on the server", async () => (await onServer()).find((p) => p.title === "Autumn 10k"))
  assert.equal(created.owner, alice.id)
  assert.equal(created.description, "Eight weeks, three runs a week")
  // It is for her: its assignment is made with it (ADR 0110).
  const assigned = await waitFor("the plan's assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: alice.token })).body.items[0])
  assert.deepEqual([assigned.plan, assigned.athlete, assigned.assigned_by, assigned.start_date], [created.id, alice.id, alice.id, ""])
  assert.deepEqual([created.base_weeks, created.pre_competition_weeks, created.competition_weeks, created.weekly_distance_m], [4, 4, 2, 35000])
  assert.equal(weekdayOf(new Date(`${created.start_date}T12:00:00`)), 0, "it starts on the coming Monday (ADR 0108)")
  assert.equal(w.location.pathname, `/plans/${created.id}`)

  // Back in the list, and in again
  click(w, d.querySelector(".tabs a[href=\"/plans\"]"))
  const link = await waitFor("the plan in the list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Autumn 10k"))
  assert.equal(link.getAttribute("href"), `/plans/${created.id}`)
  await waitFor("the synced marker", () => !d.body.textContent.includes("Not synced yet"))

  // Edit, on the plan's own screen
  click(w, link)
  await waitFor("the plan screen", () => d.querySelector(".bar h1")?.textContent === "Autumn 10k" && byLabel(w, "Edit plan"))
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

test("a coach's plan for the user shows up read-only under From your coaches, and appears without a reload", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await h.create("bob", "coach_grants", { id: "bobgrant0000001", athlete: bob.id, coach: alice.id, athlete_name: "bob", coach_name: "alice" })
  const w = startApp("/plans", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the empty list", () => d.body.textContent.includes("You have no plans yet"))
  // His coach makes a plan for him while Bob has the app open; Bob's next sync brings it in (ADR 0110).
  await h.create("alice", "plans", { id: "aliceforbob0001", owner: alice.id, title: "Alice's plan for Bob", start_date: "2026-11-02" })
  await h.create("alice", "assignments", { id: "aliceforbobasg1", plan: "aliceforbob0001", athlete: bob.id, assigned_by: alice.id })
  w.dispatchEvent(new w.Event("offline"))
  w.dispatchEvent(new w.Event("online"))
  await waitFor("the coach's plan", () => d.body.textContent.includes("From your coaches") && d.body.textContent.includes("From alice"))
  click(w, [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Alice's plan for Bob"))
  await waitFor("the plan's screen", () => d.body.textContent.includes("From alice") && d.body.textContent.includes("Only they can change it."))
  assert.equal(byLabel(w, "Edit plan"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  assert.equal(button(w, "Remove"), undefined, "only the coach takes the plan away, by deleting it")
  w.close()
})

// Workouts inside a plan ------------------------------------------------------------------------------


test("the owner builds a plan's workouts: add, add to the same day, move, delete, and the server follows", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "baseplan0000001", owner: alice.id, title: "Base building" })
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
  assert.equal(first.kind, "run")
  assert.equal(first.day_index, 1)
  assert.equal(first.position, 0)
  assert.equal(first.distance_m, 8500)
  assert.equal(first.duration_s, 4500)
  await waitFor("the workout on screen with its targets", () => d.body.textContent.includes("Easy run") && d.body.textContent.includes("8.5 km · 1:15:00"))
  await waitFor("the week total", () => d.querySelector(".week-distance")?.textContent.includes("8.5 km"))

  // A second workout on the same day, from that day's own "+ Add".
  click(w, byLabel(w, "Add a workout to week 1, Tue"))
  await waitFor("the form for day 2", () => d.querySelector("#workout-title") && d.querySelector("#workout-day").value === "2")
  typeInto(w, d.querySelector("#workout-title"), "Parkrun")
  pick(w, "kind", "race")
  submit(w, d.querySelector(".workout-form"))
  const second = await waitFor("the second workout", async () => (await workouts()).find((x) => x.title === "Parkrun"))
  assert.equal(second.kind, "race")
  assert.equal(second.day_index, 1)
  assert.equal(second.position, 1, "it goes after the first one on that day")

  // An interval workout with a warm-up, sets and a cool-down, kept in steps (ADR 0104, 0116).
  click(w, byLabel(w, "Add a workout to week 1, Fri"))
  await waitFor("the form for day 5", () => d.querySelector("#workout-title") && d.querySelector("#workout-day").value === "5")
  assert.equal(d.querySelector("#workout-set1-reps"), null, "no repetitions for a run")
  typeInto(w, d.querySelector("#workout-title"), "Track")
  pick(w, "kind", "interval")
  await waitFor("the fields of the parts", () => d.querySelector("#workout-set1-reps"))
  assert.equal(d.querySelector("#workout-zone"), null, "each part has its own zone")
  typeInto(w, d.querySelector("#workout-warmup-time"), "15")
  typeInto(w, d.querySelector("#workout-set1-reps"), "6")
  typeInto(w, d.querySelector("#workout-set1-work-distance"), "800")
  typeInto(w, d.querySelector("#workout-set1-recovery-time"), "1:30")
  choose(w, d.querySelector("#workout-set1-work-zone"), "4")
  // The time of a rep from its zone's pace, 5:08 /km in the default zones, and the totals (ADR 0106).
  await waitFor("the rep time from the zone", () => d.querySelector("#workout-set1-work-time").value === "4:06")
  assert.equal(d.querySelector("#workout-total-distance").value, "4.8")
  assert.equal(d.querySelector("#workout-total-time").value, "47:06")
  assert.equal(d.querySelector("#workout-distance"), null, "its distance and duration are its parts' (ADR 0131)")
  assert.equal(d.querySelector("#workout-duration"), null)
  // A second set, at first a copy of the first.
  click(w, [...d.querySelectorAll(".workout-form button, .workout-form fluent-button")].find((el) => el.textContent.includes("Add set")))
  await waitFor("the second set", () => d.querySelector("#workout-set2-reps")?.value === "6")
  typeInto(w, d.querySelector("#workout-set2-reps"), "4")
  typeInto(w, d.querySelector("#workout-set2-work-distance"), "")
  typeInto(w, d.querySelector("#workout-set2-work-time"), "")
  typeInto(w, d.querySelector("#workout-set2-work-distance"), "400")
  choose(w, d.querySelector("#workout-set2-work-zone"), "5")
  typeInto(w, d.querySelector("#workout-cooldown-distance"), "2")
  submit(w, d.querySelector(".workout-form"))
  const track = await waitFor("the interval workout", async () => (await workouts()).find((x) => x.title === "Track"))
  assert.deepEqual(track.steps, {
    v: 2,
    warmup: { duration_s: 900 },
    sets: [
      { reps: 6, work: { zone: 4, distance_m: 800, duration_s: 246 }, recovery: { duration_s: 90 } },
      { reps: 4, work: { zone: 5, distance_m: 400, duration_s: 119 }, recovery: { duration_s: 90 } },
    ],
    cooldown: { distance_m: 2000 },
  })
  assert.equal(track.zone, 0, "no zone of its own: its parts have one (ADR 0117)")
  // 15:00 + 6 × 4:06 + 4 × 1:59 + 9 × 1:30, and 6 × 800 m + 4 × 400 m + 2 km (ADR 0131).
  assert.equal(track.duration_s, 3662)
  assert.equal(track.distance_m, 8400)
  await waitFor("the parts on the calendar", () => d.querySelector(".calendar").textContent.includes("15:00 warm-up · 6 × 800 m in 4:06 (Zone 4), 1:30 recovery · 4 × 400 m in 1:59 (Zone 5), 1:30 recovery · 2 km cool-down"))
  click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Track")))
  await waitFor("the parts in the form", () => d.querySelector("#workout-set2-reps")?.value === "4")
  assert.equal(d.querySelector("#workout-set1-work-distance").value, "800")
  assert.equal(d.querySelector("#workout-set1-recovery-time").value, "1:30")
  assert.equal(d.querySelector("#workout-set1-work-zone").value, "4")
  assert.equal(d.querySelector("#workout-warmup-time").value, "15")
  assert.equal(d.querySelector("#workout-cooldown-distance").value, "2")
  pick(w, "kind", "run")
  submit(w, d.querySelector(".workout-form"))
  await waitFor("the parts cleared with the kind", async () => (await workouts()).find((x) => x.id === track.id && x.kind === "run")?.steps === null)

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
    click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Parkrun")))
    await waitFor("the second workout in its form", () => d.querySelector("#workout-title")?.value === "Parkrun")
    click(w, byLabel(w, "Delete workout"))
    await waitFor("the Undo snackbar", () => d.body.textContent.includes("Workout deleted") && !d.querySelector(".calendar").textContent.includes("Parkrun"))
  }
  await deleteCore()
  click(w, button(w, "Undo"))
  await waitFor("back on the calendar", () => d.querySelector(".calendar").textContent.includes("Parkrun"))
  assert.equal((await workouts()).find((x) => x.id === second.id).deleted, false, "Undo wrote nothing")
  await deleteCore()
  click(w, byLabel(w, "Close"))
  await waitFor("the delete on the server", async () => (await workouts()).find((x) => x.id === second.id)?.deleted === true)
  await waitFor("gone from the screen", () => !d.body.textContent.includes("Parkrun"))
  w.close()
})

test("the owner sets a week's intensity in its dialog and the plan's phases and goal with Edit (ADR 0043, 0066)", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  await h.create("alice", "plans", { id: "phaseplan000001", owner: alice.id, title: "Season", base_weeks: 2, pre_competition_weeks: 1, competition_weeks: 1 })
  await h.create("alice", "workouts", { id: "phasework000001", plan: "phaseplan000001", day_index: 7, position: 0, title: "Long run", kind: "run", distance_m: 20000 })
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
  await h.create("bob", "coach_grants", { id: "sharedgrant0001", athlete: bob.id, coach: alice.id })
  await h.create("alice", "plans", { id: "sharedplan00001", owner: alice.id, title: "Coach's plan" })
  await h.create("alice", "assignments", { id: "sharedasg000001", plan: "sharedplan00001", athlete: bob.id, assigned_by: alice.id })
  await h.create("alice", "workouts", { id: "sharedwork00001", plan: "sharedplan00001", day_index: 0, position: 0, title: "Hill repeats", kind: "interval", distance_m: 6000, duration_s: 2400 })
  const w = startApp("/plans/sharedplan00001", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  const d = w.document
  await waitFor("the shared workout", () => d.body.textContent.includes("Hill repeats") && d.body.textContent.includes("6 km · 40:00"))
  assert.equal(button(w, "Add workout"), undefined)
  assert.equal(byLabel(w, "Add a workout to week 1, Mon"), undefined)
  assert.equal(byLabel(w, "Edit plan"), undefined)
  assert.equal(button(w, "Delete"), undefined)
  // A workout opens read-only in its dialog.
  click(w, [...d.querySelectorAll(".workout")].find((el) => el.textContent.includes("Hill repeats")))
  await waitFor("the workout in its dialog", () => d.querySelector("#workout-dialog[open]")?.textContent.includes("Week 1 · Mon"))
  assert.equal(d.querySelector("#workout-title"), null)
  assert.equal(byLabel(w, "Delete workout"), undefined)
  w.close()
})

// A plan and its athlete --------------------------------------------------------------------------------

test("a plan made with a start date is followed from that date, and moving the plan moves the schedule (ADR 0108, 0110)", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const w = startApp("/plans", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const plans = async () => (await h.api("GET", "collections/plans/records?perPage=50", { token: alice.token })).body.items
  const assignments = async () => (await h.api("GET", "collections/assignments/records?perPage=50", { token: alice.token })).body.items

  await waitFor("the empty list", () => d.body.textContent.includes("You have no plans yet"))
  click(w, button(w, "New plan"))
  await waitFor("the form", () => d.querySelector("#plan-start"))
  typeInto(w, d.querySelector("#plan-title"), "Spring 10k")
  typeInto(w, d.querySelector("#plan-start"), "")
  submit(w, d.querySelector(".plan-form"))
  await waitFor("a start date error", () => d.querySelector("[role=alert]")?.textContent === "Pick the plan's first day.")
  // Wednesday 4 Nov 2026: the calendar starts on Monday 2 Nov, whose first two days are not part of the plan.
  typeInto(w, d.querySelector("#plan-start"), "2026-11-04")
  submit(w, d.querySelector(".plan-form"))
  const created = await waitFor("the plan on the server", async () => (await plans()).find((p) => p.title === "Spring 10k"))
  assert.equal(created.start_date, "2026-11-04")
  await waitFor("the calendar with dates", () => d.querySelector(".calendar")?.textContent.includes("2–8 Nov"))
  assert.ok(d.querySelector(".week-label").textContent.startsWith("Week 1"), "counted from the plan's start (ADR 0126)")
  assert.equal(d.querySelectorAll(".calendar-day.before-start").length, 2)
  assert.equal(byLabel(w, "Add a workout to week 1, Mon 2 Nov"), undefined, "nothing can be added before the start")
  click(w, byLabel(w, "Add a workout to week 1, Wed 4 Nov"))
  await waitFor("the workout form on Wednesday", () => d.querySelector("#workout-day")?.value === "3")
  typeInto(w, d.querySelector("#workout-title"), "Easy run")
  submit(w, d.querySelector(".workout-form"))
  await waitFor("the workout on the calendar", () => d.querySelector(".calendar").textContent.includes("Easy run"))

  // The plan is hers from the start, following its date: there is nothing to start, and no tabs (ADR 0110).
  const following = await waitFor("the assignment on the server", async () => (await assignments())[0])
  assert.equal(following.plan, created.id)
  assert.equal(following.start_date, "", "it follows the plan")
  assert.equal(button(w, "Start this plan"), undefined)
  assert.equal(d.querySelector('[role="tablist"]'), null)

  // Moving the plan a week later moves the schedule with it.
  click(w, byLabel(w, "Edit plan"))
  await waitFor("the edit form", () => d.querySelector("#plan-start")?.value === "2026-11-04")
  typeInto(w, d.querySelector("#plan-start"), "2026-11-11")
  submit(w, d.querySelector(".plan-form"))
  await waitFor("the new date on the server", async () => (await plans()).find((p) => p.id === created.id)?.start_date === "2026-11-11")
  await waitFor("the calendar moved", () => d.querySelector(".calendar")?.textContent.includes("9–15 Nov"))
  assert.equal((await assignments())[0].start_date, "", "the assignment itself is unchanged")
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

test("an athlete adds two goals in Settings, edits one and deletes the other, and the server follows (ADR 0115)", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const goals = async () => (await h.api("GET", "collections/goals/records?perPage=50&sort=distance_m&filter=" + encodeURIComponent("deleted = false"), { token: alice.token })).body.items
  const w = startApp("/settings/goals", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  await waitFor("no goals yet", () => d.body.textContent.includes("No goals yet"))

  // A goal needs both values: without a time nothing is sent.
  click(w, button(w, "Add goal"))
  await waitFor("the form", () => d.querySelector("#distance"))
  typeInto(w, d.querySelector("#distance"), "42.195")
  submit(w, d.querySelector(".goal-form"))
  await waitFor("a time error", () => d.querySelector("[role=alert]")?.textContent.startsWith("Enter the time"))
  typeInto(w, d.querySelector("#time"), "3:30")
  submit(w, d.querySelector(".goal-form"))
  await waitFor("the marathon on the server", async () => (await goals()).length === 1)

  click(w, button(w, "Add goal"))
  await waitFor("an empty form", () => d.querySelector("#distance")?.value === "")
  typeInto(w, d.querySelector("#distance"), "10")
  typeInto(w, d.querySelector("#time"), "0:45:30")
  submit(w, d.querySelector(".goal-form"))
  let rows = await waitFor("both goals on the server", async () => { const r = await goals(); return r.length === 2 && r })
  assert.deepEqual(rows.map((g) => [g.owner, g.distance_m, g.time_s]), [[alice.id, 10000, 2730], [alice.id, 42195, 12600]])
  await waitFor("both on screen, shortest first", () => {
    const items = [...d.querySelectorAll(".goals .list li")].map((li) => li.textContent)
    return items.length === 2 && items[0].includes("45:30") && items[1].includes("3:30:00")
  })

  // Edit the marathon's time from its row (ADR 0080).
  const row = (text) => [...d.querySelectorAll(".goals .list li")].find((li) => li.textContent.includes(text))
  click(w, row("42.195 km").querySelector(".row-link"))
  await waitFor("the edit form", () => d.querySelector("#time")?.value === "3:30")
  typeInto(w, d.querySelector("#time"), "3:15")
  submit(w, d.querySelector(".goal-form"))
  await waitFor("the new time on the server", async () => (await goals()).find((g) => g.distance_m === 42195)?.time_s === 11700)

  // Delete the 10 km from its form; the delete is written when the Undo snackbar goes (ADR 0056).
  click(w, row("10 km").querySelector(".row-link"))
  await waitFor("the edit form", () => d.querySelector("#distance")?.value === "10")
  click(w, d.querySelector("[aria-label='Delete goal']"))
  await waitFor("Undo", () => d.body.textContent.includes("Goal deleted"))
  click(w, byLabel(w, "Close"))
  rows = await waitFor("one goal left on the server", async () => { const r = await goals(); return r.length === 1 && r })
  assert.equal(rows[0].distance_m, 42195)
  await waitFor("gone from the list", () => d.querySelectorAll(".goals .list li").length === 1)
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

  // 2. Bob makes a plan for Alice: who it is for is chosen when it is made (ADR 0110).
  w = startApp("/plans", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  d = w.document
  await waitFor("the plans screen", () => d.body.textContent.includes("You have no plans yet"))
  click(w, button(w, "New plan"))
  await waitFor("the form with athletes, which needs the grant on his device", () => d.querySelector("#plan-athlete"))
  const options = [...d.querySelectorAll("#plan-athlete option")].map((o) => o.textContent)
  assert.deepEqual(options, ["Myself", "alice"])
  typeInto(w, d.querySelector("#plan-title"), "Coach's base plan")
  typeInto(w, d.querySelector("#plan-start"), "2026-11-02")
  choose(w, d.querySelector("#plan-athlete"), alice.id)
  submit(w, d.querySelector(".plan-form"))
  const assignment = await waitFor("the assignment on the server", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items[0])
  assert.equal(assignment.athlete, alice.id)
  assert.equal(assignment.assigned_by, bob.id)
  await waitFor("the plan's screen says who it is for", () => d.querySelector(".bar h1")?.textContent === "Coach's base plan" && d.querySelector(".plan-meta")?.textContent === "For alice")
  await setup(h.create("bob", "workouts", { id: "coachwork000001", plan: assignment.plan, day_index: 0, position: 0, title: "Easy run", kind: "run", distance_m: 5000 }))
  w.close()

  // 3. Alice opens the app and finds the plan from her coach, read-only.
  w = startApp("/plans", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  d = w.document
  const link = await waitFor("the coach's plan in her list", () => [...d.querySelectorAll(".list a")].find((a) => a.textContent === "Coach's base plan"))
  assert.ok(d.body.textContent.includes("From your coaches") && d.body.textContent.includes("From bob"))
  click(w, link)
  await waitFor("the plan screen", () => d.querySelector(".plan-meta")?.textContent === "From bob" && d.body.textContent.includes("Easy run"))
  assert.equal(byLabel(w, "Edit plan"), undefined, "its workouts cannot be changed")
  assert.equal(button(w, "Change date"), undefined, "and nor can its date")
  assert.equal(button(w, "Remove"), undefined, "only the coach removes it, by deleting the plan")
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
  assert.equal([...stravaCard.querySelectorAll("button, fluent-button")].length, 0, "Strava activities cannot be changed here")

  click(w, button(w, "Add activity"))
  await waitFor("the form", () => d.querySelector("#activity-date"))
  typeInto(w, d.querySelector("#activity-date"), "2026-10-05")
  typeInto(w, d.querySelector("#activity-time"), "07:30")
  submit(w, d.querySelector(".activity-form"))
  await waitFor("a distance or time error", () => d.querySelector("[role=alert]")?.textContent === "Enter a distance or a duration, or both.")
  assert.equal((await activities()).length, 1, "nothing is sent for an invalid form")
  // The kinds and fields of a workout (ADR 0121).
  assert.equal(d.querySelector("#activity-elevation"), null, "no climb")
  pick(w, "kind", "race")
  await waitFor("the race's warm-up", () => d.querySelector("#activity-warmup-time"))
  typeInto(w, d.querySelector("#activity-title"), "Morning loop")
  choose(w, d.querySelector("#activity-zone"), "5")
  typeInto(w, d.querySelector("#activity-warmup-time"), "15")
  typeInto(w, d.querySelector("#activity-distance"), "8,5")
  typeInto(w, d.querySelector("#activity-duration"), "1:05")
  typeInto(w, d.querySelector("#activity-description"), "Windy")
  submit(w, d.querySelector(".activity-form"))
  const created = await waitFor("the activity on the server", async () => (await activities()).find((a) => a.name === "Morning loop"))
  assert.equal(created.owner, alice.id)
  assert.equal(created.source, "manual")
  assert.equal(created.sport, "run")
  assert.equal(created.kind, "race")
  assert.equal(created.zone, 5)
  assert.deepEqual(created.steps, { v: 2, warmup: { duration_s: 900 } })
  assert.equal(created.description, "Windy")
  assert.equal(created.distance_m, 8500)
  assert.equal(created.moving_time_s, 3900)
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
  assert.equal(d.querySelector("#activity-zone").value, "5")
  assert.equal(d.querySelector("#activity-warmup-time").value, "15")
  typeInto(w, d.querySelector("#activity-title"), "Easy loop")
  submit(w, d.querySelector(".activity-form"))
  await waitFor("the new name on the server", async () => (await activities()).some((a) => a.id === created.id && a.name === "Easy loop"))
  const after = (await activities()).find((a) => a.id === created.id)
  assert.equal(after.started_at, expectedUtc, "the start is untouched")
  assert.equal(after.distance_m, 8500)

  // Delete, from its form; it is written when the Undo snackbar is closed.
  click(w, card().querySelector(".row-link"))
  await waitFor("the form again", () => d.querySelector("#activity-title")?.value === "Easy loop")
  click(w, byLabel(w, "Delete activity"))
  await waitFor("the Undo snackbar", () => d.body.textContent.includes("Activity deleted"))
  assert.equal((await activities()).find((a) => a.id === created.id).deleted, false)
  click(w, byLabel(w, "Close"))
  await waitFor("deleted on the server", async () => (await activities()).find((a) => a.id === created.id)?.deleted === true)
  await waitFor("gone from the list", () => !d.body.textContent.includes("Easy loop"))
  assert.ok(d.body.textContent.includes("Lunch run"), "the Strava activity is still there")
  w.close()
})

// Importing a FIT file (ADR 0100) ---------------------------------------------------------------------------

// A FIT activity file with a file ID, one lap and the session, little-endian throughout.
const fitFile = (startUnix) => {
  const bytes = []
  const u8 = (...values) => bytes.push(...values)
  const u16 = (v) => u8(v & 0xff, (v >> 8) & 0xff)
  const u32 = (v) => { u16(v % 65536); u16(Math.floor(v / 65536)) }
  const define = (local, global, fields) => { u8(0x40 | local, 0, 0); u16(global); u8(fields.length); for (const f of fields) u8(...f) }
  const start = startUnix - 631065600 // FIT counts from 1989-12-31
  define(0, 0, [[0, 1, 0x00], [3, 4, 0x8c], [4, 4, 0x86]])
  u8(0, 4); u32(3456789012); u32(start)
  define(1, 19, [[7, 4, 0x86], [8, 4, 0x86], [9, 4, 0x86], [15, 1, 0x02]])
  u8(1); u32(3000400); u32(2900600); u32(1023456); u8(150)
  define(2, 18, [[2, 4, 0x86], [5, 1, 0x00], [6, 1, 0x00], [7, 4, 0x86], [8, 4, 0x86], [9, 4, 0x86], [16, 1, 0x02], [17, 1, 0x02], [22, 2, 0x84]])
  u8(2); u32(start); u8(1, 0); u32(3000400); u32(2900600); u32(1023456); u8(155, 171); u16(87)
  const size = bytes.length
  const header = [14, 0x20, 0x54, 0x08, size & 0xff, (size >> 8) & 0xff, 0, 0, ...".FIT"].map((c) => typeof c === "string" ? c.charCodeAt(0) : c)
  return Uint8Array.from([...header, 0, 0, ...bytes, 0, 0])
}

const chooseFile = (w, input, bytes, name) => {
  Object.defineProperty(input, "files", { value: [new w.File([bytes], name)], configurable: true })
  input.dispatchEvent(new w.Event("change", { bubbles: true }))
}

test("a user imports a FIT file: the form is filled in, the file's exact values are saved, a second import is refused, a deleted one comes back", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const startMs = Date.UTC(2026, 9, 5, 5, 20, 12)
  const file = fitFile(startMs / 1000)
  const w = startApp("/activities", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const activities = async () => (await h.api("GET", "collections/activities/records?perPage=50", { token: alice.token })).body.items
  const input = () => d.querySelector("#activity-fit-file")

  await waitFor("the empty list", () => d.body.textContent.includes("No activities yet"))
  click(w, button(w, "Add activity"))
  await waitFor("the import button", () => button(w, "Import a .fit file") && input())
  click(w, button(w, "Import a .fit file"))
  chooseFile(w, input(), Uint8Array.from([1, 2, 3]), "notes.txt")
  await waitFor("not a FIT file", () => d.querySelector(".activity-import [role=alert]")?.textContent.startsWith("This is not a FIT file."))

  chooseFile(w, input(), file, "morning.fit")
  await waitFor("the form filled in", () => d.querySelector("#activity-distance")?.value === "10.235")
  assert.ok(d.body.textContent.includes("Filled in from morning.fit."))
  const start = new Date(startMs)
  assert.equal(d.querySelector("#activity-date").value, ymd(start))
  assert.equal(d.querySelector("#activity-time").value, `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}`)
  assert.equal(d.querySelector("#activity-duration").value, "0:48:21")
  typeInto(w, d.querySelector("#activity-title"), "Watch run")
  submit(w, d.querySelector(".activity-form"))

  const created = await waitFor("the activity on the server", async () => (await activities()).find((a) => a.name === "Watch run"))
  assert.equal(created.source, "fit")
  assert.equal(created.external_id, `3456789012-${startMs / 1000 - 631065600}`, "serial number and time created")
  assert.equal(created.started_at, "2026-10-05 05:20:12.000Z", "the start to the second")
  assert.equal(created.sport, "run")
  assert.equal(created.distance_m, 10234.56)
  assert.equal(created.moving_time_s, 2901)
  assert.equal(created.elapsed_time_s, 3000)
  assert.equal(created.elevation_gain_m, 87)
  assert.equal(created.avg_hr, 155)
  assert.equal(created.max_hr, 171)
  assert.deepEqual(created.laps, [{ index: 1, name: null, distance_m: 10234.56, moving_time_s: 2901, elapsed_time_s: 3000, elevation_gain_m: null, avg_hr: 150, max_hr: null }])
  await waitFor("it in the list, from a file", () => [...d.querySelectorAll(".list li")].some((li) => li.textContent.includes("Watch run") && li.textContent.includes("From a file")))

  // The same file again is refused before anything is sent.
  click(w, button(w, "Add activity"))
  await waitFor("the import button", () => input())
  chooseFile(w, input(), file, "morning-copy.fit")
  await waitFor("already imported", () => d.querySelector(".activity-import [role=alert]")?.textContent.startsWith("This file is imported already: Watch run,"))
  d.querySelector(".form-dialog").dispatchEvent(new w.Event("close"))
  await waitFor("the form closed", () => !d.querySelector("#activity-fit-file"))

  // Deleted, then imported again: the same row comes back, as the server keeps one row per file.
  click(w, [...d.querySelectorAll(".list li")].find((li) => li.textContent.includes("Watch run")).querySelector(".row-link"))
  await waitFor("its form", () => d.querySelector("#activity-title")?.value === "Watch run")
  click(w, byLabel(w, "Delete activity"))
  await waitFor("the Undo snackbar", () => d.body.textContent.includes("Activity deleted"))
  click(w, byLabel(w, "Close"))
  await waitFor("deleted on the server", async () => (await activities()).find((a) => a.id === created.id)?.deleted === true)
  click(w, button(w, "Add activity"))
  await waitFor("the import button", () => input())
  chooseFile(w, input(), file, "morning.fit")
  await waitFor("the form filled in again", () => d.querySelector("#activity-distance")?.value === "10.235")
  submit(w, d.querySelector(".activity-form"))
  const revived = await waitFor("the row back on the server", async () => (await activities()).find((a) => a.id === created.id && a.deleted === false))
  assert.equal((await activities()).length, 1, "no second row")
  assert.equal(revived.name, "")
  assert.equal(revived.distance_m, 10234.56)
  await waitFor("back in the list", () => [...d.querySelectorAll(".list li")].some((li) => li.textContent.includes("Run") && li.textContent.includes("From a file")))
  w.close()
})

// The Home screen -------------------------------------------------------------------------------------


test("Home shows missed, looks-done and rest days; the user confirms, unlinks, re-links and links by hand", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const yesterday = daysFromNow(-1)
  const today = daysFromNow(0)
  await setup(h.create("alice", "plans", { id: "todayplan000001", owner: alice.id, title: "Tempo block", start_date: ymd(yesterday) }))
  // Days count from the Monday of the week the plan starts in (ADR 0108).
  const firstDay = weekdayOf(yesterday)
  await setup(h.create("alice", "workouts", { id: "todaywork000001", plan: "todayplan000001", day_index: firstDay, position: 0, title: "Easy shake-out", kind: "run", distance_m: 5000 }))
  await setup(h.create("alice", "workouts", { id: "todaywork000002", plan: "todayplan000001", day_index: firstDay + 1, position: 0, title: "Tempo intervals", kind: "run", distance_m: 8000, duration_s: 2700 }))
  await setup(h.create("alice", "workouts", { id: "todaywork000003", plan: "todayplan000001", day_index: firstDay + 2, position: 0, title: "Recovery day", kind: "rest" }))
  // The plan started yesterday: its first day is yesterday (missed), then today, then tomorrow.
  await setup(h.create("alice", "assignments", { id: "todayasg0000001", plan: "todayplan000001", athlete: alice.id, assigned_by: alice.id }))
  const activity = (id, day, hour, name) => setup(h.create("alice", "activities", {
    id, owner: alice.id, source: "manual", started_at: utcOf(day, hour, 0), sport: "run", name, distance_m: 8000, moving_time_s: 2700,
  }))
  await activity("todayact0000001", today, 7, "Morning tempo")
  const matches = async () => (await h.api("GET", "collections/matches/records?perPage=50", { token: alice.token })).body.items

  const w = startApp("/", { token: alice.token, user_id: alice.id, name: "alice", email: alice.email })
  const d = w.document
  const card = (title) => [...d.querySelectorAll(".item")].find((li) => li.textContent.includes(title))
  const inCard = (title, text) => [...card(title).querySelectorAll("button, fluent-button")].find((b) => b.textContent.trim() === text)

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

test("Home without a plan points to the plans", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const bob = h.people.bob
  const w = startApp("/", { token: bob.token, user_id: bob.id, name: "bob", email: bob.email })
  await waitFor("the empty state", () => w.document.body.textContent.includes("You are not following a plan yet"))
  assert.equal(w.document.querySelector('a[href="/plans"]')?.textContent, "Go to plans")
  w.close()
})

// Copying a plan --------------------------------------------------------------------------------------

test("an athlete copies a coach's plan with its workouts, for herself, then edits the copy; the original is untouched", { skip: !built && "frontend not built" }, async () => {
  await h.world()
  const alice = h.people.alice
  const bob = h.people.bob
  await setup(h.create("bob", "coach_grants", { id: "copygrant000001", athlete: bob.id, coach: alice.id }))
  await setup(h.create("alice", "plans", { id: "copysrcplan0001", owner: alice.id, title: "Autumn 10k", description: "Eight weeks", start_date: "2026-11-02" }))
  await setup(h.create("alice", "assignments", { id: "copysrcasg00001", plan: "copysrcplan0001", athlete: bob.id, assigned_by: alice.id }))
  await setup(h.create("alice", "workouts", { id: "copysrcwork0001", plan: "copysrcplan0001", day_index: 3, position: 0, title: "Tempo", kind: "run", description: "3 x 10 min", distance_m: 8000, duration_s: 2700, steps: { v: 1, reps: 3, work: { duration_s: 600 } }, zone: 3 }))
  await setup(h.create("alice", "workouts", { id: "copysrcwork0002", plan: "copysrcplan0001", day_index: 0, position: 0, title: "Easy run", kind: "run", distance_m: 5000 }))

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
  assert.equal(copy.source_plan, "copysrcplan0001")
  assert.equal(copy.start_date, "2026-11-02")
  const copyAssignment = await waitFor("the copy's assignment", async () =>
    (await h.api("GET", "collections/assignments/records?perPage=50", { token: bob.token })).body.items.find((a) => a.plan === copy.id))
  assert.deepEqual([copyAssignment.athlete, copyAssignment.assigned_by], [bob.id, bob.id], "the copy is for him")
  const copied = await waitFor("both workouts on the server", async () => { const ws = await workoutsOf(copy.id); return ws.length === 2 && ws })
  assert.deepEqual(copied.map((x) => [x.title, x.day_index, x.kind]), [["Easy run", 0, "run"], ["Tempo", 3, "run"]])
  assert.equal(copied[1].description, "3 x 10 min")
  assert.equal(copied[1].distance_m, 8000)
  assert.equal(copied[1].duration_s, 2700)
  assert.deepEqual(copied[1].steps, { v: 2, sets: [{ reps: 3, work: { zone: 3, duration_s: 600 } }] }, "the repetitions came along (ADR 0104), in the second version of steps (ADR 0116)")
  assert.equal(copied[1].zone, 3, "the zone came along (ADR 0105)")

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

// Access that is taken away reaches the other person's device (ADR 0030) -------------------------------------

const flipOnline = (w) => { w.dispatchEvent(new w.Event("offline")); w.dispatchEvent(new w.Event("online")) }
const onDevice = async (collection) => {
  await call(store.open, "atlas")
  return (await call(store.getAll, collection)).value.toArray().map((r) => r.id)
}

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
  await setup(h.create("bob", "plans", { id: "coachview000001", owner: bob.id, title: "Spring base", start_date: ymd(start) }))
  // The first day is ten days ago (missed), the sixth five days ago (done), the eleventh today (still to do). Days
  // count from the Monday of the week the plan starts in (ADR 0108).
  const workout = (id, day, title, kind, distance) =>
    setup(h.create("bob", "workouts", { id, plan: "coachview000001", day_index: weekdayOf(start) + day, position: 0, title, kind, distance_m: distance }))
  await workout("cvworkout000001", 0, "Missed easy run", "run", 5000)
  await workout("cvworkout000002", 5, "Tempo they did", "run", 8000)
  await workout("cvworkout000003", 10, "Today's long run", "run", 10000)
  await setup(h.create("bob", "assignments", { id: "cvassign0000001", plan: "coachview000001", athlete: alice.id, assigned_by: bob.id }))
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
  assert.equal(d.querySelectorAll(".athlete button, .athlete fluent-button").length, 0, "nothing can be changed here")
  const stats = [...d.querySelectorAll(".stat")].map((stat) => stat.textContent)
  assert.ok(stats.includes("Missed1 in the last 6 weeks"), `the missed workouts: ${stats}`)

  // The athlete takes access away: the page, the tab and the data leave the coach's device.
  const grant = (await h.api("GET", "collections/coach_grants/records/cvgrant00000001", { token: alice.token })).body
  await setup(h.update("alice", "coach_grants", grant.id, { deleted: true, base_updated: grant.updated }))
  flipOnline(w)
  await waitFor("the page to lose the athlete", () => d.body.textContent.includes("You do not coach this person"))
  assert.ok(![...d.querySelectorAll("nav a")].some((a) => a.textContent === "Athletes"), "the tab goes away")
  assert.ok(!(await onDevice("activities")).includes("cvactivity00001"), "and her activity is gone from his device")
  w.close()
})
