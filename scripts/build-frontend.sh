#!/usr/bin/env bash
# Builds the Lustre app and copies it to backend/pb_public, where PocketBase serves it. See ADR 0013.
# The service worker gets a per-build cache name and the list of files to precache (ADR 0004).
# ATLAS_BUILD_ID and ATLAS_PUBLIC_OUT override the build id and the output directory.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

rm -rf frontend/dist # the build does not remove files from earlier builds
(cd frontend && gleam run -m lustre/dev build atlas --minify=true)

dist=frontend/dist
build="${ATLAS_BUILD_ID:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)-$(date +%Y%m%d%H%M%S)}"
precache=$(cd "$dist" && find . -type f ! -name sw.js | sed 's|^\./|/|' | sort | awk 'BEGIN{printf "[\"/\""} {printf ",\"%s\"", $0} END{print "]"}')
sed -i -e "s|__BUILD__|$build|" -e "s|\[\"/__PRECACHE__\"\]|$precache|" "$dist/sw.js"

out="${ATLAS_PUBLIC_OUT:-backend/pb_public}" # the Nix build sets both variables (ADR 0033)
mkdir -p "$out"
find "$out" -mindepth 1 ! -name .gitkeep -delete
cp -r "$dist"/. "$out"/
echo "Built $build into $out"
