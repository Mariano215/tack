#!/usr/bin/env bash
# graphify-session.sh (SessionStart)
# Makes the graphify code graph the first stop for codebase questions. In a git
# repo it builds graphify-out/ when missing, or refreshes it when a write marked
# it stale, then tells the model to query the graph before grep.
# `graphify update` is AST-only: no LLM, no cost, seconds on a normal repo. It
# runs detached so session start never waits on it.
# Opt-in per profile with GRAPHIFY_AUTO=1 in the manifest env. Fail-open.

[ "${GRAPHIFY_AUTO:-}" = "1" ] || exit 0
command -v graphify >/dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || exit 0
[ -n "$root" ] && cd "$root" 2>/dev/null || exit 0

# Keep the graph out of commits without editing a tracked .gitignore. A repo
# that already ignores or tracks graphify-out/ keeps its own rule.
if ! git check-ignore -q graphify-out/ 2>/dev/null && [ -z "$(git ls-files graphify-out 2>/dev/null | head -1)" ]; then
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null | tr -d '\r')"
  if [ -n "$ex" ] && mkdir -p "$(dirname "$ex")" 2>/dev/null; then
    # A last line with no newline would fuse with ours and break both rules.
    [ -s "$ex" ] && [ -n "$(tail -c1 "$ex" 2>/dev/null)" ] && echo >> "$ex"
    echo "graphify-out/" >> "$ex" 2>/dev/null
  fi
fi

state="ready"
if [ ! -f graphify-out/graph.json ] || [ -f graphify-out/.needs_update ]; then
  state="building"
  # One build per repo: two sessions starting together would both write
  # graph.json. A lock older than 10 minutes is a crashed build, so clear it.
  mkdir -p graphify-out 2>/dev/null
  # ponytail: age test and rmdir run in one find, so the window where a second
  # session could remove a fresh lock is one stat long, not two commands.
  find graphify-out -maxdepth 1 -name .build.lock -mmin +10 -exec rmdir {} \; 2>/dev/null
  if mkdir graphify-out/.build.lock 2>/dev/null; then
    ( graphify update . >/dev/null 2>&1 && rm -f graphify-out/.needs_update; rmdir graphify-out/.build.lock ) </dev/null >/dev/null 2>&1 &
  fi
fi

msg="graphify: code graph for this repo is $state at graphify-out/graph.json. For codebase questions (where is X, what calls Y, how does Z flow) run \`graphify query \"<question>\"\` first. Use the LSP tool for exact definitions, references and types, and grep for literal strings or when the graph has no answer."
[ "$state" = "building" ] && msg="$msg If the query says no graph, the build is still running (seconds), so use grep meanwhile."
jq -n --arg m "$msg" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$m}}' 2>/dev/null || true
exit 0
