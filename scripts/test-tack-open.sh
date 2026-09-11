#!/usr/bin/env bash
# tack open command parsing, preflight, and tmux layout against throwaway state.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tackopen)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
export HARNESS_PROFILE_HOME="$HOME/.claude-profiles"
export HARNESS_NO_MEMORY_SETUP=1
export HARNESS_NO_PLUGIN_SETUP=1
ROOT="$TMP/profiles"
PROFILE="$ROOT/tack-dev"
BIN="$TMP/bin"
export TACK_OPEN_PROVIDER_LOG="$TMP/providers.log"
export TACK_OPEN_TMUX_LOG="$TMP/tmux.log"
export TACK_OPEN_TMUX_STATE="$TMP/tmux-state"
export TACK_OPEN_HERDR_LOG="$TMP/herdr.log"
export TACK_OPEN_HERDR_STATE="$TMP/herdr-state"
mkdir -p "$HOME/.claude/plugins" "$CODEX_HOME" "$PROFILE" "$BIN" "$TACK_OPEN_TMUX_STATE" "$TACK_OPEN_HERDR_STATE"
printf '%s\n' "$ROOT" > "$HOME/.claude/.harness-root"
ln -s "$CORE" "$PROFILE/core"

cat > "$PROFILE/install.sh" <<'SH'
#!/usr/bin/env bash
printf 'claude:%s\n' "${CLAUDE_CONFIG_DIR:-missing}" >> "$TACK_OPEN_PROVIDER_LOG"
mkdir -p "${CLAUDE_CONFIG_DIR:?}"
printf 'dev\n' > "$CLAUDE_CONFIG_DIR/.harness-active"
SH
cat > "$PROFILE/manifest.json" <<'JSON'
{
  "schema_version": 2,
  "name": "dev",
  "mcp": [],
  "memory": {"enabled": false, "engine": "none"},
  "providers": {
    "claude": {"plugins": {}, "env": {}},
    "codex": {"plugins": {}, "config": {"model_reasoning_effort": "high"}}
  }
}
JSON
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$BIN/tmux" <<'SH'
#!/usr/bin/env bash
{
  printf '%s' "${1:-}"
  shift || true
  for arg in "$@"; do printf '\t%s' "$arg"; done
  printf '\n'
} >> "$TACK_OPEN_TMUX_LOG"

case "$(tail -n1 "$TACK_OPEN_TMUX_LOG" | cut -f1)" in
  has-session)
    session=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = "-t" ] && { shift; session="${1:-}"; break; }
      shift
    done
    [ -f "$TACK_OPEN_TMUX_STATE/$session" ]
    ;;
  new-session)
    session=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = "-s" ] && { shift; session="${1:-}"; break; }
      shift
    done
    [ -n "$session" ] && : > "$TACK_OPEN_TMUX_STATE/$session"
    ;;
esac
SH
cat > "$BIN/herdr" <<'SH'
#!/usr/bin/env bash
{
  printf '%s' "${1:-}"
  shift || true
  for arg in "$@"; do printf '\t%s' "$arg"; done
  printf '\n'
} >> "$TACK_OPEN_HERDR_LOG"

group="$(tail -n1 "$TACK_OPEN_HERDR_LOG" | cut -f1-2)"
case "$group" in
  $'workspace\tlist')
    if [ -f "$TACK_OPEN_HERDR_STATE/label" ]; then
      label="$(cat "$TACK_OPEN_HERDR_STATE/label")"
      printf '{"result":{"type":"workspace_list","workspaces":[{"workspace_id":"w9","label":"%s"}]}}\n' "$label"
    else
      printf '{"result":{"type":"workspace_list","workspaces":[]}}\n'
    fi
    ;;
  $'workspace\tcreate')
    label=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--label" ] && { shift; label="${1:-}"; break; }
      shift
    done
    printf '%s\n' "$label" > "$TACK_OPEN_HERDR_STATE/label"
    printf '{"result":{"workspace":{"workspace_id":"w9"}}}\n'
    ;;
  $'workspace\tfocus') printf '{"result":{"focused":true}}\n' ;;
  $'workspace\tclose') rm -f "$TACK_OPEN_HERDR_STATE/label" "$TACK_OPEN_HERDR_STATE/split" ;;
  $'pane\tlist')
    if [ -f "$TACK_OPEN_HERDR_STATE/split" ]; then
      printf '{"result":{"panes":[{"pane_id":"w9:p1"},{"pane_id":"w9:p2"}]}}\n'
    else
      printf '{"result":{"panes":[{"pane_id":"w9:p1"}]}}\n'
    fi
    ;;
  $'pane\tsplit')
    : > "$TACK_OPEN_HERDR_STATE/split"
    printf '{"result":{"pane":{"pane_id":"w9:p2"}}}\n'
    ;;
  $'pane\trename'|$'pane\trun') printf '{"result":{"ok":true}}\n' ;;
