#!/usr/bin/env bash
# sync-runtime-files.sh <source-manifest.json> <provider-view.json>
# Installs Codex policy and skills without deleting user-owned content.
set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${1:?usage: sync-runtime-files.sh <manifest.json> <provider-view.json>}"
VIEW="${2:?usage: sync-runtime-files.sh <manifest.json> <provider-view.json>}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
PROFILE_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo now).$$"
BACKUP_ROOT="$CODEX_DIR/backups/$TS"
SOURCES="$(mktemp "$CODEX_DIR/.harness-skill-sources.XXXXXX")"
DESIRED="$(mktemp "$CODEX_DIR/.harness-skills.XXXXXX")"
cleanup() { rm -f "$SOURCES" "$DESIRED"; }
trap cleanup EXIT

backup_path() {
  local target="$1" relative="$2" backup
  backup="$BACKUP_ROOT/$relative"
  mkdir -p "$(dirname "$backup")"
  mv "$target" "$backup"
  echo "  preserved previous Codex content: $backup"
}

sync_agents() {
  local source="$CORE_DIR/templates/AGENTS.md" target="$CODEX_DIR/AGENTS.md"
  local rendered="$(mktemp "$CODEX_DIR/.harness-agents.XXXXXX")"
  if [ ! -f "$target" ]; then
    cp "$source" "$rendered"
  elif grep -qF '<!-- >>> codex-harness policy >>> -->' "$target"; then
    awk -v source="$source" '
      $0 == "<!-- >>> codex-harness policy >>> -->" {
        while ((getline line < source) > 0) print line
        skip=1
        next
      }
      $0 == "<!-- <<< codex-harness policy <<< -->" {skip=0; next}
      !skip {print}
    ' "$target" > "$rendered"
  elif grep -q '^# AGENTS.md - codex-harness$' "$target"; then
    # Legacy donor repo owned the whole file but had no marker. Preserve one
    # copy, then migrate to the managed block format.
    cp "$source" "$rendered"
  else
    { cat "$target"; echo ""; cat "$source"; } > "$rendered"
  fi

  if cmp -s "$rendered" "$target"; then
    rm -f "$rendered"
    echo "  Codex AGENTS.md unchanged"
    return
  fi
  [ -e "$target" ] && backup_path "$target" "AGENTS.md"
  mv "$rendered" "$target"
  echo "  Codex AGENTS.md policy synced"
}

valid_skill_name() {
  case "$1" in ""|.|..|*[!A-Za-z0-9._-]*) return 1 ;; *) return 0 ;; esac
}

add_source() {
  local name="$1" source="$2"
  valid_skill_name "$name" || { echo "codex skills: invalid skill name '$name'" >&2; exit 1; }
  [ -f "$source/SKILL.md" ] || return 0
  printf '%s\t%s\n' "$name" "$source" >> "$SOURCES"
}

sync_skills() {
  local name source target old managed="$CODEX_DIR/.harness-managed-skills"
  mkdir -p "$CODEX_DIR/skills"

  # Provider-neutral core skills use one source. Coupled workflows have compact
  # Codex-native variants below until their shared versions lose tool coupling.
  for name in gauntlet-loop git-best-practices ingest-scrubbing prompt-injection-defense repro security-audit; do
    add_source "$name" "$CORE_DIR/skills/$name"
  done
  for source in "$CORE_DIR"/adapters/codex/skills/*; do
    [ -d "$source" ] || continue
    add_source "$(basename "$source")" "$source"
  done

  # Profile skills are higher precedence than core skills, matching Claude.
  for source in "$PROFILE_DIR"/skills/*; do
    [ -d "$source" ] || continue
    add_source "$(basename "$source")" "$source"
  done

  HARNESS_ROOT="$(cat "$HOME/.claude/.harness-root" 2>/dev/null | tr -d '\r' || true)"
  HARNESS_ROOT="${HARNESS_ROOT:-$HOME/Projects}"
  # shellcheck source=resolve-link-target.sh
  . "$CORE_DIR/lib/resolve-link-target.sh"
  while IFS=$'\t' read -r name raw; do
    [ -n "$name" ] || continue
    source="$(resolve_link_target "$raw" "$HARNESS_ROOT")"
    if [ -d "$source" ] && [ -f "$source/SKILL.md" ]; then
      add_source "$name" "$source"
    else
      echo "  Codex linked skill skipped, target missing: $name -> $source"
    fi
  done < <(jq -r '(.skills_link // {}) | to_entries[] | "\(.key)\t\(.value)"' "$VIEW" | tr -d '\r')

  # Last source wins. This gives linked skills precedence over profile skills,
  # then profile over adapter/core, without copying the same name twice.
  awk -F '\t' '{source[$1]=$2} END {for (name in source) print name "\t" source[name]}' "$SOURCES" \
    | sort > "$DESIRED"

  if [ -f "$managed" ]; then
    while IFS= read -r old; do
      valid_skill_name "$old" || continue
      cut -f1 "$DESIRED" | grep -qxF "$old" && continue
      target="$CODEX_DIR/skills/$old"
      [ -e "$target" ] || [ -L "$target" ] || continue
      backup_path "$target" "skills/$old"
      echo "  retired harness skill moved aside: $old"
    done < "$managed"
  fi

  while IFS=$'\t' read -r name source; do
    [ -n "$name" ] || continue
    target="$CODEX_DIR/skills/$name"
    if [ -d "$target" ] && diff -rq "$source" "$target" >/dev/null 2>&1; then
      continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      backup_path "$target" "skills/$name"
    fi
    cp -R "$source" "$target"
    echo "  Codex skill synced: $name"
  done < "$DESIRED"

  cut -f1 "$DESIRED" > "$managed.tmp"
  mv "$managed.tmp" "$managed"
  echo "  Codex skills managed: $(wc -l < "$managed" | tr -d ' ')"
}

sync_agents
sync_skills
