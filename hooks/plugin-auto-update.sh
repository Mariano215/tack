#!/bin/bash
# Daily self-maintenance: fetch the active profile repo (+ core) and report waiting
# commits, drift-check and heal, update plugins. Never applies new code.
# Runs async from SessionStart. Safe to kill mid-run (no destructive ops).

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Two stamps, because the work below splits in two. Steps 1 and 2 are per
# profile: each config dir needs its own pull and its own heal. Steps 3 onward
# touch the shared plugins tree, so they run once per machine per day. Two
# `claude plugin update` sweeps racing over one 3 GB tree is the thing to avoid.
STAMP="$CLAUDE_DIR/.plugin-update-last-run"
SHARED_STAMP="$HOME/.claude/.plugin-update-shared"
INTERVAL_SECONDS=86400  # 24h

export PATH="$PATH:$HOME/.local/bin"

stale() {  # stale <stampfile> -> 0 if older than the interval or absent
    [ -f "$1" ] || return 0
    local last; last=$(cat "$1" 2>/dev/null || echo 0)
    [ "$(( now - last ))" -ge "$INTERVAL_SECONDS" ]
}

# A marketplace that ships a JS project and has lost node_modules makes its
# session hook pay a cold `bun install` in front of the user. For claude-mem
# that install has a 120s timeout, which is long enough to drop the client's
# in-flight API connection: the session start fails with "API Error: Connection
# error", and `/login` dies before a browser ever opens. Running
# `npx claude-mem repair` by hand is what clears it, so that is what this does.

# True when at least one enabled plugin comes from marketplace $1. Reads the
# declared state out of settings.json rather than spawning `claude plugin list`,
# because this runs ahead of the daily gate on every session start.
marketplace_has_enabled_plugin() {
    f='(.enabledPlugins // {}) | with_entries(select(.value)) | keys | any(endswith($m))'
    jq -e --arg m "@$1" "$f" "$CLAUDE_DIR/settings.json" >/dev/null 2>&1
}

