#!/usr/bin/env bash
# Register claude-mem's Codex plugin from the Claude marketplace clone.
# Missing local runtime reports unavailable; it never selects a provider.
set -uo pipefail

VIEW="${1:?usage: setup-memory.sh <provider-view.json>}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
STATUS="$CODEX_DIR/.harness-memory-status"

if [ -n "${HARNESS_NO_MEMORY_SETUP:-}" ]; then
  echo "  Codex memory setup skipped (HARNESS_NO_MEMORY_SETUP is set)"
  echo "skipped" > "$STATUS"
  exit 0
fi

version="$(jq -r '.schema_version // 1' "$VIEW" | tr -d '\r')"
if [ "$version" = "1" ]; then
  enabled="true"
  engine="claude-mem"
else
  enabled="$(jq -r '.memory.enabled // false' "$VIEW" | tr -d '\r')"
  engine="$(jq -r '.memory.engine // "none"' "$VIEW" | tr -d '\r')"
fi

if [ "$enabled" != "true" ] || [ "$engine" = "none" ]; then
  echo "disabled" > "$STATUS"
  echo "  Codex memory disabled by profile"
  exit 0
fi
if [ "$engine" = "native" ]; then
  echo "native" > "$STATUS"
  echo "  Codex native memory enabled by profile"
  exit 0
fi
if [ "$engine" != "claude-mem" ]; then
  echo "unavailable: unknown engine $engine" > "$STATUS"
  echo "  Codex memory unavailable: unknown engine '$engine'"
  exit 0
fi

MARKETPLACE="$HOME/.claude/plugins/marketplaces/thedotmack"
if [ ! -f "$MARKETPLACE/.agents/plugins/marketplace.json" ]; then
  echo "unavailable: claude-mem local marketplace missing" > "$STATUS"
  echo "  Codex memory unavailable: claude-mem local marketplace missing"
  exit 0
fi
if ! command -v codex >/dev/null 2>&1; then
  echo "unavailable: codex CLI missing" > "$STATUS"
  echo "  Codex memory unavailable: codex CLI missing"
  exit 0
fi

codex plugin marketplace add "$MARKETPLACE" >/dev/null 2>&1 || true
codex plugin add claude-mem@claude-mem-local >/dev/null 2>&1 || true

# An older setup registered the same plugin MCP directly. Once the plugin is
# available, that second server duplicates search tools and can pin a stale
# cache version. Back up config.toml before asking Codex to remove only that
# named legacy server.
CONFIG="$CODEX_DIR/config.toml"
if grep -q '^\[mcp_servers\.claude-mem\]$' "$CONFIG" 2>/dev/null; then
  TS="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)"
  cp "$CONFIG" "$CONFIG.before-claude-mem-mcp.$TS"
  if codex mcp remove claude-mem >/dev/null 2>&1; then
    echo "  stale direct claude-mem MCP removed"
    echo "    restore: cp $CONFIG.before-claude-mem-mcp.$TS $CONFIG"
  else
    echo "  Codex memory warning: stale direct claude-mem MCP could not be removed"
  fi
fi

if grep -q '^\[marketplaces\.claude-mem-local\]$' "$CONFIG" 2>/dev/null \
  && grep -q '^\[plugins\."claude-mem@claude-mem-local"\]$' "$CONFIG" 2>/dev/null; then
  echo "claude-mem" > "$STATUS"
  echo "  Codex memory: claude-mem plugin registered"
else
  echo "unavailable: plugin registration failed" > "$STATUS"
  echo "  Codex memory unavailable: claude-mem plugin registration failed"
fi
