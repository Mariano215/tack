#!/usr/bin/env bash
# claude-mem-setup.sh - make claude-mem actually run on this machine.
# Two failure modes this closes:
#   1. The plugin is enabled in settings.json but was never installed. The
#      enabledPlugins entry is inert until `npx claude-mem install` registers
#      the hooks and the worker, so a fresh container reports claude-mem
#      "enabled" and stores no memory at all.
#   2. The provider points at a local ollama (openrouter transport against a
#      Tailscale host). On a machine without that host reachable (Windows 11,
#      a container, off the tailnet) claude-mem fails quietly. Probe the host
#      and fall back to provider=claude on haiku.
# Best-effort by design: never fails the profile apply.
set -uo pipefail

CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MEM_DIR="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}"
MEM_SETTINGS="$MEM_DIR/settings.json"
FALLBACK_MODEL="${HARNESS_MEM_FALLBACK_MODEL:-claude-haiku-4-5-20251001}"

command -v jq >/dev/null 2>&1 || exit 0

# The ollama endpoint is per-tailnet, not a harness constant, so it is never
# committed: take it from HARNESS_MEM_OLLAMA_URL, else from what claude-mem is
# already configured with on this machine. No endpoint means no ollama, which
# lands on the claude/haiku path below.
OLLAMA_URL="${HARNESS_MEM_OLLAMA_URL:-$(jq -r '.CLAUDE_MEM_OPENROUTER_BASE_URL // ""' "$MEM_SETTINGS" 2>/dev/null)}"
OLLAMA_MODEL="${HARNESS_MEM_OLLAMA_MODEL:-$(jq -r '.CLAUDE_MEM_OPENROUTER_MODEL // ""' "$MEM_SETTINGS" 2>/dev/null)}"
enabled="$(jq -r '(.enabledPlugins // {})["claude-mem@thedotmack"] // false' "$CLAUDE/settings.json" 2>/dev/null)"
[ "$enabled" = "true" ] || { echo "  claude-mem: not enabled by this profile, skipped"; exit 0; }

# Provider choice. HARNESS_MEM_PROVIDER pins it; otherwise probe ollama.
if [ -n "${HARNESS_MEM_PROVIDER:-}" ]; then
  provider="$HARNESS_MEM_PROVIDER"
  [ "$provider" = "openrouter" ] && model="${OLLAMA_MODEL:-}" || model="$FALLBACK_MODEL"
elif [ -n "$OLLAMA_URL" ] && curl -fsS --max-time 3 "${OLLAMA_URL%/v1}/api/tags" >/dev/null 2>&1; then
  provider="openrouter"; model="$OLLAMA_MODEL"
else
  provider="claude"; model="$FALLBACK_MODEL"
  [ -n "$OLLAMA_URL" ] \
    && echo "  claude-mem: ollama unreachable at $OLLAMA_URL, falling back to claude/$FALLBACK_MODEL" \
    || echo "  claude-mem: no ollama endpoint configured, using claude/$FALLBACK_MODEL"
fi

if [ ! -f "$MEM_SETTINGS" ]; then
  command -v npx >/dev/null 2>&1 || { echo "  claude-mem: npx missing, install skipped"; exit 0; }
  echo "  claude-mem: installing (provider=$provider)"
  npx -y claude-mem install --provider "$provider" --model "$model" --disable-auto-memory >/dev/null 2>&1 \
    || echo "  claude-mem: install failed, run 'npx claude-mem install' by hand"
fi
[ -f "$MEM_SETTINGS" ] || exit 0

# Marketplace runtime. `claude plugin update` re-extracts the marketplace clone
# without running its install step, so node_modules vanishes and claude-mem's
# Setup hook falls back to a cold `bun install` (120s timeout) on every session
# start. That stall is long enough to drop the client's in-flight API
# connection, which surfaces as an intermittent "API Error: Connection error".
# Repair here so the profile apply, and the drift heal in plugin-auto-update.sh
# that calls it, actually fixes the state verify-setup.sh fails on.
MKT="${CLAUDE_MEM_MARKETPLACE_DIR:-$CLAUDE/plugins/marketplaces/thedotmack}"
if [ -f "$MKT/package.json" ] && [ ! -d "$MKT/node_modules" ]; then
  if command -v npx >/dev/null 2>&1; then
    echo "  claude-mem: marketplace runtime missing, repairing"
    npx -y claude-mem repair >/dev/null 2>&1 \
      || echo "  claude-mem: repair failed, run 'npx claude-mem repair' by hand"
  else
    echo "  claude-mem: marketplace runtime missing, npx absent (run: npx claude-mem repair)"
  fi
fi

# Provider keys are harness-owned so every machine summarizes the same way.
# Everything else in this file stays machine-local (ports, data dir, display).
tmp="$MEM_SETTINGS.harness.$$"
jq --arg p "$provider" --arg m "$model" --arg u "$OLLAMA_URL" '
  .CLAUDE_MEM_PROVIDER = $p
  | if $p == "openrouter" then
      .CLAUDE_MEM_OPENROUTER_BASE_URL = $u
      | .CLAUDE_MEM_OPENROUTER_MODEL = $m
      | .CLAUDE_MEM_OPENROUTER_API_KEY = (if (.CLAUDE_MEM_OPENROUTER_API_KEY // "") == "" then "ollama" else .CLAUDE_MEM_OPENROUTER_API_KEY end)
    else
      .CLAUDE_MEM_MODEL = $m
    end
' "$MEM_SETTINGS" > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }
if cmp -s "$tmp" "$MEM_SETTINGS"; then
  rm -f "$tmp"
  echo "  claude-mem: provider $provider ($model)"
else
  mv "$tmp" "$MEM_SETTINGS"
  echo "  claude-mem: provider set to $provider ($model)"
fi
