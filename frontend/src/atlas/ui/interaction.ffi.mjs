// Page-wide interaction that needs the DOM: touch feedback and the app bar's scrolled state (ADR 0051), opening and
// closing dialogs with data-open (ADR 0057, 0066, 0133), and reading out messages (ADR 0124). Fluent UI's menus place
// themselves and move between their items (ADR 0133). It only sets attributes, CSS variables and focus and calls the dialogs' own methods; it never
// adds or removes nodes inside the app, so Lustre's view of the DOM stays right. The one node it adds, the live
// region, is outside the app's root.

const rippling = ".md-button, .md-icon-button, .choice-label, .link-list a, .tabs a .nav-indicator"

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

  // A ripple grows from where the pointer went down. The two names restart the animation on every press.
  document.addEventListener("pointerdown", (event) => {
    const start = event.target instanceof Element ? event.target : null
    const target = start?.closest(".tabs a")?.querySelector(".nav-indicator") ?? start?.closest(rippling)
    if (!target || target.matches(":disabled")) return
    const box = target.getBoundingClientRect()
    const size = Math.hypot(box.width, box.height) * 2
    target.style.setProperty("--ripple-x", `${event.clientX - box.left}px`)
    target.style.setProperty("--ripple-y", `${event.clientY - box.top}px`)
    target.style.setProperty("--ripple-size", `${size}px`)
    target.dataset.ripple = target.dataset.ripple === "a" ? "b" : "a"
  }, { passive: true })

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
      if (wanted && !dialog.open) {
        // Basic dialogs (details, choices; ADR 0066) close on a click outside them, as M3's do; form dialogs do not,
        // so nothing typed is lost (ADR 0057).
        if (!dialog.classList.contains("form-dialog") && !dialog.dataset.lightDismiss) {
          dialog.dataset.lightDismiss = "on"
          dialog.addEventListener("click", (event) => { if (clickedOutside(dialog, event)) dialog.close() })
        }
        dialog.showModal()
      }
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
