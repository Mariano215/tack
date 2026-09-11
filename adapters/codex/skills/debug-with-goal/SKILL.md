---
name: "debug-with-goal"
description: "Use for bugs, failures, errors, crashes, regressions, broken behavior, or repeated failed fixes. Requires root-cause investigation before fixes."
---

# Debug With Goal

1. Read full error, stack trace, logs, file paths, and line numbers.
2. Reproduce consistently when possible.
3. Check recent changes with git diff/log.
4. Find similar working code.
5. Trace bad value or failing state backward to source.
6. State: `Root cause is X because Y`.
7. Make smallest fix that addresses root cause.
8. Verify with tests or a direct repro.

After 3 failed fixes, stop and reassess architecture. Do not stack speculative fixes.
