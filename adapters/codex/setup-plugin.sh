#!/usr/bin/env bash
# Register the repo-local Codex policy plugin. Registration is best effort;
# Codex requires the user to review and trust hooks separately through /hooks.
set -uo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
MARKETPLACE="$CORE_DIR/codex-marketplace"
STATUS="$CODEX_DIR/.harness-plugin-status"
mkdir -p "$CODEX_DIR"

if [ -n "${HARNESS_NO_PLUGIN_SETUP:-}" ]; then
  echo "skipped" > "$STATUS"
  echo "  Codex policy plugin setup skipped (HARNESS_NO_PLUGIN_SETUP is set)"
  exit 0
fi
if [ ! -f "$MARKETPLACE/.agents/plugins/marketplace.json" ]; then
  echo "unavailable: marketplace missing" > "$STATUS"
  echo "  Codex policy plugin unavailable: marketplace missing"
  exit 0
fi
if ! command -v codex >/dev/null 2>&1; then
  echo "unavailable: codex CLI missing" > "$STATUS"
  echo "  Codex policy plugin unavailable: codex CLI missing"
  exit 0
fi

if ! codex plugin marketplace add "$MARKETPLACE" >/dev/null 2>&1; then
  # Re-adding an existing marketplace can return non-zero on some CLI builds.
  # Config inspection below determines the actual result.
  :
fi
if ! codex plugin add harness-policy@agent-harness >/dev/null 2>&1; then
  :
fi

CONFIG="$CODEX_DIR/config.toml"
if grep -q '^\[marketplaces\.agent-harness\]$' "$CONFIG" 2>/dev/null \
  && grep -q '^\[plugins\."harness-policy@agent-harness"\]$' "$CONFIG" 2>/dev/null; then
  echo "registered: review trust with /hooks" > "$STATUS"
  echo "  Codex policy plugin registered; review hook trust with /hooks"
else
  echo "unavailable: registration failed" > "$STATUS"
  echo "  Codex policy plugin unavailable: registration failed"
fi
