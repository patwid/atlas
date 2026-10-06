#!/usr/bin/env bash
# Installs the pinned toolchain from .tool-versions (Debian/Ubuntu, x86_64 or aarch64). See ADR 0006.
set -euo pipefail
cd "$(dirname "$0")/.."
ver() { awk -v t="$1" '$1 == t { print $2 }' .tool-versions; }
GLEAM=$(ver gleam); PB=$(ver pocketbase)
BIN="${BIN:-$HOME/.local/bin}"; mkdir -p "$BIN"
case "$(uname -m)" in
  x86_64)  GLEAM_ARCH=x86_64;  PB_ARCH=amd64 ;;
  aarch64) GLEAM_ARCH=aarch64; PB_ARCH=arm64 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq erlang-base erlang-dev erlang-crypto \
  erlang-inets erlang-ssl erlang-public-key erlang-syntax-tools erlang-eunit erlang-xmerl \
  erlang-parsetools rebar3

curl -sSLf "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM}/gleam-v${GLEAM}-${GLEAM_ARCH}-unknown-linux-musl.tar.gz" \
  | tar xz -C "$BIN"
curl -sSLf -o "$tmp/pb.zip" "https://github.com/pocketbase/pocketbase/releases/download/v${PB}/pocketbase_${PB}_linux_${PB_ARCH}.zip"
unzip -oq "$tmp/pb.zip" pocketbase -d "$BIN"

"$BIN/gleam" --version; "$BIN/pocketbase" --version
