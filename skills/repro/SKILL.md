---
name: repro
description: Use when the user invokes /repro or asks to iterate a verification or review task a bounded number of times. Triggers on "/repro <task>", "do this at most N times", "repeat until clean", "loop X checking Y". Parses the prompt, announces the loop plan, executes iteratively with per-iteration status lines, and produces a final report.
trigger: /repro
---

# /repro — Bounded Iterative Loop

Run a task repeatedly until it passes or hits the iteration cap.

## Parse

From the user's `/repro` message, extract:

| Field | Where | Default |
|---|---|---|
| **task** | the action to run each iteration | (required) |
| **max** | "at most N times", "up to N", "N iterations" | 3 |
| **exit** | "until clean", "until passing", explicit stop condition | infer from task |

Infer **exit**: if task is "review for X" exit when X is not found; if task is "fix failing tests" exit when all tests pass.

## Announce before starting

Before iteration 1, state the plan so the user can correct it:

```
/repro loop
  task:   [one-line description of what runs each iteration]
  max:    N iterations
  exit:   [condition that ends early]
```

## Each iteration

1. Execute the task in full
2. Collect findings
3. Check exit condition
4. Print status line: `[iter X/N] findings: N | exit met: yes → stopping / no → continuing`

Stop immediately when exit condition is met. No extra iterations.

## Final report

```
=== /repro complete: X of N iterations run ===
exit met: yes / no
───────────────────────────────────────
iter 1: [one-line summary]
iter 2: [one-line summary]
...
───────────────────────────────────────
remaining issues: [list, or "none — clean"]
```

## Example

User: `/repro review all code for fake, mock, or temp data — at most 5 times`

Announce:
```
/repro loop
  task:   scan codebase for fake/mock/temp/placeholder/hardcoded test values; fix found instances
  max:    5 iterations
  exit:   zero violations found on scan
```

Iterate: grep → list → fix → grep → ... stop when scan returns nothing or after 5 runs.

## Parsing quick reference

| User says | Parsed |
|---|---|
| "at most N times" | max = N |
| "up to N passes" | max = N |
| "until tests pass" | exit = all tests green |
| "until no warnings" | exit = zero warnings |
| "until clean" | exit = zero findings |
| no count given | max = 3 |
