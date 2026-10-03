#!/usr/bin/env bash
# Status line. Reads Claude Code's session JSON on stdin, prints one or two lines.
# Layout: full (default) or compact. Compact when TACK_STATUSLINE=compact, when
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.statusline-mode says "compact", or when
# COLUMNS is set and under 100. TACK_STATUSLINE=full beats the COLUMNS fallback.
# NO_COLOR turns the colors off.
input=$(cat)

cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# One jq call for every field. Fields are joined by the unit separator, which
# is not whitespace, so read keeps empty fields. tr strips the CR that jq emits
# on Git Bash. Times are computed here with jq's now, so no date fork.
sep=$'\x1f'
IFS="$sep" read -r model cwd session_name used output_style vim_mode effort \
  worktree_branch git_worktree five_h seven_d five_h_reset seven_d_reset \
  session_id cost dur_ms cache_seen cache_warm cache_left cache_pct miss_cause miss_age <<EOF
$(echo "$input" | jq -r '
  (.prompt_cache // {}) as $c
  | [ (.model.display_name // "Claude"),
      (.workspace.current_dir // .cwd // ""),
      (.session_name // ""),
      (.context_window.used_percentage // ""),
      (.output_style.name // ""),
      (.vim.mode // ""),
      (.effort.level // ""),
      (.worktree.branch // ""),
      (.workspace.git_worktree // ""),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.resets_at // ""),
      (.session_id // ""),
      (.cost.total_cost_usd // ""),
      (.cost.total_duration_ms // ""),
      (if $c.caching_observed == true then "1" else "" end),
      (if $c.warm == true then "1" else "" end),
      (if $c.expires_at then (($c.expires_at - now) | floor) else "" end),
      (if $c.hit_ratio != null then (($c.hit_ratio * 100) | round) else "" end),
      ($c.last_miss_cause.causes[0] // ""),
      (if $c.last_miss_at then ((now - $c.last_miss_at) | floor) else "" end)
    ] | map(tostring) | join("\u001f")' 2>/dev/null | tr -d '\r')
EOF

# Colors. Empty when NO_COLOR is set.
if [ -n "${NO_COLOR:-}" ]; then
  c_g=""; c_y=""; c_r=""; c_0=""
else
  c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_0=$'\033[0m'
fi

# Sets C to green below 60, yellow below 85, red above.
pick_color() {
  if [ "$1" -ge 85 ]; then C="$c_r"; elif [ "$1" -ge 60 ]; then C="$c_y"; else C="$c_g"; fi
}

# Layout
mode="full"
if [ "${TACK_STATUSLINE:-}" = "compact" ]; then
  mode="compact"
elif [ "${TACK_STATUSLINE:-}" != "full" ]; then
  file_mode=""
  [ -r "$cfg/.statusline-mode" ] && read -r file_mode < "$cfg/.statusline-mode"
  file_mode="${file_mode%$'\r'}"
  if [ "$file_mode" = "compact" ]; then
    mode="compact"
  elif [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -lt 100 ] 2>/dev/null; then
    mode="compact"
  fi
fi

# Shorten cwd: replace $HOME with ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Active harness profile. With `tack shell` two terminals run two profiles at
# once, and this is the only thing on screen that tells them apart.
harness_profile=$(cat "$cfg/.harness-active" 2>/dev/null)

# Git branch (skip locks, silent on failure)
branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
[ -z "$branch" ] && [ -n "$worktree_branch" ] && branch="$worktree_branch"

# Context window progress bar (10 blocks wide)
build_bar() {
  local pct="${1:-0}"
  local filled=$(( (pct * 10 + 50) / 100 ))
  [ "$filled" -gt 10 ] && filled=10
  local empty=$(( 10 - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty; i++ )); do bar="${bar}░"; done
  printf "[%s]" "$bar"
}

# Context history: the last 12 context percentages for this session, one per
# line, appended only when the value changes. This is the only state the line
# keeps. Files older than 2 days are removed whenever a new sample lands.
spark=""
used_int=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  sid="${session_id//[^A-Za-z0-9_-]/}"
  if [ -n "$sid" ]; then
    hist_dir="$cfg/.statusline"
    hist="$hist_dir/$sid"
    last=""
    [ -f "$hist" ] && last=$(tail -n 1 "$hist" 2>/dev/null | tr -d '\r')
    if [ "$last" != "$used_int" ]; then
      mkdir -p "$hist_dir" 2>/dev/null
      printf '%s\n' "$used_int" >> "$hist" 2>/dev/null
      tail -n 12 "$hist" > "$hist.tmp" 2>/dev/null && mv "$hist.tmp" "$hist" 2>/dev/null
      find "$hist_dir" -type f -mtime +2 -delete 2>/dev/null
    fi
    if [ -f "$hist" ]; then
      glyphs=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
      n=0
      while IFS= read -r v; do
        v="${v%$'\r'}"
        case "$v" in ''|*[!0-9]*) continue ;; esac
        [ "$v" -gt 100 ] && v=100
        spark="${spark}${glyphs[$(( v * 7 / 100 ))]}"
        n=$(( n + 1 ))
      done < "$hist"
      [ "$n" -lt 2 ] && spark=""
    fi
  fi
fi

# resets_at is epoch seconds. BSD date wants -r, GNU date wants -d @, and on
# Linux -r means "read a file's mtime", so it failed silently: containers showed
# the usage percentages with no reset time. Try both, print nothing if neither
# parses (an ISO timestamp would land here).
fmt_epoch() {
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}

# Cache segment: hit ratio and time left before the cached prefix goes cold.
# Cold turns red and names the cause when a miss landed in the last 5 minutes.
cache_seg=""
if [ -n "$cache_seen" ]; then
  if [ -n "$cache_warm" ] && [ -n "$cache_left" ] && [ "$cache_left" -gt 0 ] 2>/dev/null; then
    if [ "$cache_left" -ge 60 ]; then
      left_txt="$(( cache_left / 60 ))m"; C="$c_g"
    else
      left_txt="${cache_left}s"; C="$c_y"
    fi
    cache_seg="cache "
    [ -n "$cache_pct" ] && cache_seg="${cache_seg}${cache_pct}% "
    cache_seg="${C}${cache_seg}${left_txt}${c_0}"
  else
    cache_seg="${c_r}cache cold${c_0}"
    if [ -n "$miss_cause" ] && [ -n "$miss_age" ] && [ "$miss_age" -le 300 ] 2>/dev/null; then
      cache_seg="${c_r}cache cold(${miss_cause})${c_0}"
    fi
  fi
fi

# Cost and session time
cost_seg=""
if [ -n "$cost" ]; then
  cost_seg="$(printf '$%.2f' "$cost")"
  if [ -n "$dur_ms" ]; then
    mins=$(( ${dur_ms%.*} / 60000 ))
    if [ "$mins" -ge 60 ]; then
      cost_seg="${cost_seg} $(( mins / 60 ))h$(printf '%02d' $(( mins % 60 )))m"
    else
      cost_seg="${cost_seg} ${mins}m"
    fi
  fi
fi

# Colored percentage, e.g. "5h:23%". Sets PCT_TXT.
pct_txt() {
  local label="$1" val
  val=$(printf '%.0f' "$2")
  pick_color "$val"
  PCT_TXT="${C}${label}${val}%${c_0}"
}

# ── Compact: one line ───────────────────────────────────────────────
if [ "$mode" = "compact" ]; then
  out="$model"
  if [ -n "$used_int" ]; then
    pct_txt "" "$used_int"
    out="${out} ${spark:+$spark }${PCT_TXT}"
  fi
  if [ -n "$five_h" ]; then
    pct_txt "5h " "$five_h"
    out="${out} | ${PCT_TXT}"
  fi
  [ -n "$cache_seg" ] && out="${out} | ${cache_seg}"
  printf "%s" "$out"
  exit 0
fi

# ── Line 1: location / mode ─────────────────────────────────────────
line1=""

if [ -n "$session_name" ]; then
  line1="[${session_name}]"
fi

if [ -n "$harness_profile" ]; then
  [ -n "$line1" ] && line1="${line1} | ${harness_profile}" || line1="${harness_profile}"
fi

[ -n "$line1" ] && line1="${line1} | ${short_cwd}" || line1="${short_cwd}"

if [ -n "$branch" ]; then
  if [ -n "$git_worktree" ]; then
    line1="${line1} | ${branch}(wt)"
  else
    line1="${line1} | ${branch}"
  fi
fi

if [ -n "$output_style" ] && [ "$output_style" != "default" ]; then
  line1="${line1} | style:${output_style}"
fi

if [ -n "$vim_mode" ]; then
  line1="${line1} | ${vim_mode}"
fi

# ── Line 2: model / effort / context bar + usage limits ─────────────
line2="${model}"

if [ -n "$effort" ] && [ "$effort" != "max" ]; then
  line2="${line2} | ${effort}"
fi

if [ -n "$used_int" ]; then
  bar=$(build_bar "$used_int")
  pct_txt "ctx:" "$used_int"
  line2="${line2} | ${bar}${spark:+ $spark} ${PCT_TXT}"
fi

if [ -n "$five_h" ]; then
  pct_txt "5h:" "$five_h"
  line2="${line2} | ${PCT_TXT}"
  if [ -n "$five_h_reset" ]; then
    t="$(fmt_epoch "$five_h_reset" "%H:%M")"
    [ -n "$t" ] && line2="${line2}(resets ${t})"
  fi
fi

if [ -n "$seven_d" ]; then
  pct_txt "7d:" "$seven_d"
  line2="${line2} | ${PCT_TXT}"
  if [ -n "$seven_d_reset" ]; then
    t="$(fmt_epoch "$seven_d_reset" "%a %H:%M")"
    [ -n "$t" ] && line2="${line2}(resets ${t})"
  fi
fi

[ -n "$cache_seg" ] && line2="${line2} | ${cache_seg}"
[ -n "$cost_seg" ] && line2="${line2} | ${cost_seg}"

# ── Output ──────────────────────────────────────────────────────────
printf "%s\n%s" "$line1" "$line2"
