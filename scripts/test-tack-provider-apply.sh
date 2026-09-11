#!/usr/bin/env bash
# tack use applies each installed provider from one profile selection.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t hxproviders)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
ROOT="$TMP/profiles"
PROFILE="$ROOT/tack-dev"
BIN="$TMP/bin"
CLAUDE_CONFIG_DIR="$HOME/.claude"
export CLAUDE_CONFIG_DIR
mkdir -p "$HOME/.claude" "$CODEX_HOME" "$PROFILE" "$BIN"
printf '%s\n' "$ROOT" > "$HOME/.claude/.harness-root"
ln -s "$CORE" "$PROFILE/core"
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

cat > "$PROFILE/install.sh" <<'SH'
#!/usr/bin/env bash
echo claude >> "$TACK_PROVIDER_LOG"
SH
cat > "$PROFILE/manifest.json" <<'JSON'
{
  "schema_version": 2,
  "name": "dev",
  "mcp": [],
  "memory": {"enabled": true, "engine": "claude-mem"},
  "providers": {
    "claude": {"plugins": {}, "env": {}, "permissions": {}},
    "codex": {
      "plugins": {},
      "config": {"model_reasoning_effort": "high"},
      "permissions": {"approval_policy": "on-request"}
    }
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
chmod +x "$PROFILE/install.sh" "$BIN/claude" "$BIN/codex"
export PATH="$BIN:$PATH"
export TACK_PROVIDER_LOG="$TMP/providers.log"

echo "== 1. one selection applies Claude and Codex =="
out="$(bash "$CORE/bin/tack" use dev)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "tack use exited $rc"; }
[ "$(cat "$TACK_PROVIDER_LOG" 2>/dev/null)" = "claude" ] \
  && ok "Claude profile installer ran once" || bad "Claude profile installer did not run once"
[ -f "$CODEX_HOME/dev.config.toml" ] \
  && ok "Codex profile rendered" || bad "Codex profile missing"
[ "$(cat "$CODEX_HOME/.harness-active" 2>/dev/null)" = "dev" ] \
  && ok "Codex active profile matches selection" || bad "Codex active profile mismatch"
case "$out" in
  *"provider: Claude"*"provider: Codex"*) ok "provider boundaries printed in order" ;;
  *) echo "$out"; bad "provider boundaries missing" ;;
esac

echo "== 2. Codex-only machine skips Claude =="
ONLY_BIN="$TMP/codex-only-bin"
mkdir -p "$ONLY_BIN"
ln -s "$BIN/codex" "$ONLY_BIN/codex"
# Wrappers, not links: Git Bash's ln copies, and a copied python3.exe launcher
# can no longer find its install.
for t in jq python3; do printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" > "$ONLY_BIN/$t"; chmod +x "$ONLY_BIN/$t"; done
: > "$TACK_PROVIDER_LOG"
out="$(PATH="$ONLY_BIN:/usr/bin:/bin" bash "$CORE/bin/tack" use dev)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Codex-only tack use exited $rc"; }
[ ! -s "$TACK_PROVIDER_LOG" ] \
  && ok "Claude installer skipped" || bad "Claude installer ran without Claude CLI"
case "$out" in
  *"provider: Claude (CLI absent, skipped)"*"provider: Codex"*) ok "missing Claude reported" ;;
  *) echo "$out"; bad "missing Claude boundary absent" ;;
esac
list_out="$(PATH="$ONLY_BIN:/usr/bin:/bin" bash "$CORE/bin/tack" list)"
case "$list_out" in
  *"active: Claude=none   Codex=dev"*) ok "Codex-only active profile listed" ;;
  *) echo "$list_out"; bad "Codex-only active profile hidden" ;;
esac

echo "== 3. isolated Claude context does not switch global Codex =="
export CLAUDE_CONFIG_DIR="$HOME/.claude-profiles/dev"
mkdir -p "$CLAUDE_CONFIG_DIR"
out="$(bash "$CORE/bin/tack" use dev)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "isolated Claude tack use exited $rc"; }
case "$out" in
  *"provider: Codex (isolated Claude context, skipped)"*) ok "isolated Codex side effect prevented" ;;
  *) echo "$out"; bad "isolated Claude context applied global Codex" ;;
esac
export CLAUDE_CONFIG_DIR="$HOME/.claude"

echo "== 4. Codex collision makes tack use fail loudly =="
echo 'model = "user-owned"' > "$CODEX_HOME/dev.config.toml"
out="$(bash "$CORE/bin/tack" use dev)"; rc=$?
[ "$rc" -ne 0 ] || bad "tack use hid Codex apply failure"
case "$out" in
  *"Codex apply failed"*) ok "Codex failure names provider" ;;
  *) echo "$out"; bad "Codex failure did not name provider" ;;
esac
grep -q 'user-owned' "$CODEX_HOME/dev.config.toml" \
  && ok "failed Codex apply preserved user profile" || bad "failed Codex apply changed user profile"

echo ""
if [ "$fails" -ne 0 ]; then
  echo "test-tack-provider-apply FAILED ($fails)."
  exit 1
fi
echo "test-tack-provider-apply passed."
