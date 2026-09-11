#!/usr/bin/env bash
# verify-setup.sh - engine invariants after a profile is applied.
# Profile-agnostic: checks what apply-profile guarantees, NOT which profile skills
# or MCP happen to be present (those vary by profile). Exit 1 on a hard failure.
set -uo pipefail
CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
red=$'\033[0;31m'; grn=$'\033[0;32m'; ylw=$'\033[0;33m'; rst=$'\033[0m'
fail=0
ok()   { echo "   ${grn}✓${rst} $1"; }
warn() { echo "   ${ylw}!${rst} $1"; }
err()  { echo "   ${red}✗${rst} $1"; fail=1; }

echo "Verifying harness engine..."

command -v jq >/dev/null 2>&1 || err "jq missing (hooks need it)"

S="$CLAUDE/settings.json"
if [ -f "$S" ] && jq -e . "$S" >/dev/null 2>&1; then ok "settings.json valid JSON"
else err "settings.json missing or invalid JSON"; fi

grep -q "skill-router.sh" "$S" 2>/dev/null && ok "skill-router wired" || err "skill-router not wired in settings"
grep -q "ghost_precheck.py" "$S" 2>/dev/null && ok "ghost precheck wired" || warn "ghost precheck not wired"

# doctor-parity: config parses, default mode is sane, tack/claude reachable
J="$CLAUDE/.claude.json"
if [ -f "$J" ]; then
  jq -e . "$J" >/dev/null 2>&1 && ok ".claude.json valid JSON" || err ".claude.json invalid JSON (settings silently ignored)"
fi
dm="$(jq -r '.permissions.defaultMode // "unset"' "$S" 2>/dev/null)"
case "$dm" in
  auto|acceptEdits|default|dontAsk|plan|bypassPermissions|manual) ok "defaultMode: $dm" ;;
  unset) warn "defaultMode not set (falls back to default)" ;;
  *) err "defaultMode invalid: $dm" ;;
esac
# The authority the agent runs under is a profile decision. A legal value is not
# the same as the declared one, and the old check only tested legality.
declared_file="$CLAUDE/.harness-declared-mode"
if [ -s "$declared_file" ]; then
  declared="$(tr -d '\r' < "$declared_file")"
  if [ "$dm" != "$declared" ]; then
    warn "defaultMode is '$dm' but the active profile declares '$declared'. Fix: re-apply with 'tack use \$(cat $CLAUDE/.harness-active)', or change the profile manifest if '$dm' is what you want."
  fi
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ok "~/.local/bin on PATH" ;; *) warn "~/.local/bin not on PATH (tack/claude may be unreachable)" ;; esac

for h in skill-router.sh skill-routes.json session-summary.sh; do
  if [ -f "$CLAUDE/hooks/$h" ] && [ ! -L "$CLAUDE/hooks/$h" ]; then ok "hook $h (regular file)"
  else err "hook $h missing or a symlink"; fi
done
jq -e . "$CLAUDE/hooks/skill-routes.json" >/dev/null 2>&1 && ok "skill-routes.json valid JSON" || err "skill-routes.json invalid"

# CRLF line endings: a repo cloned on Windows with core.autocrlf=true yields
# scripts that die at the shebang, so every hook fails while the install looks
# complete. .gitattributes prevents new clones from getting them; this catches a
# machine cloned before that existed.
crlf=""
for f in "$CLAUDE/hooks/skill-router.sh" "$CLAUDE/statusline-command.sh" "$CLAUDE/verify-setup.sh"; do
  [ -f "$f" ] || continue
  head -1 "$f" | grep -q "$(printf '\r')" && crlf="$crlf $(basename "$f")"
done
[ -z "$crlf" ] && ok "scripts have LF endings" || err "CRLF line endings:$crlf (re-clone with the repo's .gitattributes, or: sed -i 's/\r$//' <file>)"

# router probe: a bug prompt must route to goal-iteration (tests the hook, not skill presence)
if [ -x "$CLAUDE/hooks/skill-router.sh" ]; then
  out="$(SKILL_ROUTES_FILE="$CLAUDE/hooks/skill-routes.json" bash "$CLAUDE/hooks/skill-router.sh" <<<'{"prompt":"the login form is broken and failing"}' 2>/dev/null)"
  echo "$out" | grep -q "goal-iteration" && ok "router probe routes bug -> goal-iteration" || warn "router probe did not match"
fi

# router targets: every skill named in skill-routes.json should be reachable.
# Warn-only: a route may legitimately point at a plugin-provided skill (not a
# directory under ~/.claude/skills), and profiles intentionally carry different sets.
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE/hooks/skill-routes.json" ]; then
  missing=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    # skills-disabled: quarantined by apply-profile, present but not in this profile
    { [ -d "$CLAUDE/skills/$s" ] || [ -d "$CLAUDE/skills-disabled/$s" ]; } && continue
    # plugin-provided: layout varies (marketplaces/<plugin>/skills|commands/<name>)
    # -H because in an isolated config dir plugins/ is a symlink to the shared
    # tree, and BSD find does not follow a symlinked start point. Without it this
    # check degrades to a permanent warning.
    [ -n "$(find -H "$CLAUDE/plugins" -maxdepth 5 -name "$s" -o -maxdepth 5 -name "$s.md" -o -maxdepth 5 -name "$s.toml" 2>/dev/null | head -1)" ] && continue
    missing="$missing $s"
    # jq.exe on Windows emits CRLF; without tr the names compare as "fullreview\r"
  done < <(jq -r '.routes[].skill' "$CLAUDE/hooks/skill-routes.json" 2>/dev/null | tr -d '\r' | sort -u)
  if [ -z "$missing" ]; then ok "all router targets resolve"
  else warn "router targets not found locally:$missing (plugin-provided or absent in this profile)"; fi
