#!/usr/bin/env bash
# test-context-cost.sh
# The one thing context-cost.sh can get badly wrong is counting the plugin
# cache instead of the installed plugin. The cache keeps every version ever
# pulled, so a naive glob reported this machine at ~47k always-on tokens when
# the real figure was ~11k, and a 4x error is worse than no number at all.
# This fixture pins that: two cached versions, one installed, one counted.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CFG="$TMP/home/.claude"
mkdir -p "$CFG/skills/local-one" "$CFG/output-styles"
printf 'memory\n' > "$CFG/CLAUDE.md"
cat > "$CFG/skills/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: LOCALSKILLDESCRIPTION
---
body that must not be counted, only the description is always on
EOF
printf '{"enabledPlugins":{"p@m":true,"off@m":false}}\n' > "$CFG/settings.json"

for v in 1.0.0 2.0.0; do
  mkdir -p "$TMP/home/.claude/plugins/cache/m/p/$v/skills/dup"
  cat > "$TMP/home/.claude/plugins/cache/m/p/$v/skills/dup/SKILL.md" <<'EOF'
---
name: dup
description: DUPDESCRIPTION
---
EOF
done
mkdir -p "$TMP/home/.claude/plugins/cache/m/off/1.0.0/skills/never"
cat > "$TMP/home/.claude/plugins/cache/m/off/1.0.0/skills/never/SKILL.md" <<'EOF'
---
name: never
description: DISABLEDDESCRIPTION
---
EOF
cat > "$TMP/home/.claude/plugins/installed_plugins.json" <<EOF
{"version":2,"plugins":{
 "p@m":[{"installPath":"$TMP/home/.claude/plugins/cache/m/p/2.0.0","version":"2.0.0"}],
 "off@m":[{"installPath":"$TMP/home/.claude/plugins/cache/m/off/1.0.0","version":"1.0.0"}]
}}
EOF

out="$(cd "$TMP" && HOME="$TMP/home" CLAUDE_CONFIG_DIR="$CFG" bash "$REPO_ROOT/scripts/context-cost.sh" 2>&1)" || {
  echo "FAIL: context-cost.sh exited non-zero"; echo "$out"; exit 1; }

case "$out" in
  *TOTAL*) ;;
  *) echo "FAIL: no TOTAL line"; echo "$out"; exit 1 ;;
esac

n="$(printf '%s\n' "$out" | grep -c 'plugin p@m')"
[ "$n" = 1 ] || { echo "FAIL: enabled plugin counted $n times, expected 1 (cache holds 2 versions)"; echo "$out"; exit 1; }

printf '%s\n' "$out" | grep -q 'plugin off@m' && { echo "FAIL: disabled plugin was counted"; echo "$out"; exit 1; }

# The fixture skill body is longer than its description. If the body leaked
# into the count the number would jump, so pin the description-only figure:
# len("LOCALSKILLDESCRIPTION") + len("local-one") + 4 = 34.
printf '%s\n' "$out" | grep -E '^skills +~/\.claude/skills/ +34 ' >/dev/null || {
  echo "FAIL: local skill should count 34 chars (description + name only)"; echo "$out"; exit 1; }

echo "test-context-cost: ok"
