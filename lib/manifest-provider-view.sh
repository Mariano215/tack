#!/usr/bin/env bash
# manifest-provider-view.sh <manifest.json> <claude|codex>
# Emits the selected provider's normalized view. Existing composers can keep
# reading legacy top-level keys while manifests migrate independently to v2.
set -euo pipefail

MANIFEST="${1:?usage: manifest-provider-view.sh <manifest.json> <claude|codex>}"
PROVIDER="${2:?usage: manifest-provider-view.sh <manifest.json> <claude|codex>}"

[ -f "$MANIFEST" ] || { echo "manifest-provider-view: no manifest at $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "manifest-provider-view: jq required" >&2; exit 1; }
case "$PROVIDER" in claude|codex) ;; *) echo "manifest-provider-view: unknown provider '$PROVIDER'" >&2; exit 1 ;; esac

version="$(jq -r 'if type == "object" then (.schema_version // 1) else "invalid" end' "$MANIFEST" | tr -d '\r')"
case "$version" in
  1)
    if [ "$PROVIDER" = "claude" ]; then
      jq '.' "$MANIFEST"
    else
      # v1 provider mechanics are Claude-specific. Codex receives only shared
      # intent until that profile declares an explicit providers.codex block.
      jq '. + {plugins: {}, env: {}, permissions: {}, config: {}}' "$MANIFEST"
    fi
    ;;
  2)
    jq --arg provider "$PROVIDER" '
      (.providers[$provider] // {}) as $runtime
      | . + {
          plugins: ($runtime.plugins // {}),
          env: ($runtime.env // {}),
          permissions: ($runtime.permissions // {}),
          config: ($runtime.config // {})
        }
    ' "$MANIFEST"
    ;;
  *)
    echo "manifest-provider-view: unsupported schema_version '$version'" >&2
    exit 1
    ;;
esac
