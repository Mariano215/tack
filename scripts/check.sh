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
while IFS= read -r f; do SHFILES+=("$f"); done < <(git ls-files --cached --others --exclude-standard -- '*.sh'; echo bin/tack)

# 0. Line endings. .gitattributes pins *.sh, *.py, *.json and *.md to eol=lf
#    because a CRLF script dies at the shebang. When the working tree carries
#    CRLF anyway (a Windows editor rewrote it, sync-from-live copied it back out
#    of ~/.claude, a merge landed it), the symptom that reaches you is step 1
#    reporting "syntax error near unexpected token $'do\r'", which reads as a
#    broken script rather than a broken checkout. Cost a session on 2026-08-18.
#    Name the cause before step 1 gets to mislabel it. *.ps1 and *.cmd are
#    exempt by asking git for the attribute, not by re-listing the patterns.
CRLF_HITS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  [ "$(git check-attr eol -- "$f" 2>/dev/null | sed 's/.*: //')" = "lf" ] || continue
  CRLF_HITS="$CRLF_HITS $f"
done < <(git ls-files --cached --others --exclude-standard -z | xargs -0 grep -l -- "$(printf '\r')" 2>/dev/null)
if [ -n "$CRLF_HITS" ]; then
  err "CRLF in the working tree for files .gitattributes pins to eol=lf:$CRLF_HITS" \
    "The index is almost certainly fine; only the checkout is wrong. Strip the CR in place: for f in$CRLF_HITS; do t=\"\$(mktemp)\"; tr -d '\\r' < \"\$f\" > \"\$t\" && cat \"\$t\" > \"\$f\" && rm -f \"\$t\"; done"
fi

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
done < <(git ls-files --cached --others --exclude-standard -- '*.py')
find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null

# 3. Every tracked JSON must parse. settings.json is composed from
#    base-settings.json, and an unparseable manifest silently drops a profile.
while IFS= read -r f; do
  jq -e . "$f" >/dev/null 2>&1 || err "$f is not valid JSON." "Run: jq . $f to see where it breaks."
done < <(git ls-files --cached --others --exclude-standard -- '*.json')

