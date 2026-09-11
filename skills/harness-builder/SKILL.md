---
name: harness-builder
description: Use when the user wants a new tack harness or profile for a kind of work (legal, data, a client, a stack), asks "build me a harness for X", "add a profile", "what should a X profile have", or wants an existing profile redesigned.
---

# Harness builder

A harness here is a profile: `tack-<name>`, a repo under your `$HARNESS_ORG`
holding a `manifest.json`, an `install.sh` and optional `skills/`, pinning tack
as the `core` submodule. `tack use <name>` composes Claude and Codex from it. Most
of the work is choosing less, not more: everything a profile enables costs
context in every session.

## Phase 1: research (read, write nothing)

1. Ask what the work is, which agent runs it (Claude, Codex, both), whether
   client material is involved, and which machines need it. One round of
   questions, then proceed on defaults.
2. Read the closest manifest in the tack repo's `profiles/` and copy its shape.
3. Take stock of what every profile already gets, so you do not add it twice:
   - every skill in tack's `skills/` is installed in every profile. Never list
     one in `skills_link`.
   - `base-settings.json` sets the baseline plugins and owns the marketplaces.
4. Candidates, cheapest first: an existing core or profile skill, a plugin
   from a marketplace already in `base-settings.json` `extraKnownMarketplaces`,
   a public skill (`npx skills find <query>`), an MCP server. For each, write
   one line on what it is for and what it costs.

## Phase 2: design, then stop for approval

Write the proposed `profiles/<name>/manifest.json` (schema v2, see
`manifest.schema.json`) and show it with one line per entry saying why.
Rules the engine enforces, so check them before proposing:

| Want | Constraint |
|---|---|
| Plugin | Its marketplace must already be in `base-settings.json`. A new marketplace is an engine change for every machine; propose it separately. |
| MCP server | Plugin-provided (context7, chrome-devtools, playwright) rides `providers.claude.plugins`. Anything else must exist in the Claude `MCP_TABLE` (`adapters/claude/apply-profile.sh`) and in `adapters/codex/mcp-catalog.json`, or the Codex apply fails. New server = engine change. |
| External skill | `skills_link` with a `~/` or `$HARNESS_ROOT/` path, plus `skills_source` (`owner/repo@skill`) so a missing target installs itself. |
| Skill owned by another profile | `skills_link` to `$HARNESS_ROOT/tack-<owner>/skills/<skill>`; do not copy it. |
| New skill for this work only | `skills/` in the profile repo. |
| Codex settings | `providers.codex.config` and `providers.codex.permissions`. |
| Permission mode | `providers.claude.permissions.defaultMode` makes it profile-owned. |

Do not write files until the user approves the manifest.

## Phase 3: build

Start from the example repo, which carries the canonical `install.sh` and the
`core` submodule:

```bash
git clone --recurse-submodules https://github.com/Mariano215/tack-profile-example "$HARNESS_ROOT/tack-<name>"
cd "$HARNESS_ROOT/tack-<name>"
git -C core pull -q origin main  # newest engine
$EDITOR manifest.json            # the approved manifest; name must be <name>
rm -rf skills/hello-tack         # add this profile's own skills under skills/
bash core/scripts/sanitize-check.sh
git add -A && git commit -m "feat: <name> profile"
git remote remove origin
gh repo create "$HARNESS_ORG/tack-<name>" --private --source=. --remote=origin --push
tack use <name>
```

Make the repo public only if the manifest and skills carry nothing about the
user's clients or machines.

## Phase 4: verify, then roll out

- `tack use <name>` exits 0 and names both providers (or says which CLI is absent).
- `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/verify-setup.sh"` prints no errors.
  The Codex apply runs its own verifier; read its output.
- `tack status` shows the expected MCP set and plugin count.
- Other machines: `tack install <name>` once on each, with `HARNESS_ORG` set. `tack sync` only updates
  profile repos a machine already has; it never clones a new one.

Report what passed with the lines that prove it.

## Common mistakes

- Listing a core skill in `skills_link`: it is already installed.
- A bare absolute `skills_link` path: resolves on one machine only, and
  `check.sh` rejects it.
- Adding a plugin from an unknown marketplace in the profile: the apply
  cannot register it, and a per-profile marketplace makes two config dirs
  fight over one plugins tree.
- Hand-building the repo with `git submodule add` instead of the template:
  the `install.sh` then drifts from the canonical three lines.
- Telling the user `tack sync` will put the profile on their other machines.

## Sharing it

A public profile gets the `tack-profile` topic
(`gh repo edit --add-topic tack-profile`) and can be added to `PROFILES.md` in
the tack repo by PR. Its README should say which plugins and MCP servers it
enables and whether it sets `permissions.defaultMode`.
