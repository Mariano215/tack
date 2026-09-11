#!/usr/bin/env bash
# apply-profile.sh <manifest.json>
# Composes the active config dir for one profile: settings, engine, skills, MCP.
# Called by a profile repo's install.sh (which pins core as a submodule) or by
# `tack use`. Copy-mode only, no symlinks (v1.3). Fail-loud on compose errors.
set -euo pipefail

# Two profiles can now be applied concurrently from two terminals (`tack shell`),
# each with its own CLAUDE_CONFIG_DIR. Steps 3c, 4 and 4c touch machine-global
# state regardless of which config dir is active: the shared plugins registry,
# the user-scope MCP list, and the shell rc files. So the lock is on
# $HOME/.claude, not on $CLAUDE.
# ponytail: mkdir is the atomic primitive everywhere; macOS has no flock(1).
LOCK="$HOME/.claude/.harness-apply.lock"
mkdir -p "$HOME/.claude"  # harness:shared, the lock is machine-wide by design

# A lock only means something while the process holding it is alive. The EXIT
# trap below does not run on SIGKILL, and it does not run when the terminal
# goes away under the script, so a crashed apply used to leave the directory
# behind forever. Every later apply then waited the full 180s and failed, and
# the SessionStart heal re-ran the same failing apply. That state lasted from
# 00:01 to 14:35 on 2026-09-01 across five runs. Record the holder's pid so a
# waiter can tell a held lock from an abandoned one.
lock_take() {
  mkdir "$LOCK" 2>/dev/null || return 1
  echo $$ > "$LOCK/pid"
}
# True when the lock exists but nothing is running behind it. A missing pid
# file counts as dead: it means either a lock written by a version of this
# script from before the pid existed, or the microsecond between mkdir and the
# write above, and the caller sleeps first so that window is closed.
lock_is_dead() {
  local p
  p="$(cat "$LOCK/pid" 2>/dev/null | tr -d '\r')"
  [ -n "$p" ] || return 0
  ! kill -0 "$p" 2>/dev/null
}
# ponytail: read-then-break is not atomic, so two waiters that find the same
# dead lock in the same second can both go on to apply. One person with two
# terminals never hits it. If it ever matters, move to an O_EXCL pid file.
if ! lock_take; then
  sleep 1
  if lock_is_dead; then
    echo "apply-profile: clearing a stale lock, the process that held it is gone." >&2
    rm -rf "$LOCK"
  fi
  # Wait rather than fail. Opening two profiles in two terminals is the headline
  # use case, and both applies race for this lock the moment you do it. Failing
  # the second one made the documented workflow break on first contact.
  if ! lock_take; then
    echo "apply-profile: another apply is running, waiting for it to finish..." >&2
    waited=0
    while ! lock_take; do
      sleep 1
      waited=$((waited + 1))
      # Overridable only so scripts/test-apply.sh can assert the give-up branch
      # without sitting through three minutes. Nothing sets it in normal use.
      if [ "$waited" -ge "${HARNESS_LOCK_WAIT_S:-180}" ]; then
        echo "apply-profile: still locked after ${waited}s, giving up." >&2
        echo "  If no other apply is running the lock is stale: rm -rf $LOCK" >&2
        exit 1
      fi
    done
    echo "apply-profile: lock acquired after ${waited}s." >&2
  fi
fi
# Only clear the lock if it is still ours. A lock we lost (broken as stale by a
# waiter, then retaken) belongs to another apply, and rm -rf here would hand a
# third process a lock the second one thinks it holds.
NORMALIZED_MANIFEST=""
cleanup() {
  [ -n "$NORMALIZED_MANIFEST" ] && rm -f "$NORMALIZED_MANIFEST"
  [ "$(cat "$LOCK/pid" 2>/dev/null | tr -d "\r")" = "$$" ] && rm -rf "$LOCK"
  true
}
trap cleanup EXIT

