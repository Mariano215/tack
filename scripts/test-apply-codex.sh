#!/usr/bin/env bash
# End-to-end Codex profile rendering against a throwaway CODEX_HOME.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t codexapply)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CODEX_HOME="$HOME/.codex"
export HARNESS_NO_PLUGIN_SETUP=1
mkdir -p "$CODEX_HOME"
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

printf '# preserve-me\nmodel_reasoning_effort = "medium"\n' > "$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$TMP/base-before.toml"
printf '# user policy\n' > "$CODEX_HOME/AGENTS.md"
mkdir -p "$CODEX_HOME/skills/user-skill" "$CODEX_HOME/skills/build-with-goal"
printf '%s\n' 'user skill' > "$CODEX_HOME/skills/user-skill/SKILL.md"
printf '%s\n' 'old collision' > "$CODEX_HOME/skills/build-with-goal/SKILL.md"

cat > "$TMP/v2.json" <<'JSON'
{
  "schema_version": 2,
  "name": "dev",
  "mcp": ["context7", "playwright"],
  "memory": {"enabled": true, "engine": "claude-mem"},
  "providers": {
    "codex": {
      "plugins": {"example@market": true},
      "config": {
        "model_reasoning_effort": "high",
        "personality": "pragmatic",
        "tui": {
          "status_line": ["model-with-reasoning"],
          "status_line_use_colors": false
        }
      },
      "permissions": {
        "approval_policy": "on-request",
        "sandbox_mode": "workspace-write"
      }
    }
  }
}
JSON

echo "== 1. v2 renders an isolated Codex profile =="
out="$(bash "$CORE/adapters/codex/apply-profile.sh" "$TMP/v2.json")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "Codex apply exited $rc"; }
PROFILE="$CODEX_HOME/dev.config.toml"
[ -f "$PROFILE" ] || bad "profile config missing"
if python3 - "$PROFILE" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
assert data["model_reasoning_effort"] == "high"
assert data["personality"] == "pragmatic"
assert data["approval_policy"] == "on-request"
assert data["sandbox_mode"] == "workspace-write"
assert data["tui"]["status_line"] == ["model-with-reasoning"]
assert data["tui"]["status_line_use_colors"] is False
assert data["features"]["hooks"] is True
assert data["features"]["memories"] is False
assert data["plugins"]["example@market"]["enabled"] is True
assert data["plugins"]["harness-policy@agent-harness"]["enabled"] is True
assert data["mcp_servers"]["context7"]["command"] == "npx"
assert data["mcp_servers"]["playwright"]["args"] == ["@playwright/mcp@latest"]
PY
then
  ok "v2 config, permissions, plugins, MCP, and memory policy rendered"
else
  bad "rendered TOML has wrong values"
fi
[ "$(cat "$CODEX_HOME/.harness-active")" = "dev" ] \
  && ok "Codex active profile recorded" || bad "Codex active profile missing"
cmp -s "$TMP/base-before.toml" "$CODEX_HOME/config.toml" \
  && ok "user config.toml untouched" || bad "user config.toml changed"
if grep -q '^# user policy$' "$CODEX_HOME/AGENTS.md" \
  && [ "$(grep -c '<!-- >>> codex-harness policy >>> -->' "$CODEX_HOME/AGENTS.md")" = "1" ] \
  && [ "$(grep -c '<!-- <<< codex-harness policy <<< -->' "$CODEX_HOME/AGENTS.md")" = "1" ]; then
  ok "Codex policy merged into existing AGENTS.md"
else
  bad "Codex AGENTS.md merge lost user content or duplicated policy"
fi
[ -f "$CODEX_HOME/skills/user-skill/SKILL.md" ] \
  && ok "user-owned Codex skill preserved" || bad "user-owned Codex skill removed"
[ -f "$CODEX_HOME/skills/build-with-goal/SKILL.md" ] \
  && grep -q 'Build With Goal' "$CODEX_HOME/skills/build-with-goal/SKILL.md" \
  && ok "Codex-native workflow skill installed" || bad "Codex workflow skill missing"
