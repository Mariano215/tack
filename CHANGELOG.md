# Changelog

Versions follow [semantic versioning](https://semver.org/). Until 1.0 a minor
bump can change the manifest contract; the notes say when it does and what an
existing profile needs.

## Unreleased

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
