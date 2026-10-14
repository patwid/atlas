// Page-wide interaction that needs the DOM: the app bar's scrolled state (ADR 0051), opening and closing dialogs
// with data-open (ADR 0057, 0066, 0133), and reading out messages (ADR 0124). Fluent UI's menus place themselves and
// move between their items, and Fluent has no ripple (ADR 0133). It only sets attributes and focus and calls the
// dialogs' own methods; it never adds or removes nodes inside the app, so Lustre's view of the DOM stays right. The
// one node it adds, the live region, is outside the app's root.

/** Opens a Fluent UI dialog (ADR 0133). A form with method="dialog" in it cannot close it, as its <dialog> is in its
 * shadow root, so the form's submit closes it instead. */
export function showFluent(dialog) {
  if (!dialog.dataset.submitBound) {
    dialog.addEventListener("submit", (event) => {
      if (event.target.getAttribute("method") !== "dialog") return
      event.preventDefault()
      dialog.hide()
    })
    dialog.dataset.submitBound = "true"
  }
  dialog.show()
}

/** Whether a click on a dialog fell outside its box, on the backdrop. A click on the dialog's own padding also has
 * the dialog as its target, so the target alone does not tell (ADR 0124). */
export function clickedOutside(dialog, event) {
  if (event.target !== dialog) return false
  const box = dialog.getBoundingClientRect()
  return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom
}

export function install() {
  if (typeof document === "undefined" || document.documentElement.dataset.interaction) return
  document.documentElement.dataset.interaction = "on"

  // Form dialogs (ADR 0057) say with data-open whether they should show; this keeps the native modal in step. So do
  // Fluent UI's dialogs (details and choices, ADR 0133), whose own show() and hide() open and close them.
  const syncDialogs = () => {
    for (const dialog of document.querySelectorAll("fluent-dialog[data-open]")) {
      // Drawn before Fluent's bundle has loaded: again once it has.
      if (typeof dialog.show !== "function") {
        customElements.whenDefined("fluent-dialog").then(syncDialogs)
        continue
      }
      const wanted = dialog.dataset.open === "true"
      const open = !!dialog.shadowRoot?.querySelector("dialog")?.open
      if (wanted && !open) showFluent(dialog)
      else if (!wanted && open) dialog.hide()
    }
    for (const dialog of document.querySelectorAll("dialog[data-open]")) {
      const wanted = dialog.dataset.open === "true"
      // Only form dialogs are native and open this way; they do not close on a click outside, so nothing typed is
      // lost (ADR 0057).
      if (wanted && !dialog.open) dialog.showModal()
      else if (!wanted && dialog.open) dialog.close()
    }
  }
  // Messages (snackbars, loading) carry their text in data-announce. A live region added to the page together with
  // its text is often not read out, so one region stays in the page, empty, and each new message is put into it.
  const region = document.createElement("div")
  region.className = "visually-hidden"
  region.setAttribute("role", "status")
  region.setAttribute("aria-live", "polite")
  document.body.append(region)
  const announced = new WeakMap()
  const announce = () => {
    for (const el of document.querySelectorAll("[data-announce]")) {
      const text = el.dataset.announce
      if (announced.get(el) === text) continue
      announced.set(el, text)
      // Emptied first, so the same words said again are read again.
      region.textContent = ""
      setTimeout(() => { region.textContent = text }, 50)
    }
  }
  new MutationObserver(() => { syncDialogs(); announce() }).observe(document.body, {
    subtree: true, childList: true, attributes: true, attributeFilter: ["data-open", "data-announce"],
  })
  syncDialogs()
  announce()

  // The top app bar takes a container color once the page has scrolled under it.
  const scrolled = () => {
    if (window.scrollY > 0) document.documentElement.dataset.scrolled = ""
    else delete document.documentElement.dataset.scrolled
  }
  window.addEventListener("scroll", scrolled, { passive: true })
  scrolled()
}