[ -f "$CODEX_HOME/skills/security-audit/SKILL.md" ] \
  && ok "provider-neutral core skill installed" || bad "shared core skill missing"
find "$CODEX_HOME/backups" -path '*/skills/build-with-goal/SKILL.md' -type f | grep -q . \
  && ok "skill collision backed up" || bad "skill collision had no backup"
if bash "$CORE/adapters/codex/verify-setup.sh" dev >/dev/null 2>&1; then
  ok "Codex verifier accepts composed runtime"
else
  bad "Codex verifier rejected composed runtime"
fi

echo "== 2. canonical v2 manifest does not leak Claude plugins =="
out="$(bash "$CORE/adapters/codex/apply-profile.sh" "$CORE/profiles/dev/manifest.json")"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "v1 Codex apply exited $rc"; }
if python3 - "$PROFILE" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
plugins = data.get("plugins", {})
# tack profiles ship memory off, so the canonical profile registers no memory plugin.
assert "claude-mem@claude-mem-local" not in plugins
assert not any("claude-plugins-official" in name for name in plugins)
assert data["tui"]["status_line"] == [
    "model-with-reasoning",
    "current-dir",
    "git-branch",
    "context-remaining",
    "five-hour-limit",
    "weekly-limit",
]
assert data["tui"]["status_line_use_colors"] is True
PY
then
  ok "Claude plugin IDs excluded and native Codex status line rendered"
else
  bad "canonical Codex profile plugins or status line wrong"
fi
if [ "$(grep -c '<!-- >>> codex-harness policy >>> -->' "$CODEX_HOME/AGENTS.md")" = "1" ] \
  && [ "$(grep -c '<!-- <<< codex-harness policy <<< -->' "$CODEX_HOME/AGENTS.md")" = "1" ]; then
  ok "Codex policy sync is idempotent"
else
  bad "Codex policy duplicated on re-apply"
fi

echo "== 3. existing non-harness profile fails closed =="
echo 'model = "user-owned"' > "$CODEX_HOME/dev.config.toml"
if bash "$CORE/adapters/codex/apply-profile.sh" "$TMP/v2.json" >/dev/null 2>&1; then
  bad "non-harness profile was overwritten"
else
  grep -q 'user-owned' "$CODEX_HOME/dev.config.toml" \
    && ok "non-harness profile preserved" || bad "non-harness profile changed"
fi

echo "== 4. unknown shared MCP fails before replacement =="
sed 's/"context7", "playwright"/"unknown-server"/' "$TMP/v2.json" > "$TMP/bad-mcp.json"
before="$(cat "$CODEX_HOME/dev.config.toml")"
if bash "$CORE/adapters/codex/apply-profile.sh" "$TMP/bad-mcp.json" --force >/dev/null 2>&1; then
  bad "unknown MCP was accepted"
else
  [ "$(cat "$CODEX_HOME/dev.config.toml")" = "$before" ] \
    && ok "unknown MCP failed without replacing profile" || bad "failed render replaced profile"
fi

echo "== 5. isolated preflight does not change default profile =="
echo dev > "$CODEX_HOME/.harness-active"
out="$(bash "$CORE/adapters/codex/apply-profile.sh" "$CORE/profiles/minimal/manifest.json" --no-activate)"; rc=$?
[ "$rc" -eq 0 ] || { echo "$out"; bad "--no-activate apply exited $rc"; }
[ "$(cat "$CODEX_HOME/.harness-active")" = "dev" ] \
  && [ -f "$CODEX_HOME/minimal.config.toml" ] \
  && ok "Codex overlay rendered without changing default" \
  || bad "Codex --no-activate changed default or missed overlay"

echo ""
if [ "$fails" -ne 0 ]; then
  echo "test-apply-codex FAILED ($fails)."
  exit 1
fi
echo "test-apply-codex passed."
