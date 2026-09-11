#!/usr/bin/env bash
# Mark a repo's generated Graphify graph stale after Codex edits a file.
set -u

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')"
[ -d "$CWD" ] || CWD="$(pwd)"
[ -f "$CWD/graphify-out/graph.json" ] || exit 0

touch "$CWD/graphify-out/.needs_update" 2>/dev/null || exit 0
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "Graphify source changed -> graphify-out/.needs_update created. Run graphify . --update before the next graph query."
  }
}'
