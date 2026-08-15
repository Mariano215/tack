---
name: pre-push-auto-fix
description: "Auto-fix lint, test, and format issues before pushing. Use when the user says ready to push, can I push, or check before push. Conservative limits: 3 iterations, 10 minutes. Trigger: /pre-push"
---

# Pre-Push Auto-Fix

This skill enhances pre-push checks with automatic fixing using `/goal`. Ensures code quality before pushing to remote, with aggressive "fail fast" safety limits.

## When This Skill Is Used

### Manual Invocation:
```bash
/pre-push
/pre-push --auto-fix
```

### Automatic Invocation by Claude:
Claude should automatically use this skill when:
- ✅ User says "ready to push" or "about to push"
- ✅ User asks "can I push?" or "is it safe to push?"
- ✅ User requests pre-push checks or quality gates
- ✅ User says "check before push" or "validate before push"
- ❌ Do NOT auto-invoke for: regular development, mid-feature work

**Examples triggering automatic use:**
- "Is this ready to push?"
- "Can I push this to main?"
- "Check if it's safe to push"
- "Run pre-push checks"

---

## Safety Configuration

**MANDATORY SAFETY LIMITS** (loaded from `~/.claude/skills/goal-safety-config.json`):
- **Max Iterations:** 3 (VERY CONSERVATIVE)
- **Timeout:** 10m (VERY SHORT)
- **Rationale:** Fail fast before push - if it needs more than 3 fixes, manual review required

**Philosophy:** Pre-push should be quick checks + auto-fixes for trivial issues. Complex problems should fail fast and require manual investigation.

These limits are **NON-NEGOTIABLE**.

---

## Workflow

### Phase 1: Run All Quality Checks
1. **Linting:**
   ```bash
   npm run lint  # or appropriate linter
   ```
2. **Type Checking:**
   ```bash
   tsc --noEmit  # if TypeScript
   ```
3. **Formatting:**
   ```bash
   npm run format  # or prettier
   ```
4. **Tests:**
   ```bash
   npm test
   ```
5. **Build (if applicable):**
   ```bash
   npm run build
   ```

### Phase 2: Auto-Fix Mode (if --auto-fix)
6. If any checks fail AND `--auto-fix` flag present:
   ```bash
   /goal "all quality checks pass" --max-iterations 3 --timeout 10m
   ```
7. **Auto-fixable issues:**
   - Linting errors (auto-fix with --fix)
   - Formatting issues (run prettier)
   - Missing imports
   - Simple type errors
   - Trivial test fixes

8. **NOT auto-fixable (fail immediately):**
   - Logic errors in tests
   - Complex type errors
   - Architecture problems
   - Failing integration tests
   - Build errors from bad code

### Phase 3: Report Results
9. If all checks pass:
   - ✅ Report: "All quality checks passed. Safe to push."
   - List what was checked
   - Show test coverage if available

10. If checks fail after auto-fix attempts:
    - ❌ Report: "Not safe to push. Manual fixes required."
    - Show specific failures
    - Provide guidance on how to fix

---

## Safety Limit Handling

### When Safety Limit Is Reached (3 iterations):

**DO:**
- ✅ Stop immediately
- ✅ Report which checks pass and which fail
- ✅ Explain why auto-fix couldn't resolve issues
- ✅ Recommend manual investigation

**DO NOT:**
- ❌ Continue trying to fix
- ❌ Push despite failures
- ❌ Claim checks passed if they didn't

### Example Safety Failure Response:

```
⚠️ Pre-push auto-fix limit reached: 3 iterations, quality checks still failing.

Status:
- ✅ Linting: passed (12 auto-fixed)
- ✅ Formatting: passed
- ✅ Type checking: passed
- ❌ Tests: 2 failing
  * test/auth.test.js:45 - "login should return token"
  * test/auth.test.js:67 - "logout should clear session"
- ❌ Build: failed (TypeScript compilation error)

Issue:
Tests are failing due to changes in auth.js that broke the token generation
logic. This is not an auto-fixable issue - requires manual investigation.

🛑 NOT SAFE TO PUSH

Next Steps:
1. Investigate auth.js changes (likely lines 34-52)
2. Run failing tests locally: npm test test/auth.test.js
3. Use `/debug "auth tests failing"` for systematic debugging
4. Fix the issue manually
5. Run `/pre-push` again before pushing
```

