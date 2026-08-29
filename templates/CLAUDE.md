# Project instructions

Starter template. Delete what you do not want; this file is copied into a
config dir on apply and is meant to be edited.

# Writing style
Write plain and direct. Short sentences. No LLM-tell phrasing: "not just X,
it's Y", delve, seamless, robust, leverage, comprehensive, "worth noting",
transition pile-ups (furthermore/moreover), reflexive rule-of-three lists,
emoji bullets, title-case marketing headers. ghost:allow

The ghost hook enforces this on client-facing document formats only (.txt,
.docx, .pdf). Markdown and chat are yours to hold to the standard by hand. Run
`/ghost <file>` to check anything on demand, and edit `ghost/patterns.json` to
make the list your own.

# Coding defaults
Before writing code, state assumptions. Prefer the standard library over custom
code, and the shortest diff that actually fixes the problem.

# Skills
When a request matches a skill description in the skills list, invoke that
skill instead of improvising. Slash forms work directly: /tdd /debug /build
/pre-push /document /graphify /handoff.

Goal-driven skills (/tdd /debug /build /pre-push /document) iterate under hard
limits from `~/.claude/skills/goal-safety-config.json`. At iteration 4 without
convergence they pause and offer to switch strategy or stop. When a hard limit
is hit: stop, report progress and next steps, never claim success.

# Project record: the .agent/ directory
A repo that contains a `.agent/` directory collects its own paper trail. The
approved plan is written there automatically when plan mode exits, and the
end-of-session summary (work done, open branches, unfixed CRITICAL/HIGH
security findings, next steps) is appended to `.agent/log.md`. Nothing is
written to a repo without that directory, so `mkdir .agent` is how a project
opts in. Write `.agent/intent.md` and `.agent/spec.md` by hand when the work
needs them. Commit `.agent/` when the reasoning should ship with the code.
These files are for handover, not for evidence: an unsigned git history is
rewritable, so treat them as notes, not as an audit trail.
