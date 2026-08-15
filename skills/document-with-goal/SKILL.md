---
name: document-with-goal
description: "Generate and verify documentation until complete and accurate. Use when the user asks to update docs, README, or API documentation, or asks whether docs are current. Not for code-only changes. Trigger: /document"
---

# Document with Goal-Driven Iteration

This skill generates comprehensive documentation with automatic iteration using `/goal`, ensuring docs are complete, accurate, and up-to-date.

## When This Skill Is Used

### Manual Invocation:
```bash
/document
/document README.md
/document --full  # All docs
```

### Automatic Invocation by Claude:
Claude should automatically use this skill when:
- ✅ User says "update the documentation"
- ✅ User requests "generate docs" or "document this"
- ✅ After significant code changes when docs mentioned
- ✅ User asks "are the docs up to date?"
- ❌ Do NOT auto-invoke for: code-only changes, mid-development

**Examples triggering automatic use:**
- "Update the README"
- "Document the new API"
- "Are the docs complete?"
- "Generate documentation for this feature"

---

## Safety Configuration

**MANDATORY SAFETY LIMITS** (loaded from `~/.claude/skills/goal-safety-config.json`):
- **Max Iterations:** 5
- **Timeout:** 15m
- **Rationale:** Documentation should converge quickly or needs human input

These limits are **NON-NEGOTIABLE**.

---

## Workflow

### Phase 1: Analyze Documentation Needs
1. **Identify what needs documenting:**
   - README.md (project overview, setup, usage)
   - API documentation (endpoints, parameters, responses)
   - User guides (how-tos, tutorials)
   - Code comments (inline documentation)
   - CHANGELOG.md (version history)

2. **Check current state:**
   - What docs exist?
   - What's missing?
   - What's outdated?
   - What recent code changes need documenting?

### Phase 2: Goal-Driven Documentation
3. Use `/goal` with mandatory safety limits:
   ```bash
   /goal "all documentation complete and accurate" --max-iterations 5 --timeout 15m
   ```

4. **Generate/Update docs:**
   - Write missing documentation
   - Update outdated sections
   - Add examples where missing
   - Document new features/APIs
   - Fix broken links or references

5. **Verify completeness:**
   - All public APIs documented?
   - All user-facing features explained?
   - Examples provided and working?
   - Setup instructions complete?
   - No stale content?

6. Iterate until documentation meets quality bar

### Phase 3: Quality Checks
7. If docs complete before safety limits:
   - Verify links work
   - Check code examples are correct
   - Ensure formatting is consistent
   - Validate no stale references
   - Confirm readability

---

## Documentation Checklist

### README.md Must Have:
- [ ] Project description
- [ ] Installation instructions
- [ ] Quick start / basic usage
- [ ] Key features list
- [ ] Configuration options
- [ ] Links to detailed docs
- [ ] License information
- [ ] Contributing guidelines (if open source)

### API Documentation Must Have:
- [ ] All endpoints listed
- [ ] Request/response formats
- [ ] Parameters and types
- [ ] Example requests/responses
- [ ] Error codes and meanings
- [ ] Authentication requirements

### User Guide Must Have:
- [ ] Step-by-step tutorials
- [ ] Common use cases
- [ ] Troubleshooting section
- [ ] FAQ
- [ ] Examples with explanations

### Code Comments Must Have:
- [ ] Function/class purpose
- [ ] Parameter descriptions
- [ ] Return value descriptions
- [ ] Usage examples (for complex functions)
- [ ] Notes about edge cases

---

## Safety Limit Handling

### When Safety Limit Is Reached:

**DO:**
- ✅ Stop immediately
- ✅ Report what was documented
- ✅ List what's still missing or unclear
- ✅ Identify sections needing human input

**DO NOT:**
- ❌ Claim docs are complete
- ❌ Leave obvious gaps
- ❌ Continue iteration

### Example Safety Failure Response:

```
⚠️ Safety limit reached: 5 iterations completed, documentation incomplete.

Completed:
- ✅ README.md: Updated with new API features
- ✅ API docs: 8 new endpoints documented
- ✅ Quick start guide: Added installation steps
- ✅ Code examples: 12 working examples added

Remaining:
- ❌ Advanced configuration section (unclear what options exist)
- ❌ Deployment guide (need environment-specific info)
- ❌ Troubleshooting FAQ (need common issues from users)

Issue:
Some documentation requires domain knowledge or user input that I don't have.
For example, deployment steps vary by hosting provider, and I need clarification
on which providers to document.

Next Steps:
1. Review completed docs for accuracy
2. Provide answers to these questions:
   * Which deployment platforms should be documented? (AWS, Heroku, Digital Ocean?)
   * What are the most common user issues? (for FAQ)
   * Are there any advanced config options not in the code?
3. Run `/document` again after clarifications
4. OR manually complete remaining sections
```

