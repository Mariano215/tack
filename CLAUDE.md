# tack: repo contributor instructions

This is the engine. Every machine running a profile pulls it through a git
submodule, and the hook that would heal a broken apply heals by running the
apply. A bad commit here does not fail on one workstation, it fails on all of
them.

## Before every commit

```bash
bash scripts/check.sh
```

It runs shell and python syntax checks, JSON parsing, the manifest contract,
the CR lint, the sanitize sweep, the resolve-link tests, and shellcheck when
installed. CI runs the same script and nothing else, so a green local run is a
green build.

Note that `check.sh` discovers files through git, so a new file is invisible to
it until staged. Run `git add -A` first.

## Invariants

- **Never pipe a bare `jq -r` onward.** jq on Git Bash emits CRLF, so a value
  read into a variable or a `while read` loop carries a trailing CR and every
  comparison against it silently fails. Append `| tr -d '\r'`.
- **Shell scripts are LF only.** `.gitattributes` enforces it. Do not add
  exceptions; `verify-setup.sh` fails a machine whose shebangs carry CR.
- **`apply-profile.sh` is destructive by design.** Any new removal must be
  reversible and must print how to undo it. The existing patterns are
  quarantine to `skills-disabled` with a `.harness-skills-keep` escape hatch,
  and `.harness-prev-settings.json` for settings. A config dir the harness has
  never composed gets a confirmation prompt first; that gate keys on
  `.harness-base-settings.json` and must not be weakened.
- **`base-settings.json` owns `enabledPlugins` and `extraKnownMarketplaces`,**
  and a profile that declares `permissions.defaultMode` owns that too.
  `personal-overrides.json` must never win on a profile-owned key. When it
  tries, say so on stdout rather than merging quietly.
- **Every check in `verify-setup.sh` must name the fix.** The reader is often
  an agent, and "check failed" gives it nothing to act on. Match the style of
  the CRLF and marketplace-drift messages.
- **The config root is `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, never a bare
  `$HOME/.claude`.** `tack shell` runs a second profile in another terminal by
  exporting that variable, so a hardcoded path writes into the other terminal's
  config dir, and the SessionStart heal repeats it daily. `check.sh` enforces
  this over `lib/ hooks/ ghost/ bin/tack verify-setup.sh statusline-command.sh`
  and over the hook commands in `base-settings.json`. State that is genuinely
  machine-wide (the login, the plugins tree, `.harness-root`, the apply lock)
  stays on `$HOME/.claude` and carries a `harness:shared` comment on the line.
- **Exactly one `base-settings.json` per machine.** Profiles share one plugins
  tree, so a profile-specific `extraKnownMarketplaces` would make two config
  dirs fight: A's apply prunes a marketplace, B's `verify-setup.sh` fails, B's
  heal re-adds it, A prunes it again, forever.
- **Runtime dependencies are bash, jq, git, python3.** Nothing else. bash 3.2
  is a target (macOS), so no `mapfile`, no associative arrays.
- **Hooks are fail-open.** Any parse problem exits 0. PreToolUse blocking uses
  exit 2, nothing else.
- **ghost checks deliverable formats only.** `scan_extensions` is `.txt`,
  `.docx`, `.pdf`. Markdown is excluded on purpose: `.md` is internal (notes,
  READMEs, plans, skills), and a block costs a full rewrite of the file, so
  scanning it burned tokens on prose no one read. Do not add `.md` back.
  `scripts/test-ghost-scope.sh` holds the line.
- **Do not parse a CLI's human output.** `git rev-parse`, `jq`, and exit codes
  survive locale changes and upstream rewording; grepping for "Fast-forward"
  does not.
- **Nothing user-specific ships here.** `scripts/sanitize-check.sh` is the gate.
  Fork it by adding `.sanitize-patterns` with your own names rather than editing
  the script.

## What installs where

`apply-profile.sh` copies `hooks ghost agents commands templates scripts
output-styles` plus `verify-setup.sh` and `statusline-command.sh` from this repo
into the config dir. `lib/` is never copied, so nothing in `lib/` can be shared
with an installed script. A profile repo contributes only its `skills/` and its
manifest.

The Codex adapter (`adapters/codex/`) writes `$CODEX_HOME/<name>.config.toml`,
a marked block in `AGENTS.md`, its skills under `$CODEX_HOME/skills` (backing
up a collision first) and `.harness-active`. It never writes the base
`config.toml` itself; the Codex CLI does, when it registers the repo
marketplace and plugin.

## Style

Conventional commits. No em-dashes or en-dashes anywhere, prose or comments.
The ghost hook only blocks writes to `.txt`, `.docx` and `.pdf`, so nothing in
this repo is enforced automatically. Hold prose, comments and commit messages to
the standard by hand.
