#!/usr/bin/env bash
# Compatibility entrypoint. Profile repos pin and call this path; provider
# mechanics now live behind adapters without changing the existing contract.
# The Claude adapter honors CLAUDE_CONFIG_DIR for isolated profile sessions.
set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$CORE_DIR/adapters/claude/apply-profile.sh" "$@"
