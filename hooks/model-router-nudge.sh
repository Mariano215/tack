#!/usr/bin/env bash
# model-router-nudge.sh
# PreToolUse hook (matcher: Agent|Task|Workflow): asks whether this spawn is
# warranted at all, then reminds Claude of smart-agent-spawner's model, effort
# and retry rules. Current models delegate readily on their own, so the first
# question is whether to delegate, not which tier to delegate to.
# Advisory only. FAIL-OPEN: any error, missing dep -> exit 0, no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: "Before spawning: is this large, genuinely independent, parallelizable work? If you could finish it in a handful of tool calls, do it yourself instead. Never spawn an agent to verify or double-check your own output. If you do spawn, apply smart-agent-spawner: pick model tier (haiku/sonnet/opus) by task complexity, set effort only if using Workflow agent(), keep the count low, and on failure escalate one tier and retry (cap 3 attempts, then ask the user)."
  }
}' 2>/dev/null || exit 0

exit 0
