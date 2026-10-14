// The scrolled-app-bar, dialog and announcement glue (src/atlas/ui/interaction.ffi.mjs, ADR 0051) in jsdom. Run with
// scripts/test-frontend-js.sh.
import { test } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM(`<!doctype html><body>
  <button class="link-button">Save</button>
  <button class="link-button" disabled>Off</button>
  <nav class="tabs"><a href="/"><span class="nav-indicator"></span>Home</a></nav>
  <p class="plain">text</p>
</body>`, { pretendToBeVisual: true })
Object.assign(globalThis, {
  document: dom.window.document, window: dom.window, Element: dom.window.Element, MutationObserver: dom.window.MutationObserver,
})
dom.window.HTMLDialogElement.prototype.showModal = function () { this.setAttribute("open", "") }
dom.window.HTMLDialogElement.prototype.close = function () { this.removeAttribute("open") }
const { install, clickedOutside } = await import("../build/dev/javascript/atlas/atlas/ui/interaction.ffi.mjs")
install()
install() // a second call adds no second set of listeners

const d = dom.window.document

test("the page is marked as scrolled once it scrolls, and unmarked at the top", () => {
  assert.equal(d.documentElement.dataset.scrolled, undefined)
  dom.window.scrollY = 120
  dom.window.dispatchEvent(new dom.window.Event("scroll"))
  assert.equal(d.documentElement.dataset.scrolled, "")
  dom.window.scrollY = 0
  dom.window.dispatchEvent(new dom.window.Event("scroll"))
  assert.equal(d.documentElement.dataset.scrolled, undefined)
})

test("a form dialog opens and closes with its data-open attribute", async () => {
  const dialog = d.createElement("dialog")
  dialog.dataset.open = "true"
  d.body.append(dialog)
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.ok(dialog.hasAttribute("open"), "opened when added open")
  dialog.dataset.open = "false"
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.ok(!dialog.hasAttribute("open"), "closed")
  dialog.dataset.open = "true"
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.ok(dialog.hasAttribute("open"), "opened again")
})

test("a click on a dialog's padding is not a click outside it; a form dialog stays open on either", async () => {
  const form = d.createElement("dialog")
  form.className = "form-dialog"
  form.dataset.open = "true"
  d.body.append(form)
  await new Promise((resolve) => setTimeout(resolve, 0))
  // jsdom lays nothing out, so the dialog gets a box: a click on the dialog inside it is a click on its padding.
  form.getBoundingClientRect = () => ({ left: 100, right: 400, top: 100, bottom: 300 })
  const at = (x, y) => new dom.window.MouseEvent("click", { bubbles: true, clientX: x, clientY: y })
  const event = (x, y) => { const e = at(x, y); Object.defineProperty(e, "target", { value: form }); return e }
  assert.equal(clickedOutside(form, event(110, 110)), false, "the padding")
  assert.equal(clickedOutside(form, event(20, 20)), true, "the backdrop")
  form.dispatchEvent(at(20, 20))
  assert.ok(form.hasAttribute("open"), "the form dialog stays")
})

test("a message is put into the page's one live region, and read again when it comes again", async () => {
  const region = d.querySelector('body > [role="status"][aria-live="polite"]')
  assert.ok(region, "the live region is there from the start")
  assert.equal(region.textContent, "")
  const snackbar = d.createElement("div")
  snackbar.dataset.announce = "Workout deleted"
  d.body.append(snackbar)
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.equal(region.textContent, "Workout deleted")
  snackbar.dataset.announce = "Plan deleted"
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.equal(region.textContent, "Plan deleted")
  snackbar.remove()
  const again = d.createElement("div")
  again.dataset.announce = "Plan deleted"
  d.body.append(again)
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(region.textContent, "", "emptied before the same words are put in again")
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.equal(region.textContent, "Plan deleted")
})
