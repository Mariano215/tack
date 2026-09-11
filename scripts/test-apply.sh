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

# Keep the test off the host's live Claude installation. apply-profile
# reconciles MCP whenever `claude` is on PATH, and a real CLI can perform auth
# or network work even though HOME points at the temp tree.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "mcp list") exit 0 ;;
  "mcp "*|"plugin "*) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/claude"
cat > "$BIN/codex" <<'STUB'
#!/usr/bin/env bash
[ -n "${CODEX_STUB_LOG:-}" ] && printf '%s\n' "$*" > "$CODEX_STUB_LOG"
exit 0
STUB
chmod +x "$BIN/codex"
export PATH="$BIN:$PATH"

apply() {
  # $1 = config dir, rest = extra args. stdin closed so the confirmation
  # prompt takes its non-interactive branch. Memory setup is separately tested
  # and can reach npm, so this composition test disables it explicitly.
  local cfg="$1"; shift
  CLAUDE_CONFIG_DIR="$cfg" HARNESS_NO_MEMORY_SETUP=1 bash "$CORE/lib/apply-profile.sh" \
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

echo "== 5. shell aliases are opt-in, the codex wrapper is not =="
# A stranger running a README command should not get their API key blanked or
# permission prompts skipped, so both sit behind HARNESS_NO_API_KEY and
# HARNESS_YOLO_ALIAS. The private engine this was forked from defaults both on;
# the difference is deliberate and this case pins it.
RC="$HOME/.bashrc"; : > "$RC"
bash "$CORE/lib/setup-shell-aliases.sh" >/dev/null 2>&1
grep -q 'ANTHROPIC_API_KEY' "$RC" && bad "default setup blanks ANTHROPIC_API_KEY"
grep -q 'dangerously-skip-permissions' "$RC" && bad "default setup enables skip-permissions"
grep -q "alias .*='claude'" "$RC" || bad "no plain alias written"
export CODEX_HOME="$HOME/.codex"
mkdir -p "$CODEX_HOME"
echo dev > "$CODEX_HOME/.harness-active"
echo '# harness test' > "$CODEX_HOME/dev.config.toml"
export CODEX_STUB_LOG="$TMP/codex.log"
bash -c '. "$1"; codex exec test' _ "$RC"
[ "$(cat "$CODEX_STUB_LOG")" = "-p dev exec test" ]   || bad "bare codex did not load the tack-selected profile"
bash -c '. "$1"; codex -p other exec test' _ "$RC"
[ "$(cat "$CODEX_STUB_LOG")" = "-p other exec test" ]   || bad "explicit Codex profile was overridden by the harness"
: > "$RC"
HARNESS_NO_API_KEY=1 HARNESS_YOLO_ALIAS=1 bash "$CORE/lib/setup-shell-aliases.sh" >/dev/null 2>&1
grep -q 'ANTHROPIC_API_KEY' "$RC" || bad "--no-api-key opt-in did not take effect"
grep -q 'dangerously-skip-permissions' "$RC" || bad "--yolo-alias opt-in did not take effect"
[ "$fails" -eq 0 ] && ok "aliases opt-in, codex wrapper loads the active profile and keeps explicit args"

echo "== 6. a second apply waits for the lock instead of failing =="
CFG3="$TMP/lockA"; CFG4="$TMP/lockB"; mkdir -p "$CFG3" "$CFG4"
apply "$CFG3" >/dev/null 2>&1 &
bg=$!
sleep 0.3
out="$(apply "$CFG4")"; rc=$?
wait "$bg" 2>/dev/null
if [ "$rc" -ne 0 ]; then
  echo "$out"; bad "second concurrent apply failed instead of waiting"
else
  ok "concurrent applies serialise without failing"
fi
[ -f "$CFG4/settings.json" ] || bad "second apply produced no settings.json"

echo "== 7. skills_link installs a missing target from skills_source =="
# The only path in the apply that reaches the network. A stub `skills` first on
# PATH keeps this case offline and makes the argv assertable, which matters more
# than exercising the real CLI: what breaks here is the argv and the fallbacks,
# not npm.
cat > "$BIN/skills" <<'STUB'
#!/usr/bin/env bash
# Reads stdin on purpose. The real CLI does, and step 3a runs inside a
# `jq | while read` loop, so an installer that inherits the loop's stdin eats
# the entries not yet read and every skills_link after the first disappears
# with no error at all. A stub that ignores stdin cannot see that.
cat >/dev/null 2>&1
echo "$@" > "$SKILLS_STUB_LOG"
for a in "$@"; do case "$a" in */*@*) mkdir -p "$HOME/.agents/skills/${a##*@}"; echo stub > "$HOME/.agents/skills/${a##*@}/SKILL.md" ;; esac; done
STUB
chmod +x "$BIN/skills"
PROF="$TMP/profile"; mkdir -p "$PROF"
mk_manifest() {
  # $1 = jq expression applied to the minimal profile's manifest
  jq "$1" "$CORE/profiles/minimal/manifest.json" > "$PROF/manifest.json"
}
apply_prof() {
  local cfg="$1"; shift
  CLAUDE_CONFIG_DIR="$cfg" HARNESS_NO_MEMORY_SETUP=1 PATH="$BIN:$PATH" bash "$CORE/lib/apply-profile.sh" \
    "$PROF/manifest.json" --force "$@" </dev/null 2>&1
}

CFG5="$TMP/link"; mkdir -p "$CFG5"
export SKILLS_STUB_LOG="$TMP/stub.log"

mk_manifest '.skills_link = {"stubskill":"~/.agents/skills/stubskill"}'
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
case "$out" in
  *"No source recorded"*) ok "a skills_link with no skills_source skips and names the fix" ;;
  *) echo "$out"; bad "no skills_source did not print the fix" ;;
esac
[ -s "$SKILLS_STUB_LOG" ] && bad "installer ran with no skills_source recorded"

mk_manifest '.skills_link = {"stubskill":"~/.agents/skills/stubskill"}
  | .skills_source = {"stubskill":"owner/repo@stubskill"}'
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(HARNESS_NO_SKILL_INSTALL=1 apply_prof "$CFG5")"
[ -s "$SKILLS_STUB_LOG" ] && bad "HARNESS_NO_SKILL_INSTALL=1 did not stop the install"
case "$out" in
  *"HARNESS_NO_SKILL_INSTALL is set"*) ok "HARNESS_NO_SKILL_INSTALL=1 skips and prints the command" ;;
  *) echo "$out"; bad "opt-out did not say why it skipped" ;;
esac

rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
[ "$(cat "$SKILLS_STUB_LOG")" = "add owner/repo@stubskill -g -y" ] \
  || { echo "argv was: $(cat "$SKILLS_STUB_LOG")"; bad "installer called with the wrong argv"; }
[ -e "$CFG5/skills/stubskill" ] || { echo "$out"; bad "installed skill was not linked into the config dir"; }
grep -qx "stubskill" "$CFG5/.harness-managed-skills" \
  || bad "installed skill not recorded as managed, the quarantine sweep will move it aside"
[ -e "$CFG5/skills/stubskill" ] && ok "missing target installed, then linked and recorded"

: > "$SKILLS_STUB_LOG"
apply_prof "$CFG5" >/dev/null 2>&1
[ -s "$SKILLS_STUB_LOG" ] && bad "installer ran again on a target that already exists"
[ -s "$SKILLS_STUB_LOG" ] || ok "no reinstall when the target is already there"

# Two entries, because one cannot show that the loop survives an install. The
# installer runs inside `jq | while read`, so anything it reads from stdin comes
# out of the loop's own input and the remaining entries are lost in silence.
mk_manifest '.skills_link = {"stubskill":"~/.agents/skills/stubskill","stubtwo":"~/.agents/skills/stubtwo"}
  | .skills_source = {"stubskill":"owner/repo@stubskill","stubtwo":"owner/repo@stubtwo"}'
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
if [ -e "$CFG5/skills/stubskill" ] && [ -e "$CFG5/skills/stubtwo" ]; then
  ok "every skills_link entry is processed, not just the first"
else
  echo "$out"; bad "an install consumed the loop's stdin and dropped the later entries"
fi

mk_manifest '.skills_link = {"stubskill":"~/.agents/skills/stubskill"}
  | .skills_source = {"stubskill":"owner/repo@stubskill"}'

# Windows: a node from the MSI or a version manager can put only the .cmd
# wrappers on PATH, and Git Bash finds those by their full name. Same stub, only
# renamed, so the case runs on every OS. Except on Git Bash itself: it hands any
# .cmd to cmd.exe, which cannot run a bash script, so there the .cmd is a real
# batch file that calls the stub, the same shape npm writes.
mv "$BIN/skills" "$BIN/skills-stub"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) printf '@"%s" "%%~dp0skills-stub" %%*\r\n' "$(cygpath -w "$BASH")" > "$BIN/skills.cmd" ;;
  *) cp "$BIN/skills-stub" "$BIN/skills.cmd"; chmod +x "$BIN/skills.cmd" ;;
esac
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
[ -e "$CFG5/skills/stubskill" ] || { echo "$out"; bad "skills.cmd on PATH was not used (Git Bash would find no installer)"; }
[ -e "$CFG5/skills/stubskill" ] && ok "the .cmd wrapper is found too"
rm -f "$BIN/skills.cmd"; mv "$BIN/skills-stub" "$BIN/skills"

# A $HARNESS_ROOT target is one of our own repo checkouts. No skills_source
# value can install it, so the message has to send the reader to git clone
# rather than to a manifest key that cannot help.
mk_manifest '.skills_link = {"repolinked":"$HARNESS_ROOT/some-repo/skills/repolinked"}'
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
case "$out" in
  *"clone some-repo into"*) ok "a repo-checkout target is told to clone, not to add a source" ;;
  *) echo "$out"; bad "repo-checkout target got the registry advice" ;;
esac

mk_manifest '.skills_link = {"stubskill":"~/.agents/skills/stubskill"}
  | .skills_source = {"stubskill":"owner/repo@s; touch /tmp/pwned"}'
rm -rf "$HOME/.agents"; : > "$SKILLS_STUB_LOG"
out="$(apply_prof "$CFG5")"
[ -s "$SKILLS_STUB_LOG" ] && bad "a skills_source carrying shell metacharacters reached the installer"
case "$out" in
  *"is not a package spec"*) ok "a non-spec skills_source is rejected, not run" ;;
  *) echo "$out"; bad "non-spec skills_source was not rejected" ;;
esac

echo "== 8. a v2 manifest composes the same Claude settings contract =="
mk_manifest '.schema_version = 2
  | .providers = {"claude": {
      "plugins": {"v2-plugin@example": true},
      "env": {"V2_MARKER": "claude"},
      "permissions": {"defaultMode": "plan"}
    }}
  | del(.plugins, .env, .permissions)'
CFG8="$TMP/v2"; mkdir -p "$CFG8"
out="$(apply_prof "$CFG8")"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "$out"; bad "v2 Claude apply exited $rc"
elif jq -e '.enabledPlugins["v2-plugin@example"] == true
  and .env.V2_MARKER == "claude"
  and .env.CAVEMAN_DEFAULT_MODE == "off"
  and .permissions.defaultMode == "plan"' "$CFG8/settings.json" >/dev/null; then
  ok "v2 provider config reached composed Claude settings"
else
  bad "v2 provider config did not reach composed Claude settings"
fi

echo "== 9. a lock left behind by a dead process does not block an apply =="
# The real failure this covers: an apply killed hard leaves the lock directory,
# the EXIT trap never runs, and every later apply waits 180s and exits 1. That
# cost a whole day on 2026-09-01. The waiter must clear a lock whose holder is
# gone, and must still respect one whose holder is alive.
LOCK="$HOME/.claude/.harness-apply.lock"
CFG9="$TMP/lock"; mkdir -p "$CFG9" "$HOME/.claude"
rm -rf "$LOCK"; mkdir -p "$LOCK"; echo 999999 > "$LOCK/pid"   # a pid nothing owns
out="$(apply "$CFG9")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "apply blocked on a lock whose holder is dead (exit $rc)"; }
case "$out" in
  *"clearing a stale lock"*) ok "a dead holder's lock is cleared and named" ;;
  *) echo "$out"; bad "stale lock was not reported" ;;
esac
[ -d "$LOCK" ] && bad "the lock survived a completed apply"

# A pre-upgrade lock carries no pid file at all. Same treatment, or the fix
# does not reach the machine that is stuck right now.
rm -rf "$LOCK"; mkdir -p "$LOCK"
out="$(apply "$CFG9")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "apply blocked on a pid-less lock from an older engine (exit $rc)"; }
[ "$rc" -eq 0 ] && ok "a lock with no pid file is treated as abandoned"

# The other half, and the one that matters more: a live holder must still be
# waited on, never trampled. $$ is this test, which is very much alive, so the
# apply has to wait and then give up. HARNESS_LOCK_WAIT_S shortens the wait so
# the case costs 3 seconds instead of 180.
rm -rf "$LOCK"; mkdir -p "$LOCK"; echo $$ > "$LOCK/pid"
out="$(HARNESS_LOCK_WAIT_S=3 apply "$CFG9")"; rc=$?
[ "$rc" -ne 0 ] || bad "apply broke into a lock held by a running process"
case "$out" in
  *"another apply is running"*) ok "a live holder's lock is respected, not broken" ;;
  *) echo "$out"; bad "no wait message on a live lock" ;;
esac
if [ -f "$LOCK/pid" ] && [ "$(cat "$LOCK/pid")" = "$$" ]; then
  ok "the live lock is still intact and still ours"
else
  bad "the live lock was destroyed"
fi
rm -rf "$LOCK"

echo ""
if [ "$fails" -ne 0 ]; then
  echo "test-apply FAILED ($fails)."
  echo "  Fix: an apply is the only thing that rewrites a config dir. Read the"
  echo "  failing case above and re-run: bash scripts/test-apply.sh"
  exit 1
fi
echo "test-apply passed."
