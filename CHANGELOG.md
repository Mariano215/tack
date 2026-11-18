# Changelog

Versions follow [semantic versioning](https://semver.org/). Until 1.0 a minor
bump can change the manifest contract; the notes say when it does and what an
existing profile needs.

## v0.8.1

- `bash-guard.sh` no longer asks before `git push`, `gh pr merge`, `gh release`
  or `gh api` writes. Publishing is left to the permission mode. The guard now
  only denies Bash commands that read secret files and asks when a secret path
  is written in a form it cannot parse.
- The PreCompact hook that only echoed a warning is gone. Claude Code already
  shows when it compacts.

## v0.8.0

- security-guidance and commit-commands are off in `base-settings.json`
  (prompt-only plugins). The dev profile no longer turns them back on, and now
  enables no plugins at all (feature-dev, pyright-lsp, typescript-lsp,
  plugin-dev and code-review dropped; the built-in `/code-review` covers the
  last one). Every plugin in `base-settings.json` is now off.
- `base-settings.json` drops the marketplaces addy-agent-skills, caveman,
  frontend-slides, nateherk, openai-codex, ponytail and ui-ux-pro-max-skill and
  their plugin entries, the `"agent": "task-orchestrator"` default, and
  `CAVEMAN_DEFAULT_MODE`. apply prunes a dropped marketplace from the registry
  unless it is listed in `.harness-marketplaces-keep`.
- The model-router-nudge PreToolUse hook and the security-file-nudge
  PostToolUse hook are gone, with `scripts/test-model-router.sh`. So are the
  agents task-orchestrator and code-security-auditor, and the skills
  smart-agent-spawner, fullreview, repro, git-best-practices and
  security-audit. Use the built-in `/code-review` and `/security-review`.
- Manifest contract: the `caveman` key is removed from the schema, the
  `check.sh` validator and apply. A profile that still sets it is ignored for
  that key; delete the line.
- `templates/CLAUDE.md` drops its Skills section and the "Deliver what was
  asked" line. `templates/AGENTS.md` drops its Communication section.
- Profiles drop the design plugins frontend-design, ui-ux-pro-max and
  frontend-slides. animate and the tool plugins stay.
- The daily update hook no longer upgrades graphifyy or runs
  `graphify install --platform claude`.
- The Codex plugin's graph-stale and security-file-nudge PostToolUse hooks and
  their scripts are gone, so `harness-policy` ships with no active hooks, and
  `templates/AGENTS.md` drops its Graphify section. The `graphify` skill stays.

## v0.7.0

- The UserPromptSubmit skill router is gone: `hooks/skill-router.sh`,
  `hooks/skill-routes.json`, `scripts/test-skill-routes.sh`, and the router
  checks in `verify-setup.sh`, `scripts/drift-report.sh` and `tack tune`
  (the `route_ignored` signal, and `hooks/skill-routes.json` as an allowed tune
  path). Skills now load from their own descriptions.
- Both graphify hooks are gone: the SessionStart `graphify-session.sh` and the
  PostToolUse hook that flagged `graphify-out/` stale. The `graphify` skill and
  the Codex plugin's stale flag stay.
- The vendored superpowers skills are gone (brainstorming, writing-plans,
  executing-plans, subagent-driven-development, systematic-debugging,
  test-driven-development, requesting-code-review,
  verification-before-completion, finishing-a-development-branch,
  using-git-worktrees), with `skills/SUPERPOWERS.md` and
  `scripts/vendor-superpowers.sh`. `task-orchestrator`, `fullreview` and
  `pre-push-auto-fix` no longer name them.
- `templates/CLAUDE.md` is shorter: the methodology-skill lines and the token
  discipline section are dropped, and the coding defaults are cut to two rules.
- `autoMemoryEnabled` is now true in `base-settings.json` (the built-in auto
  memory, not claude-mem, which stays off).
- New core skill `writing-for-agents`, adapted from mattpocock/skills (MIT, license kept in the skill folder): how to write a skill, CLAUDE.md or AGENTS.md so agents follow it.
- bash-guard skips heredoc text written by cat, tee, git commit or git tag (quoted delimiter such as <<'EOF', nothing piped onward, terminator found), so log entries and commit messages no longer trigger false asks or denies. Anything that a shell could run is still checked.
- bash-guard no longer skips heredoc text when the same command has git diff, git log with an output flag, a single &, or a process substitution. These could write the hidden text to a file or run it.
- New core skill `ui-library-picker`: decision rules and checked install commands for shadcn/ui, coss ui, AlignUI, daisyUI, HeroUI and Ant Design.

## v0.6.0

- `hooks/bash-guard.sh` (PreToolUse on Bash): denies commands that read secret files (tokens, keys, credentials) and asks before publishing (push, merge, release, `gh api` writes). Six more `Read()` deny rules cover Claude, gh and fal credential files.
- The daily hook reports instead of applying. It fetches, marks `.harness-update-pending`, and the statusline shows `update waiting: tack sync`. Only `tack sync` applies and clears it.
- Only the newest core writes shared state (`CLAUDE.md`, the `tack` binary, shell aliases). An apply through an older pin leaves them and prints the fix. `verify-setup.sh` warns, not fails, when two profiles' cores differ.
- Apply keeps your own files in `agents/`, `commands/` and `output-styles/`. It removes only what the engine shipped last time (`.harness-managed-engine`).

- ghost decodes hook input as UTF-8. On Windows the cp1252 locale let em-dashes through.
- The plugin auto-update hook takes a machine-wide lock, so sessions that start together no longer race installs and plugin sweeps.
- Profile config dirs are 0700 and their `.claude.json` copies 0600 (they were 0644 and carry every project's MCP env).
- `tack tmux` clears `CLAUDE_CONFIG_DIR` for the pane and handles `.` and `:` in names; `tack open` matches its session name exactly.
- The plugin auto-update hook runs `graphify install` against the shared
  config dir. In a profile it wrote that profile's skill path into the shared
  `CLAUDE.md`, because the profile's `CLAUDE.md` is a link to it.
- An apply through an older core pin no longer downgrades `~/.local/bin/tack`.
  It refreshes only a `tack` that the pinned core's history contains, and
  otherwise prints `tack left as it is` with the fix (`tack sync --push`).
- `tack tmux` opens a new session on every run (`audit`, `audit-2`, ...).
  It used to attach to the session of the same name, so every terminal that
  ran it mirrored the same input.
- `tack tmux` and `tack shell` take `--login <tag>`: a separate config dir
  (`<name>@<tag>`) and keychain slot, so one profile can run on a second
  Claude login.
- Codex installs `read-document` too. Its SKILL.md no longer assumes
  Claude Code's Read tool or config path.
- `tack tune`: a weekly self-tuning job modeled on google-research/harness2.
  It mines the last 7 days of transcripts, drafts cited edits to skills,
  agents, commands and skill routes, drops uncited and single-session edits,
  and opens a draft PR labeled `tack-tune`. Closed PRs feed a ledger that
  blocks the same proposal next week. `--install-schedule` adds macOS launchd
  jobs (Sunday 02:00 run, 08:00 Telegram report with PR buttons).
- claude-mem telemetry and error reporting are off: base env sets
  `CLAUDE_MEM_TELEMETRY` and `CLAUDE_MEM_TELEMETRY_ERRORS` to false, and the
  setup script exports both for the worker it starts.

## 0.5.1 (2026-10-10)

- New skill `read-document`: `docmd` converts Word, Excel, PowerPoint,
  OpenDocument, RTF, EPUB and long text PDFs to Markdown on the machine with
  anydoc (`pip install --user firecrawl-anydoc`), so the agent can read files
  the Read tool cannot open. It never uses anydoc's hosted OCR. A skill-router
  route sends a prompt that names one of these files to the skill.

## 0.5.0 (2026-10-07)

- Mods: `mods/` ships `agent-graph` (live subagent tree above the prompt)
  and `agent-dock` (`/dock N` picks the helper team), served by this repo as
  the `tack-mods` marketplace. Both are off; turn one on in a profile
  manifest. `scripts/check.sh` validates and tests each mod when the claude
  CLI is present, and refuses a changed mod whose version did not go up.
- Status line: the full layout is now three rows (location, model and
  context, limits and cache and cost) so each row fits an 80 column terminal.
  The third row is dropped when it has nothing to show. The compact layout is
  unchanged.

## 0.4.1 (2026-10-03)

- Prompt audit of the skills, agents and output style: fixed conflicts, dead
  references, expired dates, `trigger:` frontmatter that never routed, emoji
  and em-dash report templates, and the update suppressor in the Plain style.
  The vendor script carries the local patches for the vendored skills.
- Status line: cache segment (hit ratio and time until the prompt cache goes
  cold, with the miss cause), session cost and time, a context sparkline, and
  green, yellow and red percentages. `TACK_STATUSLINE=compact`, a
  `.statusline-mode` file, or `COLUMNS` under 100 gives a one-line layout. One
  `jq` call instead of about twenty, so a run takes a fifth of the time.
  `statusLine.refreshInterval` is 30 so the countdown ticks while idle.
  Needs Claude Code 2.1.251 for `prompt_cache`; older versions just omit it.
- New seed manifest `profiles/design`: Playwright and frontend-design, for UI
  work checked against a brand DESIGN.md. The skills live in the profile repo.

## 0.4.0 (2026-09-29)

- `tack use` now writes `CLAUDE.md` in the config dir. The engine instructions
  from `templates/CLAUDE.md` go between `<!-- harness:begin ... -->` and
  `<!-- harness:end -->`, and each apply refreshes only that block. Text
  outside the markers is yours and is kept, line endings included. Before this,
  `templates/CLAUDE.md` was only copied to `templates/` and nothing wrote the
  live file, so a hand-kept copy drifted from the engine.
  **Existing installs:** the first apply over a `CLAUDE.md` you wrote puts the
  block on top, saves the old file as `CLAUDE.md.harness-prev`, and prints the
  undo command. Delete any of your sections that now repeat the block. A
  `python3` failure leaves the file as it was and does not stop the apply.

- `templates/CLAUDE.md` is now the managed block, not a starter file. It adds
  the `code-reviewer` exception to the no-self-check rule, delegation by the
  shape of the work, and a code lookup order (graphify, then LSP or tokensave,
  then grep). The slash forms name the real skills: `/pre-push-auto-fix` and
  `/document-with-goal`.

- New `scripts/test-claude-md-render.sh`, run by `check.sh`.

## 0.3.0 (2026-09-29)

- The `model-router-nudge` PreToolUse hook now pins a model on an `Agent` or `Task`
  call that names none: haiku for `Explore`, opus for `Plan`,
  `code-reviewer` and `code-security-auditor`. An explicit model always wins.
  Hooks cannot change the main session's model or effort, and an injected
  `ultrathink` did not reliably raise thinking in a measured test, so the
  orchestrator is left alone.

- New `graphify-session` SessionStart hook. With `GRAPHIFY_AUTO=1` in a
  profile's env, it builds or refreshes the graphify code graph in the repo
  (AST only, no LLM, runs detached) and tells the model to query the graph
  first, the LSP tool for exact symbols, and grep last. It keeps
  `graphify-out/` out of commits through `.git/info/exclude`. Off by default.
- The stale-graph note after a write now names `graphify update .` (no LLM)
  instead of the LLM-backed `/graphify --update`.
- The daily update runs `graphify install --platform claude`, so the Claude
  skill tracks the installed package.

- `verify-setup.sh` warns when an enabled LSP plugin (TypeScript, Pyright,
  C#) has no server program on PATH, and prints the install command. Before,
  the plugin loaded, started nothing, and edits lost their diagnostics with
  no message.

- The daily update no longer pulls core past the profile's pin. It ran
  `submodule update --remote`, then re-applied through `install.sh`, which
  snaps core back to the pin: the pull was thrown away and the profile repo
  was left dirty. Core now moves only through a pin bump (`tack sync --push`).

- The skill router skips background-task notifications, which pass through
  `UserPromptSubmit` and sent the model to graphify or document-with-goal on
  agent reports with no request from the user. The pre-push,
  knowledge-graph, tdd, bugfix, docs and codebase-review patterns now need an
  action plus an object, or a bug-report shape ("crashes", "is failing"),
  instead of a bare noun. A replay of 1,500 real prompts went from 58 matches
  at about 53% wrong to 38 with about 5 doubtful. `test-skill-routes.sh`
  carries the real misfires as negative cases.

- The superpowers methodology skills are vendored from 6.4.1 by
  `scripts/vendor-superpowers.sh`: brainstorming, writing-plans,
  executing-plans, subagent-driven-development, systematic-debugging,
  test-driven-development, requesting-code-review,
  verification-before-completion, finishing-a-development-branch and
  using-git-worktrees. The plugin's SessionStart bootstrap, which orders a
  skill on "even a 1% chance" and over-triggers on Claude 5 models, is left
  out. Local patches: the brainstorming description drops "You MUST use",
  and subagent-driven-development defers model tier and its retry cap to
  `smart-agent-spawner` (3 rounds, not 5). See `skills/SUPERPOWERS.md`.
- `goal-iteration` is removed; it only pointed at those skills. Routes go to
  `brainstorming`, `systematic-debugging` and `test-driven-development`, and
  the `verify-setup.sh` router probe follows.
- The `dev` and `web` profiles no longer enable
  `superpowers@claude-plugins-official`. **Profile action:** remove it from
  your own manifest too, or the bootstrap comes back alongside the vendored
  skills.
- `templates/CLAUDE.md` points at the vendored skills by name and says their
  spec, plan and implementer self-review checklists are artifact checks, not
  the second verification pass it forbids.
- Not ported from the private engine: rendering `templates/CLAUDE.md` into
  the live CLAUDE.md on every apply. Here the template is a user-owned
  starter, and tack never writes the live CLAUDE.md.

- Delegation is decided by the shape of the work, not by call count. Work that
  reads a lot and returns a little (search, log or test triage, review) and
  specified implementation units go to a subagent, so the noise stays out of
  the main context. Decisions, plans and small edits stay in the main thread.
  Changed in `task-orchestrator`, `smart-agent-spawner` and the
  `model-router-nudge` hook. The orchestrator roster now names agents that
  exist instead of six that were never shipped.

- New `code-reviewer` agent: a read-only, fresh-context reviewer of a
  checkpoint diff against the plan. It flags only correctness, requirement and
  trust-boundary gaps. `code-security-auditor` is now read-only too.
- The orchestrator's New Feature workflow is a checkpoint loop: plan split
  into small checkpoints; each is built by a subagent, reviewed by
  `code-reviewer` until it approves, and committed only after the user
  approves. Large features suggest `/clear` and build from the saved plan.

- `smart-agent-spawner` effort guidance follows Opus 5.5: the default effort
  is `medium`, not `high`, and Opus 5.5 at `medium` beats Opus 5 at `high`, so
  the Opus tier now starts there. Thinking cannot be disabled at any effort
  level, and the Opus/Sonnet price gap is about 1.3x.

- Base settings turn off `syncClaudeAiPlugins` and `syncClaudeAiSkills`.
  Since Claude Code 2.1.275 the plugins and skills enabled on the claude.ai
  account load into every terminal session outside `enabledPlugins`, so a
  profile could not filter them, and each one can bring its own MCP servers.
  `verify-setup.sh` fails when either key is not false and names the fix.
  claude.ai connectors are left on; set `disableClaudeAiConnectors` yourself
  if you want those gone too.

- `scripts/context-cost.sh` prints what the harness costs in every request,
  per layer: memory files, skill descriptions, subagent descriptions, and
  with `--run-hooks` the SessionStart output. Skills are usually the largest
  and the least visible, because every enabled skill advertises its
  description on every turn whether or not it is ever invoked. It counts each
  enabled plugin once at its installed version, since the plugin cache keeps
  every version ever pulled, and it reads each plugin's hooks file from its
  `plugin.json` rather than assuming `hooks/hooks.json`.
- `check.sh` fails when `enabledPlugins` in the live `settings.json` is not
  what an apply would produce, meaning base-settings plus the active
  profile manifest's plugins. It only compares when this repo is the engine
  that produced that config.
- Fixed `tack open --herdr` creating a duplicate workspace instead of
  focusing the open one. `label` is a jq keyword, so `--arg label` made the
  workspace lookup a compile error on every call.

- `tack --help` has a "New profile" section: ask the agent, which uses
  `harness-builder`, or follow Walkthrough 3 by hand.
- CI runs `scripts/check.sh` only; the separate apply job ran the same
  apply twice per OS.

## 0.2.0 (2026-09-11)

tack now drives Codex as well as Claude Code, from the same profile.

### Added

- **Codex provider.** `tack use <name>` applies the profile to every installed
  agent CLI and skips a missing one with a message. The Codex adapter
  (`adapters/codex/`) renders `$CODEX_HOME/<name>.config.toml` without touching
  your base `config.toml`, merges a marked policy block into `AGENTS.md`,
  installs Codex-native workflow skills with a backup on any collision,
  registers the repo-local `harness-policy` plugin, and verifies what it wrote.
- **`tack open <name>`** starts Claude and Codex together in one tmux or Herdr
  workspace, in the current directory, and reuses it on the next run. Flags:
  `--claude`, `--codex`, `--cwd`, `--detach`, `--dry-run`, `--tmux`, `--herdr`.
- **Manifest schema v2.** Shared intent (`mcp`, `memory`) stays at the top
  level; agent-specific settings move under `providers.claude` and
  `providers.codex`. The five bundled profiles are v2.
- **`codex` shell wrapper.** Bare `codex` starts with the active tack profile;
  `codex -p <other>` still wins. PowerShell gets the same function.
- **`harness-builder` skill.** Research, design and build a new profile with
  the agent, with an approval gate before anything is written.
- **`goal-iteration` skill,** which pairs the superpowers methodology skills
  with the built-in `/goal` loop.
- `tack sync` resets a profile whose only local commits are core pin bumps
  onto upstream, keeping an undo branch, instead of stopping on that
  divergence every run.
- The apply names `.harness-marketplaces-keep` before it removes a
  marketplace, not after.
- 23 more phrase patterns in `ghost/patterns.json`, and the scope test now
  compiles every pattern.
- Tests: Codex apply, provider selection, memory provider choice, Codex
  plugin hooks, `tack open`, sync pin reset. All run from `scripts/check.sh`.
- `sanitize-check.sh` strips a trailing CR from each pattern line. On a CRLF
  checkout every pattern ended in CR and the sweep reported clean while
  matching nothing. `scripts/test-sanitize-crlf.sh` holds the line.
- Windows: the suites run on Git Bash (tool wrappers instead of copied
  launchers, and a real batch file for the `.cmd` installer case).

### Changed

- `base-settings.json` caps subagent spawn depth at 2 and concurrency at 4.
- Prompt files follow the current Claude guidance: `check.sh` fails on retired
  patterns such as "you MUST use" and "double-check your work".
- The skill router sends test, debug and build prompts to `goal-iteration`.

### Removed

- `build-with-goal`, `debug-with-goal` and `tdd-with-goal` Claude skills, and
  `skills/goal-safety-config.json`. `goal-iteration` replaces them. Codex keeps
  its own versions under `adapters/codex/skills/`.

### Upgrading a profile

A v1 manifest (top-level `plugins`, `env`, `permissions`) keeps working
unchanged; Codex then receives only the shared intent. To configure Codex,
move those keys under `providers.claude`, add `"schema_version": 2` and a
`providers.codex` block. See `profiles/dev/manifest.json`.

## 0.1.0 (2026-08-29)

First public release: the Claude Code profile engine.

- `tack use`, `shell`, `tmux`, `herd`, `install`, `sync`, `status`.
- Isolated config dirs per terminal that share one login and one plugins tree.
- First-apply guard that lists what would be replaced and stops, and an apply
  lock that waits instead of failing a second terminal.
- Opt-in shell aliases (`--no-api-key`, `--yolo-alias`).
- Plugin auto-update, marketplace dependencies, a Windows launcher.
- `.agent/` plan and session-summary capture.
- `ghost` prose gate for `.txt`, `.docx`, `.pdf`.
