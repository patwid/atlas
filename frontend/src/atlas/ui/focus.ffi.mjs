// Moves the focus to an element once the view that holds it has been drawn. Focusing also scrolls it into view,
// which is what brings the plan's sidebar form into sight on a phone (ADR 0043).
export function focusSoon(id) {
  if (typeof document === "undefined") return
  requestAnimationFrame(() => document.getElementById(id)?.focus())
}
