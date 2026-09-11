#!/usr/bin/env bash
# Real Herdr smoke test from a managed pane, using throwaway profile state.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "${HERDR_ENV:-}" = "1" ] || {
  echo "smoke-tack-open-herdr: run from a Herdr-managed pane (HERDR_ENV=1)" >&2
  exit 1
}
command -v herdr >/dev/null 2>&1 || { echo "smoke-tack-open-herdr: herdr required" >&2; exit 1; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tackopenherdr)"
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
export HARNESS_PROFILE_HOME="$HOME/.claude-profiles"
export HARNESS_NO_MEMORY_SETUP=1
export HARNESS_NO_PLUGIN_SETUP=1
ROOT="$TMP/profiles"
NAME="smoke-$$"
LABEL="tack-$NAME"
PROFILE="$ROOT/tack-$NAME"
BIN="$TMP/bin"
WORK="$TMP/project with space"
WORKSPACE=""
cleanup() {
  [ -n "$WORKSPACE" ] && herdr workspace close "$WORKSPACE" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$HOME/.claude/plugins" "$CODEX_HOME" "$PROFILE" "$BIN" "$WORK"
WORK="$(cd "$WORK" && pwd -P)"
printf '%s\n' "$ROOT" > "$HOME/.claude/.harness-root"
ln -s "$CORE" "$PROFILE/core"

cat > "$PROFILE/install.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "${CLAUDE_CONFIG_DIR:?}"
printf '%s\n' "smoke" > "$CLAUDE_CONFIG_DIR/.harness-active"
SH
cat > "$PROFILE/manifest.json" <<JSON
{
  "schema_version": 2,
  "name": "$NAME",
  "mcp": [],
  "memory": {"enabled": false, "engine": "none"},
  "providers": {
    "claude": {"plugins": {}, "env": {}},
    "codex": {"plugins": {}, "config": {}}
  }
}
JSON
cat > "$BIN/claude" <<SH
#!/bin/bash
printf '%s\n' "TACK_SMOKE_CLAUDE_STARTED:\$(pwd -P)"
pwd -P > "$TMP/claude.cwd"
exec sleep 30
SH
cat > "$BIN/codex" <<SH
#!/bin/bash
printf '%s\n' "TACK_SMOKE_CODEX_STARTED:\$(pwd -P)"
pwd -P > "$TMP/codex.cwd"
exec sleep 30
SH
chmod +x "$PROFILE/install.sh" "$BIN/claude" "$BIN/codex"
export PATH="$BIN:$PATH"

echo "== resolved launch plan =="
bash "$CORE/bin/tack" open "$NAME" --herdr --cwd "$WORK" --detach --dry-run
bash "$CORE/bin/tack" open "$NAME" --herdr --cwd "$WORK" --detach
WORKSPACE="$(herdr workspace list | jq -r --arg label "$LABEL" '
  [.result.workspaces[]? | select(.label == $label) | .workspace_id][0] // empty
' | tr -d '\r')"
[ -n "$WORKSPACE" ] || { echo "smoke-tack-open-herdr: workspace not found" >&2; exit 1; }

panes="$(herdr pane list --workspace "$WORKSPACE")"
printf '%s\n' "$panes"
[ "$(printf '%s' "$panes" | jq '[.result.panes[]?] | length' | tr -d '\r')" = "2" ]
claude_pane="$(printf '%s' "$panes" | jq -r --arg label "Claude $LABEL" '
  [.result.panes[]? | select(.label == $label) | .pane_id][0] // empty
' | tr -d '\r')"
codex_pane="$(printf '%s' "$panes" | jq -r --arg label "Codex $LABEL" '
  [.result.panes[]? | select(.label == $label) | .pane_id][0] // empty
' | tr -d '\r')"
bad_cwd="$(printf '%s' "$panes" | jq -r --arg cwd "$WORK" '
  [.result.panes[]? | select(.cwd != $cwd)] | length
' | tr -d '\r')"
[ "$bad_cwd" = "0" ] || {
  echo "smoke-tack-open-herdr: panes did not preserve working directory" >&2
  exit 1
}

attempt=0
while { [ ! -f "$TMP/claude.cwd" ] || [ ! -f "$TMP/codex.cwd" ]; } && [ "$attempt" -lt 100 ]; do
  sleep 0.1
  attempt=$((attempt + 1))
done

diagnose_pane() {
  local provider="$1" pane="$2" cwd_file="$3"
  echo "== $provider failure diagnostics ==" >&2
  echo "expected cwd: $WORK" >&2
  if [ -f "$cwd_file" ]; then
    echo "recorded cwd: $(cat "$cwd_file")" >&2
  else
    echo "recorded cwd: <probe did not start>" >&2
  fi
  if [ -n "$pane" ]; then
    echo "pane process:" >&2
    herdr pane process-info --pane "$pane" >&2 || true
    echo "pane transcript:" >&2
    herdr pane read "$pane" --source recent-unwrapped --lines 40 >&2 || true
  else
    echo "pane id: <not found>" >&2
  fi
}

[ "$(cat "$TMP/claude.cwd" 2>/dev/null || true)" = "$WORK" ] || {
  diagnose_pane "Claude" "$claude_pane" "$TMP/claude.cwd"
  echo "smoke-tack-open-herdr: Claude process cwd probe failed" >&2
  exit 1
}
[ "$(cat "$TMP/codex.cwd" 2>/dev/null || true)" = "$WORK" ] || {
  diagnose_pane "Codex" "$codex_pane" "$TMP/codex.cwd"
  echo "smoke-tack-open-herdr: Codex process cwd probe failed" >&2
  exit 1
}

echo "smoke-tack-open-herdr passed"
