#!/usr/bin/env bash
# Codex harness-policy marketplace registration and hook behavior.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$CORE/codex-marketplace/plugins/harness-policy"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t codexplugin)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
BIN="$TMP/bin"
mkdir -p "$CODEX_HOME" "$BIN"
export CODEX_PLUGIN_LOG="$TMP/codex.log"

cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODEX_PLUGIN_LOG"
if [ "${1:-} ${2:-} ${3:-}" = "plugin marketplace add" ]; then
  printf '\n[marketplaces.agent-harness]\nsource_type = "local"\nsource = "test"\n' >> "$CODEX_HOME/config.toml"
elif [ "${1:-} ${2:-} ${3:-}" = "plugin add harness-policy@agent-harness" ]; then
  printf '\n[plugins."harness-policy@agent-harness"]\nenabled = true\n' >> "$CODEX_HOME/config.toml"
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

echo "== 1. local policy plugin registers through Codex CLI =="
out="$(bash "$CORE/adapters/codex/setup-plugin.sh")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "plugin setup exited $rc"; }
grep -qxF "plugin marketplace add $CORE/codex-marketplace" "$CODEX_PLUGIN_LOG" \
  && ok "repo marketplace registered" || bad "marketplace registration argv wrong"
grep -qxF 'plugin add harness-policy@agent-harness' "$CODEX_PLUGIN_LOG" \
  && ok "policy plugin installed" || bad "plugin install argv wrong"
grep -q '^registered:' "$CODEX_HOME/.harness-plugin-status" \
  && ok "manual hook trust recorded" || bad "plugin status incorrect"

echo "== 2. edits mark Graphify output stale =="
mkdir -p "$TMP/repo/graphify-out"
echo '{}' > "$TMP/repo/graphify-out/graph.json"
graph_out="$(printf '%s' "{\"cwd\":\"$TMP/repo\"}" | bash "$PLUGIN/scripts/graph-stale.sh")"
[ -f "$TMP/repo/graphify-out/.needs_update" ] \
  && printf '%s' "$graph_out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null \
  && ok "Graphify stale marker and context emitted" || bad "Graphify stale hook failed"

echo "== 3. sensitive edits inject security context =="
security_out="$(printf '%s' '{"tool_input":{"file_path":"src/auth/session.ts"}}' | bash "$PLUGIN/scripts/security-file-nudge.sh")"
printf '%s' "$security_out" | jq -e '.hookSpecificOutput.additionalContext | contains("SECURITY-SENSITIVE CHANGE")' >/dev/null \
  && ok "security nudge emitted" || bad "security nudge missing"
safe_out="$(printf '%s' '{"tool_input":{"file_path":"src/colors.ts"}}' | bash "$PLUGIN/scripts/security-file-nudge.sh")"
[ -z "$safe_out" ] && ok "ordinary edit stays quiet" || bad "ordinary edit triggered security nudge"

echo "== 4. malformed hook input fails open =="
malformed="$(printf '%s' 'not-json' | bash "$PLUGIN/scripts/security-file-nudge.sh")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$malformed" ] \
  && ok "malformed input allowed" || bad "malformed input blocked tool execution"

if [ "$fails" -ne 0 ]; then
  echo "Codex plugin tests FAILED: $fails"
  exit 1
fi
echo "Codex plugin tests passed"
