---
name: tdd-with-goal
description: "Test-driven development with automatic iteration until all tests pass. Use when implementing features, functions, APIs, or fixes where the user mentions tests, TDD, or test coverage, or the logic is testable. Not for UI design, docs, or bug investigation (use debug-with-goal). Trigger: /tdd"
---

# TDD with Goal-Driven Iteration

This skill wraps `superpowers:test-driven-development` with automatic iteration using `/goal`, eliminating manual "run test, fix, repeat" cycles.

## When This Skill Is Used

### Manual Invocation:
```bash
/tdd "implement user authentication"
/tdd "add validation for email field"
```

### Automatic Invocation by Claude:
Claude should automatically use this skill when:
- ✅ User asks to implement a feature AND mentions tests/TDD
- ✅ User says "implement X with tests"
- ✅ User asks to "test drive" or "TDD" something
- ✅ Task involves implementing testable logic (functions, APIs, components)
- ❌ Do NOT auto-invoke for: UI design, documentation, research, architecture planning

**Examples triggering automatic use:**
- "Implement user login with tests"
- "Add validation function using TDD"
- "Build API endpoint with test coverage"
- "Create utility function with tests"

---

## Safety Configuration

**MANDATORY SAFETY LIMITS** (loaded from `~/.claude/skills/goal-safety-config.json`):
- **Max Iterations:** 10
- **Timeout:** 20m
- **Rationale:** Most features should pass tests within 10 attempts

These limits are **NON-NEGOTIABLE**. If user requests higher limits, explain the risks and refuse.

---

## Workflow

### Phase 1: Test-First (Red Phase)
1. Invoke `superpowers:test-driven-development` skill for TDD methodology
2. Understand the feature requirements
3. Write **failing tests first**:
   - Unit tests for core logic
   - Integration tests if needed
   - Edge cases and error conditions
4. Run tests to confirm they fail (red phase)
5. Explain what the tests expect

### Phase 2: Goal-Driven Implementation (Green Phase)
6. Use `/goal` with mandatory safety limits:
   ```bash
   /goal "all tests pass" --max-iterations 10 --timeout 20m
   ```
7. Implement the feature to make tests pass
8. Run tests automatically
9. If tests fail:
   - Analyze failure output
   - Fix implementation
   - Re-run tests
   - Repeat until tests pass OR safety limit reached
10. Continue iterating until ALL tests pass

### Phase 3: Refactor (If Time Permits)
11. If tests pass before safety limits:
    - Review code quality
    - Refactor for clarity/performance
    - Ensure tests still pass after refactoring

---

## Safety Limit Handling

### When Safety Limit Is Reached:

**DO:**
- ✅ Stop immediately
- ✅ Report progress: which tests pass, which fail
- ✅ Explain what's working and what isn't
- ✅ Provide specific next steps

**DO NOT:**
- ❌ Claim the feature is complete
- ❌ Continue iteration
- ❌ Ignore the safety limit

### Example Safety Failure Response:

```
⚠️ Safety limit reached: 10 iterations completed, goal not achieved.

Progress:
- ✅ 4 of 6 tests passing
- ✅ Core login logic implemented
- ✅ Password validation working
- ❌ Session token generation failing (TypeError: token.sign is not a function)
- ❌ Logout test failing (depends on token generation)

Analysis:
The token generation is using an incorrect API. Line 34 in auth.js tries to call
token.sign() but should use jwt.sign(payload, secret).

Next steps:
1. Fix token generation: change token.sign() to jwt.sign() in auth.js:34
2. Verify jwt library is imported: const jwt = require('jsonwebtoken')
3. Run `/tdd "complete login feature"` to retry with fix
4. OR manually fix and run tests: npm test auth.test.js
```

---

## Test Execution

The skill should automatically run tests using the project's test command:

**Auto-detect test command:**
```bash
# Try in order:
1. npm test (if package.json exists)
2. pytest (if Python project)
3. cargo test (if Rust project)
4. go test ./... (if Go project)
5. Check package.json scripts for "test" command
```

**After each implementation iteration:**
```bash
# Run tests and capture output
npm test 2>&1

# Parse results:
- Exit code 0 = all tests pass → goal achieved
- Exit code non-zero = tests failing → continue iteration
```

---

## Success Criteria

Goal is achieved when:
1. ✅ All tests pass (exit code 0)
2. ✅ No test failures or errors
3. ✅ Test output shows green/passing status

---

## Integration with Superpowers

This skill **enhances** (not replaces) `superpowers:test-driven-development`:

- **Superpowers TDD** provides: methodology, best practices, discipline
- **This skill** adds: automatic iteration, safety limits, goal-driven execution

**Always invoke base superpowers skill first** for methodology guidance, then apply goal-driven iteration.

---

## Example Usage

### Example 1: Simple Function
```
User: "Implement a function to validate email addresses with tests"

Claude automatically invokes tdd-with-goal:
1. Writes failing test:
   test('validates email format', () => {
     expect(validateEmail('user@example.com')).toBe(true);
     expect(validateEmail('invalid')).toBe(false);
   });

2. Runs test → fails (function doesn't exist)

3. Uses /goal "all tests pass" --max-iterations 10 --timeout 20m

4. Implements validateEmail function

5. Runs test → passes!

6. Reports: "✅ Email validation implemented with passing tests"
```

### Example 2: API Endpoint
```
User: "Build POST /users endpoint with TDD"

Claude automatically invokes tdd-with-goal:
1. Writes failing integration tests
2. Implements endpoint using /goal iteration
3. Tests fail → fixes → retries → tests pass
4. Reports success with passing tests
```

---

## When NOT to Use This Skill

**Do NOT use** for:
- ❌ Tasks without clear test criteria
- ❌ UI/design work (use frontend-design instead)
- ❌ Documentation (no tests to verify)
- ❌ Architecture/planning (use brainstorming instead)
- ❌ Research or exploration
- ❌ Bug investigation (use debug-with-goal instead)

**Use manual TDD** (superpowers:test-driven-development without /goal) when:
- Tests require human judgment
- Feature needs design exploration first
- Working in unfamiliar domain (learn before automating)

---

## Notes

- This skill saves 3-5 manual iteration cycles on average
- Safety limits prevent runaway execution
- Works best for features with clear requirements
- Combines TDD discipline with automation efficiency
- Always runs actual tests (not simulated)

---

## Escalation (iteration 4)

At iteration 4 without convergence (or at this skill's own limit when lower), pause. Summarize the attempts so far and the current hypothesis, then present three options and wait for the user's choice:

1. Switch strategy: new hypothesis, different approach.
2. Hand off to the built-in /loop for self-paced retries. REQUIRES an explicit user go. Token-expensive; never start /loop on your own.
3. Stop and report findings.

Hard limits in goal-safety-config.json still apply and override everything.
