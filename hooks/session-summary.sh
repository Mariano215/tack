#!/usr/bin/env bash
# session-summary.sh
# Prompts a structured session summary at true session end (debounced: once per 10 min).
# When the repo has a .agent/ directory, the summary is also asked to land in
# .agent/log.md, so open bugs, security findings and next steps survive the
# session instead of scrolling away. `mkdir .agent` is how a repo opts in.
set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0  # fail open: the output is built with jq

SENTINEL="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.session-summary-last"
NOW=$(date +%s)
DEBOUNCE=600  # 10 minutes

if [ -f "$SENTINEL" ]; then
    LAST=$(cat "$SENTINEL" 2>/dev/null || echo 0)
    ELAPSED=$(( NOW - LAST ))
    if [ "$ELAPSED" -lt "$DEBOUNCE" ]; then
        exit 0  # Too soon, skip
    fi
fi

echo "$NOW" > "$SENTINEL"

# The hook can only inject a prompt, it cannot capture the reply, so the write
# instruction has to live in the prompt itself.
input=$(cat 2>/dev/null || echo "")
cwd=""
if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
    cwd=$(jq -r '.cwd // ""' <<< "$input" 2>/dev/null | tr -d '\r')
fi

BASE="SESSION ENDING.\n\n1. Summarize completed work (1-3 bullets: what was built, fixed, or reviewed)\n2. Note any uncommitted changes or open branches\n3. Flag any CRITICAL/HIGH security findings that remain unfixed"
TAIL="\n\nDo not ask about saving memory. claude-mem captures automatically at session end."

if [ -n "$cwd" ] && [ -d "$cwd/.agent" ]; then
    BASE="$BASE\n4. Recommend the next steps a new session should take"
    # bash-guard reads an unquoted heredoc body as commands, so a log entry that
    # mentions a push or a secret file name would ask or deny. A quoted heredoc
    # with the date printed outside it is plain text to the guard.
    TAIL="\n\nThis repo has .agent/, so append the four points above to .agent/log.md under a '## YYYY-MM-DD HH:MM' heading. Append, never rewrite the file. Write it in one Bash call: date '+%n## %Y-%m-%d %H:%M' >> .agent/log.md && cat >> .agent/log.md <<'EOF', then the four points, then a line with EOF. Keep 'EOF' quoted and add no \$( or other commands to that call.$TAIL"
fi

jq -n --arg ctx "$(printf "%b" "$BASE$TAIL")" '{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": $ctx
  }
}'
