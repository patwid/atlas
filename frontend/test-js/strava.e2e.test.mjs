// Connecting Strava through the app: the real server hooks against a fake Strava (backend/tests/fake_strava.mjs).
// jsdom cannot follow the browser's jump to Strava's page, so the test plays Strava's redirect itself:
// it asks the server for the connect address like the app does and calls the callback with its signed state.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { startPocketBase } from "../../backend/tests/harness.mjs"
import { startFakeStrava } from "../../backend/tests/fake_strava.mjs"
import { appRunner, built, button, click, pub, waitFor } from "./support.mjs"

let h, strava, bare
const requests = []
before(async () => {
  if (!built) return
  strava = await startFakeStrava({ webhookUrl: true })
  h = await startPocketBase(
    { STRAVA_CLIENT_ID: "client-1", STRAVA_CLIENT_SECRET: "secret-1", STRAVA_VERIFY_TOKEN: "verify-1", STRAVA_BASE: strava.base },
    { publicDir: pub },
  )
  bare = await startPocketBase({ STRAVA_CLIENT_ID: "", STRAVA_CLIENT_SECRET: "" }, { publicDir: pub })
})
after(() => { h?.stop(); bare?.stop(); strava?.stop() })

const startApp = appRunner(() => h, (method, url) => requests.push(`${method} ${url}`))
const startBareApp = appRunner(() => bare)
const session = (p) => ({ token: p.token, user_id: p.id, name: "alice", email: p.email })
const skip = { skip: !built && "frontend not built" }

test("a server without Strava credentials says so and offers no button", skip, async () => {
  await bare.world()
  const w = startBareApp("/settings", session(bare.people.alice))
  await waitFor("the explanation", () => w.document.body.textContent.includes("Strava is not set up on this server."))
  assert.equal(w.document.querySelector("button.strava-connect"), null)
  w.close()
})

