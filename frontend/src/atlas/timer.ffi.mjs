export function after(milliseconds, callback) {
  setTimeout(callback, milliseconds)
}

// Checked again every second while a snackbar is pointed at or has the focus.
export function afterUnheld(milliseconds, callback) {
  const held = () => typeof document !== "undefined" && document.querySelector(".snackbar:hover, .snackbar:focus-within")
  const check = () => (held() ? setTimeout(check, 1000) : callback())
  setTimeout(check, milliseconds)
}
