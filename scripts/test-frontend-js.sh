#!/usr/bin/env bash
# Tests the browser glue (frontend/src/atlas/*.ffi.mjs) with Node and fake-indexeddb. See ADR 0019.
# The npm packages are only for these tests and live in frontend/test-js, apart from the app build.
set -euo pipefail
cd "$(dirname "$0")/../frontend"
gleam build >/dev/null
cd test-js
npm ci --silent
exec node --test
