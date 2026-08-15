---
name: build-with-goal
description: "Complete feature pipeline: brainstorm the design, then test-driven implementation with automatic iteration. Use for substantial multi-component features ('build X', 'create X feature') needing design plus implementation. Not for small utilities (/tdd) or bug fixes (/debug). Trigger: /build"
---

# Build with Goal-Driven Pipeline

This skill chains `superpowers:brainstorming` → implementation → `tdd-with-goal`, creating a complete end-to-end feature development workflow with automatic iteration.

## When This Skill Is Used

### Manual Invocation:
```bash
/build "user authentication system"
/build "shopping cart feature"
```

### Automatic Invocation by Claude:
Claude should automatically use this skill when:
- ✅ User requests a complete feature (not just implementation)
- ✅ User says "build X" or "create X feature"
- ✅ Task requires both design thinking AND implementation
- ✅ Feature is substantial (not trivial single function)
- ✅ User wants end-to-end delivery
- ❌ Do NOT auto-invoke for: small utilities, bug fixes, refactoring

**Examples triggering automatic use:**
- "Build a user authentication system"
- "Create a shopping cart feature"
- "Build an admin dashboard"
- "Implement a notification system"

---

## Safety Configuration

**MANDATORY SAFETY LIMITS** (loaded from `~/.claude/skills/goal-safety-config.json`):
- **Max Iterations:** 25
- **Timeout:** 60m
- **Rationale:** Full pipeline (brainstorm → implement → test) takes longer

These limits are **NON-NEGOTIABLE**.

---

## Workflow

### Phase 1: Design Exploration (Brainstorming)
1. Invoke `superpowers:brainstorming` skill for requirements exploration
2. **Understand Intent:**
   - What problem does this solve?
   - Who are the users?
   - What are the core requirements?
   - What are the edge cases?
3. **Explore Design:**
   - What are the components/modules?
   - What's the API surface?
   - What are the dependencies?
   - What are the technical constraints?
4. **Clarify with User:**
   - Ask questions about ambiguous requirements
   - Confirm design decisions
   - Get approval on approach before implementation

### Phase 1c: Least Confident Decisions

Before implementation starts, list the calls you are least sure about, numbered,
one line each. Design choices you guessed at, not risks in general. Changing
them now costs a sentence. Ask the user to challenge any of them, then proceed.

### Phase 2: Test-Driven Implementation
5. Once design is settled, invoke `tdd-with-goal` skill
6. Write comprehensive tests covering:
   - Core functionality
   - Edge cases
   - Error conditions
   - Integration points
7. Use `/goal` with mandatory safety limits:
   ```bash
   /goal "feature complete with passing tests" --max-iterations 25 --timeout 60m
   ```
8. Implement feature using TDD methodology
9. Iterate automatically until all tests pass

### Phase 3: Verification & Documentation
10. If feature complete before safety limits:
    - Run full test suite (not just new tests)
    - Verify integration with existing code
    - Document usage and API
    - Suggest next steps or enhancements

---

## Safety Limit Handling

### When Safety Limit Is Reached:

**DO:**
- ✅ Stop immediately
- ✅ Report what's complete and what's remaining
- ✅ Show which components work and which don't
- ✅ Provide implementation plan for remaining work

**DO NOT:**
- ❌ Claim the feature is complete
- ❌ Skip critical components
- ❌ Continue iteration

### Example Safety Failure Response:

```
⚠️ Safety limit reached: 25 iterations completed, feature partially complete.

Completed:
- ✅ User registration with email validation
- ✅ Password hashing and storage
- ✅ Login endpoint with JWT generation
- ✅ Tests passing for registration and login (12/15 tests)

Remaining:
- ❌ Password reset flow (3 tests failing)
- ❌ Session refresh logic (not yet implemented)
- ❌ Email verification (not yet implemented)

Progress: ~70% complete (core auth working, advanced features pending)

Next Steps:
1. Focus on password reset: `/tdd "implement password reset"`
2. Or continue full build: `/build "complete authentication system"`
3. Or manually implement remaining features and use `/verify`

The core authentication (register + login) is production-ready.
Advanced features can be added incrementally.
```

---

## Feature Scope Guidance

**Good Fits for /build:**
- Complete user-facing features
- New subsystems or modules
- Multi-component functionality
- Features requiring design decisions

**Better handled by /tdd:**
- Single utility functions
- Isolated components
- Clear requirements (no design needed)
- Bug fixes or refactoring

**When in doubt:** Start with `/build` - it will invoke `/tdd` automatically for implementation phase.

---

## Integration with Other Skills

This skill **orchestrates** multiple skills:

1. **superpowers:brainstorming** - Requirements and design
2. **tdd-with-goal** - Test-driven implementation
3. **superpowers:verification-before-completion** - Final verification

**Execution flow:**
```
/build "feature"
  ↓
brainstorming (design phase)
  ↓
tdd-with-goal (implementation phase with /goal iteration)
  ↓
verification (quality check)
  ↓
Done: Feature complete with tests
```

---

## Success Criteria

Goal is achieved when:
1. ✅ Requirements clear and documented
2. ✅ Design approved by user
3. ✅ All tests passing
4. ✅ Feature integrated with existing code
5. ✅ Documentation complete
6. ✅ No regressions introduced

---

## Example Usage

### Example 1: Authentication System
```
User: "Build a user authentication system"

Claude automatically invokes build-with-goal:

1. Brainstorming Phase:
   - Questions user about requirements:
     * Email or username login?
     * OAuth providers needed?
     * Password reset required?
     * Session management approach?
   - User confirms: Email login, JWT tokens, password reset, no OAuth

2. Design Phase:
   - Proposes architecture:
     * User model with bcrypt password hashing
     * POST /auth/register and /auth/login endpoints
     * JWT token generation and validation
     * POST /auth/reset-password endpoint
   - User approves design

3. Implementation Phase (with /goal):
   - Invokes tdd-with-goal
   - Writes tests for all endpoints
   - Implements auth system
   - Iterates automatically until tests pass

4. Reports: "✅ Authentication system complete with 15 passing tests"
```

### Example 2: Shopping Cart
```
User: "Build a shopping cart feature"

Claude automatically invokes build-with-goal:

1. Explores requirements (brainstorming)
2. Designs cart data structure and API
3. Implements with TDD (automatic iteration)
4. Delivers complete feature with tests
```

---

## When NOT to Use This Skill

**Do NOT use** for:
- ❌ Trivial functions (use /tdd directly)
- ❌ Bug fixes (use /debug)
- ❌ Refactoring (use manual approach)
- ❌ Documentation (use /document)
- ❌ Research or exploration (use brainstorming only)

**Use /tdd instead** when:
- Requirements already clear
- No design decisions needed
- Single component or function
- Just need implementation + tests

---

## Notes

- Longest running skill (25 iterations, 60m timeout)
- Combines human judgment (design) with automation (implementation)
- Safety limits prevent over-engineering
- Best for medium-to-large features
- Breaks down work systematically
- User can stop after brainstorming phase if design needs revision

---

## Escalation (iteration 4)

At iteration 4 without convergence (or at this skill's own limit when lower), pause. Summarize the attempts so far and the current hypothesis, then present three options and wait for the user's choice:

1. Switch strategy: new hypothesis, different approach.
2. Hand off to the built-in /loop for self-paced retries. REQUIRES an explicit user go. Token-expensive; never start /loop on your own.
3. Stop and report findings.

Hard limits in goal-safety-config.json still apply and override everything.
