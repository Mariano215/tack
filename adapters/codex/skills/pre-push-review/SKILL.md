---
name: "pre-push-review"
description: "Use before pushing, publishing, opening a PR, or when the user asks whether a branch is safe to push."
---

# Pre-Push Review

1. Inspect git status.
2. Review diff for secrets, debug code, accidental files, and risky changes.
3. Run targeted tests and lint commands discovered from repo config.
4. Run security checks when auth, permissions, dependencies, or secrets changed.
5. Summarize blockers before any push.

Do not push to `main`, `master`, `release/*`, or `prod*` without explicit user
approval after review.