test("connect, import, import again and disconnect", skip, async () => {
  await h.world()
  const alice = h.people.alice
  strava.state.calls.length = 0
  strava.state.activities.clear()
  strava.state.athleteId = 2000 + h.run
  strava.state.activities.set(11, strava.activity(11, { name: "Lunch run", start_date: "2026-10-01T11:00:00Z" }))
  strava.state.activities.set(12, strava.activity(12, { name: "Hill repeats", start_date: "2026-10-02T06:30:00Z" }))

  // 1. Not connected: the button is there, with the attribution. Clicking it asks the server for Strava's address.
  let w = startApp("/settings", session(alice))
  const connectButton = () => w.document.querySelector("button.strava-connect")
  await waitFor("the connect button", () => connectButton())
  // Strava's own artwork, as the brand rules require: the official button image and the attribution logo.
  assert.equal(connectButton().querySelector("img").getAttribute("src"), "/strava/btn_strava_connect_with_orange.svg")
  assert.equal(connectButton().querySelector("img").getAttribute("alt"), "Connect with Strava")
  assert.equal(w.document.querySelector('.attribution img[alt="Powered by Strava"]').getAttribute("src"), "/strava/api_logo_pwrdBy_strava_horiz_orange.svg")
  requests.length = 0
  click(w, connectButton())
  await waitFor("the request for the address", () => requests.some((r) => r.includes("GET /api/atlas/strava/connect")))
  w.close()

  // 2. Strava sends the browser back through the server's callback, which imports the last 30 days.
  const connect = await h.api("GET", "atlas/strava/connect", { token: alice.token })
  const state = new URL(connect.body.url).searchParams.get("state")
  const back = await h.api("GET", `atlas/strava/callback?code=good-code&scope=read,activity:read_all&state=${encodeURIComponent(state)}`)
  assert.equal(back.status, 302)
  const returnTo = new URL(back.headers.get("location"))
  assert.equal(returnTo.pathname, "/settings")
  assert.equal(returnTo.searchParams.get("strava"), "connected")

  // 3. The app opens at that address: it says so, shows the connection, cleans the address, and the activities arrive.
  w = startApp(returnTo.pathname + returnTo.search, session(alice))
  const d = w.document
  await waitFor("the success message", () => d.body.textContent.includes("Strava is connected. Your last 30 days are being imported."))
  await waitFor("the connected state", () => d.body.textContent.includes("Connected to Strava") && button(w, "Disconnect"))
  assert.equal(w.location.search, "", "the address is cleaned so a reload does not repeat the message")
  click(w, [...d.querySelectorAll("nav a")].find((a) => a.textContent === "Activities"))
  await waitFor("the imported activities", () => d.body.textContent.includes("Lunch run") && d.body.textContent.includes("Hill repeats"))
  const card = [...d.querySelectorAll(".cards li")].find((li) => li.textContent.includes("Lunch run"))
  assert.ok(card.textContent.includes("Strava"))
  assert.equal(card.querySelectorAll("button").length, 0, "Strava activities are read-only")
  // Strava's rules: wherever its data is shown, a link back that says "View on Strava".
  const viewLink = card.querySelector("a.strava-link")
  assert.equal(viewLink.textContent, "View on Strava")
  assert.equal(viewLink.getAttribute("href"), "https://www.strava.com/activities/11")
  assert.equal(viewLink.getAttribute("rel"), "noopener noreferrer")

  // 4. Importing again picks up an activity that appeared since.
  strava.state.activities.set(13, strava.activity(13, { name: "Easy jog", start_date: "2026-10-03T07:00:00Z" }))
  click(w, [...d.querySelectorAll("nav a")].find((a) => a.textContent === "Settings"))
  await waitFor("the import button", () => button(w, "Import the last 30 days again"))
  click(w, button(w, "Import the last 30 days again"))
  await waitFor("the count", () => d.body.textContent.includes("Imported 3 activities from the last 30 days."))
  click(w, [...d.querySelectorAll("nav a")].find((a) => a.textContent === "Activities"))
  await waitFor("the new activity", () => d.body.textContent.includes("Easy jog"))

  // 5. Disconnecting asks first, tells Strava, and removes its activities from Atlas.
  click(w, [...d.querySelectorAll("nav a")].find((a) => a.textContent === "Settings"))
  await waitFor("the disconnect button", () => button(w, "Disconnect"))
  click(w, button(w, "Disconnect"))
  await waitFor("the question", () => d.body.textContent.includes("Disconnect Strava and remove its activities from Atlas?"))
  assert.equal((await h.api("GET", "atlas/strava/status", { token: alice.token })).body.connected, true, "asking does not disconnect")
  click(w, button(w, "Yes, disconnect"))
  await waitFor("the message", () => d.body.textContent.includes("Strava is disconnected. 3 activities from Strava were removed from Atlas."))
  await waitFor("the button to connect again", () => d.querySelector("button.strava-connect"))
  assert.equal((await h.api("GET", "atlas/strava/status", { token: alice.token })).body.connected, false)
  assert.ok(strava.state.calls.some((c) => c.path === "/oauth/deauthorize"), "Strava was told")
  click(w, [...d.querySelectorAll("nav a")].find((a) => a.textContent === "Activities"))
  await waitFor("the activities gone", () => !d.body.textContent.includes("Lunch run") && !d.body.textContent.includes("Easy jog"))
  w.close()
})

test("coming back from Strava with a problem explains it", skip, async () => {
  await h.world()
  const alice = h.people.alice
  const messages = {
    denied: "Strava access was not granted.",
    scope: "Atlas needs permission to read your activities. Try again and keep that box ticked.",
    taken: "This Strava account is already used by another Atlas user.",
  }
  for (const [result, text] of Object.entries(messages)) {
    const w = startApp(`/settings?strava=${result}`, session(alice))
    await waitFor(`the ${result} message`, () => w.document.body.textContent.includes(text))
    assert.equal(w.location.search, "")
    w.close()
  }
})