restore_marketplace_deps() {
    for pj in "$HOME"/.claude/plugins/marketplaces/*/package.json; do
        [ -f "$pj" ] || continue
        d=$(dirname "$pj")
        [ -d "$d/node_modules" ] && continue
        # Nothing enabled from this marketplace, so nothing needs its runtime.
        # The check sits after the node_modules stat so the normal case still
        # costs one stat and no jq. Without it, disabling a plugin left this
        # loop still paying its install every session: claude-mem stayed
        # disabled and its npm install kept failing on Windows with ENOTEMPTY,
        # which is a failure nobody could explain from the plugin list.
        marketplace_has_enabled_plugin "$(basename "$d")" || continue
        if [ "$(basename "$d")" = "thedotmack" ] && command -v npx >/dev/null 2>&1; then
            npx -y claude-mem repair >/dev/null 2>&1 && continue
        fi
        (cd "$d" && { command -v bun >/dev/null 2>&1 && bun install --silent || npm install --silent; }) >/dev/null 2>&1 || true
    done
}

now=$(date +%s)

# Ahead of the daily gate on purpose, and the only part of this hook that runs
# every session. Step 4 below re-extracts every marketplace clone WITHOUT its
# install step, which is what deletes node_modules; step 4b puts it back. But
# both stamps are written before their work runs, so a sweep that is killed
# mid-run (this hook is async and explicitly safe to kill) leaves the machine
# broken and gated shut for a full 24h. That window is where "I have to run
# repair again" and the login failures come from. The guard below is a stat per
# marketplace when nothing is wrong, so it is cheap enough to pay every time.
# One run per machine at a time. Sessions that start together (tack tmux panes,
# a tmux restore after reboot) each saw a stale stamp and raced npm installs and
# plugin sweeps over the same tree. mkdir is atomic; a lock older than 30 min is
# from a killed run and is cleared.
LOCK="$HOME/.claude/.plugin-update.lock"  # harness:shared, one plugins tree per machine
find "$LOCK" -maxdepth 0 -mmin +30 -exec rmdir {} \; 2>/dev/null
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

restore_marketplace_deps

stale "$STAMP" || exit 0
echo "$now" > "$STAMP"

# Resolve the active profile the same way tack does. .harness-root is machine
# state and stays on ~/.claude; .harness-active is per config dir, and reading
# the shared one from an isolated session would re-apply the wrong profile here.
HARNESS_ROOT=$(cat "$HOME/.claude/.harness-root" 2>/dev/null || echo "$HOME/Projects")
ACTIVE=$(cat "$CLAUDE_DIR/.harness-active" 2>/dev/null)
PROFILE_DIR="$HARNESS_ROOT/tack-$ACTIVE"

reapply() { command -v tack >/dev/null 2>&1 && tack use "$ACTIVE" >/dev/null 2>&1 || true; }

# 1. Report, never apply. Pulling and re-applying here ran whatever was last
#    pushed on every machine with no human step, so one bad push or leaked
#    token reached them all within a day. Fetch, count what is waiting, and
#    leave the apply to `tack sync`. The statusline shows the marker.
PENDING="$CLAUDE_DIR/.harness-update-pending"
if [ -n "$ACTIVE" ] && [ -d "$PROFILE_DIR/.git" ]; then
    ssh_cmd="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
    waiting=""
    if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd" git -C "$PROFILE_DIR" fetch -q </dev/null >/dev/null 2>&1; then
        waiting=$(git -C "$PROFILE_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null | tr -d '\r')
        if [ -d "$PROFILE_DIR/core/.git" ] || [ -f "$PROFILE_DIR/core/.git" ]; then
            if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd" git -C "$PROFILE_DIR/core" fetch -q origin main </dev/null >/dev/null 2>&1; then
                c=$(git -C "$PROFILE_DIR/core" rev-list --count HEAD..FETCH_HEAD 2>/dev/null | tr -d '\r')
                waiting=$(( ${waiting:-0} + ${c:-0} ))
            fi
        fi
    fi
    # A failed fetch leaves waiting empty and the marker as it was.
    if [ -n "$waiting" ]; then
        if [ "$waiting" -gt 0 ] 2>/dev/null; then echo "$waiting" > "$PENDING"; else rm -f "$PENDING"; fi
    fi
fi

# 2. Drift check: if verify fails, heal by re-applying the profile
if [ -n "$ACTIVE" ] && [ -x "$CLAUDE_DIR/verify-setup.sh" ]; then
    if ! bash "$CLAUDE_DIR/verify-setup.sh" >/dev/null 2>&1; then
        reapply
    fi
fi

# Everything below here operates on machine-global state: one plugins tree, one
# pip environment. Gate it on the shared stamp so a second profile's session on
# the same day does not run a duplicate sweep over the same files.
stale "$SHARED_STAMP" || exit 0
echo "$now" > "$SHARED_STAMP"

# 3. Update marketplace indices
claude plugin marketplace update >/dev/null 2>&1 || true

# 4. Update all enabled plugins. Read the machine-readable list, not the human
#    one: the old pipeline matched a multibyte prompt glyph inside a bracket
#    expression, so under a non-UTF-8 locale it emitted that glyph as the plugin
#    name and every update became a no-op. Third-party plugins then never moved
#    (claude-mem sat on 13.7.0 for two months while npx claude-mem repair kept
#    installing 13.15.2 into a cache dir Claude Code did not load), and the
#    official ones only looked current because the marketplace refresh restamps
#    them.
claude plugin list --json 2>/dev/null \
    | jq -r '.[] | select(.enabled) | .id' 2>/dev/null \
    | tr -d '\r' \
    | while read -r plugin; do
        [ -n "$plugin" ] || continue
        claude plugin update "$plugin" >/dev/null 2>&1 || true
    done

# 4b. Marketplace runtimes. The updates above re-extract each marketplace clone
# without running its install step, so any plugin shipping as a JS project loses
# node_modules and pays a cold install inside a session hook later. Restore deps
# now, in async background time, rather than in front of the user's next prompt.
restore_marketplace_deps

