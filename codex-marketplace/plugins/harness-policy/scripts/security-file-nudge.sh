#!/usr/bin/env bash
# Inject threat-model context after Codex edits a security-sensitive path.
set -u

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

TARGET="$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  .tool_input.command //
  ""
' 2>/dev/null | tr -d '\r')"
[ -n "$TARGET" ] || exit 0

if printf '%s' "$TARGET" | grep -qiE '(\.codex/|\.claude/|tack|codex-harness).*(hooks|skills)|plugins/harness-policy'; then
  exit 0
fi
if ! printf '%s' "$TARGET" | grep -qiE '(auth|\.env|password|secret|crypto|jwt|oauth|api.?key|credential)'; then
  exit 0
fi

jq -n --arg target "$TARGET" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("SECURITY-SENSITIVE CHANGE: " + $target + "\nCheck auth coverage, least privilege, input handling, secret storage, logs, and error disclosure before continuing.")
  }
}'
