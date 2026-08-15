#!/usr/bin/env bash
# drift-report.sh
# Compares what THIS machine has installed in the active config dir against what the
# harness repo would install. Categorizes skills, plugins, and MCP servers as:
#   [ok]        in repo AND installed        (setup reproduces it)
#   [gap]       in repo, NOT installed       (setup should install it but does not)
#   [uncaptured] installed, NOT in repo      (out-of-band; other machines never get it)
#
# Output is sorted and stable so two machines' reports diff cleanly:
#   ./scripts/drift-report.sh > machineA.txt   # on system A
#   ./scripts/drift-report.sh > machineB.txt   # on system B
#   diff machineA.txt machineB.txt
#
# Read-only. Portable: BSD (macOS) and GNU. No grep -P, no find -printf.
# Fail-open per section (a missing dep skips that section, not the run).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

row() { printf '  [%s] %s\n' "$1" "$2"; }
# list immediate subdir names of $1 (portable, sorted)
dirnames() { find "$1" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort; }
# true if a skill of this name is provided by an installed plugin marketplace.
# -H: in an isolated config dir plugins/ is a symlink to the shared tree, and BSD
# find does not follow a symlinked start point. Without it every plugin-provided
# skill is misreported as a gap.
plugin_skill() { [ -n "$(find -H "$CLAUDE/plugins/marketplaces" -maxdepth 4 -type d -name "$1" 2>/dev/null | head -1)" ]; }

# ---- SKILLS ---------------------------------------------------------------
printf '\n== SKILLS (repo=%s/skills vs %s/skills) ==\n' "$REPO_ROOT" "$CLAUDE"
# repo skill dirs = skills/*/ that contain a SKILL.md (installer deploys all of these)
repo_skills=$(find "$REPO_ROOT/skills" -mindepth 1 -maxdepth 1 -type d \
  -exec test -f '{}/SKILL.md' \; -exec basename {} \; 2>/dev/null | sort)
# actually installed = real dirs under the config dir's skills/ (symlinks/plugin skills handled separately)
inst_skills=$(dirnames "$CLAUDE/skills")

for s in $repo_skills; do
  if grep -qx "$s" <<<"$inst_skills"; then
    row ok "$s"
  else
    row gap "$s   (in repo, not installed here; run setup)"
  fi
done
comm -13 <(echo "$repo_skills") <(echo "$inst_skills") | while read -r s; do
  [ -n "$s" ] && row uncaptured "$s   (installed here, NOT in repo)"
done

# ---- ROUTES point at real skills? ----------------------------------------
printf '\n== SKILL ROUTES (skill-routes.json targets) ==\n'
routes_json="$REPO_ROOT/hooks/skill-routes.json"
if command -v jq >/dev/null 2>&1 && [ -f "$routes_json" ]; then
  # jq.exe on Windows emits CRLF; without tr every name compares as "fullreview\r"
  jq -r '.routes[].skill' "$routes_json" | tr -d '\r' | sort -u | while read -r sk; do
    # satisfiable if a repo dir, an installed dir, or a plugin-provided skill
    if [ -d "$REPO_ROOT/skills/$sk" ] || [ -e "$CLAUDE/skills/$sk" ] || plugin_skill "$sk"; then
      row ok "$sk"
    else
      row gap "$sk   (route points at a skill that exists NOWHERE)"
    fi
  done
else
  echo "  (jq or routes file missing, skipped)"
fi

# ---- MCP SERVERS ----------------------------------------------------------
# The union of every profile's .mcp is what the harness can register. Anything
# live outside that union arrived out of band.
printf '\n== MCP SERVERS (union of profiles/*/manifest.json .mcp) ==\n'
setup_mcp=$(jq -r '(.mcp // [])[]' "$REPO_ROOT"/profiles/*/manifest.json 2>/dev/null | tr -d '\r' | sort -u)
if command -v claude >/dev/null 2>&1; then
  # server rows only: "name: <target> - <status>". Requiring the status marker
  # keeps the trailer ("Location: /Users/...") out of the server list.
  live_mcp=$(claude mcp list 2>/dev/null | sed -n 's/^\([a-zA-Z0-9_-]*\): .* - .*/\1/p' | sort -u)
  for m in $live_mcp; do
    if grep -qx "$m" <<<"$setup_mcp"; then row ok "$m"; else row uncaptured "$m   (live here, setup never registers it)"; fi
  done
else
  echo "  (claude CLI unavailable, skipped)"
fi

# ---- PLUGINS --------------------------------------------------------------
# base-settings.json holds every plugin the harness knows about (true or false);
# profiles flip them. A plugin enabled here but absent from base is out of band.
printf '\n== PLUGINS (enabled in settings.json vs base-settings.json) ==\n'
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE/settings.json" ]; then
  known=$(jq -r '(.enabledPlugins // {}) | keys[]' "$REPO_ROOT/base-settings.json" 2>/dev/null | tr -d '\r' | sort)
  jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value==true) | .key' \
    "$CLAUDE/settings.json" 2>/dev/null | tr -d '\r' | sort | while read -r p; do
    if grep -qxF "$p" <<<"$known"; then row ok "$p"
    else row uncaptured "$p   (enabled here, base-settings never records it)"; fi
  done
else
  echo "  (jq or settings.json missing, skipped)"
fi

# ---- MARKETPLACES ---------------------------------------------------------
# Claude Code's own registry, not settings.json. A name here that base-settings
# dropped is a stale clone still serving skills into every session.
printf '\n== MARKETPLACES (registered here vs base-settings.json) ==\n'
KNOWN="$CLAUDE/plugins/known_marketplaces.json"
if command -v jq >/dev/null 2>&1 && [ -f "$KNOWN" ]; then
  want=$(jq -r '(.extraKnownMarketplaces // {}) | keys[]' "$REPO_ROOT/base-settings.json" 2>/dev/null | tr -d '\r' | sort)
  live=$(jq -r 'keys[]' "$KNOWN" 2>/dev/null | tr -d '\r' | sort)
  for m in $want; do
    grep -qxF "$m" <<<"$live" && row ok "$m" || row gap "$m   (in repo, not registered here; re-apply the profile)"
  done
  comm -13 <(echo "$want") <(echo "$live") | while read -r m; do
    [ -n "$m" ] && row uncaptured "$m   (registered here, repo dropped it; re-apply to prune)"
  done
else
  echo "  (jq or known_marketplaces.json missing, skipped)"
fi

echo ""
echo "Legend: [ok] reproduced by setup | [gap] repo has it, setup skips | [uncaptured] here only, repo never records it"
