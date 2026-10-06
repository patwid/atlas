#!/usr/bin/env bash
# Runs the PocketBase API rule tests against a throwaway instance. See ADR 0009.
set -euo pipefail
cd "$(dirname "$0")/.."
exec node --test --test-timeout=180000 backend/tests/*.test.mjs   # a stuck test fails instead of blocking forever
