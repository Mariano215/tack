#!/usr/bin/env bash
# Covers the one rule that keeps capture-plan.sh from writing into repos that
# never asked for it: no .agent/ directory means no write, ever. If that gate
# regresses, every project the harness touches grows plan files it did not want.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/capture-plan.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failed=0

fail() { echo "test-capture-plan: $1"; failed=1; }

# 1. No .agent/ -> nothing written.
d="$TMP/no-agent"; mkdir -p "$d"
printf '{"cwd":"%s","tool_input":{"plan":"do the thing"}}' "$d" | bash "$HOOK" >/dev/null 2>&1
[ "$(find "$d" -type f | wc -l | tr -d ' ')" = "0" ] || fail "wrote into a repo with no .agent/"

# 2. .agent/ present -> the plan text lands verbatim.
d="$TMP/opted-in"; mkdir -p "$d/.agent"
printf '{"cwd":"%s","session_id":"abc123","tool_input":{"plan":"line one\\nline two"}}' "$d" \
  | bash "$HOOK" >/dev/null 2>&1
out="$(find "$d/.agent" -name 'plan-*.md' | head -1)"
if [ -z "$out" ]; then
  fail "no plan file written for an opted-in repo"
else
  grep -q "line one" "$out" || fail "plan body missing from $out"
  grep -q "line two" "$out" || fail "plan body truncated in $out"
  grep -q "abc123" "$out" || fail "session id missing from $out"
fi

# 3. Empty and malformed stdin -> exit 0, nothing written.
d="$TMP/junk"; mkdir -p "$d/.agent"
printf '' | bash "$HOOK" >/dev/null 2>&1 || fail "empty stdin should exit 0"
printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1 || fail "malformed stdin should exit 0"
printf '{"cwd":"%s","tool_input":{}}' "$d" | bash "$HOOK" >/dev/null 2>&1 || fail "missing plan should exit 0"
[ "$(find "$d/.agent" -type f | wc -l | tr -d ' ')" = "0" ] || fail "wrote a file with no plan text"

# 4. A rejected plan leaves nothing behind.
d="$TMP/rejected"; mkdir -p "$d/.agent"
printf '{"cwd":"%s","tool_input":{"plan":"nope"},"tool_response":{"isError":true}}' "$d" \
  | bash "$HOOK" >/dev/null 2>&1
[ "$(find "$d/.agent" -type f | wc -l | tr -d ' ')" = "0" ] || fail "wrote a plan the user rejected"

[ "$failed" -eq 0 ] && echo "test-capture-plan: ok"
exit "$failed"
