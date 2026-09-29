#!/usr/bin/env bash
# The live CLAUDE.md carries the engine block between markers and the user's
# own text outside them. An apply must refresh the block and never lose the rest.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)/lib/render-claude-md.py"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0; no() { echo "FAIL: $1"; fail=1; }
printf 'engine v1\n' > "$t/tpl"

# 1. first apply over a hand-kept file: block on top, old text kept, backup made
printf '# Mine\nkeep me\n' > "$t/live"
python3 "$R" "$t/tpl" "$t/live" >/dev/null
grep -q 'engine v1' "$t/live" || no "block not written"
grep -q 'keep me' "$t/live" || no "personal text lost on first apply"
[ -f "$t/live.harness-prev" ] || no "no backup on first apply"

# 2. template changes: block replaced in place, personal text kept once
printf 'engine v2\n' > "$t/tpl"
python3 "$R" "$t/tpl" "$t/live" >/dev/null
grep -q 'engine v1' "$t/live" && no "old block survived"
grep -q 'engine v2' "$t/live" || no "new block missing"
[ "$(grep -c 'keep me' "$t/live")" = 1 ] || no "personal text lost or duplicated"
[ "$(grep -c 'harness:begin' "$t/live")" = 1 ] || no "markers duplicated"

# 3. text above the block survives too
printf 'above\n' | cat - "$t/live" > "$t/x" && mv "$t/x" "$t/live"
python3 "$R" "$t/tpl" "$t/live" >/dev/null
head -1 "$t/live" | grep -q above || no "text above the block lost"

# 4. no change means no write and no new backup
rm -f "$t/live.harness-prev"
python3 "$R" "$t/tpl" "$t/live" >/dev/null
[ -f "$t/live.harness-prev" ] && no "rewrote an unchanged file"

# 5. no live file yet
python3 "$R" "$t/tpl" "$t/new" >/dev/null
grep -q 'engine v2' "$t/new" || no "fresh file not created"

# 6. CRLF text outside the block keeps its line endings (Windows checkouts)
printf '# Mine\r\nkeep crlf\r\n' > "$t/crlf"
python3 "$R" "$t/tpl" "$t/crlf" >/dev/null
grep -q "$(printf 'keep crlf\r')" "$t/crlf" || no "CRLF in personal text was rewritten"

[ "$fail" = 0 ] && echo "claude-md render: ok"
exit "$fail"