---

## Documentation Types

### 1. README.md (High Priority)
- Project's front page
- First thing users see
- Must be complete and accurate

### 2. API Documentation (High Priority)
- Critical for developers
- Must match actual code
- Include examples

### 3. User Guides (Medium Priority)
- Helps with adoption
- Tutorial-style content
- Real-world examples

### 4. Code Comments (Medium Priority)
- Helps maintainers
- Documents intent
- Explains "why" not just "what"

### 5. CHANGELOG.md (Low Priority)
- Version history
- Breaking changes
- Migration guides

---

## Verification Methods

### Automated Checks:
```bash
# Check for broken links
find . -name "*.md" -exec markdown-link-check {} \;

# Check code examples compile
# Extract code blocks from docs and run them

# Check API docs match code
# Parse docs and compare with actual API
```

### Manual Checks:
- Read docs from user perspective
- Try following tutorials
- Verify setup instructions work
- Check examples are correct

---

## Success Criteria

Goal is achieved when:
1. ✅ All required documentation exists
2. ✅ All code examples work
3. ✅ No broken links
4. ✅ No references to old/removed features
5. ✅ Clear and readable
6. ✅ Up-to-date with latest code

---

## Integration with Post-Commit Hook

From your existing hooks:
```
📋 DOC CHECK after git commit: Verify that README.md, docs/user-guide/USER-GUIDE.md,
docs/user-guide/QUICK-START.md, and memory/MEMORY.md were updated and staged in this
commit. If any are missing, update and amend or add a follow-up commit before pushing.
```

This skill can automate that check:
```bash
# After commit, if docs outdated:
claude --prompt "/document --verify-commit"
```

---

## Example Usage

### Example 1: Update README
```
User: "Update the README with the new authentication feature"

Claude automatically invokes document-with-goal:

1. Reads current README.md
2. Identifies authentication section is outdated
3. Uses /goal to iterate on updates
4. Adds authentication docs:
   - Setup instructions
   - Configuration options
   - Usage examples
   - Security notes
5. Verifies links work
6. Reports: "✅ README.md updated with complete auth documentation"
```

### Example 2: Generate API Docs
```
User: "Document all the API endpoints"

Claude automatically invokes document-with-goal:

1. Scans codebase for API endpoints
2. Generates documentation for each:
   - Endpoint path
   - HTTP method
   - Parameters
   - Response format
   - Example request/response
3. Creates API.md file
4. Reports: "✅ API documentation generated for 15 endpoints"
```

### Example 3: Verify After Code Change
```
Post-commit hook: "Verify docs updated after commit"

Claude automatically invokes document-with-goal:

1. Compares changed files with docs
2. Identifies: new function added but not documented
3. Uses /goal to update docs
4. Adds function documentation
5. Reports: "✅ Documentation updated for new validateEmail() function"
```

---

## When NOT to Use This Skill

**Do NOT use** for:
- ❌ Mid-development (too early)
- ❌ Internal/private utilities (don't need public docs)
- ❌ Experimental code (not stable yet)
- ❌ Temporary code (will be removed)

**Use manual documentation** when:
- Documentation requires domain expertise
- Needs user research or feedback
- Requires architectural decisions
- Writing narrative or marketing content

---

## Notes

- Conservative iteration limit (5) - docs should be straightforward
- May hit limit if human input needed
- Integrates with existing post-commit hook
- Focuses on completeness and accuracy
- Works best for technical documentation
- May need human input for conceptual/marketing docs

---

## Escalation (iteration 4)

At iteration 4 without convergence (or at this skill's own limit when lower), pause. Summarize the attempts so far and the current hypothesis, then present three options and wait for the user's choice:

1. Switch strategy: new hypothesis, different approach.
2. Hand off to the built-in /loop for self-paced retries. REQUIRES an explicit user go. Token-expensive; never start /loop on your own.
3. Stop and report findings.

Hard limits in goal-safety-config.json still apply and override everything.