MANIFEST="${1:-./manifest.json}"
[ -f "$MANIFEST" ] || { echo "apply-profile: no manifest at $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "apply-profile: jq required" >&2; exit 1; }

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=resolve-link-target.sh
. "$CORE_DIR/lib/resolve-link-target.sh"
PROFILE_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
MANIFEST_SOURCE="$MANIFEST"
# v1 has provider config at top level. v2 keeps shared intent at top level and
# nests runtime mechanics under providers. Normalize once so the proven Claude
# composer below keeps its exact behavior while profiles migrate one at a time.
NORMALIZED_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/harness-manifest.XXXXXX")"
if ! bash "$CORE_DIR/lib/manifest-provider-view.sh" "$MANIFEST_SOURCE" claude > "$NORMALIZED_MANIFEST"; then
  echo "apply-profile: could not read Claude view from $MANIFEST_SOURCE" >&2
  exit 1
fi
MANIFEST="$NORMALIZED_MANIFEST"
# Claude Code resolves settings, plugins, sessions and .claude.json under
# CLAUDE_CONFIG_DIR when it is set, so honoring it here is what lets `tack shell`
# run a second profile in another terminal without touching this one. Unset, the
# expansion is the identity function and nothing changes.
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TS="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)"
NAME="$(jq -r '.name' "$MANIFEST")"

# First run on a config dir this harness has never composed. Step 2 does
# `rm -rf` over seven directories and step 3 quarantines every skill the profile
# does not declare, so on somebody's existing ~/.claude that is their own hooks,
# commands and agents gone with one command they ran from a README. An applied
# machine carries .harness-base-settings.json from step 1 and never sees this.
# --force is for CI and for re-running after you have read the list once.
FORCE=0
for a in "$@"; do [ "$a" = "--force" ] && FORCE=1; done
if [ "$FORCE" -eq 0 ] && [ ! -f "$CLAUDE/.harness-base-settings.json" ]; then
  clobber=""
  for d in hooks ghost agents commands templates scripts output-styles; do
    [ -e "$CLAUDE/$d" ] && clobber="$clobber  $CLAUDE/$d\n"
  done
  if [ -n "$clobber" ]; then
    echo "" >&2
    echo "apply-profile: $CLAUDE already has content this apply would REPLACE:" >&2
    printf "$clobber" >&2
    echo "  Each is deleted and rewritten from the profile. Any skill the profile" >&2
    echo "  does not declare is moved to $CLAUDE/skills-disabled." >&2
    echo "  settings.json is backed up to .harness-prev-settings.json; the seven" >&2
    echo "  directories above are NOT." >&2
    echo "" >&2
    echo "  Fix: back them up first (cp -R $CLAUDE ~/claude-backup), then re-run" >&2
    echo "  with --force. To keep specific skills, list them in $CLAUDE/.harness-skills-keep." >&2
    if [ -t 0 ]; then
      printf "  Type 'yes' to continue anyway: " >&2
      read -r reply
      [ "$reply" = "yes" ] || { echo "apply-profile: stopped, nothing changed." >&2; exit 1; }
    else
      echo "apply-profile: stopped, nothing changed. (non-interactive; pass --force to proceed)" >&2
      exit 1
    fi
  fi
fi

mkdir -p "$CLAUDE/hooks" "$CLAUDE/skills"

echo "==> applying profile: $NAME  (core=$CORE_DIR)"

# 1. settings.json = base * {enabledPlugins,env from manifest} * personal-overrides
comp="$CLAUDE/settings.json.compose.$TS"
jq -s '
  .[0] as $base | .[1] as $m |
  $base
  | .enabledPlugins = (($base.enabledPlugins // {}) + ($m.plugins // {}))
  | .env = (($base.env // {}) + ($m.env // {}))
  | .permissions = (($base.permissions // {}) + ($m.permissions // {}))
  | if ($m.caveman // null) != null then .env.CAVEMAN_DEFAULT_MODE = $m.caveman else . end
' "$CORE_DIR/base-settings.json" "$MANIFEST" > "$comp"
# personal-overrides.json is machine-local: env, theme, permissions, login, effort.
# It must NOT own plugin enablement. Profiles do, via base-settings + the manifest.
# Deep merge puts personal-overrides last, so a stale plugin snapshot there would
# silently outrank every profile decision (this is how context7 ended up disabled
# on the dev profile that explicitly enables it). Strip the profile-owned keys
# before merging, and say so rather than failing quietly.
# A profile that declares permissions.defaultMode owns that one path too: the
# authority the agent runs under should be readable in git, not inherited from
# an untracked file nobody reviews. The rest of .permissions (allow lists,
# per-machine grants) stays machine-local.
# A manifest that declares caveman owns CAVEMAN_DEFAULT_MODE the same way. Eight
# manifests were set to "off" and every session still came up "lite", because a
# stale key in personal-overrides.json merged last and beat all of them without
# printing a word.
PROFILE_OWNED='[["enabledPlugins"],["extraKnownMarketplaces"]]'
if jq -e '.permissions.defaultMode' "$MANIFEST" >/dev/null 2>&1; then
  PROFILE_OWNED="$(jq -nc --argjson p "$PROFILE_OWNED" '$p + [["permissions","defaultMode"]]')"
fi
if jq -e '.caveman' "$MANIFEST" >/dev/null 2>&1; then
  PROFILE_OWNED="$(jq -nc --argjson p "$PROFILE_OWNED" '$p + [["env","CAVEMAN_DEFAULT_MODE"]]')"
fi
if [ -f "$CLAUDE/personal-overrides.json" ] && jq -e . "$CLAUDE/personal-overrides.json" >/dev/null 2>&1; then
  shadowed="$(jq -r --argjson owned "$PROFILE_OWNED" \
    '. as $o | [$owned[] | select(. as $p | $o | getpath($p) != null) | join(".")] | join(", ")' \
    "$CLAUDE/personal-overrides.json" | tr -d '\r')"
  [ -n "$shadowed" ] && echo "  note: ignoring profile-owned key(s) in personal-overrides.json: $shadowed"
  # The rest of .env stays machine-local by design (telemetry endpoints, keys),
  # so shadowing there is allowed. Say it out loud anyway: an override that
  # disagrees with the profile is either deliberate or the bug above, and only
  # the reader can tell which.
  envshadow="$(jq -rs --argjson owned "$PROFILE_OWNED" '
    (.[0].env // {}) as $prof |
    ((.[1] | delpaths($owned)).env // {}) as $ovr |
    [ $ovr | to_entries[]
      | select($prof[.key] != null and $prof[.key] != .value)
      | "\(.key) (profile says \($prof[.key]), override wins with \(.value))" ]
    | join("; ")' "$comp" "$CLAUDE/personal-overrides.json" | tr -d '\r')"
  if [ -n "$envshadow" ]; then
    echo "  note: personal-overrides.json env overrides the profile: $envshadow"
    echo "        Fix: drop the key from $CLAUDE/personal-overrides.json to let the profile win, or change the profile manifest if the override is what you want."
  fi
  jq -s --argjson owned "$PROFILE_OWNED" \
    '.[0] * (.[1] | delpaths($owned))' \
    "$comp" "$CLAUDE/personal-overrides.json" > "$comp.ovr" && mv "$comp.ovr" "$comp"
fi
# Record what the profile declared so verify-setup can spot a hand-edit later.
jq -r '.permissions.defaultMode // empty' "$MANIFEST" | tr -d '\r' > "$CLAUDE/.harness-declared-mode"
jq -e . "$comp" >/dev/null || { echo "apply-profile: composed settings invalid JSON" >&2; rm -f "$comp"; exit 1; }
# Everything else this script writes regenerates from the repo, and user skills
# are preserved by quarantine. settings.json is the one file where the previous
# state is worth a copy: restore with
#   cp "$CLAUDE/.harness-prev-settings.json" "$CLAUDE/settings.json"
cp "$CLAUDE/settings.json" "$CLAUDE/.harness-prev-settings.json" 2>/dev/null || true
mv "$comp" "$CLAUDE/settings.json"
# Snapshot the baseline next to the composed result. Core lives inside a profile
# repo as a submodule, so nothing in the config dir can find base-settings.json by
# path; verify-setup reads this snapshot to spot marketplace drift.
cp "$CORE_DIR/base-settings.json" "$CLAUDE/.harness-base-settings.json"
echo "  settings.json composed"

# 2. engine: copy hooks, ghost, agents, commands, templates, scripts, output
# styles, top scripts. output-styles rides here because base-settings.json names
# an outputStyle: a machine that got the name without the file falls back to the
# default style silently, with nothing in the UI saying why.
for d in hooks ghost agents commands templates scripts output-styles; do
  [ -d "$CORE_DIR/$d" ] && { rm -rf "$CLAUDE/$d"; cp -R "$CORE_DIR/$d" "$CLAUDE/$d"; }
done
# A profile may carry its own commands. The loop above does rm -rf before it
# copies, so anything a profile installed by hand was wiped on every apply: the
# audit profile's /audit-init and /report-gen died on the next `tack use` and the
# auditor skill went on routing to commands that no longer existed. Merge the
# profile's commands in after core's. A profile that shadows a core command name
# wins, which is what a profile is for.
if [ -d "$PROFILE_DIR/commands" ]; then
  mkdir -p "$CLAUDE/commands"
  cp -R "$PROFILE_DIR/commands/." "$CLAUDE/commands/"
  echo "  profile commands merged"
fi
for f in verify-setup.sh statusline-command.sh; do
  [ -f "$CORE_DIR/$f" ] && cp "$CORE_DIR/$f" "$CLAUDE/$f"
done
find "$CLAUDE/hooks" "$CLAUDE/ghost" "$CLAUDE/scripts" -name '*.sh' -o -name '*.py' 2>/dev/null | xargs -r chmod +x 2>/dev/null || true
chmod +x "$CLAUDE/verify-setup.sh" "$CLAUDE/statusline-command.sh" 2>/dev/null || true
# Refresh the switcher itself. Only setup-core.sh installed tack, so a machine kept
# running the tack it was first set up with: a fix to tack (like sync re-applying)
# never arrived through a sync, which is exactly the update it was meant to
# deliver. Copy on change so tack improvements ride the same path as the engine.
if [ -f "$CORE_DIR/bin/tack" ] && ! cmp -s "$CORE_DIR/bin/tack" "$HOME/.local/bin/tack"; then
  mkdir -p "$HOME/.local/bin"
  # install(1) is missing in some minimal images and Git Bash setups
  { install -m 0755 "$CORE_DIR/bin/tack" "$HOME/.local/bin/tack" 2>/dev/null \
    || { cp "$CORE_DIR/bin/tack" "$HOME/.local/bin/tack" && chmod +x "$HOME/.local/bin/tack"; }; } \
    && echo "  tack refreshed"
fi
if [ -f "$CORE_DIR/bin/tack.cmd" ] && { [ ! -f "$HOME/.local/bin/tack.cmd" ] || ! cmp -s "$CORE_DIR/bin/tack.cmd" "$HOME/.local/bin/tack.cmd"; }; then
  mkdir -p "$HOME/.local/bin"
  cp "$CORE_DIR/bin/tack.cmd" "$HOME/.local/bin/tack.cmd" && echo "  tack Windows launcher refreshed"
fi
echo "  engine installed"

# 3. skills: remove previously harness-managed skills, install core + profile skills
MANIFEST_LIST="$CLAUDE/.harness-managed-skills"
if [ -f "$MANIFEST_LIST" ]; then
  while IFS= read -r s; do [ -n "$s" ] && rm -rf "$CLAUDE/skills/$s"; done < "$MANIFEST_LIST"
fi
: > "$MANIFEST_LIST"
for src in "$CORE_DIR/skills" "$PROFILE_DIR/skills"; do
  [ -d "$src" ] || continue
  find "$src" -mindepth 1 -maxdepth 1 -type d | while read -r d; do
    b="$(basename "$d")"; rm -rf "$CLAUDE/skills/$b"; cp -R "$d" "$CLAUDE/skills/$b"; echo "$b" >> "$MANIFEST_LIST"
  done
done
# 3a. skills_link: skills whose source lives outside the harness (~/.agents/skills,
# a separate skills repo). Copying them would fork the source, so link instead.
# Values are machine-specific, so write them with a `~/` or `$HARNESS_ROOT/`
# prefix (see lib/resolve-link-target.sh) rather than one machine's absolute
# path. A committed absolute path leaks the author's layout and resolves to
# nothing everywhere else. A link whose target is missing is skipped, so a
# profile stays usable on a machine that lacks the source repo.
#
# A missing target is also installable. `skills_source` maps the same skill name
# to the package the `skills` CLI knows it by, so the engine can create what is
# missing instead of only reporting it. Two notes on what that does:
#   - the CLI links the skill into ~/.claude/skills itself. Step 3a then removes
#     that and relinks under the active $CLAUDE, and writes the name into
#     .harness-managed-skills, so the 3b quarantine sweep leaves it alone.
#   - a failed install is retried on the next apply. That is wanted: it heals
#     when the machine is online again, and it prints, so it is never silent.
# jq.exe writes CRLF on Windows. `$(...)` hides it (MSYS bash strips the CR on
# capture) but `| while read` does not, so the last field on every line arrives
# with a trailing CR. Strip it, or every target resolves to a path that no
# machine has and every link is reported missing.
# Try to create a missing skills_link target from the package spec the manifest
# records for it in skills_source. Prints what it did, and a failure is never
# fatal: the whole step is fail-open and a machine with no network still has to
# finish the apply. Returns 0 only when the target now exists.
install_linked_skill() {
  local name="$1" target="$2" raw="$3" spec repo
  spec="$(jq -r --arg n "$name" '(.skills_source // {})[$n] // empty' "$MANIFEST" | tr -d '\r')"
  if [ -z "$spec" ]; then
    echo "  skills_link: $name skipped, target missing: $target"
    # A $HARNESS_ROOT target is a repo checkout of ours, not a registry skill,
    # so no skills_source value can ever fix it and saying "add one" sends the
    # reader down a path with no end. The fix there is to clone the repo.
    case "$raw" in
      '$HARNESS_ROOT/'*)
        repo="${raw#\$HARNESS_ROOT/}"; repo="${repo%%/*}"
        echo "         That is a repo checkout, not a registry skill, so skills_source cannot install it."
        echo "         Fix: clone $repo into $(harness_root)/, then re-run the apply."
        ;;
      *)
        echo "         No source recorded. Add skills_source[\"$name\"] to $MANIFEST_SOURCE to install it automatically."
        ;;
    esac
    return 1
  fi
  # A package spec, never a command line. A manifest is data, and running a
  # string out of it as a command would make any profile repo able to execute
  # anything on every machine that syncs it. Charset-check and drop it into a
  # fixed argv instead. A leading dash would read as a flag to the CLI.
  case "$spec" in
    -*|*[!A-Za-z0-9._@/-]*)
      echo "  skills_link: $name skipped, skills_source[\"$name\"] is not a package spec: $spec"
      echo "         Expected owner/repo@skill, using only A-Z a-z 0-9 . _ @ / and -."
      return 1 ;;
  esac
  if [ -n "${HARNESS_NO_SKILL_INSTALL:-}" ]; then
    echo "  skills_link: $name skipped, HARNESS_NO_SKILL_INSTALL is set."
    echo "         To install it: skills add $spec -g -y"
    return 1
  fi
  # Git Bash resolves `skills` and `npx` through the sh wrappers npm writes
  # beside the .cmd ones, but a node installed by the Windows MSI or by a
  # version manager sometimes ships only the .cmd. Try both names rather than
  # report "not on PATH" on a machine that has node.
  local runner="" shown="" c
  for c in skills skills.cmd; do
    command -v "$c" >/dev/null 2>&1 && { runner="$c"; shown="$c add $spec -g -y"; set -- "$c" add "$spec" -g -y; break; }
  done
  if [ -z "$runner" ]; then
    for c in npx npx.cmd; do
      command -v "$c" >/dev/null 2>&1 && { runner="$c"; shown="$c --yes skills add $spec -g -y"; set -- "$c" --yes skills add "$spec" -g -y; break; }
    done
  fi
  if [ -z "$runner" ]; then
    echo "  skills_link: $name skipped, target missing: $target"
    echo "         Neither the skills CLI nor npx is on PATH. Install node, then: npx skills add $spec -g -y"
    echo "         If node is there interactively but not here, it is a version manager (nvm, fnm, volta):"
    echo "         this also runs from the SessionStart hook, which does not read your shell rc."
    return 1
  fi
  # No --agent flag on purpose. claude-code's own global skills dir is
  # $CLAUDE_CONFIG_DIR/skills, so `-a claude-code` would install there and leave
  # ~/.agents/skills empty, which is exactly the path skills_link points at.
  # Plain `-g -y` always includes the CLI's "universal" agent set, and that set
  # is what writes ~/.agents/skills. The CLI then symlinks into the config dir
  # itself; the link step below removes that and redoes it, so both agree.
  # -y also matters for the hook: it is what stops the agent picker, and the CLI
  # treats a non-TTY the same way, so neither path can block on a prompt.
  echo "  skills_link: $name missing, installing $spec ..."
  # npm retries a fetch five times with a two-minute timeout each by default, so
  # offline this would sit here for ten minutes inside the async SessionStart
  # heal. timeout(1) cannot bound it: macOS does not ship it, and the runtime
  # dependencies are bash, jq, git and python3 only.
  # </dev/null is load-bearing, not hygiene. This runs inside `jq | while read`,
  # so the loop's stdin IS the pipe, and a child that reads stdin swallows the
  # entries the loop has not read yet: the first install then silently ends the
  # loop and every later skills_link vanishes with no error. Observed with four
  # entries, where only the first one was installed and the other three printed
  # nothing at all.
  if npm_config_fetch_retries=1 npm_config_fetch_timeout=60000 "$@" </dev/null >/dev/null 2>&1 && [ -e "$target" ]; then
    echo "  skills_link: $name installed"
    return 0
  fi
  echo "  skills_link: $name skipped, install failed: $shown"
  echo "         Run that by hand to see why. The commonest cause is a spec the"
  echo "         registry index still lists after the upstream repo renamed or"
  echo "         merged the skill; the CLI then prints what the repo does have."
  echo "         The next apply retries it."
  echo "         On Git Bash also check that \$HOME matches %USERPROFILE%: the CLI installs"
  echo "         under node's os.homedir(), so a remapped HOME puts the skill somewhere else."
  return 1
}

jq -r '(.skills_link // {}) | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST" \
| tr -d '\r' \
| while IFS="$(printf '\t')" read -r name target; do
  [ -n "$name" ] && [ -n "$target" ] || continue
  raw="$target"
  target="$(resolve_link_target "$target")"
  if [ ! -e "$target" ]; then
    install_linked_skill "$name" "$target" "$raw" || continue
  fi
  rm -rf "$CLAUDE/skills/$name"
  if ln -s "$target" "$CLAUDE/skills/$name" 2>/dev/null; then
    echo "$name" >> "$MANIFEST_LIST"
  elif cp -R "$target" "$CLAUDE/skills/$name" 2>/dev/null; then
    # Git Bash cannot create symlinks without developer mode or elevation, so on
    # Windows the link silently produced nothing. Copy instead, and say that the
    # copy is a snapshot: edits to it never reach the source repo.
    echo "$name" >> "$MANIFEST_LIST"
    echo "  skills_link: $name copied, symlink unavailable here (edits will not reach $target)"
  else
    echo "  skills_link: $name failed, could not link or copy $target"
  fi
done

echo "  skills installed ($(wc -l < "$MANIFEST_LIST" | tr -d ' ') managed)"

# 3b. quarantine unmanaged skills. Step 3 only removes what a previous apply
# installed, so anything dropped into the config dir's skills/ by hand survives every
# profile switch and loads its description in every session. Skills are
# profile-owned: what no profile ships gets moved aside, not deleted. Keep a
# skill on this machine regardless by listing its name in .harness-skills-keep.
QUARANTINE="$CLAUDE/skills-disabled"
KEEP="$CLAUDE/.harness-skills-keep"
moved=0
# Step 3 truncates the managed list before repopulating it, so a failure in
# between leaves it empty, and an empty list means "no skill is managed", which
# would quarantine every skill on the machine. Refuse rather than move them.
if [ ! -s "$MANIFEST_LIST" ]; then
  echo "  quarantine skipped: $MANIFEST_LIST is empty, which would move every skill aside."
  echo "  Fix: re-run this apply. If the list is still empty afterwards, step 3 failed and the skills copy is the thing to look at."
  QUARANTINE=""
fi
for p in ${QUARANTINE:+"$CLAUDE"/skills/* "$CLAUDE"/skills/.[!.]*}; do
  [ -e "$p" ] || [ -L "$p" ] || continue
  b="$(basename "$p")"
  grep -qxF "$b" "$MANIFEST_LIST" 2>/dev/null && continue
  [ -f "$KEEP" ] && grep -qxF "$b" "$KEEP" 2>/dev/null && continue
  mkdir -p "$QUARANTINE"
  rm -rf "$QUARANTINE/$b"
  mv "$p" "$QUARANTINE/$b"
  moved=$((moved+1))
done
[ "$moved" -gt 0 ] && echo "  quarantined $moved unmanaged skill(s) to $QUARANTINE (restore: mv back, or add the name to $KEEP)"
true

# 3c. marketplace reconciliation. base-settings.json owns extraKnownMarketplaces,
# but Claude Code keeps its own registry: <config dir>/plugins/known_marketplaces.json
# plus one git clone per marketplace under plugins/marketplaces. Composing
# settings.json drops a removed name from settings and leaves the clone on disk,
# still serving its skills and commands into every session. That is how headroom
# survived being removed from the repo. Prune what base-settings no longer names.
# Keep one anyway by listing it in .harness-marketplaces-keep.
KNOWN="$CLAUDE/plugins/known_marketplaces.json"
MKT_KEEP="$CLAUDE/.harness-marketplaces-keep"
if command -v claude >/dev/null 2>&1 && [ -f "$KNOWN" ]; then
  wanted="$(jq -r '(.extraKnownMarketplaces // {}) | keys[]' "$CORE_DIR/base-settings.json" 2>/dev/null | tr -d '\r')"
  # tr as at 3a: without it every name reads as "caveman\r", matches nothing in
  # $wanted (captured through $(...), so already CR-free), and the whole registry
  # is treated as prune-worthy — including the marketplaces base-settings names.
  jq -r 'keys[]' "$KNOWN" 2>/dev/null | tr -d '\r' | while read -r m; do
    [ -n "$m" ] || continue
    grep -qxF "$m" <<<"$wanted" && continue
    [ -f "$MKT_KEEP" ] && grep -qxF "$m" "$MKT_KEEP" 2>/dev/null && continue
    # Name the escape hatch at the moment it would have helped. Finding out
    # afterwards that a marketplace you added by hand is gone, and only then
    # reading a README line about .harness-marketplaces-keep, is the wrong order.
    echo "  marketplace '$m' is not in base-settings and will be removed."
    echo "    Keep it: echo '$m' >> $MKT_KEEP   then re-apply."
    if claude plugin marketplace remove "$m" >/dev/null 2>&1; then
      echo "  marketplace removed (not in base-settings): $m"
    else
      echo "  marketplace remove failed: $m (remove by hand: claude plugin marketplace remove $m)"
    fi
  done
  # The other half: register what base-settings names and this machine lacks.
  # Pruning alone left machines asymmetric, the container had no openai-codex
  # marketplace, so the enabled codex plugin was inert there and nowhere else.
  live="$(jq -r 'keys[]' "$KNOWN" 2>/dev/null)"
  jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
         | "\(.key)\t\(.value.source.repo // .value.source.url // "")"' \
    "$CORE_DIR/base-settings.json" 2>/dev/null \
  | tr -d '\r' \
  | while IFS="$(printf '\t')" read -r m src; do
    [ -n "$m" ] && [ -n "$src" ] || continue
    grep -qxF "$m" <<<"$live" && continue
    claude plugin marketplace add "$src" >/dev/null 2>&1 \
      && echo "  marketplace added (named by base-settings): $m" \
      || echo "  marketplace add failed: $m from $src"
  done
fi

# 4. MCP reconciliation. Browser MCPs ride enabledPlugins above. The servers
#    below need an explicit add because nothing else installs them. Dropped
#    always (CLI, dead, or account-level): tokensave (use the tokensave CLI),
#    sequential-thinking, headroom (removed 2026-07), and context7 (the
#    claude.ai Context7 connector follows the login, so a user-scope copy is a
#    duplicate that also warns about a missing CONTEXT7_API_KEY on machines
#    without one).
if command -v claude >/dev/null 2>&1; then
  for drop in tokensave sequential-thinking headroom context7; do
    claude mcp remove "$drop" -s user >/dev/null 2>&1 || true
  done
  # name<TAB>required binary (- if none)<TAB>full args for `claude mcp add`.
  # -s user lives in the args column: for the `-- <cmd>` form everything after
  # `--` is the server command, so a trailing flag would be passed to it.
  while IFS="$(printf '\t')" read -r name need args; do
    [ -n "$name" ] || continue
    want="$(jq -r --arg n "$name" '(.mcp // []) | index($n) | if . == null then "no" else "yes" end' "$MANIFEST" | tr -d '\r')"
    have="$(claude mcp list 2>/dev/null | grep -c "^$name:" || true)"
    if [ "$want" = "yes" ] && [ "$have" = "0" ]; then
      if [ "$need" != "-" ] && ! command -v "$need" >/dev/null 2>&1; then
        echo "  $name MCP skipped: $need not on PATH."
        case "$name" in
          # Its own venv, not the system python: scrapling upgrades anyio,
          # click, lxml and pydantic, which is how a shared env loses a
          # working tensorflow or streamlit. The venv is machine-wide state,
          # one per box like the plugins tree. harness:shared
          scrapling)
            v="\$HOME/.claude/scrapling-venv"  # harness:shared, one venv per machine
            echo "    fix: python3 -m venv $v"
            echo "         $v/bin/pip install 'scrapling[ai]'"
            echo "         $v/bin/scrapling install"
            echo "         ln -s $v/bin/scrapling-mcp \$HOME/.local/bin/" ;;
          *) echo "    fix: install $need and put it on PATH" ;;
        esac
        continue
      fi
      # IFS is still tab inside this loop, so $args would not word-split.
      # Split it explicitly into an array instead.
      IFS=' ' read -r -a add_args <<<"$args"
      claude mcp add "${add_args[@]}" >/dev/null 2>&1 \
        && echo "  $name MCP added" || echo "  $name MCP add failed (auth?)"
    elif [ "$want" = "no" ] && [ "$have" != "0" ]; then
      claude mcp remove "$name" -s user >/dev/null 2>&1 && echo "  $name MCP removed"
    fi
  done <<'MCP_TABLE'
atlassian	-	--transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2 -s user
scrapling	scrapling-mcp	scrapling -s user -- scrapling-mcp
MCP_TABLE
else
  echo "  (claude CLI absent; MCP step skipped)"
fi

# 4b. memory: install claude-mem if this profile enables it, and pick a provider
# that is actually reachable here (see lib/claude-mem-setup.sh).
bash "$CORE_DIR/lib/claude-mem-setup.sh" || true

# 4c. shell rc: refresh the alias block and strip legacy headroom lines. This
# only ran from setup-core.sh (once per machine), so an rc file that predates a
# change kept its stale content through every `tack sync`.
bash "$CORE_DIR/lib/setup-shell-aliases.sh" || true

# 5. record active + verify
echo "$NAME" > "$CLAUDE/.harness-active"
echo "==> profile '$NAME' applied. Run 'claude' reload-plugins if a session is open."
if [ -x "$CLAUDE/verify-setup.sh" ]; then
  bash "$CLAUDE/verify-setup.sh" || echo "apply-profile: verify-setup reported issues (see above)"
fi
