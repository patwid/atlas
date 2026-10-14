// Page-wide interaction that needs the DOM: touch feedback and the app bar's scrolled state (ADR 0051), placing
// and moving through menus (ADR 0056), opening and closing dialogs with data-open (ADR 0057, 0066), and reading out
// messages (ADR 0124). It only sets attributes, CSS variables and focus and calls the dialogs' own methods; it never
// adds or removes nodes inside the app, so Lustre's view of the DOM stays right. The one node it adds, the live
// region, is outside the app's root.

const rippling = ".md-button, .md-icon-button, .choice-label, .link-list a, .md-menu-item, .tabs a .nav-indicator"

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

  // Menus (ADR 0056) are native popovers. When one opens it is placed under the button that opened it, lined up
  // with its end (above it when there is no room below), and its first item takes the focus.
  document.addEventListener("toggle", (event) => {
    const menu = event.target
    if (!(menu instanceof Element) || !menu.classList.contains("md-menu") || event.newState !== "open") return
    const opener = document.querySelector(`[popovertarget="${menu.id}"]:not([role="menuitem"])`)
    if (opener) {
      const anchor = opener.getBoundingClientRect()
      const { offsetWidth: width, offsetHeight: height } = menu
      const left = Math.max(8, Math.min(anchor.right - width, window.innerWidth - width - 8))
      const below = anchor.bottom + 4
      const top = below + height > window.innerHeight - 8 ? Math.max(8, anchor.top - height - 4) : below
      menu.style.setProperty("left", `${left}px`)
      menu.style.setProperty("top", `${top}px`)
    }
    menu.querySelector('[role="menuitem"]')?.focus()
  }, true)
  // The arrow keys, Home and End move between a menu's items; Tab closes the menu and moves on from its button.
  document.addEventListener("keydown", (event) => {
    const menu = event.target instanceof Element ? event.target.closest(".md-menu") : null
    if (!menu) return
    if (event.key === "Tab") {
      menu.hidePopover?.()
      return
    }
    const items = [...menu.querySelectorAll('[role="menuitem"]')]
    const at = items.indexOf(event.target)
    const next = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: items.length - 1 }[event.key]
    if (next === undefined) return
    event.preventDefault()
    items[(next + items.length) % items.length]?.focus()
  })

  // Form dialogs (ADR 0057) say with data-open whether they should show; this keeps the native modal in step.
  const syncDialogs = () => {
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
