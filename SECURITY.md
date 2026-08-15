# Security

## Reporting

Report a vulnerability through GitHub's private advisory form on this repo
(Security > Report a vulnerability). Please do not open a public issue for
anything exploitable.

## What this tool does to a machine

Worth knowing before you audit it:

- **`apply-profile.sh` deletes directories.** It removes and rewrites `hooks`,
  `ghost`, `agents`, `commands`, `templates`, `scripts` and `output-styles`
  inside the target config dir, and quarantines undeclared skills to
  `skills-disabled`. On a config dir it has never composed, it refuses and asks
  first. `--force` skips that prompt.
- **It writes outside the config dir.** `$HOME/.local/bin/tack` (the switcher),
  `$HOME/.claude/.harness-apply.lock` (machine-wide apply lock), and your shell
  rc files if you run `setup-core.sh`.
- **It registers and removes plugin marketplaces** through the `claude` CLI, to
  match `base-settings.json`. Marketplaces you want kept go in
  `.harness-marketplaces-keep`.
- **Profiles execute code.** `tack use <name>` runs that profile repo's
  `install.sh`. Treat a profile repo exactly like any other repo you would run a
  script from.
- **`--yolo-alias` is off by default** and aliases `claude` to
  `--dangerously-skip-permissions`, which removes the confirmation prompt on file
  writes and shell commands. Turn it on only if you understand that.

## Secrets

Nothing here reads or transmits credentials. `CLAUDE_SECURESTORAGE_CONFIG_DIR`
is exported empty so isolated profiles reuse the existing keychain entry rather
than creating a second one.

`scripts/sanitize-check.sh` runs in CI and fails the build on home paths, common
key shapes and consumer email domains. Add your own patterns in
`.sanitize-patterns` and denied commit-author domains in
`.sanitize-authors-deny`; neither file needs to be public.
