---
name: handoff
description: Generate a structured handoff document (project identity, current state, architecture map, recent decisions, next steps/risks) so a new AI session or teammate can pick up full context fast. Use when the user types /handoff, asks to "write a handoff", "hand this off", "prep a handoff doc", or is wrapping up a session and wants context preserved for next time.
trigger: /handoff
---

# /handoff

Turn the current repo and conversation into one markdown file a cold read can act on. Five fixed sections, no interview, best-effort from what's already knowable. Say "not assessed" rather than guess.

## Usage

```
/handoff                    # current project, current conversation
/handoff <focus note>       # e.g. /handoff emphasize the auth refactor risk
```

## Output

Write to `<scratchpad dir>/HANDOFF_<repo-name>_<UTC compact timestamp>.md`. Use the scratchpad directory path already given in your system prompt for this session; if none was given, `mktemp -d` and use that instead. Never write the file into the project repo, it's a transport artifact, not documentation. Print the full document in chat, then print the absolute file path on its own line so the user can open it or drag it into a new session.

## What to gather

Don't ask the user unless a section would otherwise be entirely empty.

1. **Identity** - repo/dir name, one-line goal from README/CLAUDE.md opening lines, hard constraints from any CLAUDE.md/AGENTS.md in scope (tech stack, permanent rules, boundaries).
2. **Current state** - `git status --short`, current branch, ahead/behind main. If this session has a TaskList, sort its items into working/partial/broken/not-started; otherwise write "not tracked this session."
3. **Architecture & map** - `find . -maxdepth 2 -type d` (skip .git, node_modules, vendor, build output), key dependencies (package.json/requirements.txt/go.mod/Cargo.toml, whichever exists). Point at `file:line`, never paste code blocks.
4. **Recent work & decisions** - `git log --oneline -15`. Then add what this conversation decided that isn't in a commit yet: what was tried, what got rejected and why. Git can't supply this part, only conversation memory can.
5. **Next steps & risks** - open TaskList items, TODO/FIXME hits (`grep -rn "TODO\|FIXME"`, cap at 10), open questions raised in conversation. Flag uncertain assumptions as uncertain.

If the user gave a focus note, fold it into section 5 as the top item. It doesn't override sections 1-4.

## Template

```markdown
# Handoff: <repo name>
Generated <UTC timestamp> · branch <branch> · <clean/N files changed>

## 1. Project Identity
**Goal:** ...
**Hard constraints:** ...

## 2. Current State
- Working: ...
- Partial: ...
- Broken: ...
- Not started: ...

## 3. Architecture & Map
...

## 4. Recent Work & Decisions
**Just happened:** ...
**Why:** ...
**Rejected alternatives:** ...

## 5. Next Steps & Known Risks
**Next:** ...
**Risks / unknowns:** ...
```

Fill every section. "Not assessed" is a valid fill. A missing section is not.

## Honesty rules

- Never invent what's working or broken - write "not assessed" over a guess.
- Never paste large code or doc blocks in - reference file paths instead.
- If git isn't available or this isn't a repo, say so in section 2 and skip git-derived facts elsewhere.
