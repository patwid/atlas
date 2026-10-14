// The touch feedback and scrolled-app-bar glue (src/atlas/ui/interaction.ffi.mjs, ADR 0051) in jsdom. Run with
// scripts/test-frontend-js.sh.
import { test } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM(`<!doctype html><body>
  <button class="md-button">Save</button>
  <button class="md-button" disabled>Off</button>
  <nav class="tabs"><a href="/"><span class="nav-indicator"></span>Home</a></nav>
  <p class="plain">text</p>
</body>`, { pretendToBeVisual: true })
Object.assign(globalThis, {
  document: dom.window.document, window: dom.window, Element: dom.window.Element, MutationObserver: dom.window.MutationObserver,
})
dom.window.HTMLDialogElement.prototype.showModal = function () { this.setAttribute("open", "") }
dom.window.HTMLDialogElement.prototype.close = function () { this.removeAttribute("open") }
const { install } = await import("../build/dev/javascript/atlas/atlas/ui/interaction.ffi.mjs")
install()
install() // a second call adds no second set of listeners

const d = dom.window.document
const press = (el) => el.dispatchEvent(new dom.window.MouseEvent("pointerdown", { bubbles: true, clientX: 5, clientY: 6 }))

test("a press starts a ripple where the pointer went down, and the next press restarts it", () => {
  const save = d.querySelector(".md-button")
  press(save)
  assert.equal(save.dataset.ripple, "a")
  assert.equal(save.style.getPropertyValue("--ripple-x"), "5px")
  assert.equal(save.style.getPropertyValue("--ripple-y"), "6px")
  press(save)
  assert.equal(save.dataset.ripple, "b")
})

test("a navigation tab ripples in its indicator; disabled buttons and other elements do not ripple", () => {
  press(d.querySelector(".tabs a"))
  assert.equal(d.querySelector(".nav-indicator").dataset.ripple, "a")
  press(d.querySelector("button[disabled]"))
  assert.equal(d.querySelector("button[disabled]").dataset.ripple, undefined)
  press(d.querySelector(".plain"))
  assert.equal(d.querySelector(".plain").dataset.ripple, undefined)
})

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

test("a basic dialog closes on a click outside it, not on its own padding; a form dialog does not", async () => {
  const basic = d.createElement("dialog")
  basic.dataset.open = "true"
  const form = d.createElement("dialog")
  form.className = "form-dialog"
  form.dataset.open = "true"
  d.body.append(basic, form)
  await new Promise((resolve) => setTimeout(resolve, 0))
  // jsdom lays nothing out, so the dialogs get a box: a click on the dialog inside it is a click on its padding.
  const box = { left: 100, right: 400, top: 100, bottom: 300 }
  basic.getBoundingClientRect = form.getBoundingClientRect = () => box
  const click = (el, x, y) => el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, clientX: x, clientY: y }))
  click(basic, 110, 110)
  assert.ok(basic.hasAttribute("open"), "a click on the padding leaves it open")
  click(basic, 20, 20)
  click(form, 20, 20)
  assert.ok(!basic.hasAttribute("open"), "the basic dialog closed")
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
