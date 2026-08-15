# Contributing

## The gate

```bash
git add -A && bash scripts/check.sh
```

`check.sh` discovers files through git, so a new file is invisible to it until
staged. That is why `git add -A` comes first.

CI runs `check.sh` and `scripts/test-apply.sh` on both ubuntu and macos. Nothing
else. A green local run of both is a green build.

## What the checks cover

| Check | Why it exists |
|---|---|
| bash and python syntax | |
| JSON parse + manifest contract | a malformed manifest half-applies |
| CRLF lint | jq on Git Bash emits CRLF; a trailing CR makes every comparison fail silently |
| config-root lint | a hardcoded `$HOME/.claude` writes into another terminal's profile |
| sanitize sweep | personal and client data must not ship |
| ghost scope test | ghost must never scan `.md` |
| resolve-link tests | `~` and `$HARNESS_ROOT` expansion in `skills_link` |
| shellcheck (`-S error`) | |
| end-to-end apply | the only test that runs a real apply |

## Ground rules

- Read `CLAUDE.md` first. Its invariants are not style preferences; each one is
  a bug that already shipped.
- bash 3.2 is a target, so no `mapfile` and no associative arrays.
- Runtime dependencies are bash, jq, git and python3. Adding a fourth needs a
  reason in the PR.
- Hooks fail open. Any parse problem exits 0. PreToolUse blocking uses exit 2.
- Every failure message names the fix. "check failed" gives the reader, often an
  agent, nothing to act on.
- Conventional commits. No em-dashes or en-dashes in prose or comments.

## Changing the apply

`lib/apply-profile.sh` is the only thing that rewrites a config dir, and it runs
on every machine through a submodule pin. Any new removal must be reversible and
must print how to undo it. Add a case to `scripts/test-apply.sh` in the same PR.
