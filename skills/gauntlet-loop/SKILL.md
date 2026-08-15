---
name: gauntlet-loop
description: Run a Gauntlet Loop (Matt Shumer's method), driving work toward a concrete reference standard with paired builder and critic agents that loop until the output matches the bar. Use when the user says "gauntlet loop", "/gauntlet", "run a gauntlet", "make this match [reference]", "keep looping until it looks like X", or asks for output judged against a named example rather than a checklist. Best for visual, creative, or taste-driven work (game feel, landing pages, prose voice, design polish) where "done" is a comparison, not a passing test. Not for work with an objective pass/fail signal, use /tdd or /debug there.
trigger: /gauntlet
---

# Gauntlet Loop

Source: https://somethingbig.ai/gauntlet-loop (Matt Shumer).

One idea. Pick a real example of great, then have a builder and a separate
critic argue about the gap until the gap closes.

This skill spawns subagents. Invoking it is the request for them.

## 1. Set the bar first

The bar is the whole method. It must be something an agent can actually open
and compare against: screenshots, a live URL, a reference file, a writing
sample, a recorded metric.

Not a bar: "make it amazing", "production-ready", "keep improving it". Those
give the critic nothing to measure, so the loop degenerates into praise.

Ask the user for the reference if they did not give one. Offer candidates from
the domain. Confirm the bar in one line before spawning anything:

```
bar: [what the critic compares against, and how it inspects it]
```

If the reference is a file or URL, verify it is reachable now. A critic that
cannot open the bar will invent one.

## 2. Decompose

Break the goal into the smallest pieces that can be improved independently.
Independent means two builders can work at once without editing the same
thing. Aim for 3 to 8 pieces on a first run.

State the pieces before starting. The user's correction here is cheaper than
five rounds of the wrong decomposition.

## 3. Loop each piece

Per piece, per round:

1. **Builder** makes or revises the artifact. It does not judge its own work.
2. **Critic** runs in a fresh agent with no builder history and no builder
   rationale. It inspects the actual output (open the file, render the page,
   view the image), never a summary or the builder's description of it.
3. Critic answers two things: does the reference still win, and what is the
   single biggest remaining gap.
4. Reference wins, send the gap back to the builder. Next round.

Critic prompt shape:

```
Compare [artifact, and how to inspect it] against [reference, and how to open it].
Which is better and why? If the reference wins, name the single biggest
remaining gap in concrete terms the builder can act on. Do not praise. Do not
list more than one gap.
```

Fresh context per critic round is the point. A critic that watched the builder
struggle starts grading effort.

## 4. Stopping

Do not preset a round count, the article is explicit about that. Loop until
one of:

- the critic stops picking the reference
- the last two rounds produce cosmetic gaps only
- the user calls it
- budget runs out

Report per piece: rounds run, what the last gap was, whether the bar was met.
Say plainly when a piece was stopped short rather than finished.

Between phases, an optional smoothing pass over the whole artifact catches the
seams that per-piece work leaves behind.

## Running it here

- Default: `Agent` calls, builder and critic as separate agents. Sequential
  per piece, parallel across pieces.
- Many pieces or many rounds: this is a `Workflow` shape (pipeline over pieces,
  builder stage then critic stage, loop until dry). Workflow needs explicit
  user opt-in, so ask, and say roughly what it will cost, before calling it.
- Long runs: write progress to one file the user can watch instead of
  interrupting the loop to ask.

## Meta-prompt

When the user has a goal but no bar, hand them this:

```
I want to run a Gauntlet Loop for this goal: [GOAL]
Possible references or quality bars: [OPTIONAL REFERENCES]

Choose the strongest concrete bar that an agent can actually inspect and
compare its work against. Then write a short prompt for the loop. Minimal is
better, let the agent decide the specifics.
```