---

## Check Priority

Run checks in this order (fail fast):
1. **Linting** (quick, often auto-fixable)
2. **Formatting** (quick, always auto-fixable)
3. **Type Checking** (medium, sometimes auto-fixable)
4. **Tests** (slow, rarely auto-fixable)
5. **Build** (slow, rarely auto-fixable)

Stop at first non-auto-fixable failure in auto-fix mode.

---

## Auto-Fix Capabilities

### Can Auto-Fix:
- ✅ Linting errors with `--fix` flag
- ✅ Formatting with prettier/autopep8
- ✅ Missing semicolons, trailing commas
- ✅ Import sorting
- ✅ Unused imports (safe removal)
- ✅ Simple type annotations

### Cannot Auto-Fix (Fail Fast):
- ❌ Logic errors
- ❌ Test failures from broken code
- ❌ Complex type errors
- ❌ Build failures from syntax errors
- ❌ Runtime errors
- ❌ Broken business logic

---

## Integration with Git Hooks

This skill can be integrated with actual git hooks:

**In `.git/hooks/pre-push`:**
```bash
#!/bin/bash
echo "Running pre-push checks..."
claude --prompt "/pre-push --auto-fix" --non-interactive

if [ $? -ne 0 ]; then
    echo "Pre-push checks failed. Push aborted."
    exit 1
fi
```

---

## Success Criteria

Goal is achieved when:
1. ✅ All linters pass
2. ✅ All formatters pass
3. ✅ All type checks pass
4. ✅ All tests pass
5. ✅ Build succeeds (if applicable)

---

## Example Usage

### Example 1: Clean Push
```
User: "Is this ready to push?"

Claude automatically invokes pre-push-auto-fix:

1. Runs all checks:
   - Lint: ✅ passed
   - Format: ✅ passed
   - Types: ✅ passed
   - Tests: ✅ all passing (23/23)
   - Build: ✅ succeeded

2. Reports: "✅ All quality checks passed. Safe to push."
```

### Example 2: Auto-Fixable Issues
```
User: "Can I push this?"

Claude automatically invokes pre-push-auto-fix:

1. Runs checks:
   - Lint: ❌ 5 errors
   - Format: ❌ 12 files need formatting

2. Uses /goal with --auto-fix (3 iterations max)

3. Iteration 1:
   - Runs: npm run lint --fix
   - Runs: npm run format
   - Re-checks: All pass now!

4. Reports: "✅ Fixed 5 lint errors and formatted 12 files. Safe to push."
```

### Example 3: Non-Fixable Issues
```
User: "Check before push"

Claude automatically invokes pre-push-auto-fix:

1. Runs checks:
   - Lint: ✅ passed
   - Tests: ❌ 3 failing

2. Attempts auto-fix (3 iterations)
   - Cannot auto-fix test failures

3. Reports: "🛑 NOT SAFE TO PUSH. 3 tests failing. Manual fixes required."
   - Provides specific failing tests
   - Suggests using `/debug` to investigate
```

---

## When NOT to Use This Skill

**Do NOT use** for:
- ❌ Mid-development (too early for push checks)
- ❌ Experimental branches (quality gates too strict)
- ❌ Draft PRs (not ready for strict checks)
- ❌ WIP commits (work in progress)

**Use manual checks** when:
- Intentionally pushing failing tests (with explanation)
- Working on feature branches (less strict)
- Experimenting with new approaches

---

## Notes

- Most conservative safety limits (3 iterations, 10m)
- Philosophy: Fail fast, don't waste time on unfixable issues
- Auto-fix only works for trivial issues (linting, formatting)
- Complex problems require manual investigation
- Prevents pushing broken code
- Can be integrated with actual git hooks
- Combines automation with strict quality gates

---

## Escalation (iteration 4)

At iteration 4 without convergence (or at this skill's own limit when lower), pause. Summarize the attempts so far and the current hypothesis, then present three options and wait for the user's choice:

1. Switch strategy: new hypothesis, different approach.
2. Hand off to the built-in /loop for self-paced retries. REQUIRES an explicit user go. Token-expensive; never start /loop on your own.
3. Stop and report findings.

Hard limits in goal-safety-config.json still apply and override everything.
