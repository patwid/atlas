# 0103. Check for updates when the app is resumed, and reload when a new version takes over

- Status: Accepted
- Date: 2026-10-11
- Deciders: agent (approved by the owner after reporting that the installed app on Android kept the old version while the browser showed the new one)

## Context

After [0101](0101-no-dates-on-the-app-shell.md), the browser on Android showed a new deploy but the app installed on the home
screen did not. Two causes remained:

- The browser checks `sw.js` only when a page loads. An installed app is usually resumed from the background with the old page
  in memory, so it neither loads a page nor checks, and even after a new worker took over (it is shared with the browser) the
  open app keeps running the old code until it is restarted.
- The worker's `cache.addAll` goes through the HTTP cache. Shell files fetched before 0101 carry a 1970 `Last-Modified` and no
  `Cache-Control`, which heuristic caching treats as fresh for years, so a new worker could precache the old `index.html`,
  `atlas.js` and `app.css` under its new cache name. The `no-cache` from 0101 only applies to responses stored after it.

## Options considered

1. **Check on resume and reload on takeover**: `registration.update()` on `visibilitychange` to visible, and `location.reload()`
   on `controllerchange` when the page already had a worker. The new version appears about a second after reopening the app.
   A form being filled in at that moment is lost.
2. **Check on resume and show an "Update available" prompt**: no lost input, but needs UI and a message from the worker. More work
   for a single-user app.
3. **Leave it to restarts**: Android rarely restarts an app the user did not swipe away.

## Decision

Option 1, and the worker precaches with `cache: "reload"`, so it always gets the files from the network.

## Consequences

- An installed app shows a new deploy shortly after it is brought back to the foreground.
- The reload can discard unsaved input if the user starts typing in the second before the new worker takes over. Revisit with
  option 2 if that happens in practice.
- The first install does not reload the page: it is not an update, and the page had no controller.
