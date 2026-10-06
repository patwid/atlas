export function isOnline() {
  return typeof navigator === "undefined" ? true : navigator.onLine
}

export function listen(dispatch) {
  window.addEventListener("online", () => dispatch(true))
  window.addEventListener("offline", () => dispatch(false))
}
