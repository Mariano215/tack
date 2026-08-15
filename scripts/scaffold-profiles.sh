#!/usr/bin/env bash
# scaffold-profiles.sh
# Run once on a gh-authenticated box. For each profile under core/profiles/,
# populate the (already-created, empty) private repo tack-<name> with:
# core as a submodule, its manifest.json, an install.sh, and a README, then push.
# Idempotent: skips a repo that already has a manifest committed.
set -euo pipefail
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${HARNESS_ROOT:-$(cat "$HOME/.claude/.harness-root" 2>/dev/null || echo "$HOME/Projects")}"
ORG="${HARNESS_ORG:?set HARNESS_ORG to your GitHub account}"
CORE_URL="${HARNESS_CORE_URL:-https://github.com/Mariano215/tack.git}"
mkdir -p "$ROOT"

for pdir in "$CORE_DIR"/profiles/*/; do
  name="$(basename "$pdir")"
  case " ${HARNESS_SKIP:-} " in *" $name "*) echo "== $name (skipped) =="; continue;; esac
  case " ${HARNESS_ONLY:-} " in " ") ;; *" $name "*) ;; *) [ -n "${HARNESS_ONLY:-}" ] && continue;; esac
  repo="$ROOT/tack-$name"
  url="https://github.com/$ORG/tack-$name.git"
  echo "== $name =="
  if [ ! -d "$repo/.git" ]; then
    git clone "$url" "$repo" 2>/dev/null || { mkdir -p "$repo"; ( cd "$repo" && git init -q && git remote add origin "$url" ); }
  fi
  ( cd "$repo"
    if [ ! -e core/.git ] && [ ! -f .gitmodules ]; then
      git submodule add "$CORE_URL" core 2>/dev/null || true
    fi
    cp "$pdir/manifest.json" manifest.json
    cat > install.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
git submodule update --init --quiet
exec bash ./core/lib/apply-profile.sh ./manifest.json
SH
    chmod +x install.sh
    [ -f skills/.gitkeep ] || { mkdir -p skills; : > skills/.gitkeep; }
    cat > README.md <<MD
# tack-$name

Task-scoped Claude Code profile: $(jq -r .description manifest.json).
Shares the engine via the \`core\` submodule (tack).

## Install / switch
\`\`\`
git clone --recurse-submodules $url
cd tack-$name && ./install.sh      # or: tack use $name
\`\`\`

Profile-specific skills live in \`skills/\`. Engine, hooks, and the \`tack\`
switcher come from \`core/\`. Edit \`manifest.json\` to change plugins, MCP set,
or skills.
MD
    git add -A
    git commit -q -m "feat: scaffold $name profile (core submodule + manifest + install)" || echo "  (nothing to commit)"
    git push -u origin HEAD 2>&1 | tail -1 || echo "  push failed (check remote/auth)"
  )
done
echo "scaffold complete."
