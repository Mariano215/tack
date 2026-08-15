#!/usr/bin/env bash
# Checks the skills_link path expansion in lib/resolve-link-target.sh.
# Pure string work — touches no real HOME and applies no profile.
set -uo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CORE_DIR/lib/resolve-link-target.sh"

fails=0
check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok  $1"
    else
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}

# Sandbox HOME so the assertions do not depend on the developer's machine.
REAL_HOME="$HOME"
HOME="/tmp/fake-home"
mkdir -p "$HOME/.claude"

# --- $HARNESS_ROOT, the fix for the external-volume paths this replaced ---
echo "/srv/repos" > "$HOME/.claude/.harness-root"
check "harness root read from .harness-root" \
    "/srv/repos/claude-trading-skills/skills/position-sizer" \
    "$(resolve_link_target '$HARNESS_ROOT/claude-trading-skills/skills/position-sizer')"

# Falls back to ~/Projects when the machine has no .harness-root, matching tack.
rm -f "$HOME/.claude/.harness-root"
check "falls back to ~/Projects" \
    "$HOME/Projects/claude-trading-skills/skills/backtest-expert" \
    "$(resolve_link_target '$HARNESS_ROOT/claude-trading-skills/skills/backtest-expert')"

# --- ~/ expansion, the pre-existing behaviour this must not break ---
check "tilde expands to HOME" \
    "$HOME/.agents/skills/gsap" \
    "$(resolve_link_target '~/.agents/skills/gsap')"

# --- passthrough ---
check "absolute path passes through" \
    "/opt/skills/thing" \
    "$(resolve_link_target '/opt/skills/thing')"
# A bare ~ or a mid-string $HARNESS_ROOT is not a prefix match and must not be
# rewritten — only a leading prefix counts.
check "tilde without slash is not expanded" \
    "~weird/path" \
    "$(resolve_link_target '~weird/path')"
check "HARNESS_ROOT mid-string is left alone" \
    "/opt/\$HARNESS_ROOT/x" \
    "$(resolve_link_target '/opt/$HARNESS_ROOT/x')"

rm -rf "$HOME"
HOME="$REAL_HOME"

# --- every committed manifest must be portable ---
for m in "$CORE_DIR"/profiles/*/manifest.json; do
    bad="$(jq -r '(.skills_link // {}) | to_entries[] | select(.value | startswith("~/") or startswith("$HARNESS_ROOT/") | not) | .value' "$m" 2>/dev/null | tr -d '\r')"
    if [ -n "$bad" ]; then
        echo "FAIL $(basename "$(dirname "$m")"): non-portable skills_link target(s):"
        echo "$bad" | sed 's/^/       /'
        fails=$((fails + 1))
    else
        echo "ok  $(basename "$(dirname "$m")") manifest skills_link portable"
    fi
done

[ "$fails" -eq 0 ] && echo "" && echo "all checks passed" && exit 0
echo "" && echo "$fails check(s) failed" && exit 1
