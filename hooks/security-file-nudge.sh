#!/usr/bin/env bash
# security-file-nudge.sh
# Injects threat-model reminder when Claude writes security-sensitive files.
set -euo pipefail

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // ""' <<< "$input" 2>/dev/null | tr -d '\r' || echo "")

# Skip hook scripts and skill files — they aren't application security surfaces
if echo "$file_path" | grep -qiE '(\.claude/hooks/|\.claude/skills/|tack/hooks/|tack/skills/)'; then
    exit 0
fi

if ! echo "$file_path" | grep -qiE \
    '(auth|\.env|password|secret|crypto|jwt|oauth|api.?key|credential)'; then
    exit 0
fi

jq -n --arg f "$file_path" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": ("SECURITY FILE: " + $f + "\n\nApply threat-model check before continuing:\n- All paths gated? (auth middleware coverage)\n- Least privilege enforced? (role/permission checks)\n- Inputs parameterized/sanitized? (no raw string concat in queries)\n- No hardcoded secrets? (env vars only)\n- No sensitive data in logs or error responses?\n- Error messages reveal nothing to the client?\n\nIf this introduces a new auth or permission pattern: add a threat-model comment above the function.")
  }
}'
