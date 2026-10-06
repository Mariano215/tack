#!/usr/bin/env bash
# statusline-command.sh: feed fixture JSON, assert the segments, both layouts,
# CRLF safety and a missing prompt_cache. Runs against a throwaway HOME.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/cfg" NO_COLOR=1
mkdir -p "$HOME/.claude" "$CLAUDE_CONFIG_DIR"
unset TACK_STATUSLINE COLUMNS

fail=0
run() { ${BASH_UNDER_TEST:-bash} "$here/statusline-command.sh"; }
check() { # name, haystack, needle
  case "$2" in *"$3"*) ;; *) echo "FAIL $1: wanted [$3] in [$2]"; fail=1 ;; esac
}
absent() { # name, haystack, needle
  case "$2" in *"$3"*) echo "FAIL $1: did not want [$3] in [$2]"; fail=1 ;; esac
}

now=$(date +%s)
json() { # session id, context pct, cache block
  printf '{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"%s"},"session_id":"%s","context_window":{"used_percentage":%s},"cost":{"total_cost_usd":1.234,"total_duration_ms":2820000},"rate_limits":{"five_hour":{"used_percentage":23.4}}%s}' \
    "$tmp" "$1" "$2" "$3"
}
warm="$(printf ',"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":%s,"hit_ratio":0.91}' $((now + 1500)))"
soon="$(printf ',"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":%s,"hit_ratio":0.5}' $((now + 40)))"
cold="$(printf ',"prompt_cache":{"warm":false,"caching_observed":true,"hit_ratio":0.4,"last_miss_at":%s,"last_miss_cause":{"causes":["tools_changed"]}}' $((now - 30)))"

# full layout, warm cache
out="$(json s1 30 "$warm" | run)"
check full-ctx "$out" "ctx:30%"
check full-5h "$out" "5h:23%"
check full-cache "$out" "cache 91% 24m"
check full-cost "$out" "\$1.23 47m"
check full-lines "$out" "Opus 5.5"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "3" ] || { echo "FAIL full-rows: want 3 rows in [$out]"; fail=1; }
widest=$(printf '%s\n' "$out" | tail -n 2 | awk '{ if (length($0) > m) m = length($0) } END { print m }')
[ "$widest" -le 80 ] || { echo "FAIL full-width: rows 2 and 3 are $widest wide, want 80 or less"; fail=1; }

# row 1 stays within 110 characters, long path or not
long="/very/long/project/path/$(printf 'x%.0s' $(seq 1 60))/deep/leaf"
out="$(printf '{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"%s"},"session_name":"a-long-session-name"}' "$long" | run)"
row1="$(printf '%s\n' "$out" | head -n 1)"
[ "${#row1}" -le 110 ] || { echo "FAIL row1-cap: ${#row1} chars"; fail=1; }
check row1-tail "$row1" "deep/leaf"

# sparkline needs two samples, and a repeat value adds none
out="$(json s1 30 "$warm" | run)"
absent spark-repeat "$out" "▁"
json s1 80 "$warm" | run >/dev/null
out="$(json s1 80 "$warm" | run)"
check spark-two "$out" "▃▆"
[ "$(wc -l < "$CLAUDE_CONFIG_DIR/.statusline/s1" | tr -d ' ')" = "2" ] || { echo "FAIL spark-file: want 2 samples"; fail=1; }

# under 60 s left counts in seconds, cold names its cause
out="$(json s2 10 "$soon" | run)"
case "$out" in *"cache 50% "[0-9]*"s"*) ;; *) echo "FAIL cache-secs: wanted seconds in [$out]"; fail=1 ;; esac
check cache-cold "$(json s3 10 "$cold" | run)" "cache cold(tools_changed)"

# no prompt_cache: no cache segment, no crash
out="$(json s4 10 "" | run)"
check no-cache-ctx "$out" "ctx:10%"
absent no-cache "$out" "cache"

# compact: one line
out="$(json s5 42 "$warm" | TACK_STATUSLINE=compact run)"
check compact-cache "$out" "cache 91% 24m"
check compact-5h "$out" "5h 23%"
case "$out" in *$'\n'*) echo "FAIL compact: more than one line"; fail=1 ;; esac

# compact by mode file, by narrow COLUMNS, and full forced over COLUMNS
printf 'compact\n' > "$CLAUDE_CONFIG_DIR/.statusline-mode"
case "$(json s6 10 "" | run)" in *$'\n'*) echo "FAIL mode-file: not compact"; fail=1 ;; esac
rm "$CLAUDE_CONFIG_DIR/.statusline-mode"
case "$(json s6 10 "" | COLUMNS=80 run)" in *$'\n'*) echo "FAIL columns: not compact"; fail=1 ;; esac
case "$(json s6 10 "" | COLUMNS=80 TACK_STATUSLINE=full run)" in *$'\n'*) ;; *) echo "FAIL full-forced: one line"; fail=1 ;; esac

# colors: on without NO_COLOR, red when cold
out="$(json s7 90 "$cold" | NO_COLOR='' run)"
check color-red "$out" $'\033[31m'

# CRLF: a CR in a JSON string must not leak into the output
out="$(printf '{"model":{"display_name":"Opus\\r"},"workspace":{"current_dir":"/x"}}' | run)"
case "$out" in *$'\r'*) echo "FAIL crlf: CR in output"; fail=1 ;; esac

# empty input must not crash
printf '' | run >/dev/null 2>&1 || { echo "FAIL empty-input: nonzero exit"; fail=1; }

[ "$fail" = 0 ] && echo "statusline: all cases pass"
exit "$fail"
