---
name: debug-with-goal
description: "Systematic debugging with automatic iteration until the bug is fixed. Use when the user reports a bug, failing test, error, or unexpected behavior ('debug this', 'why is X failing', 'not working'). Not for feature requests or refactoring. Trigger: /debug"
---

# Debug with Goal-Driven Iteration

This skill wraps `superpowers:systematic-debugging` with automatic iteration using `/goal`, eliminating manual "test hypothesis, fail, try again" cycles.

## When This Skill Is Used

### Manual Invocation:
```bash
/debug "login form not submitting"
/debug "API returning 500 error"
```

### Automatic Invocation by Claude:
Claude should automatically use this skill when:
- ✅ User reports a bug or unexpected behavior
- ✅ User says "debug this" or "fix this bug"
- ✅ User describes something not working correctly
- ✅ Tests are failing and user wants to investigate
- ✅ User asks to troubleshoot or investigate an issue
- ❌ Do NOT auto-invoke for: feature requests, enhancements, refactoring

**Examples triggering automatic use:**
- "The login form isn't submitting"
- "API keeps returning 500 errors"
- "Why is this test failing?"
- "Debug the payment processing issue"
- "Something's wrong with the user authentication"

---

## Safety Configuration

**MANDATORY SAFETY LIMITS** (loaded from `~/.claude/skills/goal-safety-config.json`):
- **Max Iterations:** 15
- **Timeout:** 30m
- **Rationale:** Bugs may need more hypothesis iterations than features

These limits are **NON-NEGOTIABLE**.

---

## Workflow

### Phase 1: Systematic Observation
1. Invoke `superpowers:systematic-debugging` skill for scientific method
2. **Observe:** Gather information about the bug
   - What is the expected behavior?
   - What is the actual behavior?
   - Can the bug be reproduced?
   - What are the reproduction steps?
3. **Collect Evidence:**
   - Error messages and stack traces
   - Logs and console output
   - Network requests (if applicable)
   - State/data at time of failure

### Phase 2: Goal-Driven Debugging
4. Use `/goal` with mandatory safety limits:
   ```bash
   /goal "bug no longer reproduces" --max-iterations 15 --timeout 30m
   ```
5. **Scientific Method Loop:**
   - **Hypothesize:** Form hypothesis about root cause
   - **Test:** Implement fix or diagnostic code
   - **Verify:** Run reproduction steps
   - **Analyze:** Did the hypothesis hold?
   - If bug still present, form new hypothesis and repeat
6. Continue iterating until bug is fixed OR safety limit reached

### Phase 3: Verification
7. If bug is fixed:
   - Run full test suite (not just reproduction)
   - Verify no regressions introduced
   - Check edge cases
   - Document the fix and root cause

---

## Safety Limit Handling

### When Safety Limit Is Reached:

**DO:**
- ✅ Stop immediately
- ✅ Report all hypotheses tested
- ✅ Explain which hypotheses were ruled out
- ✅ Provide strongest remaining hypothesis
- ✅ Suggest next diagnostic steps

**DO NOT:**
- ❌ Claim the bug is fixed
- ❌ Continue iteration
- ❌ Guess at the solution

### Example Safety Failure Response:

```
⚠️ Safety limit reached: 15 iterations completed, bug still reproduces.

Hypotheses Tested:
1. ❌ Database connection timeout - ruled out (connections OK)
2. ❌ Race condition in async handler - ruled out (added locks, no change)
3. ❌ Invalid token format - ruled out (token validation passes)
4. ⚠️ Middleware ordering issue - partial evidence

Evidence for Middleware Theory:
- Error only occurs when auth middleware runs AFTER body parser
- Express middleware order in app.js:27-35 is suspicious
- Other routes with same pattern work (they have different order)

Strongest Hypothesis:
The auth middleware at app.js:30 tries to read req.user before body-parser
has populated it. Moving body-parser before auth middleware should fix it.

Next Steps:
1. Verify middleware order in app.js:27-35
2. Move body-parser middleware to line 28 (before auth)
3. Test with: npm run dev && curl -X POST http://localhost:3000/api/login
4. If fixed, add test to prevent regression
5. OR run `/debug "complete login bug investigation"` after manual check
```

