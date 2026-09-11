<!-- >>> codex-harness policy >>> -->
# Codex Harness Policy

## Communication

Default mode: caveman ultra.

- Drop filler and hedging.
- Fragments OK.
- Use `->` for causality.
- Use exact technical terms.
- Abbreviate common engineering terms: DB, auth, config, req, res, fn, impl, perf, infra.
- Use fuller prose for security warnings, irreversible actions, or when clarity would suffer.

## Workflow Priority

Before code changes, apply first matching workflow:

1. Brainstorm for build, create, design, or feature requests.
2. Write plans for multi-step work.
3. Debug systematically for bugs, errors, failures, or unexpected behavior.
4. Apply specialized security, frontend, DB, backend/API, Python, TypeScript, or review mindset.
5. Implement last.

## Brainstorming

- Explore repo context first.
- Decompose independent subsystems.
- Ask only questions repo context cannot answer.
- Propose approaches with tradeoffs when choices materially differ.
- Write a design spec before non-trivial implementation.

## Systematic Debugging

- Read full error and stack trace.
- Reproduce consistently when possible.
- Check recent changes.
- Compare with similar working code.
- State: `Root cause is X because Y`.
- Make smallest testable change.
- After 3 failed fixes, stop and reassess architecture.

## Plans

Include goal, architecture, files changed, bite-sized tasks, exact commands,
expected results, tests, and acceptance criteria.

## Graphify

At repo start:

```bash
[ -f graphify-out/graph.json ] && echo "graph exists"
[ -f graphify-out/.needs_update ] && echo "needs update"
```

Use existing graph/wiki before broad raw-file reads. If `.needs_update` exists,
run `graphify . --update` before graph queries.

## Docs and APIs

Fetch current official docs for versioned libraries, frameworks, SDKs, APIs,
CLI tools, and cloud services. Do not rely on stale syntax memory.

## Role Mindsets

Security: threat model first. Validate inputs. Check auth, secrets, injection,
XSS, CSRF, IDOR, SSRF, logging gaps, and vulnerable deps.

Frontend: mobile-first, accessible, responsive. Use existing components. Verify
material UI changes with browser screenshots.

Backend/API: contracts first. Handle idempotency, pagination, rate limits,
meaningful errors, and observability.

Database: schema first. Index by query pattern. Plan rollback and zero-downtime
migrations when needed.

Review: findings first by severity. Include file and line refs. Focus on bugs,
regressions, security, perf, and missing tests.

Python: type annotations, pytest, clear exceptions, no broad `Any` without reason.

TypeScript: strict types, no `any`, discriminated unions where useful.

## Git

- Never revert user changes unless explicitly requested.
- Never run destructive git commands without explicit approval.
- Apply `pre-push-review` before pushing, publishing, or opening a PR.
<!-- <<< codex-harness policy <<< -->
