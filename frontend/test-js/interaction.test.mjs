// The touch feedback and scrolled-app-bar glue (src/atlas/ui/interaction.ffi.mjs, ADR 0051) in jsdom. Run with
// scripts/test-frontend-js.sh.
import { test } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM(`<!doctype html><body>
  <button class="md-button">Save</button>
  <button class="md-button" disabled>Off</button>
  <nav class="tabs"><a href="/"><span class="nav-indicator"></span>Today</a></nav>
  <p class="plain">text</p>
  <button class="sheet-handle" aria-expanded="false">Week 1</button>
  <div role="tablist"><button role="tab">A</button><button role="tab">B</button><button role="tab">C</button></div>
  <div class="md-menu" id="m">
    <button role="menuitem">Edit</button><button role="menuitem">Delete</button><button role="menuitem">Share</button>
  </div>
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

test("dragging a sheet's handle up opens it and down closes it; a short drag does nothing", () => {
  const handle = d.querySelector(".sheet-handle")
  let clicks = 0
  handle.addEventListener("click", () => {
    clicks++
    handle.setAttribute("aria-expanded", handle.getAttribute("aria-expanded") === "true" ? "false" : "true")
  })
  const drag = (from, to) => {
    handle.dispatchEvent(new dom.window.MouseEvent("pointerdown", { bubbles: true, clientY: from }))
    d.body.dispatchEvent(new dom.window.MouseEvent("pointerup", { bubbles: true, clientY: to }))
  }
  drag(500, 490)
  assert.equal(clicks, 0, "too short")
  drag(500, 300)
  assert.equal(handle.getAttribute("aria-expanded"), "true")
  drag(500, 300)
  assert.equal(clicks, 1, "up again does not close an open sheet")
  drag(300, 500)
  assert.equal(handle.getAttribute("aria-expanded"), "false")
})

test("the arrow keys, Home and End move between a menu's items, wrapping around", () => {
  const items = [...d.querySelectorAll('[role="menuitem"]')]
  const key = (el, k) => el.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: k, bubbles: true }))
  items[0].focus()
  key(items[0], "ArrowDown")
  assert.equal(d.activeElement, items[1])
  key(items[1], "End")
  assert.equal(d.activeElement, items[2])
  key(items[2], "ArrowDown")
  assert.equal(d.activeElement, items[0])
  key(items[0], "ArrowUp")
  assert.equal(d.activeElement, items[2])
  key(items[2], "Home")
  assert.equal(d.activeElement, items[0])
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

test("the arrow keys choose the next or previous tab, wrapping around", () => {
  const tabs = [...d.querySelectorAll('[role="tab"]')]
  const chosen = []
  for (const tab of tabs) tab.addEventListener("click", () => chosen.push(tab.textContent))
  const key = (el, k) => el.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: k, bubbles: true }))
  key(tabs[0], "ArrowRight")
  key(tabs[1], "End")
  key(tabs[2], "ArrowRight")
  key(tabs[0], "ArrowLeft")
  assert.deepEqual(chosen, ["B", "C", "A", "C"])
  assert.equal(d.activeElement, tabs[2])
})

