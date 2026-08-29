#!/usr/bin/env bash
# Covers hooks/skill-router.sh against the live hooks/skill-routes.json.
# Three failures this catches that a JSON parse check cannot:
#   - a widened regex that swallows unrelated prompts (negative cases),
#   - a narrowed regex that stops matching its own intent (positive cases),
#   - a route added above an existing one, silently stealing its prompts. The
#     router takes .[0] of the matches, so file order decides the winner.
# Every route must carry at least one positive case, so adding a route without
# a case fails the build rather than shipping untested.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES="$REPO_ROOT/hooks/skill-routes.json"
HOOK="$REPO_ROOT/hooks/skill-router.sh"
failed=0
seen=""

fail() { echo "test-skill-routes: $1"; failed=1; }

# Returns the routed id, or empty for no match.
route_of() {
  SKILL_ROUTES_FILE="$ROUTES" bash "$HOOK" \
    < <(jq -nc --arg p "$1" '{prompt:$p}') 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/^Intent detected: \([^.]*\)\..*/\1/p'
}

# prompt | expected id ("" means must not route)
# Order matters in the file, so the pairs below pin the winner, not just a match.
while IFS='|' read -r prompt want; do
  [ -z "$prompt" ] && continue
  case "$prompt" in '#'*) continue ;; esac
  got="$(route_of "$prompt")"
  [ "$got" = "$want" ] || fail "\"$prompt\" routed to '${got:-<none>}', wanted '${want:-<none>}'"
  [ -n "$want" ] && seen="$seen $want"
done <<'CASES'
are we ready to push this branch|pre-push
build a knowledge graph of this repo|knowledge-graph
this keeps failing and i have no luck left|stuck-escalation
implement the parser with unit tests|tdd
the login page is broken after the merge|bugfix
build a new feature for csv export|feature
update the readme before release|docs
review the codebase for maintainability|codebase-review-agentic
what can we delete from this module|ponytail-review
audit codebase for dead weight|ponytail-audit
harden the chat endpoint against prompt injection|prompt-injection-defense
scrub documents in the rag pipeline|ingest-scrubbing
# Order sensitivity: tdd sits above bugfix, so it must win a prompt both match.
add test coverage for the crash|tdd
# Negatives: these must route nowhere.
please explain how this module is organised|
summarize the meeting notes for me|
rename this variable to something clearer|
# Guard rails in the router itself.
/commit these changes now|
hi|
CASES

# Coverage: every route in the file needs a positive case above.
while read -r id; do
  [ -z "$id" ] && continue
  case " $seen " in
    *" $id "*) ;;
    *) fail "route '$id' has no positive case in this file" ;;
  esac
done < <(jq -r '.routes[].id' "$ROUTES" | tr -d '\r')

[ "$failed" -eq 0 ] && echo "test-skill-routes: ok"
exit "$failed"