esac
SH
chmod +x "$PROFILE/install.sh" "$BIN/claude" "$BIN/codex" "$BIN/tmux" "$BIN/herdr"
export PATH="$BIN:$PATH"

fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

echo "== 1. help is discoverable and plain =="
help="$(bash "$CORE/bin/tack" --help)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$help" | grep -qF 'tack open <profile>' \
  && printf '%s' "$help" | grep -qF 'Print the plan without applying or starting anything.' \
  && printf '%s' "$help" | grep -qF 'Publish reviewed core-pin commits after syncing.' \
  && ok "top-level help explains open and dry-run" || bad "top-level help incomplete"
open_help="$(bash "$CORE/bin/tack" open --help)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$open_help" | grep -qF 'Starts Codex with an explicit -p <profile> overlay.' \
  && printf '%s' "$open_help" | grep -qF 'Workspace names:' \
  && ok "open help explains isolation and names" || bad "open help incomplete"

echo "== 2. dry-run has no side effects =="
PROJECT="$TMP/project with space"
mkdir -p "$PROJECT"
PROJECT="$(cd "$PROJECT" && pwd -P)"
out="$(bash "$CORE/bin/tack" open dev --tmux --cwd "$PROJECT" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "dry-run exited $rc"; }
case "$out" in
  *"agents: both"*"workspace: tack-dev"*"working directory: $PROJECT"*"Codex pane: env CODEX_HOME="*"$BIN/codex -p dev -C"*)
    ok "dry-run prints resolved workspace plan" ;;
  *) echo "$out"; bad "dry-run output missing resolved values" ;;
esac
[ ! -e "$TACK_OPEN_PROVIDER_LOG" ] && [ ! -e "$TACK_OPEN_TMUX_LOG" ] \
  && ok "dry-run changed nothing" || bad "dry-run executed preflight or tmux"

echo "== 3. conflicting options fail before mutation =="
if bash "$CORE/bin/tack" open dev --claude --codex >/dev/null 2>&1; then
  bad "conflicting providers accepted"
else
  [ ! -e "$TACK_OPEN_PROVIDER_LOG" ] && [ ! -e "$TACK_OPEN_TMUX_LOG" ] \
    && ok "conflict rejected without mutation" || bad "conflict mutated state"
fi
if bash "$CORE/bin/tack" open '../dev' --dry-run >/dev/null 2>&1; then
  bad "unsafe profile name accepted"
else
  ok "unsafe profile name rejected"
fi

echo "== 4. tmux workspace prepares both agents once =="
echo global > "$CODEX_HOME/.harness-active"
out="$(bash "$CORE/bin/tack" open dev --tmux --cwd "$PROJECT" --detach)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "tmux open exited $rc"; }
grep -qxF "claude:$HARNESS_PROFILE_HOME/dev" "$TACK_OPEN_PROVIDER_LOG" \
  && ok "Claude isolated profile prepared" || bad "Claude preflight missing or wrong"
[ -f "$CODEX_HOME/dev.config.toml" ] && [ "$(cat "$CODEX_HOME/.harness-active")" = "global" ] \
  && ok "Codex overlay prepared without changing default" || bad "Codex preflight changed default"
