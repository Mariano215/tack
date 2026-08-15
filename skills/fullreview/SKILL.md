---
name: fullreview
description: Comprehensive multi-domain code + security + ops review driven by parallel agent teams, looped until clean. Use when the user types /fullreview or asks for a "comprehensive review", "full review", "full audit", "ship-readiness audit", or wants multiple domains (security, backend, frontend/backend sync, background jobs, service integrations, perf, observability, migrations, config, telemetry) reviewed simultaneously across several iterations.
trigger: /fullreview
---

# /fullreview — Comprehensive Multi-Domain Review

Dispatch parallel agent teams across every domain that matters, consolidate findings, fix CRITICAL/HIGH issues, and loop until clean or the iteration budget is exhausted.

## Usage

```
/fullreview                     # full pipeline on current project (default: 5 loops)
/fullreview --loops 3           # cap iterations at 3 instead of 5
/fullreview --max-loops 5       # same thing
/fullreview --scope security    # single-domain review, still looped
/fullreview --scope backend,jobs  # multi-domain, only listed
/fullreview --no-fix            # report only, never edit code
/fullreview --fast              # skip the 5 "extra" domains (perf, observability, etc.)
```

## Required behavior

The agent running this skill must:

1. **Invoke** `superpowers:dispatching-parallel-agents` and `superpowers:verification-before-completion` skills up-front (they govern parallel dispatch and the "claim clean only with evidence" gate).
2. **Track progress** via TaskCreate/TaskUpdate with one task per loop. Mark in_progress when starting, completed when done. Never claim "clean" without running the verification command in the same message.
3. **Capture baseline** before any review: detect and run the project's typecheck and test commands (e.g. `npm run typecheck && npm test`, `pytest`, `cargo test`, `go test ./...`), save exit codes, save test counts. Abort with a clear message if the baseline is already broken and tell the user to fix the baseline first.
4. **Dispatch review agents in parallel** in a single message with multiple Agent tool calls. Each agent is read-only — it produces findings, it does NOT edit code. The coordinator does all edits.
5. **Consolidate findings** into `.reviews/loop{N}-findings.md` — dedupe across agents, sort by severity.
6. **Fix CRITICAL/HIGH issues** in the coordinator session (verify each finding by reading the actual code before editing). Use Edit, not Write, for existing files.
7. **Re-run typecheck + tests** after each fix batch. If red, fix before moving on.
8. **Loop** until either (a) the latest loop returns zero CRITICAL and zero HIGH findings, or (b) the iteration budget is hit. Early loops fix structural problems; later loops sweep for regressions.
9. **Final verification**: fresh typecheck and test run with evidence in the output, then a summary table.

## Agentic product detection (before dispatch)

Before dispatching, check whether the product under review is itself agentic: grep for LLM SDK usage (`anthropic`, `openai`, `@anthropic-ai`, `langchain`, `litellm`, model IDs like `claude-`/`gpt-`), MCP servers or clients, tool/function-call schemas, agent loops, and prompt/instruction files (CLAUDE.md, AGENTS.md, system prompts in code or config). If any hit, add domain 11 below to the dispatch set. Most products reviewed will qualify; absence of all markers is the only reason to skip it.

## Standard review domains (10 agents by default)

Dispatch all 10 agents in parallel in a single message. Each gets a focused, self-contained prompt with exact files to review.

### 1. Security / auth / permissions / tokens
- Auth middleware chain coverage on every route — no unguarded endpoints
- Role/permission enforcement on every read and write path
- Multi-tenant data leaks: list/read helpers that return rows from wrong tenant
- Cross-tenant writes: body/query tenant ID overrides not validated server-side
- Token handling: hashed storage, timing-safe compare, log scrubbing, rotation
- WebSocket auth: ticket single-use, nonce replay prevention
- Cookie flags (httpOnly, Secure, SameSite)
- SQL injection / prototype pollution / JSON.parse on user input
- Dev bypasses and env var fallbacks that silently weaken prod security

### 2. Backend routes + DB code quality
- SQL: missing indexes, N+1 queries, LIMIT on potentially large result sets, prepared statement caching
- Error handling: unhandled promise rejection, stack traces leaked to clients, `.catch(() => {})` silent swallow
- Race conditions: UPDATE-then-SELECT, serialization assumptions, transaction usage
- Schema drift across multiple databases or services, migrations with `IF NOT EXISTS`
- Type/contract drift between handlers and callers
- Input validation on every POST/PUT/PATCH body (Zod, Joi, class-validator, etc.)
- Timestamp units (ms vs s) — audit every place that mixes them

