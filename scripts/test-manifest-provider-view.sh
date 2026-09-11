#!/usr/bin/env bash
# Provider-view contract: v1 stays unchanged; v2 exposes one provider's
# runtime-specific config while retaining shared profile intent.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t manifestview)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

cat > "$TMP/v1.json" <<'JSON'
{
  "name": "dev",
  "caveman": "off",
  "plugins": {"claude-plugin@example": true},
  "env": {"SHARED": "v1"},
  "permissions": {"defaultMode": "plan"},
  "mcp": ["atlassian"],
  "skills_link": {"example": "~/.agents/skills/example"}
}
JSON

cat > "$TMP/v2.json" <<'JSON'
{
  "schema_version": 2,
  "name": "dev",
  "caveman": "off",
  "mcp": ["atlassian"],
  "skills_link": {"example": "~/.agents/skills/example"},
  "memory": {"enabled": true, "engine": "claude-mem"},
  "providers": {
    "claude": {
      "plugins": {"claude-plugin@example": true},
      "env": {"SHARED": "claude"},
      "permissions": {"defaultMode": "plan"}
    },
    "codex": {
      "plugins": {"codex-plugin": true},
      "config": {"model_reasoning_effort": "high"},
      "permissions": {"approval_policy": "on-request"}
    }
  }
}
JSON

v1="$TMP/v1-view.json"
if bash "$CORE/lib/manifest-provider-view.sh" "$TMP/v1.json" claude > "$v1"; then
  if jq -e '.schema_version == null
    and .plugins["claude-plugin@example"] == true
    and .env.SHARED == "v1"
    and .permissions.defaultMode == "plan"' "$v1" >/dev/null; then
    ok "v1 manifest keeps legacy provider keys"
  else
    bad "v1 manifest changed during normalization"
  fi
else
  bad "v1 manifest normalization failed"
fi

v1_codex="$TMP/v1-codex-view.json"
if bash "$CORE/lib/manifest-provider-view.sh" "$TMP/v1.json" codex > "$v1_codex"; then
  if jq -e '.mcp == ["atlassian"]
    and .skills_link.example == "~/.agents/skills/example"
    and .plugins == {}
    and .env == {}
    and .permissions == {}
    and .config == {}' "$v1_codex" >/dev/null; then
    ok "v1 Codex view keeps shared intent without Claude config"
  else
    bad "v1 Codex view leaked Claude-only config"
  fi
else
  bad "v1 Codex normalization failed"
fi

claude="$TMP/claude-view.json"
if bash "$CORE/lib/manifest-provider-view.sh" "$TMP/v2.json" claude > "$claude"; then
  if jq -e '.name == "dev"
    and .mcp == ["atlassian"]
    and .skills_link.example == "~/.agents/skills/example"
    and .memory.engine == "claude-mem"
    and .plugins["claude-plugin@example"] == true
    and .env.SHARED == "claude"
    and .permissions.defaultMode == "plan"' "$claude" >/dev/null; then
    ok "v2 Claude view combines shared and Claude config"
  else
    bad "v2 Claude view lost or mis-mapped fields"
  fi
else
  bad "v2 Claude normalization failed"
fi

codex="$TMP/codex-view.json"
if bash "$CORE/lib/manifest-provider-view.sh" "$TMP/v2.json" codex > "$codex"; then
  if jq -e '.plugins["codex-plugin"] == true
    and .config.model_reasoning_effort == "high"
    and .permissions.approval_policy == "on-request"
    and .env == {}' "$codex" >/dev/null; then
    ok "v2 Codex view selects only Codex config"
  else
    bad "v2 Codex view leaked or lost provider config"
  fi
else
  bad "v2 Codex normalization failed"
fi

if jq '.schema_version = 3' "$TMP/v2.json" \
  | bash "$CORE/lib/manifest-provider-view.sh" /dev/stdin claude >/dev/null 2>&1; then
  bad "unknown schema version was accepted"
else
  ok "unknown schema version fails closed"
fi

if [ "$fails" -ne 0 ]; then
  echo "manifest provider-view tests FAILED: $fails"
  exit 1
fi
echo "manifest provider-view tests passed"
