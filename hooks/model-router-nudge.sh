#!/usr/bin/env bash
# model-router-nudge.sh
# PreToolUse hook (matcher: Agent|Task|Workflow): reminds Claude to apply
# smart-agent-spawner's model/effort/retry rules before spawning a subagent.
# Advisory only. FAIL-OPEN: any error, missing dep -> exit 0, no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: "Apply smart-agent-spawner skill rules before this spawn: pick model tier (haiku/sonnet/opus) by task complexity, set effort only if using Workflow agent(), and on failure escalate one tier and retry (cap 3 attempts, then ask the user)."
  }
}' 2>/dev/null || exit 0

exit 0
