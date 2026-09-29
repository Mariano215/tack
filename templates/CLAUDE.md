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
Do not add a verification pass of your own, and do not spawn an agent to
check your own output. The model already re-checks its work, so a second pass
costs tokens and changes nothing. Run the checks that produce evidence (tests,
lint, a build) and report what they printed. Before reporting a step as done,
check that claim against a tool result from this session.
One exception: the `code-reviewer` agent at a checkpoint or commit gate. It
reads the plan and the diff in a fresh context, without the writer's
assumptions, so it is an independent check, not a second pass.
The checklists inside the methodology skills (spec, plan and implementer
self-review) are not that second pass either: they check a written artifact
against named items such as placeholders, spec coverage and type names. Run
them as written.
Delegate by the shape of the work, not its size. Work that reads a lot and
returns a little (search, log or test triage, review) and specified
implementation units with a clear check go to a subagent, so the noise stays
out of the main context. Decisions, plans, small edits, and edits that need
detail you already hold stay in the main thread.

# Skills
When a request matches a skill description in the skills list, invoke that
skill instead of improvising. Slash forms work directly: /pre-push-auto-fix
/document-with-goal /graphify /handoff /harness-builder.
For a new feature use brainstorming, then writing-plans, then executing-plans
or subagent-driven-development. For a bug use systematic-debugging, and for
test-first work test-driven-development. Then set the built-in /goal with a
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

# Token discipline
Code lookup order: the graphify graph first (`graphify query "<question>"`,
built at session start when the profile sets `GRAPHIFY_AUTO=1`), then the LSP
tool for exact definitions, references and types (tokensave when no language
server covers the file), then grep for literal strings or when the graph has no
answer.
