#!/usr/bin/env bash
# Covers the model pin in model-router-nudge.sh: a listed subagent_type with no
# model gets its smart-agent-spawner tier through updatedInput, an explicit model
# is never overridden, and junk input exits 0. If the pin regresses, spawns fall
# back to the session model silently, or worse, the hook overrides a model the
# caller chose on purpose.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/model-router-nudge.sh"
failed=0

fail() { echo "test-model-router: $1"; failed=1; }
model_for() { printf '%s' "$1" | bash "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.model // "none"' | tr -d '\r'; }

[ "$(model_for '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"p"}}')" = "haiku" ] || fail "Explore not pinned to haiku"
[ "$(model_for '{"tool_name":"Agent","tool_input":{"subagent_type":"code-reviewer","prompt":"p"}}')" = "opus" ] || fail "code-reviewer not pinned to opus"
[ "$(model_for '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"sonnet"}}')" = "none" ] || fail "overrode an explicit model"
[ "$(model_for '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose"}}')" = "none" ] || fail "pinned an unlisted type"
[ "$(model_for '{"tool_name":"Workflow","tool_input":{"script":"x"}}')" = "none" ] || fail "rewrote a Workflow call"

# The rewrite must keep every other field of tool_input.
p="$(printf '%s' '{"tool_name":"Agent","tool_input":{"subagent_type":"Plan","prompt":"keep me"}}' | bash "$HOOK" | jq -r '.hookSpecificOutput.updatedInput.prompt' | tr -d '\r')"
[ "$p" = "keep me" ] || fail "updatedInput dropped the prompt"

printf '' | bash "$HOOK" >/dev/null 2>&1 || fail "empty stdin should exit 0"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1 || fail "malformed stdin should exit 0"

[ "$failed" = 0 ] && echo "test-model-router: ok"
exit "$failed"