fi

[ -f "$CLAUDE/ghost/ghost_scan.py" ] && ok "ghost engine present" || warn "ghost engine missing"

# statusline: wired in settings AND the script it points at exists
if grep -q "statusline-command.sh" "$S" 2>/dev/null; then
  [ -f "$CLAUDE/statusline-command.sh" ] && ok "statusline wired" || err "statusline wired but script missing"
else
  warn "statusline not wired"
fi

# output style: settings names one, the file that defines it must be here too.
# Claude Code falls back to the default style in silence when it is not, so the
# prose rules quietly stop applying with nothing on screen to say so.
if command -v jq >/dev/null 2>&1; then
  os="$(jq -r '.outputStyle // empty' "$S" 2>/dev/null | tr -d '\r')"
  if [ -n "$os" ]; then
    if grep -rqi "^name: *$os\$" "$CLAUDE/output-styles" 2>/dev/null; then
      ok "output style '$os' present"
    else
      err "settings names outputStyle '$os' but no file in $CLAUDE/output-styles declares it (run: tack sync, which re-copies output-styles from tack)"
    fi
  fi
fi

# marketplace drift: a marketplace still registered here that base-settings no
# longer names keeps serving its skills into every session. Hard failure so the
# plugin-auto-update hook re-applies the profile and prunes it.
KNOWN="$CLAUDE/plugins/known_marketplaces.json"
CORE_BASE="$CLAUDE/.harness-base-settings.json"
if command -v jq >/dev/null 2>&1 && [ -f "$KNOWN" ] && [ -f "$CORE_BASE" ]; then
  want="$(jq -r '(.extraKnownMarketplaces // {}) | keys[]' "$CORE_BASE" 2>/dev/null | tr -d '\r')"
  keep="$CLAUDE/.harness-marketplaces-keep"
  stale=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    grep -qxF "$m" <<<"$want" && continue
    [ -f "$keep" ] && grep -qxF "$m" "$keep" 2>/dev/null && continue
    stale="$stale $m"
  done < <(jq -r 'keys[]' "$KNOWN" 2>/dev/null | tr -d '\r')
  [ -z "$stale" ] && ok "no stale marketplaces" || err "stale marketplace(s):$stale (re-apply the profile to prune)"
fi

# memory: claude-mem enabled but never installed stores nothing
if command -v jq >/dev/null 2>&1 && [ "$(jq -r '(.enabledPlugins // {})["claude-mem@thedotmack"] // false' "$S" 2>/dev/null)" = "true" ]; then
  if [ -f "${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json" ]; then
    ok "claude-mem installed (provider: $(jq -r '.CLAUDE_MEM_PROVIDER // "?"' "${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json" 2>/dev/null))"
  else
    warn "claude-mem enabled but not installed (run: npx claude-mem install)"
  fi
  # Marketplace runtime: `claude plugin update` re-extracts the clone without
  # installing deps, so node_modules disappears while settings.json above stays
  # valid and the install looks complete. claude-mem then burns a cold install
  # inside its Setup hook at every session start, long enough to drop the API
  # connection. Hard failure on purpose: plugin-auto-update.sh re-applies the
  # profile on non-zero, and claude-mem-setup.sh repairs it there.
  MKT="$CLAUDE/plugins/marketplaces/thedotmack"
  if [ -f "$MKT/package.json" ]; then
    [ -d "$MKT/node_modules" ] \
      && ok "claude-mem marketplace runtime present" \
      || err "claude-mem marketplace runtime missing (re-apply the profile, or: npx claude-mem repair)"
  fi
  # Telegram alerts on with no credentials. TelegramNotifier returns in silence
  # when the token or the chat id is empty, so the feature reads as configured
  # and never sends. The file is machine-wide, so this is true in every profile.
  MEM_S="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/settings.json"
  if [ -f "$MEM_S" ] && [ "$(jq -r '.CLAUDE_MEM_TELEGRAM_ENABLED // "false"' "$MEM_S" 2>/dev/null | tr -d '\r')" = "true" ]; then
    if [ -n "$(jq -r '.CLAUDE_MEM_TELEGRAM_BOT_TOKEN // ""' "$MEM_S" 2>/dev/null | tr -d '\r')" ] \
    && [ -n "$(jq -r '.CLAUDE_MEM_TELEGRAM_CHAT_ID // ""' "$MEM_S" 2>/dev/null | tr -d '\r')" ]; then
      ok "claude-mem telegram configured"
    else
      warn "claude-mem telegram enabled with no token or chat id, so no alert is ever sent. Fix: set CLAUDE_MEM_TELEGRAM_BOT_TOKEN and CLAUDE_MEM_TELEGRAM_CHAT_ID in $MEM_S, or set CLAUDE_MEM_TELEGRAM_ENABLED to false"
    fi
  fi
fi
[ -f "$CLAUDE/.harness-active" ] && ok "active profile: $(cat "$CLAUDE/.harness-active")" || warn "no active profile recorded"

echo ""
if [ "$fail" = 0 ]; then echo "${grn}Engine OK${rst}"; else echo "${red}Engine check failed${rst}"; fi
exit $fail
