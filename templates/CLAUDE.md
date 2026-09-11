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
Deliver what was asked, at the scope asked. Make routine judgment calls yourself
and check in only when two readings of the request lead to materially different
work. If the request looks mistaken, say so in one sentence and do it as asked
rather than quietly narrowing or widening it. Finish the whole task and stop there.
Do not add a verification pass of your own. The model already re-checks its
work, so a second "now double-check" step costs tokens and changes nothing. Run
the checks that produce evidence (tests, lint, a build) and report what they
printed.

# Skills
When a request matches a skill description in the skills list, invoke that
skill instead of improvising. Slash forms work directly: /pre-push /document
/graphify /handoff /harness-builder.
For test-driven work, debugging or a new feature, invoke the matching
superpowers skill for the methodology, then set the built-in /goal with a
condition the transcript can prove and a turn clause to bound it (/goal takes
plain text, no flags). Never claim success without the command output that
proves it.

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