### 3. Frontend ↔ backend contract sync
- Every frontend `fetch(...)` call resolves to a real backend route with matching method, path, body shape, response shape
- Orphan backend routes with no caller
- WebSocket event type/shape drift between emitters and handlers
- Auth header / cookie consistency across all requests
- Tenant/scope ID propagated correctly on every scoped endpoint
- Cache-bust query strings on static assets vs deploy date

### 4. Background jobs + scheduled tasks
- Job/task state machine: valid transitions, stuck states, orphan job recovery
- State updated BEFORE job execution (prevents double-fires on restart or crash)
- Backlog storm protection on startup: missed jobs during downtime should not all fire at once
- Stale/timed-out job enforcement (jobs stuck in-progress indefinitely)
- Cron expression correctness, TZ/DST handling
- Graceful shutdown: in-flight jobs complete, no new jobs accepted during drain
- Retry + backoff strategy: max attempts, exponential delay, dead-letter handling
- Concurrency limits: queue depth cap, worker saturation handling

### 5. External integrations + API clients
- Every outbound API call has a timeout, retry with backoff, and error boundary
- API secrets/tokens never logged or included in error messages
- Inbound webhook signature verification (HMAC, shared secret, replay window)
- Outbound rate limit handling (429 with Retry-After respected)
- Circuit breaker or graceful degradation when external service is unavailable
- API client initialization: credentials validated at startup, not silently absent
- Idempotency keys on state-mutating outbound calls where supported
- SDK/client version pinned; deprecated endpoints flagged

### 6. Performance + resource leaks
- setInterval / setTimeout that never get cleared (leak on teardown or restart)
- Unbounded Promise.allSettled / parallel execution (concurrency cap missing)
- DB prepared statements re-compiled inside request handlers (should be module-level)
- DB WAL / file growth unbounded
- WebSocket client set that never removes disconnected clients
- In-memory caches with no size cap or TTL (memory leak)
- Long-running queries without LIMIT in hot paths
- File handles / child processes left open

### 7. Observability + logging
- PII in logs (tokens, secrets, user content not scrubbed)
- Structured logging consistency (right field names, right level)
- Missing audit log on security-critical mutations (auth changes, permission changes, config changes)
- Noisy logs drowning real signal (info-level on every routine tick vs debug)
- Error events without sufficient context to triage (missing request ID, user ID, resource ID)
- Metric/event attribution gaps (events missing correlation IDs or tenant context)

### 8. Migration + schema safety
- Every ALTER TABLE wrapped in try/catch for re-run safety, or uses `ADD COLUMN IF NOT EXISTS` where supported
- Schema drift across services or DB replicas — run a diff
- Deploy path: does the deploy script run migrations on remote, or are tables `CREATE TABLE IF NOT EXISTS`?
- Column renames on one side only
- Dropped columns still referenced in code
- Check constraints present where the code relies on domain values

### 9. Config + env validation
- Every env var used anywhere is validated on boot (presence, length, format)
- Production requires strict config (NODE_ENV=production forbids dev bypasses, insecure defaults)
- Secret handling: key length validated, never logged
- Default values that silently weaken security (empty string secrets, localhost-only fallbacks)
- Config drift between .env.example and actual usage

### 10. Telemetry + event tracking
- Every significant user action and system event is recorded with enough context to reconstruct what happened
- Events include: actor, resource, action, outcome, timestamp — nothing critical omitted
- Analytics aggregations (counts, rollups) match raw event totals when spot-checked
- Timestamps consistent throughout: same unit (ms or s), same timezone (UTC)
- No PII in event payloads unless explicitly required and documented
- Event schema changes are backward-compatible; old consumers don't break on new fields
- Sampling decisions documented and applied consistently; missing events explained

### 11. Agentic harness review (conditional: only when the product is agentic)

Score this domain against the Agent Harness Maturity Specification, twelve primitives scored HML 0-5, at https://github.com/Mariano215/agent-harness-maturity/blob/main/SPEC.md. Read `SPEC.md` from a local checkout if one exists, otherwise fetch it. Fall back to the `harness-review` skill's `references/rubric.md` if the spec is unreachable; it carries the same twelve primitives in prose form. Say which source was used either way. If neither is reachable, skip domain 11 and say so.

The review agent scores all twelve primitives against evidence in the codebase and returns the gap analysis in the standard findings format with primitive scores attached. Two rules from the spec that change the output: a primitive the workload never exercises scores N/A, never 5 or 0, and the overall level is the minimum across applicable primitives rather than an average. Key evidence to collect:

