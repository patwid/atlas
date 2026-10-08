// Material 3 touch feedback and the app bar's scrolled state (ADR 0051). Both only set data attributes and CSS
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

  // The top app bar takes a container color once the page has scrolled under it.
  const scrolled = () => {
    if (window.scrollY > 0) document.documentElement.dataset.scrolled = ""
    else delete document.documentElement.dataset.scrolled
  }
  window.addEventListener("scroll", scrolled, { passive: true })
  scrolled()
}
