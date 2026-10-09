// Page-wide interaction that needs the DOM: touch feedback and the app bar's scrolled state (ADR 0051), placing
// and moving through menus (ADR 0056), opening and closing dialogs with data-open (ADR 0057, 0066), and moving
// between tabs (ADR 0058). It only sets attributes, CSS variables and focus and calls the dialogs' own methods; it
// never adds or removes nodes, so Lustre's view of the DOM stays right.

const rippling = ".md-button, .md-fab, .md-icon-button, .choice-label, .link-list a, .tabs a .nav-indicator"

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
  // The arrow keys, Home and End move between a menu's items.
  document.addEventListener("keydown", (event) => {
    const menu = event.target instanceof Element ? event.target.closest(".md-menu") : null
    if (!menu) return
    const items = [...menu.querySelectorAll('[role="menuitem"]')]
    const at = items.indexOf(event.target)
    const next = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: items.length - 1 }[event.key]
    if (next === undefined) return
    event.preventDefault()
    items[(next + items.length) % items.length]?.focus()
  })

  // Tabs (ADR 0058): the arrow keys, Home and End choose the next, previous, first or last tab, as ARIA's tabs pattern
  // with automatic activation does.
  document.addEventListener("keydown", (event) => {
    const tab = event.target instanceof Element ? event.target.closest('[role="tab"]') : null
    const list = tab?.closest('[role="tablist"]')
    if (!list) return
    const tabs = [...list.querySelectorAll('[role="tab"]')]
    const at = tabs.indexOf(tab)
    const next = { ArrowRight: at + 1, ArrowLeft: at - 1, Home: 0, End: tabs.length - 1 }[event.key]
    if (next === undefined) return
    event.preventDefault()
    const target = tabs[(next + tabs.length) % tabs.length]
    target.focus()
    target.click()
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
          dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close() })
        }
        dialog.showModal()
      }
      else if (!wanted && dialog.open) dialog.close()
    }
  }
  new MutationObserver(syncDialogs).observe(document.body, {
    subtree: true, childList: true, attributes: true, attributeFilter: ["data-open"],
  })
  syncDialogs()

  // The top app bar takes a container color once the page has scrolled under it.
  const scrolled = () => {
    if (window.scrollY > 0) document.documentElement.dataset.scrolled = ""
    else delete document.documentElement.dataset.scrolled
  }
  window.addEventListener("scroll", scrolled, { passive: true })
  scrolled()
}
