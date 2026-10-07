#!/usr/bin/env bash
# Tests the browser glue (frontend/src/atlas/*.ffi.mjs) and the whole app with Node: fake-indexeddb,
# jsdom and a real PocketBase. See ADR 0019 and 0020. Needs the toolchain (scripts/install-tools.sh) and npm.
# The npm packages are only for these tests and live in frontend/test-js, apart from the app build.
# ATLAS_NPM_INSTALL=0 skips npm install: the Nix check (ADR 0042) brings node_modules from the lock file.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-frontend.sh >/dev/null   # also compiles the Gleam code the tests import
cd frontend/test-js
[ "${ATLAS_NPM_INSTALL:-1}" = 0 ] || npm install --silent
exec node --test --test-timeout=120000   # a stuck test fails after two minutes instead of blocking forever
