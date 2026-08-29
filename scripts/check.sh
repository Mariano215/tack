#!/usr/bin/env bash
# check.sh
# Pre-integration gate for this repo. Everything here is deterministic and
# cheap enough to run on every change. Every failure prints the file, the line
# where it can be found, and the fix, because the reader is often an agent.
#
# Run it before committing. CI runs the same script, nothing else.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail=0
err() { echo "check: $1"; echo "  Fix: $2"; fail=1; }

# bash 3.2 on macOS has no mapfile, and this repo targets it.
SHFILES=()
while IFS= read -r f; do SHFILES+=("$f"); done < <(git ls-files '*.sh'; echo bin/tack)

# 1. Shell syntax. This is the class that bricks every machine: a broken
#    apply-profile.sh reaches every workstation through tack sync, and the hook
#    that would heal it heals by running the broken script.
for f in "${SHFILES[@]}"; do
  [ -f "$f" ] || continue
  out="$(bash -n "$f" 2>&1)" || err "$out" "Fix the syntax error above. Nothing else in this gate runs against a file bash cannot parse."
done

# 2. Python syntax.
while IFS= read -r f; do
  out="$(python3 -m py_compile "$f" 2>&1)" || err "$f does not compile: $(printf '%s' "$out" | tail -n2 | tr '\n' ' ')" "Fix the syntax error. ghost hooks run on every write, so a broken one blocks work until the next apply."
done < <(git ls-files '*.py')
find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null

# 3. Every tracked JSON must parse. settings.json is composed from
#    base-settings.json, and an unparseable manifest silently drops a profile.
while IFS= read -r f; do
  jq -e . "$f" >/dev/null 2>&1 || err "$f is not valid JSON." "Run: jq . $f to see where it breaks."
done < <(git ls-files '*.json')

# 4. Manifest contract. This mirrors what lib/apply-profile.sh actually reads.
#    manifest.schema.json stays the guide a human or agent reads; this is its
#    sensor. They can drift, which is cheaper than a schema validator dependency
#    for eight files.
for m in profiles/*/manifest.json; do
  [ -f "$m" ] || continue
  msg="$(jq -r '
    [ (if (.name | type) != "string" then "name must be a string" else empty end),
      (if has("plugins") and ((.plugins | type) != "object" or ([.plugins[] | select(type != "boolean")] | length) > 0) then "plugins must be an object of booleans" else empty end),
      (if has("mcp") and ((.mcp | type) != "array" or ([.mcp[] | select(type != "string")] | length) > 0) then "mcp must be an array of strings" else empty end),
      (if has("caveman") and ([.caveman] | inside(["off","lite","full","ultra"]) | not) then "caveman must be one of off, lite, full, ultra" else empty end),
      (if has("env") and ((.env | type) != "object" or ([.env[] | select(type != "string")] | length) > 0) then "env values must be strings" else empty end),
      (if has("permissions") and (.permissions.defaultMode != null) and ([.permissions.defaultMode] | inside(["default","auto","acceptEdits","plan","bypassPermissions"]) | not) then "permissions.defaultMode is not a mode the CLI accepts" else empty end),
      (if has("skills_link") and ([.skills_link[] | select((startswith("~/") or startswith("$HARNESS_ROOT/")) | not)] | length) > 0 then "skills_link values must start with ~/ or $HARNESS_ROOT/" else empty end)
    ] | join("; ")' "$m" 2>/dev/null)"
  [ -n "$msg" ] && err "$m: $msg" "The engine reads these keys directly (lib/apply-profile.sh). See manifest.schema.json for the full contract."
done

# 5. The CRLF class. jq on Git Bash emits CRLF, so a value read into a shell
#    variable compares as "name\r" and silently matches nothing. Two commits
#    exist only to add a missing tr -d '\r' (de91865, eb00522); this is the
#    check that stops the third.
while IFS=: read -r f ln _; do
  # A pipeline can span lines, so look at the match and the next three before
  # calling it unstripped. Guessing from one line alone reports every
  # correctly-continued jq -r as a bug.
  line="$(sed -n "${ln},$((ln + 3))p" "$f")"
  case "$line" in
    *"tr -d"*|*jqr*) continue ;;
  esac
  err "$f:$ln pipes jq -r onward without stripping CR." \
    "Append '| tr -d \"\\r\"' to the pipeline. On Git Bash jq emits CRLF, the value carries a trailing CR, and every comparison against it fails silently."
done < <(grep -rn "jq -r" lib/ hooks/ scripts/ verify-setup.sh 2>/dev/null \
         | grep '|' | grep -v '^scripts/check.sh:')

# 6. Sensors that already existed and were invoked by nothing.
bash scripts/sanitize-check.sh >/dev/null 2>&1 || { bash scripts/sanitize-check.sh; fail=1; }
out="$(bash scripts/test-resolve-link-target.sh 2>&1)" || { echo "$out"; err "scripts/test-resolve-link-target.sh failed." "See the failing case above. It covers \$HARNESS_ROOT and ~/ expansion in skills_link."; }
out="$(bash scripts/test-ghost-scope.sh 2>&1)" || { echo "$out"; err "scripts/test-ghost-scope.sh failed." "ghost must scan only client-facing document formats (.txt, .docx, .pdf). Putting .md back in scan_extensions makes every internal note able to block a write and cost a rewrite."; }
out="$(bash scripts/test-skill-routes.sh 2>&1)" || { echo "$out"; err "scripts/test-skill-routes.sh failed." "A route in hooks/skill-routes.json changed behaviour. Fix the pattern, or if the new behaviour is intended, update the case table in scripts/test-skill-routes.sh. Routes are matched in file order and the first hit wins, so moving a route can steal another route's prompts."; }
out="$(bash scripts/test-capture-plan.sh 2>&1)" || { echo "$out"; err "scripts/test-capture-plan.sh failed." "hooks/capture-plan.sh must write only when the repo already has a .agent/ directory, and must exit 0 on empty, malformed or rejected input. Restore the gate at the top of the hook."; }

# 7b. Config-root parameterization. Two profiles now run side by side, each with
#     its own CLAUDE_CONFIG_DIR (tack shell / tack tmux / tack herd). A path hardcoded
#     to $HOME/.claude reads and writes the OTHER terminal's state, and the
#     SessionStart heal turns that into a daily timer rather than a one-off.
#     Paths that are shared by design are exempt below.
SHARED_OK='\.harness-root|\.claude-mem|\.fal-key|\.credentials\.json|\.local/bin|harness-apply\.lock|plugin-update-shared|plugins/marketplaces|claude-profiles'
while IFS=: read -r f ln rest; do
  # Comments name ~/.claude as prose; only code is a real hardcode.
  case "$(printf '%s' "$rest" | sed 's/^[[:space:]]*//')" in '#'*) continue ;; esac
  case "$rest" in *CLAUDE_CONFIG_DIR*|*harness:shared*) continue ;; esac
  printf '%s' "$rest" | grep -qE "$SHARED_OK" && continue
  err "$f:$ln hardcodes the config root." \
      "Use \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}\". Two profiles run at once, so a hardcoded path writes into the other terminal's config dir. Known shared paths (.harness-root, .claude-mem, .fal-key, .credentials.json, ~/.local/bin, the apply lock, the shared plugins tree) are exempt via \$SHARED_OK in this file. If this line is deliberately reaching the machine-wide ~/.claude, append a 'harness:shared' comment saying why."
