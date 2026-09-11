#!/usr/bin/env bash
# Codex claude-mem registration and stale direct-MCP cleanup.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t codexmemory)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
BIN="$TMP/bin"
MARKET="$HOME/.claude/plugins/marketplaces/thedotmack/.agents/plugins"
mkdir -p "$CODEX_HOME" "$BIN" "$MARKET"
echo '{}' > "$MARKET/marketplace.json"
cat > "$CODEX_HOME/config.toml" <<'TOML'
[mcp_servers.claude-mem]
command = "node"
args = ["stale.cjs"]
TOML
cat > "$TMP/view.json" <<'JSON'
{"schema_version":2,"memory":{"enabled":true,"engine":"claude-mem"}}
JSON
export CODEX_MEMORY_LOG="$TMP/codex.log"
cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODEX_MEMORY_LOG"
if [ "${1:-} ${2:-} ${3:-}" = "plugin marketplace add" ]; then
  printf '\n[marketplaces.claude-mem-local]\nsource_type = "local"\nsource = "test"\n' >> "$CODEX_HOME/config.toml"
elif [ "${1:-} ${2:-} ${3:-}" = "plugin add claude-mem@claude-mem-local" ] \
  && [ -z "${CODEX_MEMORY_SKIP_PLUGIN:-}" ]; then
  printf '\n[plugins."claude-mem@claude-mem-local"]\nenabled = true\n' >> "$CODEX_HOME/config.toml"
fi
exit 0
SH
chmod +x "$BIN/codex"
# /usr/bin:/bin hides a real codex, but on Git Bash it hides jq and python3 too.
for t in jq python3; do printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$t")" > "$BIN/$t"; chmod +x "$BIN/$t"; done
export PATH="$BIN:/usr/bin:/bin"
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

out="$(bash "$CORE/adapters/codex/setup-memory.sh" "$TMP/view.json")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Codex memory setup exited $rc"; }
grep -qxF "plugin marketplace add $HOME/.claude/plugins/marketplaces/thedotmack" "$CODEX_MEMORY_LOG" \
  && ok "local claude-mem marketplace registered" || bad "marketplace registration argv wrong"
grep -qxF 'plugin add claude-mem@claude-mem-local' "$CODEX_MEMORY_LOG" \
  && ok "claude-mem Codex plugin installed" || bad "plugin install argv wrong"
grep -qxF 'mcp remove claude-mem' "$CODEX_MEMORY_LOG" \
  && ok "stale direct MCP removal requested" || bad "stale direct MCP not reconciled"
find "$CODEX_HOME" -name 'config.toml.before-claude-mem-mcp.*' -type f | grep -q . \
  && ok "base config backed up before MCP cleanup" || bad "MCP cleanup backup missing"
[ "$(cat "$CODEX_HOME/.harness-memory-status")" = "claude-mem" ] \
  && ok "memory status recorded" || bad "memory status incorrect"

echo "== plugin install failure remains unavailable =="
cat > "$CODEX_HOME/config.toml" <<'TOML'
[marketplaces.claude-mem-local]
source_type = "local"
source = "test"
TOML
out="$(CODEX_MEMORY_SKIP_PLUGIN=1 bash "$CORE/adapters/codex/setup-memory.sh" "$TMP/view.json")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "failed plugin setup exited $rc"; }
[ "$(cat "$CODEX_HOME/.harness-memory-status")" = "unavailable: plugin registration failed" ] \
  && ok "failed plugin install not reported as ready" || bad "failed plugin install reported as ready"

if [ "$fails" -ne 0 ]; then
  echo "Codex memory tests FAILED: $fails"
  exit 1
fi
echo "Codex memory tests passed"
