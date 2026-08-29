#!/usr/bin/env bash
# capture-plan.sh
# PostToolUse hook on ExitPlanMode: copy the approved plan into the repo, so the
# reasoning behind a change ships with the code instead of staying in
# ~/.claude/plans on one laptop.
# OPT-IN: writes only when the repo already has a .agent/ directory. `mkdir
# .agent` is how a project asks for this; every other repo is untouched.
# FAIL-OPEN: any error, missing dep, or missing field -> exit 0, no output.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

cwd=$(jq -r '.cwd // ""' <<< "$input" 2>/dev/null | tr -d '\r') || exit 0
[ -n "$cwd" ] || exit 0
[ -d "$cwd/.agent" ] || exit 0

# A rejected plan should leave nothing behind. PostToolUse normally fires only
# on a tool that ran, but the response shape is not contractual, so treat an
# explicit error or denial as "no plan approved" rather than trusting the event.
if jq -e '(.tool_response // empty)
          | if type == "object"
            then (.isError == true) or ((.decision? // "") == "reject")
            else (tostring | test("rejected|user doesn.t want to proceed"; "i"))
            end' <<< "$input" >/dev/null 2>&1; then
  exit 0
fi

plan=$(jq -r '.tool_input.plan // ""' <<< "$input" 2>/dev/null | tr -d '\r') || exit 0
[ -n "$plan" ] || exit 0

session=$(jq -r '.session_id // "unknown"' <<< "$input" 2>/dev/null | tr -d '\r')
ts=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now)
out="$cwd/.agent/plan-$ts.md"

{
  echo "<!-- captured $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown) -->"
  echo "<!-- session ${session:-unknown} -->"
  echo
  printf '%s\n' "$plan"
} > "$out" 2>/dev/null || exit 0

exit 0
