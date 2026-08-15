#!/usr/bin/env bash
# test-apply.sh
# End-to-end: run a real apply against throwaway HOME and config dirs.
# scripts/check.sh is static analysis only, so nothing there notices when the
# apply itself breaks. This is the one thing that has to work on a fresh
# machine, and it is what CI could not catch before.
#
# Hermetic: HOME is redirected, so the apply lock, the shared config dir and
# ~/.local/bin all land in a temp tree and your real setup is never touched.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tackapply)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; fails=$((fails+1)); }

# The apply reads HOME for the lock, the plugins tree and the switcher install.
export HOME="$TMP/home"
mkdir -p "$HOME"

apply() {
  # $1 = config dir, rest = extra args. stdin closed so the confirmation
  # prompt takes its non-interactive branch.
  local cfg="$1"; shift
  CLAUDE_CONFIG_DIR="$cfg" bash "$CORE/lib/apply-profile.sh" \
    "$CORE/profiles/minimal/manifest.json" "$@" </dev/null 2>&1
}

echo "== 1. apply to an empty config dir succeeds =="
CFG="$TMP/empty"; mkdir -p "$CFG"
out="$(apply "$CFG")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "apply exited $rc"; }
[ -f "$CFG/settings.json" ] || bad "no settings.json written"
jq -e . "$CFG/settings.json" >/dev/null 2>&1 || bad "settings.json is not valid JSON"
[ -f "$CFG/.harness-base-settings.json" ] || bad "no .harness-base-settings.json marker"
[ -d "$CFG/hooks" ] || bad "hooks not installed"
[ -d "$CFG/skills" ] || bad "skills not installed"
[ "$fails" -eq 0 ] && ok "clean apply produced a composed config dir"

echo "== 2. re-apply on an applied dir does not prompt =="
out="$(apply "$CFG")"
case "$out" in
  *"already has content"*) bad "guard fired on an already-applied config dir" ;;
  *) ok "no confirmation prompt on re-apply" ;;
esac

echo "== 3. first apply over somebody else's config refuses =="
CFG2="$TMP/occupied"; mkdir -p "$CFG2/hooks" "$CFG2/commands"
echo "mine" > "$CFG2/hooks/mine.sh"
echo "mine" > "$CFG2/commands/mine.md"
out="$(apply "$CFG2")"; rc=$?
[ "$rc" -ne 0 ] || bad "apply succeeded when it should have refused"
case "$out" in
  *"already has content"*) ok "refused and explained" ;;
  *) echo "$out"; bad "no explanation of what would be replaced" ;;
esac
[ -f "$CFG2/hooks/mine.sh" ]   || bad "user hook was destroyed by a refused apply"
[ -f "$CFG2/commands/mine.md" ] || bad "user command was destroyed by a refused apply"
[ -f "$CFG2/settings.json" ] && bad "a refused apply still wrote settings.json"

echo "== 4. --force proceeds =="
out="$(apply "$CFG2" --force)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "--force apply exited $rc"; }
[ -f "$CFG2/settings.json" ] || bad "--force did not compose settings.json"
[ "$rc" -eq 0 ] && ok "--force applied over existing content"

echo "== 5. shell aliases are opt-in =="
RC="$HOME/.bashrc"; : > "$RC"
bash "$CORE/lib/setup-shell-aliases.sh" >/dev/null 2>&1
grep -q 'ANTHROPIC_API_KEY' "$RC" && bad "default setup blanks ANTHROPIC_API_KEY"
grep -q 'dangerously-skip-permissions' "$RC" && bad "default setup enables skip-permissions"
grep -q "alias .*='claude'" "$RC" || bad "no plain alias written"
: > "$RC"
HARNESS_NO_API_KEY=1 HARNESS_YOLO_ALIAS=1 bash "$CORE/lib/setup-shell-aliases.sh" >/dev/null 2>&1
grep -q 'ANTHROPIC_API_KEY' "$RC" || bad "--no-api-key opt-in did not take effect"
grep -q 'dangerously-skip-permissions' "$RC" || bad "--yolo-alias opt-in did not take effect"

echo ""
if [ "$fails" -ne 0 ]; then
  echo "test-apply FAILED ($fails)."
  echo "  Fix: an apply is the only thing that rewrites a config dir. Read the"
  echo "  failing case above and re-run: bash scripts/test-apply.sh"
  exit 1
fi
echo "test-apply passed."
