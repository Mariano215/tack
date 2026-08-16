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
# Wait rather than fail. Opening two profiles in two terminals is the headline
# use case, and both applies race for this lock the moment you do it. Failing
# the second one made the documented workflow break on first contact.
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "apply-profile: another apply is running, waiting for it to finish..." >&2
  waited=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge 180 ]; then
      echo "apply-profile: still locked after ${waited}s, giving up." >&2
      echo "  If no other apply is running the lock is stale: rmdir $LOCK" >&2
      exit 1
    fi
  done
  echo "apply-profile: lock acquired after ${waited}s." >&2
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

MANIFEST="${1:-./manifest.json}"
[ -f "$MANIFEST" ] || { echo "apply-profile: no manifest at $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "apply-profile: jq required" >&2; exit 1; }

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=resolve-link-target.sh
. "$(dirname "${BASH_SOURCE[0]}")/resolve-link-target.sh"
PROFILE_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
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
  [ -f "$src/goal-safety-config.json" ] && cp "$src/goal-safety-config.json" "$CLAUDE/skills/"
done
# 3a. skills_link: skills whose source lives outside the harness (~/.agents/skills,
# a separate skills repo). Copying them would fork the source, so link instead.
# Values are machine-specific, so write them with a `~/` or `$HARNESS_ROOT/`
# prefix (see lib/resolve-link-target.sh) rather than one machine's absolute
# path. A committed absolute path leaks the author's layout and resolves to
# nothing everywhere else. A link whose target is missing is skipped, so a
# profile stays usable on a machine that lacks the source repo.
# jq.exe writes CRLF on Windows. `$(...)` hides it (MSYS bash strips the CR on
# capture) but `| while read` does not, so the last field on every line arrives
# with a trailing CR. Strip it, or every target resolves to a path that no
# machine has and every link is reported missing.
jq -r '(.skills_link // {}) | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST" \
| tr -d '\r' \
| while IFS="$(printf '\t')" read -r name target; do
  [ -n "$name" ] && [ -n "$target" ] || continue
  target="$(resolve_link_target "$target")"
  if [ ! -e "$target" ]; then
    echo "  skills_link: $name skipped, target missing: $target"
    continue
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
  [ "$b" = "goal-safety-config.json" ] && continue
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

# 4. MCP reconciliation. Browser MCPs ride enabledPlugins above. Only atlassian
#    needs explicit add. Dropped always (CLI, dead, or account-level): tokensave
#    (use the tokensave CLI), sequential-thinking, headroom (removed 2026-07),
#    and context7 (the claude.ai Context7 connector follows the login, so a
#    user-scope copy is a duplicate that also warns about a missing
#    CONTEXT7_API_KEY on machines without one).
if command -v claude >/dev/null 2>&1; then
  for drop in tokensave sequential-thinking headroom context7; do
    claude mcp remove "$drop" -s user >/dev/null 2>&1 || true
  done
  want_atlassian="$(jq -r '(.mcp // []) | index("atlassian") | if . == null then "no" else "yes" end' "$MANIFEST" | tr -d '\r')"
  have_atlassian="$(claude mcp list 2>/dev/null | grep -c '^atlassian:' || true)"
  if [ "$want_atlassian" = "yes" ] && [ "$have_atlassian" = "0" ]; then
    claude mcp add --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2 -s user >/dev/null 2>&1 \
      && echo "  atlassian MCP added" || echo "  atlassian MCP add failed (auth?)"
  elif [ "$want_atlassian" = "no" ] && [ "$have_atlassian" != "0" ]; then
    claude mcp remove atlassian -s user >/dev/null 2>&1 && echo "  atlassian MCP removed"
  fi
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
