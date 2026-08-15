---
name: git-best-practices
description: >-
  Enforce git workflow conventions: commit message format (conventional commits),
  branch naming (feature/, bugfix/, hotfix/), pre-commit checks (lint, tests, docs,
  secrets scan), and pre-push validation (rebase, squash, full tests, CHANGELOG).
trigger:
  - "git commit"
  - "create commit"
  - "ready to push"
  - "create branch"
---

# Git Best Practices

## When to Use

Invoke before `git commit` or `git push`, or when creating a branch. Skip for read-only git commands (`log`, `show`, `diff`, `status`) and for emergency hotfixes the user explicitly overrides with `--no-verify`.

## Conventions

- Commits: conventional commits format (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `revert`), imperative subject, body explains why not what.
- Branches: `<type>/<short-description>`, lowercase-hyphenated (`feature/add-mfa`, `bugfix/login-validation`).
- Before push: rebase on target branch, squash WIP commits, run the project's own lint/typecheck/test/build (whatever it already uses, don't invent a parallel check).

Anything beyond this (secrets scanning, debug-code detection, doc-staleness warnings) is standard practice the model applies by judgment, not a fixed script to run.

**Emergency override**: `--no-verify` skips hooks. Only for true emergencies, and say so when doing it.
