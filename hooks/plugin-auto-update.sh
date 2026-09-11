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

# 5. Update graphifyy (uv-managed tool install; pip only if uv is unavailable)
if command -v uv >/dev/null 2>&1; then
    # [gemini] extra pulls in openai (Gemini's OpenAI-compat client); a plain
    # upgrade drops it silently and semantic extraction fails at runtime.
    uv tool install --upgrade "graphifyy[gemini]" -q >/dev/null 2>&1
else
    pip install --upgrade graphifyy -q >/dev/null 2>&1
fi
graphify install >/dev/null 2>&1 || true
