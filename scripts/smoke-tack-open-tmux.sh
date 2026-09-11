#!/usr/bin/env bash
# Real tmux smoke test on an isolated tmux server and throwaway HOME.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_TMUX="$(command -v tmux 2>/dev/null || true)"
[ -n "$REAL_TMUX" ] || { echo "smoke-tack-open-tmux: tmux required" >&2; exit 1; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tackopentmux)"
SOCKET="$TMP/tmux.sock"
cleanup() {
  "$REAL_TMUX" -S "$SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
export HARNESS_PROFILE_HOME="$HOME/.claude-profiles"
export HARNESS_NO_MEMORY_SETUP=1
export HARNESS_NO_PLUGIN_SETUP=1
export TACK_OPEN_TMUX_SOCKET="$SOCKET"
ROOT="$TMP/profiles"
NAME="smoke-$$"
PROFILE="$ROOT/tack-$NAME"
BIN="$TMP/bin"
WORK="$TMP/project with space"
mkdir -p "$HOME/.claude" "$CODEX_HOME" "$PROFILE" "$BIN" "$WORK"
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
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
exec sleep 30
SH
cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
exec sleep 30
SH
cat > "$BIN/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -S "$SOCKET" "\$@"
SH
chmod +x "$PROFILE/install.sh" "$BIN/claude" "$BIN/codex" "$BIN/tmux"
export PATH="$BIN:$PATH"

if ! launch_out="$(bash "$CORE/bin/tack" open "$NAME" --tmux --cwd "$WORK" --detach 2>&1)"; then
  printf '%s\n' "$launch_out"
  case "$launch_out" in
    *"Operation not permitted"*)
      echo "smoke-tack-open-tmux SKIPPED: environment forbids tmux socket creation"
      exit 0
      ;;
  esac
  exit 1
fi
printf '%s\n' "$launch_out"
SESSION="tack-$NAME"
panes="$("$REAL_TMUX" -S "$SOCKET" list-panes -t "$SESSION:agents" -F '#{pane_start_command}|#{pane_current_path}')"
printf '%s\n' "$panes"

[ "$(printf '%s\n' "$panes" | wc -l | tr -d ' ')" = "2" ]
printf '%s\n' "$panes" | grep -q 'CLAUDE_CONFIG_DIR='
printf '%s\n' "$panes" | grep -q 'codex -p'
if [ "$(printf '%s\n' "$panes" | awk -F '|' -v cwd="$WORK" '$2 == cwd {count++} END {print count+0}')" != "2" ]; then
  echo "smoke-tack-open-tmux: panes did not preserve working directory" >&2
  exit 1
fi

echo "smoke-tack-open-tmux passed"