- System prompts and instruction files: versioned, tested, or ad-hoc strings in code
- Tool definitions: schemas validated, side effects bounded, least privilege
- Execution environment: sandboxing, permission gates, secrets isolation (treat gaps as security findings)
- Verification: output checks gated on, not just present; eval or regression harness for prompt changes
- Observability: traces of agent runs, token/cost accounting, failure attribution
- Durable state, orchestration (retries, loop caps, approval gates, model routing), sub-agents, context delivery and management, skills
- Governance: the identity the agent acts under, authorization scope, audit trail, human approval gates on irreversible actions

Map CRITICAL/HIGH as follows: any primitive scoring 0-1 that the workload exercises is HIGH; execution-environment gaps are CRITICAL when they expose secrets or unsandboxed writes. Primitives the workload never exercises are notes, not findings.

## Optional extra domains (add on request)

- **Accessibility audit** — keyboard nav, screen reader, color contrast, ARIA roles
- **Dependency security** — `npm audit`, `trivy fs`, known CVEs, transitive vulns
- **Dead code detection** — unused exports, unreachable routes, commented-out blocks
- **Backup + recovery** — DB corruption recovery path, backup freshness, restore procedure tested
- **Documentation coverage** — docs/ files match actual code state; README claims verified against behavior
- **CI/CD pipeline audit** — secrets in workflows, pinned action versions, OIDC vs long-lived tokens

## Agent prompt template

Each review agent gets:

```
You are reviewing <domain> for <project> at <absolute path>. Working dir is already set — use absolute paths.

SCOPE (read-only, DO NOT edit):
- <file 1>
- <file 2>
- ...

CONTEXT:
- <project-specific context, e.g. from CLAUDE.md or README>

WHAT TO HUNT (concrete functional/security bugs only, not style):
1. <specific thing>
2. <specific thing>
...

APPROACH:
- <how to efficiently search>

REPORT FORMAT:
```
## <Domain> Review

### CRITICAL
- **[Issue]** file.ts:line — one-line
  What breaks: concrete scenario
  Repro: steps
  Fix: specific direction (no code)

### HIGH / MEDIUM / LOW
...

### Test coverage gaps
- list of untested paths
```

Do NOT report stylistic issues. Only concrete bugs. Target 200-400 lines.

Return markdown findings only — no preamble, no offer to fix. Do NOT run tests or build. Do NOT edit any file.
```

## Prioritization for fixes

When consolidating findings, apply this ordering:

1. **Auth/permission bypasses** — any path that grants access it shouldn't — fix first
2. **Cross-tenant data leaks** — fix second, usually in list/read helpers
3. **Cross-tenant writes** (state corruption) — fix third
4. **State machine bugs** (stuck jobs, orphan tasks, race conditions on state update) — fix fourth
5. **Schema/SQL bugs** that silently fail (swallowed errors, missing rollbacks) — fix fifth
6. **Functional bugs** that degrade product but don't corrupt data — fix last

Skip LOW-severity nitpicks unless the loop budget has spare capacity.

## Stopping rules

- **Early stop when clean**: if loop N returns zero CRITICAL and zero HIGH findings for every dispatched agent, STOP. Report clean. Do not run more loops for the sake of running more loops.
- **Baseline red**: if baseline typecheck/test is red, refuse to proceed and tell the user to fix baseline first.
- **Test regression after fix**: if your fixes cause previously-green tests to go red, revert the bad fix and re-dispatch the review agent with the failing context.
- **Budget exhausted**: if all loops run and findings remain, write a final handoff doc listing outstanding work and run `TaskCreate` so the next session can pick up.

## Output artifacts

Write all findings + consolidated reports under `.reviews/` in the project root:

- `.reviews/loop1-findings.md` — consolidated CRITICAL/HIGH/MEDIUM/LOW per loop
- `.reviews/loop1-security.md`, `.reviews/loop1-backend.md`, etc. — raw agent reports (optional; may be inlined)
- `.reviews/loopN-fixes.md` — list of fixes applied in loop N with commit-ready descriptions
- `.reviews/summary.md` — final summary across all loops: counts by severity, fix status, outstanding work

Add `.reviews/` to `.gitignore` unless the user specifically wants it committed.

## Notes + footguns

- **Single message, multiple Agent calls.** Dispatching sequentially defeats the purpose of parallel review.
- **Each agent gets its own scope.** Do not ask "review everything" — dead weight, low signal.
- **Coordinator does all edits.** Agents are read-only or they conflict.
- **Verify each finding** by reading the actual code at the cited line before editing — agents sometimes cite a line that's slightly off, or report a bug that's already fixed elsewhere.
- **Run tests after every fix batch**, not only at the end. Catch regressions fast.
- **Use the `run_in_background: true` option** when dispatching — don't block the coordinator while agents read code.
- **Don't re-read sub-agent transcripts.** Summaries come back as tool results automatically. Reading raw transcripts overflows context.
