#!/usr/bin/env bash
# bootstrap.sh - one-shot install for a fresh devcontainer or workstation.
# Clones (or updates) core, installs tack + tokensave, applies a profile.
# Idempotent: safe to run on every container start (postCreateCommand).
# Requires git credentials if any profile repo is private (gh auth or a token).
#   HARNESS_ORG    GitHub account the repos live under (required)
#   HARNESS_ROOT   where profile repos live      (default: $HOME/Projects)
#   HARNESS_PROFILE profile to apply on bootstrap (default: dev)
set -euo pipefail

ROOT="${HARNESS_ROOT:-$HOME/Projects}"
PROFILE="${HARNESS_PROFILE:-dev}"
ORG="${HARNESS_ORG:?set HARNESS_ORG to your GitHub account}"
# The engine itself, not a profile: defaults to upstream, override for a fork.
CORE_URL="${HARNESS_CORE_URL:-https://github.com/Mariano215/tack.git}"
CORE="$ROOT/tack"
mkdir -p "$ROOT"

if [ -d "$CORE/.git" ]; then
  git -C "$CORE" pull --quiet || true
else
  git clone --quiet "$CORE_URL" "$CORE"
fi

cd "$CORE"
./setup-core.sh "$ROOT"
export PATH="$HOME/.local/bin:$PATH"
tack install "$PROFILE"
echo "bootstrap done: profile=$PROFILE root=$ROOT"
