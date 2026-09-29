#!/usr/bin/env bash
# model-router-nudge.sh
# PreToolUse hook (matcher: Agent|Task|Workflow): asks whether this spawn is
# warranted by the shape of the work, then reminds Claude of smart-agent-spawner's model, effort
# and retry rules. Current models delegate readily on their own, so the first
# question is whether to delegate, not which tier to delegate to.
# For an Agent/Task call with no model set, it also pins the tier smart-agent-spawner
# names for that subagent_type, through updatedInput. An explicit model always wins,
# and an unlisted type keeps the session default.
# FAIL-OPEN: any error, missing dep -> exit 0, no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

jq -c '
  {
    Explore: "haiku",
    Plan: "opus",
    "code-reviewer": "opus",
    "code-security-auditor": "opus"
  } as $tiers
  | (if (.tool_name == "Agent" or .tool_name == "Task")
        and ((.tool_input.model // "") == "")
     then $tiers[.tool_input.subagent_type // ""]
     else null end) as $model
  | {
      hookSpecificOutput: ({
        hookEventName: "PreToolUse",
        additionalContext: "Before spawning: does this work read a lot and return a little (search, log or test triage, review), or is it a specified implementation unit with a clear check? Then delegate. If it is a decision, a plan, a small edit, or depends on detail you already hold, do it yourself. Never spawn an agent to verify or double-check your own output; the one exception is code-reviewer at a checkpoint or commit gate. If you do spawn, apply smart-agent-spawner: pick model tier (haiku/sonnet/opus) by task complexity, set effort only if using Workflow agent(), keep the count low, and on failure escalate one tier and retry (cap 3 attempts, then ask the user)."
      } + (if $model then {updatedInput: (.tool_input + {model: $model})} else {} end))
    }
' <<< "$input" 2>/dev/null || exit 0

exit 0
