#!/usr/bin/env bash
# tack tmux: every run gets its own session, and --login picks a separate config dir.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t hxtmux)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export HARNESS_PROFILE_HOME="$HOME/.claude-profiles"
export TMUX_LOG="$TMP/tmux.log" TMUX_STATE="$TMP/state"
BIN="$TMP/bin"
mkdir -p "$HOME/.claude" "$TMP/profiles/tack-audit" "$BIN" "$TMUX_STATE"
printf '%s\n' "$TMP/profiles" > "$HOME/.claude/.harness-root"

# Fake tmux: has-session checks state by exact name, new-session logs its args.
cat > "$BIN/tmux" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$TMUX_STATE/${3#=}" ] ;;
  new-session) printf '%s|%s\n' "$3" "$4" >> "$TMUX_LOG"; : > "$TMUX_STATE/$3" ;;
esac
FAKE
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1: got '$2', want '$3'"; fail=1; fi; }

for _ in 1 2 3; do bash "$CORE/bin/tack" tmux audit; done
bash "$CORE/bin/tack" tmux audit --login work
check "three runs give three sessions" "$(cut -d'|' -f1 "$TMUX_LOG" | head -3 | tr '\n' ' ')" "audit audit-2 audit-3 "
check "login session and command" "$(sed -n 4p "$TMUX_LOG")" "audit-work|tack shell audit --login work"

bash "$CORE/bin/tack" tmux audit --login 'a;b' 2>/dev/null; check "bad tag refused" "$?" "2"
bash "$CORE/bin/tack" tmux audit extra 2>/dev/null; check "stray arg refused" "$?" "2"
exit "$fail"
