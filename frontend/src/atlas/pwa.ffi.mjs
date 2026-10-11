// Service workers need HTTPS or localhost.
// An installed app is mostly resumed rather than reloaded, so it checks for a new worker whenever it comes back
// to the foreground, and reloads once a new worker takes over (ADR 0103).
export function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return
  const local = location.hostname === "localhost" || location.hostname === "127.0.0.1"
  if (location.protocol !== "https:" && !local) return
  const register = () =>
    navigator.serviceWorker
      .register("/sw.js")
      .then((registration) => {
        document.addEventListener("visibilitychange", () => {
          if (document.visibilityState === "visible") registration.update().catch(() => {})
        })
      })
      .catch((e) => console.warn("service worker:", e))
  // The first install also takes control (clients.claim), which is not an update.
  let reloading = false
  if (navigator.serviceWorker.controller) {
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (reloading) return
      reloading = true
      location.reload()
    })
  }
  if (document.readyState === "complete") register()
  else window.addEventListener("load", register)
}
