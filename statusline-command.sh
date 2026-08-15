#!/usr/bin/env bash
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')
session_name=$(echo "$input" | jq -r '.session_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
version=$(echo "$input" | jq -r '.version // empty')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
worktree_branch=$(echo "$input" | jq -r '.worktree.branch // empty')
git_worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

# Usage limits (Claude Max subscription — 5h session window, 7d weekly window)
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Shorten cwd: replace $HOME with ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Active harness profile. With `tack shell` two terminals run two profiles at
# once, and this is the only thing on screen that tells them apart.
harness_profile=$(cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.harness-active" 2>/dev/null)

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

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  bar=$(build_bar "$used_int")
  line2="${line2} | ${bar} ctx:${used_int}%"
fi

# resets_at is epoch seconds. BSD date wants -r, GNU date wants -d @, and on
# Linux -r means "read a file's mtime", so it failed silently: containers showed
# the usage percentages with no reset time. Try both, print nothing if neither
# parses (an ISO timestamp would land here).
fmt_epoch() {
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}

if [ -n "$five_h" ]; then
  line2="${line2} | 5h:$(printf '%.0f' "$five_h")%"
  if [ -n "$five_h_reset" ]; then
    t="$(fmt_epoch "$five_h_reset" "%H:%M")"
    [ -n "$t" ] && line2="${line2}(resets ${t})"
  fi
fi

if [ -n "$seven_d" ]; then
  line2="${line2} | 7d:$(printf '%.0f' "$seven_d")%"
  if [ -n "$seven_d_reset" ]; then
    t="$(fmt_epoch "$seven_d_reset" "%a %H:%M")"
    [ -n "$t" ] && line2="${line2}(resets ${t})"
  fi
fi

# ── Output ──────────────────────────────────────────────────────────
if [ -n "$line2" ]; then
  printf "%s\n%s" "$line1" "$line2"
else
  printf "%s" "$line1"
fi
