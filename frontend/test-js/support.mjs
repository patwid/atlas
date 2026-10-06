// Helpers shared by the whole-app tests: running the built app in jsdom and driving it like a user.
import "fake-indexeddb/auto"
import assert from "node:assert/strict"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { JSDOM } from "jsdom"

export const pub = join(dirname(fileURLToPath(import.meta.url)), "../../backend/pb_public")
export const built = existsSync(join(pub, "atlas.js"))
export const call = (fn, ...a) => new Promise((resolve) => fn(...a, (ok, value) => resolve({ ok, value })))
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

/**
 * Returns `startApp(path, session)`, which runs the built app in a window whose requests go to the PocketBase
 * returned by `getHarness()`. `fetched` receives every request the app makes: `(method, url)`.
 */
export const appRunner = (getHarness, fetched = () => {}) => (path, session) => {
  const h = getHarness()
  const html = readFileSync(join(pub, "index.html"), "utf8").replace(/<script[^>]*src="\/atlas.js"[^>]*><\/script>/, "")
  const dom = new JSDOM(html, { url: h.url + path, runScripts: "outside-only", pretendToBeVisual: true })
  const w = dom.window
  // jsdom's AbortSignal is not Node's, so the signal is left out of the shim.
  w.fetch = (url, opts) => {
    const { signal, ...rest } = opts
    fetched(rest.method, url)
    return fetch(new URL(url, h.url), rest)
  }
  w.indexedDB = globalThis.indexedDB
  if (session) w.localStorage.setItem("atlas.session", JSON.stringify(session))
  w.eval(readFileSync(join(pub, "atlas.js"), "utf8"))
  return w
}

export const waitFor = async (what, check, ms = 8000) => {
  const end = Date.now() + ms
  let last
  while (Date.now() < end) {
    try { last = await check(); if (last) return last } catch {}
    await sleep(50)
  }
  assert.fail(`timed out waiting for: ${what}`)
}
export const click = (w, el) => el.dispatchEvent(new w.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }))
export const typeInto = (w, el, value) => { el.value = value; el.dispatchEvent(new w.Event("input", { bubbles: true })) }
export const submit = (w, form) => form.dispatchEvent(new w.Event("submit", { bubbles: true, cancelable: true }))
export const button = (w, text) => [...w.document.querySelectorAll("button")].find((b) => b.textContent.trim() === text)
export const choose = (w, select, value) => { select.value = value; select.dispatchEvent(new w.Event("change", { bubbles: true })) }
export const byLabel = (w, label) => [...w.document.querySelectorAll("button")].find((b) => b.getAttribute("aria-label") === label)

// Setup calls must work: a silent 400 (for example an ID of the wrong length) would only show up later as a timeout.
export const setup = async (request) => {
  const response = await request
  assert.equal(response.status, 200, `setup failed: ${JSON.stringify(response.body)}`)
  return response
}

export const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
export const daysFromNow = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d }
export const utcOf = (day, hour, minute) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute).toISOString().replace("T", " ")
