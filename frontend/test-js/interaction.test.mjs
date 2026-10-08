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
</body>`, { pretendToBeVisual: true })
Object.assign(globalThis, { document: dom.window.document, window: dom.window, Element: dom.window.Element })
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
