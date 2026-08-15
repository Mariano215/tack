---
description: Scan a file (or text) for LLM-cliche/slop and rewrite it clean
argument-hint: [file-path]
---
# /ghost — de-slop prose

Target: `$ARGUMENTS`

Goal: remove every em/en-dash, cliche phrase, and slop buzzword while preserving meaning, facts, numbers, citations, and structure. Surgical edits only. Add no new content.

Steps:

1. **Scan.** If `$ARGUMENTS` is a file path, run:
   `python3 ~/.claude/ghost/ghost_scan.py "$ARGUMENTS"`
   If it is pasted text, scan via stdin:
   `printf '%s' "<text>" | python3 ~/.claude/ghost/ghost_scan.py -`
   With no argument, target the file most recently written or discussed in this session and confirm it before editing.

2. **Rewrite each flagged span:**
   - em/en-dash (— – ―) -> comma, period, parentheses, or colon; restructure if needed
   - cliche phrase (delve, furthermore, it's worth noting, testament to, navigate the landscape, ...) -> plain direct wording, or delete
   - buzzword (comprehensive, robust, ensure, leverage, utilize, seamless, ...) -> simpler word, or cut
   - if a term is a genuine domain requirement (FDA/standards), keep it and either add the exact phrase to `allowlist` in `~/.claude/ghost/patterns.json` or append `ghost:allow` on that line

3. **Write back** with Edit/Write. The PreToolUse hook re-checks on save only for `.txt`, `.docx` and `.pdf`, so on a markdown target step 4 is the real gate.

4. **Verify clean:** re-run `python3 ~/.claude/ghost/ghost_scan.py "$ARGUMENTS"` — it must print `ghost: clean`. Do not claim done until it does.

5. **Summarize** the before/after changes in a short list.

Note: client-facing rewrites (proposals, emails, reports) suspend caveman mode per engagement rules — write in normal professional prose.
