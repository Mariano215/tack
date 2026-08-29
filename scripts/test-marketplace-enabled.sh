#!/usr/bin/env bash
# Checks the enabled-marketplace guard in hooks/plugin-auto-update.sh.
#
# The guard decides whether restore_marketplace_deps pays a cold `bun install`
# or `npm install` for a marketplace clone. Before it existed the loop had no
# enabled check at all, so `claude plugin disable` left the install running on
# every session start. On Windows that install fails with ENOTEMPTY and the
# failure is invisible from the plugin list, which is a bad way to spend a
# session start.
#
# The function is extracted rather than sourced: the hook runs work at load
# time, and hooks/ cannot depend on lib/ because apply-profile copies hooks/
# into the config dir and never copies lib/.
set -uo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$CORE_DIR/hooks/plugin-auto-update.sh"

fn="$(sed -n '/^marketplace_has_enabled_plugin() {/,/^}/p' "$HOOK")"
if [ -z "$fn" ]; then
    echo "FAIL could not extract marketplace_has_enabled_plugin from $HOOK"
    exit 1
fi
eval "$fn"

fails=0
check() { # check <label> <expected: yes|no> <marketplace>
    local got=no
    marketplace_has_enabled_plugin "$3" && got=yes
    if [ "$2" = "$got" ]; then
        echo "ok  $1"
    else
        echo "FAIL $1: expected '$2', got '$got'"
        fails=$((fails + 1))
    fi
}

CLAUDE_DIR="$(mktemp -d)"
trap 'rm -rf "$CLAUDE_DIR"' EXIT
cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "caveman@caveman": true,
    "code-review@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": false,
    "claude-mem@thedotmack": false,
    "frontend-slides@frontend-slides": false
  }
}
JSON

check "enabled plugin means the marketplace is live"     yes caveman
check "one enabled among several is enough"              yes claude-plugins-official
check "every plugin false means skip"                    no  thedotmack
check "single false plugin means skip"                   no  frontend-slides
check "marketplace absent from enabledPlugins means skip" no nosuchmarket

# A name that is a suffix of another must not match. Without the leading "@"
# in the comparison, "market" would match "plugin@othermarket".
cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{ "enabledPlugins": { "p@othermarket": true } }
JSON
check "suffix of a longer marketplace name does not match" no market
check "the full name still matches"                        yes othermarket

# Missing or malformed settings.json must answer no rather than error out. This
# hook runs async at session start and must never take the session down.
rm -f "$CLAUDE_DIR/settings.json"
check "missing settings.json is not an error"  no caveman
echo 'not json' > "$CLAUDE_DIR/settings.json"
check "malformed settings.json is not an error" no caveman
printf '{}' > "$CLAUDE_DIR/settings.json"
check "settings.json with no enabledPlugins key" no caveman

[ "$fails" -eq 0 ] && echo "test-marketplace-enabled: all passed"
exit "$fails"