# 4. Manifest contract. This mirrors what lib/apply-profile.sh actually reads.
#    manifest.schema.json stays the guide a human or agent reads; this is its
#    sensor. They can drift, which is cheaper than a schema validator dependency
#    for eight files.
for m in profiles/*/manifest.json; do
  [ -f "$m" ] || continue
  msg="$(jq -r '
    [ (if (.name | type) != "string" then "name must be a string" else empty end),
      (if has("schema_version") and ([.schema_version] | inside([1,2]) | not) then "schema_version must be 1 or 2" else empty end),
      (if .schema_version == 2 and ((.providers | type) != "object") then "v2 providers must be an object" else empty end),
      (if .schema_version == 2 and ((.providers // {}) | type) == "object" and ([.providers | keys[] | select(. != "claude" and . != "codex")] | length) > 0 then "providers supports only claude and codex" else empty end),
      (if .schema_version == 2 and ([.providers // {} | .[] | select(type != "object")] | length) > 0 then "each provider config must be an object" else empty end),
      (if .schema_version == 2 and ([.providers // {} | .[] | select(type == "object" and has("plugins")) | .plugins | select(type != "object" or ([.[] | select(type != "boolean")] | length) > 0)] | length) > 0 then "provider plugins must be objects of booleans" else empty end),
      (if .schema_version == 2 and ([.providers // {} | .[] | select(type == "object" and has("env")) | .env | select(type != "object" or ([.[] | select(type != "string")] | length) > 0)] | length) > 0 then "provider env values must be strings" else empty end),
      (if .schema_version == 2 and ([.providers // {} | .[] | select(type == "object" and has("permissions")) | .permissions | select(type != "object")] | length) > 0 then "provider permissions must be objects" else empty end),
      (if .schema_version == 2 and ([.providers // {} | .[] | select(type == "object" and has("config")) | .config | select(type != "object")] | length) > 0 then "provider config must be objects" else empty end),
      (if has("plugins") and ((.plugins | type) != "object" or ([.plugins[] | select(type != "boolean")] | length) > 0) then "plugins must be an object of booleans" else empty end),
      (if has("mcp") and ((.mcp | type) != "array" or ([.mcp[] | select(type != "string")] | length) > 0) then "mcp must be an array of strings" else empty end),
      (if has("caveman") and ([.caveman] | inside(["off","lite","full","ultra"]) | not) then "caveman must be one of off, lite, full, ultra" else empty end),
      (if has("env") and ((.env | type) != "object" or ([.env[] | select(type != "string")] | length) > 0) then "env values must be strings" else empty end),
      (if has("permissions") and (.permissions.defaultMode != null) and ([.permissions.defaultMode] | inside(["default","auto","acceptEdits","plan","bypassPermissions"]) | not) then "permissions.defaultMode is not a mode the CLI accepts" else empty end),
      (if has("skills_link") and ([.skills_link[] | select((startswith("~/") or startswith("$HARNESS_ROOT/")) | not)] | length) > 0 then "skills_link values must start with ~/ or $HARNESS_ROOT/" else empty end),
      (if has("skills_source") and ((.skills_source | type) != "object" or ([.skills_source[] | select(type != "string")] | length) > 0) then "skills_source must be an object of strings" else empty end),
      (. as $m | if ($m | has("skills_source")) and ([$m.skills_source | keys[] as $k | select((($m.skills_link // {}) | has($k)) | not) | $k] | length) > 0 then "every skills_source key must also be a skills_link key" else empty end),
      (if has("skills_source") and ([.skills_source[] | select(type == "string") | select(test("^[A-Za-z0-9._@/-]+$") and (startswith("-") | not) | not)] | length) > 0 then "skills_source values must be package specs (owner/repo@skill), not commands" else empty end)
    ] | join("; ")' "$m" 2>/dev/null)"
  [ -n "$msg" ] && err "$m: $msg" "The engine reads these keys directly (lib/apply-profile.sh). See manifest.schema.json for the full contract."
done

# 4b. Output style default. base-settings.json names one; the file that
#     declares it must exist in output-styles/, or Claude Code falls back to
#     its built-in default in silence, with nothing on screen to say so.
os="$(jq -r '.outputStyle // empty' base-settings.json 2>/dev/null | tr -d '\r')"
if [ -n "$os" ]; then
  grep -rqi "^name: *$os\$" output-styles 2>/dev/null || \
    err "base-settings.json names outputStyle '$os' but no file in output-styles/ declares it." \
        "Add a 'name: $os' line to the intended output-styles/*.md file, or fix the typo in base-settings.json."
fi

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
done < <(grep -rn "jq -r" lib/ adapters/ hooks/ scripts/ verify-setup.sh 2>/dev/null \
         | grep '|' | grep -v '^scripts/check.sh:')

# 6. Sensors that already existed and were invoked by nothing.
bash scripts/sanitize-check.sh >/dev/null 2>&1 || { bash scripts/sanitize-check.sh; fail=1; }
out="$(bash scripts/test-sanitize-crlf.sh 2>&1)" || { echo "$out"; err "scripts/test-sanitize-crlf.sh failed." "sanitize-check.sh must strip a trailing CR from every line it reads from .sanitize-patterns, .sanitize-allow and .sanitize-authors-deny. Without it a Windows checkout sweeps for nothing and reports clean."; }
out="$(bash scripts/test-resolve-link-target.sh 2>&1)" || { echo "$out"; err "scripts/test-resolve-link-target.sh failed." "See the failing case above. It covers \$HARNESS_ROOT and ~/ expansion in skills_link."; }
out="$(bash scripts/test-manifest-provider-view.sh 2>&1)" || { echo "$out"; err "scripts/test-manifest-provider-view.sh failed." "Provider manifest normalization broke. v1 must retain legacy behavior; v2 must expose only the selected provider config plus shared intent."; }
out="$(bash scripts/test-ghost-scope.sh 2>&1)" || { echo "$out"; err "scripts/test-ghost-scope.sh failed." "ghost must scan only client-facing document formats (.txt, .docx, .pdf). Putting .md back in scan_extensions makes every internal note able to block a write and cost a rewrite."; }
out="$(bash scripts/test-sync-pin-reset.sh 2>&1)" || { echo "$out"; err "scripts/test-sync-pin-reset.sh failed." "tack sync must reset a profile whose only local commits are core pin bumps, and must stop on divergence that carries work. See the failing case above."; }
out="$(bash scripts/test-skill-routes.sh 2>&1)" || { echo "$out"; err "scripts/test-skill-routes.sh failed." "A route in hooks/skill-routes.json changed behaviour. Fix the pattern, or if the new behaviour is intended, update the case table in scripts/test-skill-routes.sh. Routes are matched in file order and the first hit wins, so moving a route can steal another route's prompts."; }
out="$(bash scripts/test-capture-plan.sh 2>&1)" || { echo "$out"; err "scripts/test-capture-plan.sh failed." "hooks/capture-plan.sh must write only when the repo already has a .agent/ directory, and must exit 0 on empty, malformed or rejected input. Restore the gate at the top of the hook."; }
out="$(bash scripts/test-apply.sh 2>&1)" || { echo "$out"; err "scripts/test-apply.sh failed." "A real apply against a throwaway HOME broke. Read the failing case above and re-run: bash scripts/test-apply.sh. Everything else here is static analysis, so this is the only check that notices when the apply itself stops working."; }
out="$(bash scripts/test-apply-codex.sh 2>&1)" || { echo "$out"; err "scripts/test-apply-codex.sh failed." "Codex profile rendering broke. It must write only <profile>.config.toml under a throwaway CODEX_HOME and preserve config.toml."; }
out="$(bash scripts/test-tack-provider-apply.sh 2>&1)" || { echo "$out"; err "scripts/test-tack-provider-apply.sh failed." "tack use must apply Claude and Codex from one profile selection and return non-zero with the failed provider named."; }
out="$(bash scripts/test-tack-open.sh 2>&1)" || { echo "$out"; err "scripts/test-tack-open.sh failed." "tack open must validate options before mutation, preserve the Codex default, and create or reuse the expected tmux panes."; }
out="$(bash scripts/test-memory-provider.sh 2>&1)" || { echo "$out"; err "scripts/test-memory-provider.sh failed." "A Codex-only machine without a local provider must report memory unavailable instead of silently selecting Anthropic."; }
out="$(bash scripts/test-codex-memory.sh 2>&1)" || { echo "$out"; err "scripts/test-codex-memory.sh failed." "Codex must register claude-mem through one plugin path, request removal of the stale direct MCP, and back up config.toml first."; }
out="$(bash scripts/test-codex-plugin.sh 2>&1)" || { echo "$out"; err "scripts/test-codex-plugin.sh failed." "Codex policy plugin registration or hook behavior broke. Graphify and security hooks must fail open and emit valid context."; }
out="$(bash scripts/test-marketplace-enabled.sh 2>&1)" || { echo "$out"; err "scripts/test-marketplace-enabled.sh failed." "plugin-auto-update.sh must skip a marketplace whose plugins are all disabled. Without the guard, disabling a plugin still pays its bun/npm install on every session start, and on Windows that install fails with ENOTEMPTY where nobody will see it."; }

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
           lib/ adapters/ hooks/ ghost/ bin/tack verify-setup.sh statusline-command.sh 2>/dev/null)

# 7c. Hook commands in base-settings.json are run through sh, so they must
#     expand the variable rather than name a literal path. Separate check
#     because jq reads the command strings exactly as the CLI will.
bad="$(jq -r '[(.hooks[][]?.hooks[]?.command), .statusLine.command]
              | .[] | select(. != null)
              | select(test("(~|\\$\\{?HOME\\}?)/\\.claude"))
              | select(test("CLAUDE_CONFIG_DIR") | not)' base-settings.json 2>/dev/null | tr -d '\r')"
[ -n "$bad" ] && err "base-settings.json hook command hardcodes ~/.claude: $bad" \
  "Write it as \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/...\". Hook commands are spawned with a shell and inherit the variable, which is why \${HOME} already worked there."

# 7d. Retired prompting patterns. These instruction shapes were fixes for older
#    models and now cost tokens or suppress real output on current ones:
#    "you MUST use <tool>" and "if in doubt, use" make tools over-trigger,
#    "double-check"/"re-verify" duplicates self-checking the model already does,
#    "only report high-severity" is followed literally and drops real findings,
#    and "think step by step" is dead scaffolding. Source: Anthropic's
#    "Prompting Claude Opus 5" guide. Scanned over the files that actually reach
#    a model as instructions. A line that genuinely needs one of these (a
#    diagram label, a quoted example, a rule about the harness itself) opts out
#    with a trailing "prompt-ok" comment.
PROMPT_FILES="CLAUDE.md templates/CLAUDE.md"
while IFS= read -r f; do PROMPT_FILES="$PROMPT_FILES $f"; done < <(git ls-files --cached --others --exclude-standard -- 'skills/*/SKILL.md' 'adapters/codex/skills/*/SKILL.md' 'agents/*.md' 'commands/*.md' 'output-styles/*.md')
# shellcheck disable=SC2086
while IFS=: read -r f ln rest; do
  case "$rest" in *prompt-ok*) continue ;; esac
  err "$f:$ln carries a retired prompting pattern." \
    "Rewrite it. 'You MUST use X'/'if in doubt, use X' over-trigger the tool on current models, so say 'Use X when ...' and give the reason. 'double-check'/'re-verify' duplicates self-checking the model already does. 'only report high-severity' is obeyed literally and hides real findings, so ask for everything and filter in a second pass. If the line is a quoted example or a label rather than an instruction, append a 'prompt-ok' comment."
done < <(grep -rniE "you must use|if in doubt, *use|double[ -]check (your|the) (work|answer|output)|re-verify before|think step by step|only report (high|critical)[- ]severity" $PROMPT_FILES 2>/dev/null)

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

echo "check passed: ${#SHFILES[@]} shell files, $(git ls-files --cached --others --exclude-standard -- '*.json' | wc -l | tr -d ' ') json files, $(ls -d profiles/*/ | wc -l | tr -d ' ') manifests."
exit 0
