#!/usr/bin/env bash
# A Codex-only machine must not silently choose the Anthropic memory provider.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t memoryprovider)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"enabledPlugins":{"claude-mem@thedotmack":true}}
JSON
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# /usr/bin:/bin hides a real claude, but on Git Bash it hides jq and python3 too,
# and the setup exits 0 in silence without jq. Wrap the real ones back in.
TOOLS="$TMP/tools"; mkdir -p "$TOOLS"
for t in jq python3; do printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" > "$TOOLS/$t"; chmod +x "$TOOLS/$t"; done

echo "== 1. no Claude CLI means no implicit Anthropic provider =="
out="$(PATH="$TOOLS:/usr/bin:/bin" bash "$CORE/lib/claude-mem-setup.sh")"; rc=$?
[ "$rc" -eq 0 ] || bad "memory setup failed instead of reporting unavailable"
case "$out" in
  *"no local provider and Claude CLI is absent"*"no Anthropic fallback was selected"*)
    ok "Codex-only setup reports unavailable without Anthropic fallback" ;;
  *) echo "$out"; bad "Codex-only setup did not explain provider refusal" ;;
esac
case "$out" in *"using claude/"*) bad "Codex-only setup selected Claude implicitly" ;; esac
[ ! -f "$HOME/.claude-mem/settings.json" ] \
  && ok "unavailable provider wrote no memory config" || bad "unavailable provider wrote settings"

echo "== 2. existing Claude installs keep legacy fallback =="
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$BIN/claude"
out="$(PATH="$BIN:$TOOLS:/usr/bin:/bin" bash "$CORE/lib/claude-mem-setup.sh")"
case "$out" in
  *"using claude/"*) ok "Claude install retains configured fallback behavior" ;;
  *) echo "$out"; bad "Claude fallback changed unexpectedly" ;;
esac

if [ "$fails" -ne 0 ]; then
  echo "memory provider tests FAILED: $fails"
  exit 1
fi
echo "memory provider tests passed"
