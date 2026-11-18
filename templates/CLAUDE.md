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
Deliver what was asked, at the scope asked. If the request looks mistaken, say
so in one sentence and do it as asked.
Do not spawn an agent to check your own output. The `code-reviewer` agent at a
commit gate is the exception: it reads the diff in a fresh context.

# Skills
When a request matches a skill description in the skills list, invoke that
skill instead of improvising. Slash forms work directly: /pre-push-auto-fix
/document-with-goal /graphify /handoff /harness-builder.

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
