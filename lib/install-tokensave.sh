#!/usr/bin/env bash
# install-tokensave.sh - best-effort install of the tokensave CLI (code-graph).
# Used as a CLI, not MCP, so we do NOT run `tokensave install` (that would
# re-register the MCP + hooks). Non-blocking: any failure warns and returns 0.
set -uo pipefail

if command -v tokensave >/dev/null 2>&1; then
  echo "tokensave present: $(tokensave --version 2>/dev/null | head -1)"
  exit 0
fi

echo "installing tokensave CLI (best-effort)..."
if command -v brew >/dev/null 2>&1; then
  brew install aovestdipaperino/tap/tokensave && { echo "  installed via brew"; exit 0; }
fi
if command -v cargo >/dev/null 2>&1; then
  # --locked uses the crate's shipped Cargo.lock, avoiding transitive-dep
  # version conflicts on the default resolver. Fall back to unlocked.
  { cargo install --locked tokensave || cargo install tokensave; } \
    && { echo "  installed via cargo"; exit 0; }
fi

# Prebuilt archive fallback: detect os/arch, resolve the latest tag, pull the
# matching release asset. Assets are named tokensave-<tag>-<arch>-<os>.tar.gz.
os="$(uname -s | tr '[:upper:]' '[:lower:]')"; arch="$(uname -m)"
case "$arch" in x86_64|amd64) arch=x86_64;; arm64|aarch64) arch=aarch64;; esac
case "$os" in
  darwin) rel_os=macos ;;
  linux)  rel_os=linux ;;
  *) echo "  no installer path for $os/$arch; install tokensave manually (github.com/aovestdipaperino/tokensave)"; exit 0 ;;
esac

manual="  auto-install failed. Manual: brew install aovestdipaperino/tap/tokensave (mac), cargo install --locked tokensave, or a release archive from github.com/aovestdipaperino/tokensave/releases"
if ! command -v curl >/dev/null 2>&1; then echo "$manual"; exit 0; fi

tag="$(curl -fsSL https://api.github.com/repos/aovestdipaperino/tokensave/releases/latest \
  | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
if [ -z "$tag" ]; then echo "$manual"; exit 0; fi

url="https://github.com/aovestdipaperino/tokensave/releases/download/${tag}/tokensave-${tag}-${arch}-${rel_os}.tar.gz"
tmp="$(mktemp -d)"
mkdir -p "$HOME/.local/bin"
if curl -fsSL "$url" -o "$tmp/ts.tar.gz" 2>/dev/null && tar -xzf "$tmp/ts.tar.gz" -C "$tmp" 2>/dev/null; then
  bin="$(find "$tmp" -type f -name tokensave | head -1)"
  if [ -n "$bin" ]; then
    mv "$bin" "$HOME/.local/bin/tokensave"; chmod +x "$HOME/.local/bin/tokensave"
    echo "  installed prebuilt: ${arch}-${rel_os} (${tag})"
  else
    echo "$manual"
  fi
else
  echo "$manual"
fi
rm -rf "$tmp"
exit 0
