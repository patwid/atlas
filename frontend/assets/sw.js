// Atlas service worker (ADR 0004): caches the app shell only. API calls are never cached;
// offline data is handled by the app. The build script (scripts/build-frontend.sh) stamps a cache
// name and the file list into the two placeholders below, so each build gets its own cache and
// old ones are removed. Unstamped (dev server) it is harmless: install fails and nothing is cached.
const CACHE = "atlas-shell-__BUILD__"
const SHELL = ["/__PRECACHE__"]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith("atlas-shell-") && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener("fetch", (event) => {
  const req = event.request
  const url = new URL(req.url)
  if (req.method !== "GET" || url.origin !== self.location.origin) return
  // PocketBase API and admin UI go straight to the network.
  if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/_/")) return

  if (req.mode === "navigate") {
    // Single-page app: every page is the shell. Fall back to the network only when it is not cached.
    event.respondWith(caches.match("/").then((hit) => hit || fetch(req)))
    return
  }
  event.respondWith(caches.match(req).then((hit) => hit || fetch(req)))
})
