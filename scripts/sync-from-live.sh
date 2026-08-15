#!/usr/bin/env bash
# sync-from-live.sh
# Maintainer tool: pull live ~/.claude experiments back into this repo.
# Explicit allowlist only; never syncs state, memory, settings, or auditor
# content. DRY RUN by default; pass --apply to execute.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY="--dry-run"
if [ "${1:-}" = "--apply" ]; then
    DRY=""
    echo "APPLY mode: changes will be written."
else
    echo "DRY RUN (pass --apply to execute)."
fi
echo ""

sync() {
    local src="$1" dest="$2"
    if [ ! -e "$src" ]; then
        echo "skip (missing live): $src"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    # shellcheck disable=SC2086
    rsync -av --delete --exclude='__pycache__' --exclude='.DS_Store' $DRY "$src" "$dest"
    echo ""
}

# Allowlist: live-developed artifacts whose source of truth is ~/.claude.
# Hooks, goal skills, templates, and settings are edited IN THE REPO and are
# deliberately absent here.
sync "$HOME/.claude/skills/fullreview/"  "$REPO_ROOT/skills/fullreview/"
sync "$HOME/.claude/skills/graphify/"    "$REPO_ROOT/skills/graphify/"
sync "$HOME/.claude/skills/ghost/"       "$REPO_ROOT/skills/ghost/"
sync "$HOME/.claude/skills/scroll-world/" "$REPO_ROOT/skills/scroll-world/"
sync "$HOME/.claude/ghost/"              "$REPO_ROOT/ghost/"
sync "$HOME/.claude/commands/ghost.md"   "$REPO_ROOT/commands/ghost.md"
sync "$HOME/.claude/statusline-command.sh" "$REPO_ROOT/statusline-command.sh"

echo "Done. Before committing, run: bash $REPO_ROOT/scripts/sanitize-check.sh"
