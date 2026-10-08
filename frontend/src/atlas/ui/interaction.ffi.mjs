// Material 3 touch feedback, the app bar's scrolled state (ADR 0051), dragging a bottom sheet (ADR 0052) and
// placing and moving through menus (ADR 0056). Both only set data attributes and CSS
// variables, never add or remove nodes, so Lustre's view of the DOM stays right.

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

  // A bottom sheet's handle can be dragged as well as pressed (ADR 0052): a swipe up opens the sheet and a swipe
  // down closes it, by clicking the handle, so the page's own message does the work. A swipe that ends on the
  // handle needs nothing: the browser clicks it anyway.
  let drag = null
  document.addEventListener("pointerdown", (event) => {
    const handle = event.target instanceof Element ? event.target.closest(".sheet-handle") : null
    drag = handle ? { handle, y: event.clientY } : null
  }, { passive: true })
  document.addEventListener("pointerup", (event) => {
    if (!drag) return
    const { handle, y } = drag
    drag = null
    if (event.target instanceof Element && handle.contains(event.target)) return
    const moved = event.clientY - y
    const open = handle.getAttribute("aria-expanded") === "true"
    if ((moved < -30 && !open) || (moved > 30 && open)) handle.click()
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

  // The top app bar takes a container color once the page has scrolled under it.
  const scrolled = () => {
    if (window.scrollY > 0) document.documentElement.dataset.scrolled = ""
    else delete document.documentElement.dataset.scrolled
  }
  window.addEventListener("scroll", scrolled, { passive: true })
  scrolled()
}