grep -F $'new-session\t-d\t-s\ttack-dev\t-n\tagents\t-c\t'"$PROJECT" "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && grep -F 'CLAUDE_CONFIG_DIR=' "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && grep -F "$BIN/claude" "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && ok "first tmux pane launches isolated Claude" || bad "Claude tmux command wrong"
grep -F $'split-window\t-h\t-t\ttack-dev:agents\t-c\t'"$PROJECT" "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && grep -F "CODEX_HOME=$CODEX_HOME $BIN/codex -p dev -C ${PROJECT// /\\ }" "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && ok "second tmux pane launches profiled Codex" || bad "Codex tmux command wrong"

echo "== 5. repeated open reuses session without preflight =="
provider_lines="$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')"
new_lines="$(grep -c '^new-session' "$TACK_OPEN_TMUX_LOG")"
out="$(bash "$CORE/bin/tack" open dev --tmux --detach)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "repeat open exited $rc"; }
[ "$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')" = "$provider_lines" ] \
  && [ "$(grep -c '^new-session' "$TACK_OPEN_TMUX_LOG")" = "$new_lines" ] \
  && printf '%s' "$out" | grep -qF "attaching existing tmux session 'tack-dev'" \
  && ok "existing session attached without re-apply" || bad "repeat open duplicated work"

echo "== 6. single-provider workspace gets distinct name =="
out="$(bash "$CORE/bin/tack" open dev --codex --tmux --detach)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Codex-only open exited $rc"; }
grep -F $'new-session\t-d\t-s\ttack-dev-codex' "$TACK_OPEN_TMUX_LOG" >/dev/null \
  && ok "Codex-only session named distinctly" || bad "Codex-only session collided"
if awk -F '\t' '$1 == "split-window" && $4 == "tack-dev-codex:agents" {found=1} END {exit found ? 0 : 1}' "$TACK_OPEN_TMUX_LOG"; then
  bad "Codex-only workspace created a second pane"
else
  ok "Codex-only workspace has one pane"
fi

echo "== 7. Herdr launch requires managed context =="
before_provider="$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')"
if HERDR_ENV= bash "$CORE/bin/tack" open dev --herdr >/dev/null 2>&1; then
  bad "Herdr launch ran outside Herdr"
else
  [ "$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')" = "$before_provider" ] \
    && [ ! -e "$TACK_OPEN_HERDR_LOG" ] \
    && ok "outside-Herdr path stopped before mutation" || bad "outside-Herdr path mutated state"
fi

echo "== 8. Herdr workspace starts both agents and reuses IDs =="
out="$(HERDR_ENV=1 bash "$CORE/bin/tack" open dev --herdr --cwd "$PROJECT" --detach)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Herdr open exited $rc"; }
grep -F $'workspace\tcreate\t--cwd\t'"$PROJECT"$'\t--label\ttack-dev' "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && grep -F -- $'--env\tCLAUDE_CONFIG_DIR=' "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && ok "Herdr workspace carries cwd and Claude isolation" || bad "Herdr workspace args wrong"
grep -F $'pane\tsplit\tw9:p1\t--direction\tright\t--ratio\t0.5\t--cwd\t'"$PROJECT" "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && ok "Herdr created second pane from returned ID" || bad "Herdr split args wrong"
grep -F $'pane\trun\tw9:p1\tenv CLAUDE_CONFIG_DIR=' "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && grep -F "$BIN/claude" "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && grep -F $'pane\trun\tw9:p2\tenv CODEX_HOME=' "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && grep -F "$BIN/codex -p dev -C ${PROJECT// /\\ }" "$TACK_OPEN_HERDR_LOG" >/dev/null \
  && ok "Herdr launched Claude and Codex in explicit panes" || bad "Herdr agent commands wrong"
before_provider="$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')"
create_count="$(grep -c $'^workspace\tcreate' "$TACK_OPEN_HERDR_LOG")"
out="$(HERDR_ENV=1 bash "$CORE/bin/tack" open dev --herdr --detach)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Herdr reuse exited $rc"; }
[ "$(wc -l < "$TACK_OPEN_PROVIDER_LOG" | tr -d ' ')" = "$before_provider" ] \
  && [ "$(grep -c $'^workspace\tcreate' "$TACK_OPEN_HERDR_LOG")" = "$create_count" ] \
  && printf '%s' "$out" | grep -qF "reusing existing Herdr workspace 'tack-dev'" \
  && ok "Herdr workspace reused without preflight" || bad "Herdr reuse duplicated work"

echo "== 9. foreground Herdr create returns success =="
out="$(HERDR_ENV=1 bash "$CORE/bin/tack" open dev --codex --herdr)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "Herdr workspace 'tack-dev-codex' ready" \
  && grep -F $'workspace\tcreate' "$TACK_OPEN_HERDR_LOG" | grep -qF -- $'--focus' \
  && ok "foreground Herdr workspace focused and succeeded" || bad "foreground Herdr create failed"

if [ "$fails" -ne 0 ]; then
  echo "tack open tests FAILED: $fails"
  exit 1
fi
echo "tack open tests passed"
