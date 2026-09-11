---
name: goal-iteration
description: Pair a superpowers methodology skill with the built-in /goal loop for work that has a verifiable end state. Use when the user wants test-driven implementation, a bug fixed, or a feature built, and the finish line can be proved from Claude's own output (tests pass, build exits 0, bug no longer reproduces). Not for open-ended design, prose, or anything a command cannot check.
---

# goal-iteration

Two separate things, used together. The methodology decides *how* to work. The
`/goal` loop decides *when to stop asking the user for another turn*.

## Step 1: pick the methodology skill

| Work | Skill |
|---|---|
| Implementing a feature or fix, test first | `superpowers:test-driven-development` |
| A bug, test failure, or unexpected behavior | `superpowers:systematic-debugging` |
| A feature that needs design before code | `superpowers:brainstorming`, which chains to `superpowers:writing-plans` |

Invoke it and follow it. These skills carry their own stop rules. Systematic
debugging, for example, stops after three failed fixes and makes you question
the architecture instead of trying a fourth.

If superpowers is not enabled on this profile, say so and work without it. Do
not paraphrase the methodology from memory.

## Step 2: set the goal

`/goal` is built into Claude Code. It takes a plain-text condition, no flags.
After every turn a small fast model reads the transcript and returns met, not
yet met, or impossible.

```text
/goal npm test exits 0 for test/auth and no other test file is modified, or stop after 15 turns
```

Three rules for the condition:

- **Provable from the transcript.** The evaluator does not run commands or read
  files. It only sees what Claude surfaced. "All tests pass" works because
  Claude runs them and the output lands in the conversation.
- **Bounded.** There is no `--max-iterations` flag. The ceiling goes in the
  condition text, as `or stop after N turns`.
- **Constrained.** State what must not change on the way there.

Suggested ceilings: 15 turns for a bug, 15 for a test-first implementation, 25
for a feature with a design phase. These are starting points, not limits the
system enforces.

## Step 3: report

`/goal` clears itself when the condition is met or is judged impossible. Say
which of the two happened. Never claim success without the command output that
proves it, per `superpowers:verification-before-completion`.

Run `/goal` with no argument for status, `/goal clear` to stop early.