done < <(grep -rn -E '(\$HOME|~)/\.claude([/"'"'"']|$)' \
           lib/ hooks/ ghost/ bin/tack verify-setup.sh statusline-command.sh 2>/dev/null)

# 7c. Hook commands in base-settings.json are run through sh, so they must
#     expand the variable rather than name a literal path. Separate check
#     because jq reads the command strings exactly as the CLI will.
bad="$(jq -r '[(.hooks[][]?.hooks[]?.command), .statusLine.command]
              | .[] | select(. != null)
              | select(test("(~|\\$\\{?HOME\\}?)/\\.claude"))
              | select(test("CLAUDE_CONFIG_DIR") | not)' base-settings.json 2>/dev/null | tr -d '\r')"
[ -n "$bad" ] && err "base-settings.json hook command hardcodes ~/.claude: $bad" \
  "Write it as \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/...\". Hook commands are spawned with a shell and inherit the variable, which is why \${HOME} already worked there."

# 7. shellcheck when present. Optional locally so nobody is blocked by a stale
#    brew; the CI runner always has it.
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${SHFILES[@]}"; do
    [ -f "$f" ] || continue
    out="$(shellcheck -S error -f gcc "$f" 2>&1)" || { echo "$out"; err "shellcheck errors in $f (see above)." "Fix each, or add a targeted # shellcheck disable=SCxxxx with a reason."; }
  done
else
  echo "check: note: shellcheck not installed, skipped. CI still runs it."
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "check FAILED. Nothing here is style: every rule above has shipped as a bug at least once."
  exit 1
fi

echo "check passed: ${#SHFILES[@]} shell files, $(git ls-files '*.json' | wc -l | tr -d ' ') json files, $(ls -d profiles/*/ | wc -l | tr -d ' ') manifests."
exit 0
