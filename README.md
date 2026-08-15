# tack

Run a different Claude Code setup in every terminal.

```bash
tack tmux dev      # terminal 1: engineering plugins, LSPs, security skills
tack tmux video    # terminal 2: different plugins, different MCP servers, different permissions
```

Both sessions share one login and one plugins tree. Neither can overwrite the
other's config. Switching is one command, and the whole setup is a git repo you
can hand to a teammate.

## Why

Everything enabled in Claude Code costs context on every single session. Plugins,
skills, MCP servers and hooks all load whether the current task needs them or
not. The usual answer is to enable a superset and live with the tax, or to toggle
things by hand and forget what you changed.

A **profile** is a recipe: a set of plugins, MCP servers, env vars, permissions
and settings, kept in a git repo. `tack use <name>` composes your config dir from
it. `tack shell <name>` does the same in an isolated config dir so it only
affects that terminal.

What that buys:

- **Less context per session.** Load the eight plugins the work needs, not the
  forty you have installed.
- **Two kinds of work on one machine.** Frontend work wants Playwright and
  chrome-devtools MCP. Writing work wants neither and a stricter permission mode.
- **Reproducible across machines.** A profile repo pins the engine as a submodule,
  so every workstation converges on the same applied state. `tack sync` pulls,
  advances the pin, and re-applies.
- **Separation you can point at.** Client work and personal work in distinct config
  dirs with distinct permissions.

This is not a dotfiles sync tool. If all you want is one `~/.claude` mirrored
across machines, use [chezmoi](https://www.chezmoi.io/) or
[claude-code-dotfiles](https://github.com/elizabethfuentes12/claude-code-dotfiles).
tack is for running more than one setup.

## Install

Requires bash, git, jq, python3, and the `claude` CLI. bash 3.2 is supported, so
macOS works without upgrading bash.

```bash
git clone https://github.com/Mariano215/tack.git
cd tack
./setup-core.sh ~/Projects
```

That puts `tack` on your PATH at `~/.local/bin` and records where profile repos
live. It does not touch your config dir yet.

Then get a profile. Start from the template:

```bash
export HARNESS_ORG=your-github-account
# fork https://github.com/Mariano215/tack-profile-example to <your-account>/tack-dev
tack install dev
```

### Read this before your first apply

`tack use` is destructive by design. It deletes and rewrites these directories in
your config dir:

```
hooks/  ghost/  agents/  commands/  templates/  scripts/  output-styles/
```

and moves any skill the profile does not declare into `skills-disabled/`.
`settings.json` is backed up to `.harness-prev-settings.json`. **The seven
directories above are not backed up.**

If your config dir already has content, the first apply stops and shows you
exactly what it would replace. It only proceeds when you type `yes` or pass
`--force`. Back up first if you have hand-written hooks or commands:

```bash
cp -R ~/.claude ~/claude-backup
```

To keep specific skills across applies, list them one per line in
`~/.claude/.harness-skills-keep`. Same idea for marketplaces in
`~/.claude/.harness-marketplaces-keep`.

### Optional shell aliases

Both are off by default because both change how `claude` runs in every shell:

```bash
./setup-core.sh ~/Projects --no-api-key   # blank ANTHROPIC_API_KEY, forcing subscription auth
./setup-core.sh ~/Projects --yolo-alias   # point the alias at --dangerously-skip-permissions
```

`--no-api-key` is right on a Max subscription and will break you if you pay by
API key.

## Commands

| Command | What it does |
|---|---|
| `tack list` | Profiles found, with the active one marked |
| `tack use <name>` | Apply a profile to the current config dir |
| `tack shell <name>` | Apply into an isolated config dir and open a subshell there |
| `tack tmux <name>` | Same, wrapped in `tmux new -As <name>` |
| `tack herd <name>` | Same, as a Herdr workspace |
| `tack install <name>` | Clone `$HARNESS_ORG/tack-<name>` and apply it |
| `tack sync [--push]` | Pull every profile, advance its engine pin, re-apply the active one |
| `tack status` | Active profile, isolated config dirs, MCP servers, plugin count |

## How isolation works

`tack shell dev` creates `~/.claude-profiles/dev` and exports `CLAUDE_CONFIG_DIR`
at it. Claude Code resolves settings, sessions and `.claude.json` under that
variable, so the two terminals never see each other's config.

Shared back to `~/.claude` by symlink, on purpose:

- `plugins/` (roughly 3 GB, and a per-profile copy means re-cloning every marketplace)
- `CLAUDE.md`, `personal-overrides.json`, and the two keep-lists

`CLAUDE_SECURESTORAGE_CONFIG_DIR` is exported **empty**, which is the only value
that maps back to your existing keychain entry. Any path there, including
`~/.claude`, hashes to a second credential slot and asks you to log in again.

## Writing a profile

A profile repo is `tack-<name>` containing:

```
manifest.json     what to enable
install.sh        three lines: update the submodule, run the apply
core/             this repo, as a git submodule
skills/           your skills, copied into the config dir on apply
```

The manifest:

```json
{
  "name": "dev",
  "description": "Full-stack engineering",
  "plugins": { "superpowers@claude-plugins-official": true },
  "mcp": ["context7"],
  "env": {},
  "permissions": { "defaultMode": "auto" }
}
```

`profiles/` in this repo holds five working examples: `dev`, `minimal`,
`proposal`, `video`, `web`. They ship with an empty `skills/` because skills are
yours; the profile is the recipe around them.

`scripts/scaffold-profiles.sh` generates the repo structure if you would rather
not build it by hand.

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `HARNESS_ORG` | unset | GitHub account `tack install` clones from |
| `HARNESS_PROFILE_PREFIX` | `tack-` | Profile repo name prefix |
| `HARNESS_ROOT` | `~/Projects` | Where profile repos live |
| `HARNESS_PROFILE_HOME` | `~/.claude-profiles` | Where isolated config dirs live |
| `HARNESS_ALIAS_NAME` | `claude-code` | Name of the convenience alias |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Config dir an apply writes to |

## What ships here

The engine (`bin/tack`, `lib/`, `hooks/`, `verify-setup.sh`), a set of
general-purpose skills (TDD, debugging, docs, security audit, prompt-injection
defense, code review, knowledge graphs), and `ghost`, a hook that blocks
LLM-tell phrasing in `.txt`, `.docx` and `.pdf` writes. Edit
`ghost/patterns.json` to make that list yours.

## Contributing

`bash scripts/check.sh` before every commit. CI runs the same script and nothing
else, so a green local run is a green build. See `CLAUDE.md` for the invariants,
several of which exist because the thing they prevent has already shipped as a
bug.

## License

MIT. See `LICENSE`.
