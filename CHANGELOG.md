# Changelog

Versions follow [semantic versioning](https://semver.org/). Until 1.0 a minor
bump can change the manifest contract; the notes say when it does and what an
existing profile needs.

## 0.3.0 (unreleased)

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
