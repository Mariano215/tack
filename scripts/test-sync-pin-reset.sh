#!/usr/bin/env bash
# tack sync must heal a profile whose only local commits are core pin bumps that
# another machine also pushed (identical content, different hashes), and must
# still stop on divergence that carries real work. Runs against throwaway bare
# repos under a temp HOME, so nothing touches ~/.claude or GitHub.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude"
echo "$T/root" > "$HOME/.claude/.harness-root"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
q() { "$@" >/dev/null 2>&1; }
# Local file:// submodules need protocol.file.allow=always (git blocks it by
# default). Global, not per-call -c, so it also covers the internal clone
# git spawns for each submodule during clone --recurse-submodules.
q git config --global protocol.file.allow always

# A fake core with two commits, so a pin can move.
q git init -q -b main "$T/core"; q git -C "$T/core" commit -q --allow-empty -m one
q git -C "$T/core" commit -q --allow-empty -m two
# A profile whose remote holds bump B, while this clone holds bump B' (same pin).
# -b main: a bare repo's HEAD symref defaults to init.defaultBranch, which is
# "main" on a box that has set that config and "master" on a stock install
# (CI runners). Push targets "main" below; an unpinned HEAD pointing at a
# nonexistent "master" makes clone --recurse-submodules skip the checkout
# entirely, silently leaving core/ unpopulated.
q git init -q -b main --bare "$T/origin.git"
q git init -q -b main "$T/seed"
( cd "$T/seed"; echo x > README; git add README; git submodule add -q "$T/core" core
  git -C core checkout -q HEAD~1; git add core; git commit -qm base; git push -q "$T/origin.git" main )
mkdir -p "$T/root"
q git clone -q --recurse-submodules "$T/origin.git" "$T/root/tack-p"
# Remote side: a pushed bump to core@two.
( cd "$T/seed"; git -C core checkout -q main; git add core; git commit -qm "bump remote"; git push -q "$T/origin.git" main )
# Local side: the same bump, never pushed. Different hash, identical tree.
( cd "$T/root/tack-p"; git submodule update --init -q
  git -C core checkout -q main; git add core; git commit -qm "bump local" )

out="$(cd "$T"; bash "$HERE/bin/tack" sync 2>&1)" || true
echo "$out" | grep -q "reset onto upstream" || { echo "FAIL: pin-only divergence not healed"; echo "$out"; exit 1; }
[ "$(git -C "$T/root/tack-p" rev-list --count '@{u}..HEAD')" = 0 ] \
  || { echo "FAIL: local commits still ahead of upstream"; exit 1; }
git -C "$T/root/tack-p" branch --list 'pre-reset-*' | grep -q . \
  || { echo "FAIL: no undo branch"; exit 1; }
echo "ok: pin-only divergence reset onto upstream"

# Real work on the local side must NOT be reset.
( cd "$T/root/tack-p"; echo y > work; git add work; git commit -qm work )
( cd "$T/seed"; echo z >> README; git add README; git commit -qm more; git push -q "$T/origin.git" main )
out="$(cd "$T"; bash "$HERE/bin/tack" sync 2>&1)" || true
echo "$out" | grep -q "not a fast-forward, skipped" || { echo "FAIL: real divergence was not stopped"; echo "$out"; exit 1; }
[ -f "$T/root/tack-p/work" ] || { echo "FAIL: local work was discarded"; exit 1; }
echo "ok: divergence carrying work is left alone"