---

## Reproduction Strategy

The skill should automatically set up reproduction:

**Auto-detect reproduction method:**
```bash
# Based on project type:
1. If test file exists: run specific test
2. If web app: describe HTTP request to reproduce
3. If CLI: describe command to reproduce
4. If script: describe how to run script
```

**After each fix attempt:**
```bash
# Run reproduction steps and capture output
npm test failing-test.test.js 2>&1

# OR for web API:
curl -X POST http://localhost:3000/api/endpoint

# Parse results:
- Success/expected output = bug fixed → goal achieved
- Still failing/unexpected = continue iteration
```

---

## Success Criteria

Goal is achieved when:
1. ✅ Reproduction steps no longer trigger the bug
2. ✅ Expected behavior occurs consistently
3. ✅ Root cause identified and documented
4. ✅ Fix verified with tests

---

## Integration with Superpowers

This skill **enhances** (not replaces) `superpowers:systematic-debugging`:

- **Superpowers Debugging** provides: scientific method, hypothesis discipline
- **This skill** adds: automatic iteration, safety limits, goal-driven execution

**Always invoke base superpowers skill first** for methodology guidance.

---

## Example Usage

### Example 1: API Error
```
User: "The /users API endpoint keeps returning 500 errors"

Claude automatically invokes debug-with-goal:

1. Observes:
   - Expected: 200 with user list
   - Actual: 500 Internal Server Error
   - Error log: "Cannot read property 'map' of undefined"

2. Uses /goal "bug no longer reproduces" --max-iterations 15 --timeout 30m

3. Hypothesis 1: Database query returns null
   - Tests: Add null check before .map()
   - Verifies: curl API endpoint
   - Result: Still failing

4. Hypothesis 2: Async query not awaited
   - Tests: Add await to database query
   - Verifies: curl API endpoint
   - Result: ✅ Bug fixed! 200 response with user list

5. Reports: "✅ Bug fixed: Database query was not awaited, causing undefined result"
```

### Example 2: Test Failure
```
User: "Why is the authentication test failing?"

Claude automatically invokes debug-with-goal:

1. Runs test to observe failure
2. Forms hypotheses about root cause
3. Uses /goal iteration to test each hypothesis
4. Fixes the bug
5. Reports success with explanation
```

---

## When NOT to Use This Skill

**Do NOT use** for:
- ❌ Feature requests or enhancements (use tdd-with-goal)
- ❌ Code refactoring (use manual approach)
- ❌ Performance optimization (different methodology)
- ❌ Architecture design (use brainstorming)
- ❌ Documentation bugs (trivial, no iteration needed)

**Use manual debugging** (superpowers:systematic-debugging without /goal) when:
- Bug requires user to perform manual steps
- Reproduction requires hardware/external services
- Issue is intermittent and hard to reproduce
- Working in unfamiliar domain (learn before automating)

---

## Notes

- Debugging often takes more iterations than TDD (hence 15 vs 10)
- Scientific method prevents "shotgun debugging"
- Safety limits prevent endless hypothesis testing
- Always document root cause when bug is fixed
- Combines systematic methodology with automation efficiency

---

## Escalation (iteration 4)

At iteration 4 without convergence (or at this skill's own limit when lower), pause. Summarize the attempts so far and the current hypothesis, then present three options and wait for the user's choice:

1. Switch strategy: new hypothesis, different approach.
2. Hand off to the built-in /loop for self-paced retries. REQUIRES an explicit user go. Token-expensive; never start /loop on your own.
3. Stop and report findings.

Hard limits in goal-safety-config.json still apply and override everything.
