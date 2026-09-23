---
name: smart-agent-spawner
description: Selects model tier (opus/sonnet/haiku) and effort level for spawned agents/subagents based on task complexity, and escalates on failure. Applies automatically before any Agent, Task, or Workflow agent() call.
---

# Smart Agent Spawner

## Purpose

Automatically select the optimal Claude model (Opus, Sonnet, or Haiku) and, where available, effort level, when spawning agents based on task complexity and agent type. This balances cost, speed, and capability, and defines what to do when a spawn fails.

## When This Skill Activates

Applies automatically whenever you spawn agents via the `Agent` tool, `Task` tool, or `Workflow` tool's `agent()` calls. A `PreToolUse` hook (`hooks/model-router-nudge.sh`, matcher `Agent|Task|Workflow`) fires before every such call to remind you of these rules, so you don't need the user to ask.

## Model Selection Strategy

### Opus, most capable, highest cost

Use for critical decisions that are hard to reverse or require deep reasoning.

Agent types:
- `Plan` - architecture and implementation planning
- `code-reviewer` - code review and quality assessment
- `code-security-auditor` - security reviews and vulnerability detection
- `database-designer` - complex database schema design

Task characteristics:
- Architecture decisions and system design
- Security reviews and threat modeling
- Complex debugging (race conditions, memory leaks, subtle bugs)
- Critical refactoring that affects many files
- Code that handles sensitive data or authentication
- Performance optimization requiring deep analysis
- Migration planning between technologies

Cost: Opus 5.5 runs $4/$20 per MTok, roughly 1.3x Sonnet 5's $3/$15, not the 5x gap older models had. Opus is also the default session model. Don't downgrade a spawn to save cost unless the task is genuinely mechanical.

### Sonnet, balanced, default choice

Use for most implementation work and standard development tasks.

Agent types:
- All `*-developer` agents (backend-developer, frontend-developer, python-developer, etc.)
- `code-refactor`, `code-debugger`, `code-documenter`
- `task-orchestrator`

Task characteristics:
- Writing new features or functionality
- Implementing APIs, endpoints, or services
- Standard refactoring and cleanup
- Typical bug fixes and debugging
- Integration work between components
- Most database queries and operations
- UI/UX implementation
- Test writing and fixes

Cost: $3/$15 per MTok ($2/$10 introductory through 2026-08-31). 1M context. Good value, but the gap to Opus is small enough that Opus is the right call whenever quality matters.

### Haiku, fastest, lowest cost

Use for simple, mechanical tasks with clear requirements.

Agent types:
- `Explore` - file searches and codebase exploration
- `test-runner` - running tests and reporting results
- `code-documenter` - simple documentation tasks, when straightforward

Task characteristics:
- Searching for files or code patterns (Glob, Grep operations)
- Running existing test suites
- Simple documentation generation
- File organization and cleanup
- Reading logs or output for specific patterns
- Quick validations and checks
- Formatting and linting

Cost: $1/$5 per MTok, roughly 0.33x Sonnet.

Two hard limits on Haiku 4.5, both easy to trip:
- **200K context**, not 1M. Every other tier has 1M. An `Explore` agent sweeping a large repo, or any agent fed a big file set, will exhaust Haiku's window where Sonnet or Opus would not. Size the input before picking this tier.
- **No effort parameter.** Passing `effort` to Haiku 4.5 errors. Omit it entirely.

## Effort Level Mapping

Effort control (`low` / `medium` / `high` / `xhigh` / `max`) only exists on the `Workflow` tool's `agent(prompt, {model, effort})` option. The plain `Agent` tool has no effort parameter, don't try to pass one there.

Default when unset is `medium` on Opus 5.5 and `high` on every other model that takes effort. `xhigh` sits between `high` and `max`.

- Haiku tier: omit effort. Haiku 4.5 rejects the parameter outright.
- Sonnet 5 tier: omit effort (inherits session default) for routine work. Supports the full range up to `max`.
- Opus 5.5 tier: start at `medium`, which is the default and the same as omitting the
  parameter. Opus 5.5 at `medium` beats Opus 5 at `high` on coding and knowledge work,
  and `low` comes close on many coding tasks. Step up to `high` for hard work, and to
  `xhigh` or `max` only where you have measured a gain: at the same level Opus 5.5
  thinks more per turn than Opus 5, so those levels cost more than they used to.
