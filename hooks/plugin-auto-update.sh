#!/bin/bash
# Daily self-maintenance: pull the active profile repo (+ core submodule), re-apply
# on change, drift-check and heal, update plugins + graphifyy.
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

now=$(date +%s)
stale "$STAMP" || exit 0
echo "$now" > "$STAMP"

# Resolve the active profile the same way tack does. .harness-root is machine
# state and stays on ~/.claude; .harness-active is per config dir, and reading
# the shared one from an isolated session would re-apply the wrong profile here.
HARNESS_ROOT=$(cat "$HOME/.claude/.harness-root" 2>/dev/null || echo "$HOME/Projects")
ACTIVE=$(cat "$CLAUDE_DIR/.harness-active" 2>/dev/null)
PROFILE_DIR="$HARNESS_ROOT/tack-$ACTIVE"

reapply() { command -v tack >/dev/null 2>&1 && tack use "$ACTIVE" >/dev/null 2>&1 || true; }

# 1. Pull the active profile repo and its core submodule; re-apply if anything
#    landed. Compare commits rather than grepping git's English stdout for
#    "Updating|Fast-forward|Submodule path": under any other locale, or after a
#    wording change upstream, that grep matches nothing and the only closed loop
#    in the harness stops re-applying. tack sync already uses rev-parse this way.
if [ -n "$ACTIVE" ] && [ -d "$PROFILE_DIR/.git" ]; then
    before_repo=$(git -C "$PROFILE_DIR" rev-parse HEAD 2>/dev/null)
    before_core=$(git -C "$PROFILE_DIR/core" rev-parse HEAD 2>/dev/null)
    git -C "$PROFILE_DIR" pull --ff-only >/dev/null 2>&1
    git -C "$PROFILE_DIR" submodule update --init --remote >/dev/null 2>&1
    after_repo=$(git -C "$PROFILE_DIR" rev-parse HEAD 2>/dev/null)
    after_core=$(git -C "$PROFILE_DIR/core" rev-parse HEAD 2>/dev/null)
    if [ "$before_repo" != "$after_repo" ] || [ "$before_core" != "$after_core" ]; then
        reapply
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

# 4. Update all enabled plugins
claude plugin list 2>/dev/null \
    | grep -E "^  [❯>]|Status" \
    | paste - - \
    | grep "enabled" \
    | sed 's/  [❯>] //' \
    | awk '{print $1}' \
    | while read -r plugin; do
        claude plugin update "$plugin" >/dev/null 2>&1 || true
    done

# 4b. Marketplace runtimes. The updates above re-extract each marketplace clone
# without running its install step, so any plugin shipping as a JS project loses
# node_modules and pays a cold install inside a session hook later. Restore deps
# now, in async background time, rather than in front of the user's next prompt.
for pj in "$HOME"/.claude/plugins/marketplaces/*/package.json; do
    [ -f "$pj" ] || continue
    d=$(dirname "$pj")
    [ -d "$d/node_modules" ] && continue
    (cd "$d" && { command -v bun >/dev/null 2>&1 && bun install --silent || npm install --silent; }) >/dev/null 2>&1 || true
done

# 5. Update graphifyy
pip install --upgrade graphifyy -q >/dev/null 2>&1 && graphify install >/dev/null 2>&1 || true
