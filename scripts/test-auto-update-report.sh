#!/usr/bin/env bash
# The daily hook must fetch and report, never pull or re-apply. A pull plus
# re-apply here ran whatever was last pushed on every machine, unattended.
set -uo pipefail
CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t autoupd)"
trap 'rm -rf "$TMP"' EXIT
failed=0
fail() { echo "test-auto-update-report: $1"; failed=1; }

unset CLAUDE_CONFIG_DIR
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\necho called >> "%s/tack-called"\n' "$TMP" > "$BIN/tack"; chmod +x "$BIN/tack"
printf '#!/bin/sh\nexit 0\n' > "$BIN/claude"; chmod +x "$BIN/claude"
export PATH="$BIN:/usr/bin:/bin"
git config --global user.email t@t 2>/dev/null; git config --global user.name t 2>/dev/null

ROOT="$TMP/root"; mkdir -p "$ROOT"
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$ROOT/tack-p" 2>/dev/null
( cd "$ROOT/tack-p" && git commit -q --allow-empty -m one && git push -q -u origin HEAD 2>/dev/null )
git clone -q "$TMP/origin.git" "$TMP/other" 2>/dev/null
( cd "$TMP/other" && git commit -q --allow-empty -m two && git push -q origin HEAD 2>/dev/null )

echo "$ROOT" > "$HOME/.claude/.harness-root"
echo p > "$HOME/.claude/.harness-active"
date +%s > "$HOME/.claude/.plugin-update-shared"   # skip the shared plugin sweep
before="$(git -C "$ROOT/tack-p" rev-parse HEAD)"

bash "$CORE/hooks/plugin-auto-update.sh" </dev/null >/dev/null 2>&1

[ "$(git -C "$ROOT/tack-p" rev-parse HEAD)" = "$before" ] || fail "hook moved the profile repo"
[ -f "$TMP/tack-called" ] && fail "hook re-applied (called tack)"
[ "$(cat "$HOME/.claude/.harness-update-pending" 2>/dev/null)" = "1" ] || fail "pending marker not written with 1"

# Up to date: the marker goes away.
git -C "$ROOT/tack-p" pull -q --ff-only 2>/dev/null
rm -f "$HOME/.claude/.plugin-update-last-run"
bash "$CORE/hooks/plugin-auto-update.sh" </dev/null >/dev/null 2>&1
[ -f "$HOME/.claude/.harness-update-pending" ] && fail "marker kept when up to date"

# Unreachable remote: quiet, and an existing marker is left alone.
echo 3 > "$HOME/.claude/.harness-update-pending"
git -C "$ROOT/tack-p" remote set-url origin "$TMP/missing.git"
rm -f "$HOME/.claude/.plugin-update-last-run"
bash "$CORE/hooks/plugin-auto-update.sh" </dev/null >/dev/null 2>&1 || fail "hook failed offline"
[ "$(cat "$HOME/.claude/.harness-update-pending" 2>/dev/null)" = "3" ] || fail "marker changed when the fetch failed"

# Apply alone must not clear the marker; only tack sync does.
grep -q "harness-update-pending" "$CORE/adapters/claude/apply-profile.sh" && fail "apply-profile.sh touches the pending marker"
grep -q "rm -f \"\$CLAUDE_DIR/.harness-update-pending\"" "$CORE/bin/tack" || fail "tack sync does not clear the marker"

[ "$failed" = 0 ] && echo "test-auto-update-report: ok"
exit "$failed"
