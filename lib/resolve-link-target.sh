#!/usr/bin/env bash
# resolve_link_target <target> — expand a skills_link value to a real path.
#
# skills_link points at skill sources living outside the harness, so the values
# are inherently machine-specific. Committing one machine's absolute path (an
# external volume, a home dir) both leaks the maintainer's layout and silently
# resolves to nothing on every other machine, which skips the link without
# failing. These two prefixes keep a committed manifest portable:
#
#   ~/...              the user's home
#   $HARNESS_ROOT/...  where profile repos live on THIS machine, from
#                      ~/.claude/.harness-root (same source `tack` uses)
#
# Anything else is passed through untouched, so a genuinely local manifest can
# still use a bare absolute path.
#
# Sourced by apply-profile.sh; kept separate so it is testable without running
# a full profile apply. Tests: scripts/test-resolve-link-target.sh

harness_root() {
    local root_file="$HOME/.claude/.harness-root"
    if [ -f "$root_file" ]; then
        cat "$root_file"
    else
        echo "$HOME/Projects"
    fi
}

resolve_link_target() {
    local target="$1"
    case "$target" in
        "~/"*)              echo "$HOME/${target#\~/}" ;;
        '$HARNESS_ROOT/'*)  echo "$(harness_root)/${target#\$HARNESS_ROOT/}" ;;
        *)                  echo "$target" ;;
    esac
}
