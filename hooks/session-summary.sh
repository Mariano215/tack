#!/usr/bin/env bash
# session-summary.sh
# Prompts a structured session summary at true session end (debounced: once per 10 min).
set -euo pipefail

SENTINEL="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.session-summary-last"
NOW=$(date +%s)
DEBOUNCE=600  # 10 minutes

if [ -f "$SENTINEL" ]; then
    LAST=$(cat "$SENTINEL" 2>/dev/null || echo 0)
    ELAPSED=$(( NOW - LAST ))
    if [ "$ELAPSED" -lt "$DEBOUNCE" ]; then
        exit 0  # Too soon, skip
    fi
fi

echo "$NOW" > "$SENTINEL"

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "SESSION ENDING.\n\n1. Summarize completed work (1-3 bullets: what was built, fixed, or reviewed)\n2. Note any uncommitted changes or open branches\n3. Flag any CRITICAL/HIGH security findings that remain unfixed\n\nDo not ask about saving memory. claude-mem captures automatically at session end."
  }
}'
