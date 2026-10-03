#!/usr/bin/env bash
# vendor-superpowers.sh <superpowers plugin dir>
# Copies the superpowers methodology skills into skills/ without the plugin's
# SessionStart bootstrap. That bootstrap tells the model to invoke a skill on a
# "1% chance" in capitals, which Anthropic's Claude 5 prompting guide names as
# the pattern that over-triggers. The skills themselves are kept as shipped,
# apart from the reference rewrites below, so an upstream release re-vendors
# with one run of this script.
#   bash scripts/vendor-superpowers.sh ~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>
set -euo pipefail

SRC="${1:?usage: vendor-superpowers.sh <superpowers plugin dir>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="brainstorming writing-plans executing-plans subagent-driven-development systematic-debugging test-driven-development requesting-code-review verification-before-completion finishing-a-development-branch using-git-worktrees"
VERSION="$(jq -r '.version // "unknown"' "$SRC/.claude-plugin/plugin.json" 2>/dev/null | tr -d '\r')"

for s in $SKILLS; do
  [ -f "$SRC/skills/$s/SKILL.md" ] || { echo "vendor: $SRC/skills/$s/SKILL.md missing. Fix: point at a superpowers plugin dir that ships it, or drop it from SKILLS." >&2; exit 1; }
done

for s in $SKILLS; do
  rm -rf "${REPO:?}/skills/$s"
  cp -R "$SRC/skills/$s" "$REPO/skills/$s"
done

# Rewrites. Vendored skills lose the plugin namespace. writing-skills is only a
# pointer for skill authors, and using-superpowers (the bootstrap) is not here,
# so a pointer into its references folder is dropped.
find $(printf "$REPO/skills/%s " $SKILLS) -type f \( -name '*.md' -o -name '*.sh' \) | while IFS= read -r f; do
  python3 - "$f" "$SKILLS" <<'PY'
import re, sys
path, names = sys.argv[1], sys.argv[2].split()
s = open(path, encoding="utf-8", newline="").read()
o = s
s = re.sub(r" \(see the per-platform references in\s+`\.\./using-superpowers/references/`\)", "", s)
s = s.replace(" (superpowers:writing-skills)", "")
for n in names:
    s = s.replace("superpowers:" + n, n)
if s != o:
    open(path, "w", encoding="utf-8", newline="").write(s)
PY
done

# Upstream test fixtures and its creation log point at paths that exist only in
# the superpowers repo. The skills never read them.
rm -f "$REPO"/skills/systematic-debugging/test-*.md "$REPO"/skills/systematic-debugging/CREATION-LOG.md

# Local patches. Each must match exactly once, so an upstream rewording fails
# here instead of shipping the old conflict silently.
python3 - "$REPO/skills" <<'PY'
import re, sys
root = sys.argv[1]
def patch(rel, old, new, regex=False):
    path = root + "/" + rel
    s = open(path, encoding="utf-8", newline="").read()
    n = len(re.findall(old, s, flags=re.S)) if regex else s.count(old)
    if n != 1:
        sys.exit("vendor: patch for %s matched %d times, wanted 1: %r. Fix: update the patch in scripts/vendor-superpowers.sh to the new upstream text." % (rel, n, old[:60]))
    s = re.sub(old, new, s, flags=re.S) if regex else s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="").write(s)

# Claude 5 prompting guide: "You MUST use X" over-triggers, and check.sh bans it.
patch("brainstorming/SKILL.md", '"You MUST use this before any creative work - creating features', '"Use before creative work - creating features')

# smart-agent-spawner owns model tier. Upstream picks its own tiers. The fix
# loop stays at upstream's five rounds (it is a review loop, not a spawn retry).
patch("subagent-driven-development/SKILL.md", r"## Model Selection\n.*?(?=## The Task Loop)",
      "## Model Selection\n\nsmart-agent-spawner picks the model tier for every dispatch here:\nimplementers, reviewers, fix rounds and the final review. Name the model it\ngives on each call.\n\n", regex=True)
# Prompt audit 2026-10-03. The review default must not be the HEAD~1 that
# subagent-driven-development forbids, the reviewer is the repo's code-reviewer
# agent, and review runs at a checkpoint or commit gate (templates/CLAUDE.md).
patch("requesting-code-review/SKILL.md", "BASE_SHA=$(git rev-parse HEAD~1)  # or: git merge-base origin/main HEAD", "BASE_SHA=$(git merge-base origin/main HEAD)  # or the HEAD recorded before the task started")
patch("requesting-code-review/SKILL.md", "Dispatch a `general-purpose` subagent, filling the template at [code-reviewer.md](code-reviewer.md)", "Dispatch the `code-reviewer` agent, filling the template at [code-reviewer.md](code-reviewer.md)")
patch("requesting-code-review/SKILL.md", "**Mandatory:**\n- After each task in subagent-driven development\n- After completing major feature\n- Before merge to main\n\n**Optional but valuable:**\n- When stuck (fresh perspective)\n- Before refactoring (baseline check)\n- After fixing complex bug\n", "**At a checkpoint or commit gate:**\n- After each task in subagent-driven development\n- After completing a major feature\n- Before merge to main\n")
patch("requesting-code-review/SKILL.md", "**Core principle:** Review early, review often.\n\n", "")
# systematic-debugging names a Phase 4.5 that does not exist, and an "Ultra-think"
# keyword from the old extended-thinking era. Thinking is always on now.
patch("systematic-debugging/SKILL.md", "(see Phase 4.5)", "(see Phase 4, step 5)")
patch("systematic-debugging/SKILL.md", '- "Ultra-think this" - Question fundamentals, not just symptoms\n', "")
# brainstorming points at a skill that is not installed.
patch("brainstorming/SKILL.md", "- Use elements-of-style:writing-clearly-and-concisely skill if available\n", "")
PY

left="$(grep -rn 'superpowers:' $(printf "$REPO/skills/%s " $SKILLS) 2>/dev/null || true)"
if [ -n "$left" ]; then
  echo "$left" >&2
  echo "vendor: references to superpowers skills that are not vendored remain (above). Fix: vendor that skill too, or add a rewrite for it in this script." >&2
  exit 1
fi

cat > "$REPO/skills/SUPERPOWERS.md" <<EOF
# Vendored superpowers skills

Copied from superpowers $VERSION (github.com/obra/superpowers, MIT) by
scripts/vendor-superpowers.sh. Do not edit these skills by hand: re-run the
script on a newer plugin dir, and put any local change in its rewrite list.

Left out on purpose: the SessionStart bootstrap (using-superpowers), which
orders a skill on a "1% chance" and over-triggers on Claude 5 models,
writing-skills, which is for skill authors, and upstream test fixtures.

Local patches (listed in the script): the brainstorming description drops
"You MUST use", and subagent-driven-development defers model tier to
smart-agent-spawner (the five-round fix loop stays as upstream ships it).
requesting-code-review dispatches the code-reviewer agent at a checkpoint and
defaults its base to the merge-base, systematic-debugging drops a dead Phase 4.5
pointer and the "Ultra-think" keyword, and brainstorming drops a pointer to a
skill that is not installed. The spec, plan and implementer self-review
checklists stay: they check a written artifact against named items, and
templates/CLAUDE.md says so.

Skills: $SKILLS

$(cat "$SRC/LICENSE")
EOF
echo "vendored superpowers $VERSION: $SKILLS"
