// Service workers need HTTPS or localhost.
export function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return
  const local = location.hostname === "localhost" || location.hostname === "127.0.0.1"
  if (location.protocol !== "https:" && !local) return
  const register = () => navigator.serviceWorker.register("/sw.js").catch((e) => console.warn("service worker:", e))
  if (document.readyState === "complete") register()
  else window.addEventListener("load", register)
}