- `low` and `medium`: short scoped tasks, mechanical stages, latency-sensitive work.
  Current models respect low effort strictly and scope work to exactly what was asked,
  so raise the tier rather than prompting around shallow reasoning.

Effort names do not mean the same amount of thinking across models. Opus 4.8 wanted
`xhigh`, Opus 5 wanted `high`, Opus 5.5 wants `medium`. A caller that pins `high` or
`xhigh` by default is carrying an older setting forward, and Anthropic's guidance is to
re-measure rather than reuse it.

Effort controls how much the agent thinks, not how long its visible answer is. On Opus 5.5,
lowering effort does not reliably shorten the reply. If a spawned agent returns more prose
than the caller needs, say so in the prompt instead of dropping effort.

At `xhigh` or `max`, give the agent room in its output budget. Adaptive thinking can
consume a large share of it, and a tight budget yields a response that is mostly thinking
followed by a truncated answer. Opus 5.5 cannot run with thinking disabled at any
effort level; `thinking: disabled` and `budget_tokens` both return a 400 error. Lower
effort instead.

## When Not To Spawn At All

Opus 5 delegates more readily than earlier models, so the cheapest win here is usually
not picking a better tier, it is not spawning. Delegation multiplies cost and wall-clock
time, and on small work it loses to doing the job directly.

Spawn only when the work is large, genuinely independent, and parallelizable, such as a
wide multi-file investigation or several unrelated review dimensions. Do not spawn for
work you can finish in a handful of tool calls. Do not spawn an agent to verify or
double-check your own output: Opus 5 already checks its own work, and a verifier agent
adds cost without adding accuracy. If one agent can do the job, use one, not three.

The deterministic backstop is two environment variables, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
and `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (Claude Code 2.1.217 or later). The harness sets
both in `base-settings.json`. They cap the blast radius; they are not a substitute for
deciding not to delegate.

## Context-Based Model Selection

Upgrade to Opus when:
- Working on financial, healthcare, or security-critical systems
- Project is in early architecture phase
- Making decisions that affect the entire codebase
- User explicitly requests "use your best reasoning" or similar
- A previous attempt with a lower tier already failed on this task
- Dealing with unfamiliar or complex technology stacks

Downgrade to Haiku when:
- Task is clearly mechanical (file searches, test runs)
- User explicitly requests "use fast model" or "keep it cheap"
- Task has succeeded at this tier before (repetitive work)
- Just need to validate or check something simple

Respect user preferences: if the user names a model or effort explicitly, honor it over these rules.

## Retry and Escalation on Failure

Modeled on the retry ceilings the goal-driven skills state, don't invent a different pattern.

1. Attempt 1 uses the tier chosen by the rules above.
2. On failure (subagent errors, or its output fails the caller's own check): escalate one tier (haiku to sonnet, sonnet to opus) and raise effort one step, then retry.
3. Hard cap: 3 attempts total.
4. After the 3rd failure: stop. Report what was tried at each tier and why it failed. Ask the user to choose one of:
   - switch strategy (new approach, not just a bigger model)
   - hand off to `/loop` for self-paced retries (requires explicit user confirmation, token-expensive)
   - stop and report findings
5. Never silently loop past the cap, and never auto-start `/loop` without the user confirming.

## Special Considerations

Multi-agent teams: coordinator/team-lead uses Sonnet (or Opus if the coordination itself is complex). Individual specialists follow the rules above for their own task. Don't downgrade everything to save cost, balance is the point.

Long-running tasks: planning phase uses Opus (short duration, high value), execution uses Sonnet, monitoring/validation uses Haiku.

## Anti-Patterns

Don't use Haiku for: code reviews, security audits, complex debugging or architecture decisions, critical business logic, database schema design.

Don't use Opus for: file searches, running test suites, formatting code, simple documentation of straightforward code.

Don't ignore a user's explicit model or effort preference.

Don't change models mid-task without a reason (a failure, or a scope change).

## Summary

Critical decisions and reviews use Opus. Implementation and development use Sonnet. Searches and simple tasks use Haiku. On failure, escalate one tier and one effort step, retry, cap at 3 attempts, then ask the user.

Key principle: pick the tier that can reliably accomplish the task. The Opus/Sonnet price gap is now ~1.3x, not 5x, so cost is a weak reason to downgrade. When in doubt, inherit the session model rather than pinning a cheaper one.

`claude-fable-5` also exists ($10/$50 per MTok, above Opus tier, thinking always on). It is not part of the normal ladder. Use it only when the user names it explicitly.
