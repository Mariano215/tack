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
# Real misfires replayed from history. Each one fired a route it should not.
run graphify install on the laptop|
check which graphify resolves on PATH|
Graphify should be the default with grep as the fallback, let's update it|
do we need superpowers with the latest 5.5 versions and why did we disable it|
what was the LiteLLM API key we used last week|
discard the README change and merge the PR|
push it out on linkedin tomorrow|
review the repo so we have only what we need|
explain the architecture of the billing service|
# Background-task notifications carry no user request.
<task-notification> Agent "Review core harness engine" finished: update the docs, fix the bug, run graphify </task-notification>|
[SYSTEM NOTIFICATION - NOT USER INPUT] agent finished, the readme is broken|
# More positives for the tightened patterns.
push this to origin when checks pass|pre-push
refresh the code graph after the refactor|knowledge-graph
write the tests first, then the parser|tdd
fix the crash in the upload handler|bugfix
the export job is failing on large files|bugfix
document the retry behavior in the readme|docs
do a full review of the repo before we ship|codebase-review-agentic
review this repository for maintainability|codebase-review-agentic
# Common phrasings the first tightening missed (review of 2026-09-29).
push it now|pre-push
can you push this branch|pre-push
push the fix to origin|pre-push
push to github|pre-push
the app crashes on startup|bugfix
login is not working after the deploy|bugfix
the build fails on main|bugfix
there's a bug in the login flow|bugfix
graphify this repo|knowledge-graph
rebuild the graph after the refactor|knowledge-graph
# ...and the new false positives it created.
# A failed push is a bug report, not a request to push.
the push to main failed yesterday, what happened|bugfix
why is the regression test suite so slow|
remove the stack trace from the log output|
give me a comprehensive review of the PR|
the full review agent left comments, summarize them|
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
