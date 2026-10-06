# 0013. App shell, routing and PWA build

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (within [0003](0003-use-gleam-lustre-frontend.md) and [0004](0004-offline-first-data-and-sync.md))

## Context

ADR 0003 chose Lustre with `lustre_dev_tools`, and 0004 an app-shell-only service worker. The
frontend was still the Gleam template. It needs pages, a frame, an offline indicator and a build that
PocketBase can serve from `pb_public`.

## Decision

- **Routing**: path-based URLs (`/plans/abc`) with the `modem` package. PocketBase serves `index.html`
  for unknown paths, so deep links and reloads work without a hash. The route type and the parse and
  print functions live in a pure module (`atlas/route`) with tests. Pages are Today, Plans, a single Plan,
  Activities and Settings. The pages are empty states until the data layer is built.
- **Structure**: `atlas.gleam` has the model, `update` and the page dispatch. `atlas/shell.gleam` is the frame
  (header, offline pill, bottom tab bar). Browser access is limited to `online.ffi.mjs` and `pwa.ffi.mjs`,
  both without logic (ADR 0003).
- **Styling**: one plain CSS file (`assets/app.css`) with colour tokens, a dark scheme through
  `prefers-color-scheme`, a mobile-first layout and safe-area insets. No CSS framework.
- **PWA files** in `frontend/assets/` are copied to the build output: `manifest.json`, an SVG icon and `sw.js`.
  The manifest ends in `.json` because PocketBase serves `.webmanifest` as `text/plain`.
- **Service worker** (`sw.js`, plain JS): precaches the shell, serves it cache-first, answers
  navigations with the cached `index.html`, and never touches `/api/` or `/_/`. Cache-first would keep
  old code forever, so `scripts/build-frontend.sh` stamps each build with its own cache name and
  the file list, and the worker deletes older `atlas-shell-*` caches on activation.
- **Build**: `scripts/build-frontend.sh` runs `lustre/dev build`, stamps `sw.js` and copies `dist/` to `backend/pb_public`.
  `lustre_dev_tools` downloads Bun on first use, so the build needs network access to GitHub.
- The worker is registered only on HTTPS or localhost.

## Consequences

- A new deploy is picked up on the next visit after the new worker has activated. It takes over
  immediately (`skipWaiting`) while open tabs may still run old code until reloaded. There is no
  update prompt yet.
- The icon is an SVG only. Some platforms want PNG icons (192 and 512 px) for installation, so
  they should be added before launch.
- The shell was checked with the real bundle in jsdom (deep link, navigation, offline pill). Service
  worker behaviour and installability have not been tested in a real browser.
- The sync, IndexedDB and PocketBase auth work (0004) comes next and will replace the placeholders.
