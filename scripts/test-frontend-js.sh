#!/usr/bin/env bash
# Tests the browser glue (frontend/src/atlas/*.ffi.mjs) and the whole app with Node: fake-indexeddb,
# jsdom and a real PocketBase. See ADR 0019 and 0020. Needs the toolchain (scripts/install-tools.sh) and npm.
# The npm packages are only for these tests and live in frontend/test-js, apart from the app build.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-frontend.sh >/dev/null   # also compiles the Gleam code the tests import
cd frontend/test-js
npm install --silent
exec node --test
