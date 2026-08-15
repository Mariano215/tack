#!/usr/bin/env bash
# skill-router.sh
# UserPromptSubmit hook: deterministic keyword -> skill routing hints.
# Reads hook JSON on stdin, matches .prompt against skill-routes.json,
# emits additionalContext naming the skill to invoke. Advisory only.
# FAIL-OPEN: any error, missing dep, or no match -> exit 0, no output.
# Budget: one jq process (~15-30 ms), ~40 tokens emitted only on match.
set -uo pipefail

ROUTES="${SKILL_ROUTES_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/skill-routes.json}"

[ -f "$ROUTES" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

jq -c --slurpfile cfg "$ROUTES" '
  if ($cfg[0].enabled // true) != true then empty
  else
    (.prompt // "") as $p
    | if ($p | startswith("/")) or (($p | length) < 8) then empty
      else
        ( [ $cfg[0].routes[]
            | select(. as $r | $p | test($r.pattern; "i")) ]
          | .[0] // empty ) as $r
        | {
            hookSpecificOutput: {
              hookEventName: "UserPromptSubmit",
              additionalContext: (
                "Intent detected: " + $r.id
                + ". Invoke the Skill tool with skill \"" + $r.skill
                + "\" before responding. " + ($r.hint // "")
                + " If that skill is not installed in this profile, or the match is"
                + " clearly wrong, proceed normally and say why."
              )
            }
          }
      end
  end
' <<< "$input" 2>/dev/null || exit 0

exit 0
