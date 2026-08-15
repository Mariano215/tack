#!/usr/bin/env bash
# setup-core.sh [harness_root]
# One-time per machine: put `tack` on PATH and record where the profile repos live.
# Does NOT install a profile; run `tack use <name>` after this.
#
# Flags, both off by default because both change how `claude` runs in every
# shell on the machine:
#   --no-api-key   blank ANTHROPIC_API_KEY in the wrapper, forcing subscription
#                  auth. Correct on a Max account, breaks API-key billing.
#   --yolo-alias   point the convenience alias at --dangerously-skip-permissions,
#                  which removes the confirmation prompt on writes and commands.
set -euo pipefail
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"; mkdir -p "$CLAUDE" "$HOME/.local/bin"

args=()
for a in "$@"; do
  case "$a" in
    --no-api-key) export HARNESS_NO_API_KEY=1 ;;
    --yolo-alias) export HARNESS_YOLO_ALIAS=1 ;;
    -h|--help) echo "usage: setup-core.sh [harness_root] [--no-api-key] [--yolo-alias]"; exit 0 ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args+"${args[@]}"}

ROOT="${1:-${HARNESS_ROOT:-$HOME/Projects}}"
echo "$ROOT" > "$CLAUDE/.harness-root"
echo "harness root recorded: $ROOT"

install -m 0755 "$CORE_DIR/bin/tack" "$HOME/.local/bin/tack"
echo "installed tack -> $HOME/.local/bin/tack"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "NOTE: add ~/.local/bin to PATH";; esac

command -v jq   >/dev/null 2>&1 || echo "WARN: jq not found (required by tack/apply-profile)"
command -v claude >/dev/null 2>&1 || echo "WARN: claude CLI not found (MCP/plugin steps will skip)"

# tokensave CLI (code-graph), best-effort, non-blocking
bash "$CORE_DIR/lib/install-tokensave.sh" || true

# claude-code shell alias (plain claude, no proxy wrap)
bash "$CORE_DIR/lib/setup-shell-aliases.sh" || true

echo "done. Next: tack install <name>   (set HARNESS_ORG first), or tack use <name> if already cloned."
echo "  No profile repo yet? https://github.com/Mariano215/tack-profile-example"
