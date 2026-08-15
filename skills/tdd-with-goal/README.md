# TDD with Goal - Implementation Summary

## What Was Implemented

A new skill that combines Test-Driven Development methodology with automatic iteration using `/goal`, eliminating manual "run test, fix, repeat" cycles.

## Files Created

1. **`~/.claude/skills/tdd-with-goal/SKILL.md`** - Main skill definition
2. **`~/.claude/skills/goal-safety-config.json`** - Centralized safety limits
3. **`~/.claude/CLAUDE.md`** - Updated with automatic invocation rules

## How It Works

### Manual Invocation
```bash
/tdd "implement user authentication"
```

### Automatic Invocation
Claude automatically uses this skill when user asks for implementation with tests:
- "Implement user login with tests"
- "Add email validation using TDD"
- "Build API endpoint with test coverage"

### Safety Measures (Mandatory)
- **Max Iterations:** 10
- **Timeout:** 20 minutes
- **Emergency Kill Switch:** Global limit of 30 iterations / 90 minutes

### Workflow
1. **Red Phase:** Write failing tests first
2. **Green Phase:** Use `/goal "all tests pass"` to iterate implementation automatically
3. **Refactor Phase:** Clean up code while maintaining passing tests

### Safety Failure Handling
When limits are reached:
- ✅ Reports progress (which tests pass/fail)
- ✅ Explains what's working and what isn't
- ✅ Provides specific next steps
- ❌ NEVER claims success if goal not met

## Value Proposition

**Before (without /goal):**
```
User: "Implement login with tests"
→ Claude writes test + implementation
→ User runs tests → failure
→ User: "fix it"
→ Claude fixes
→ User runs tests → still failing
→ User: "fix it again"
→ Repeat 3-5 times
```

**After (with /goal):**
```
User: "Implement login with tests"
→ Claude automatically invokes tdd-with-goal
→ Writes tests → implements → runs → fixes → repeats automatically
→ User gets working code with passing tests in one shot
```

**Time Saved:** Eliminates 3-5 manual iteration cycles per feature

## When NOT to Use

- ❌ UI/design work (use frontend-design)
- ❌ Documentation tasks
- ❌ Architecture/planning (use brainstorming)
- ❌ Bug investigation (use debug-with-goal when available)
- ❌ Tasks without clear test criteria

## Safety Configuration

All safety limits are centralized in `~/.claude/skills/goal-safety-config.json`:

```json
{
  "tdd-with-goal": {
    "maxIterations": 10,
    "timeout": "20m",
    "description": "Most features should pass tests within 10 attempts"
  }
}
```

## Integration with Superpowers

This skill **enhances** (not replaces) `superpowers:test-driven-development`:
- **Superpowers TDD:** Provides methodology and best practices
- **tdd-with-goal:** Adds automatic iteration and safety limits

## Testing the Skill

Try it with a simple feature:
```bash
/tdd "implement a function to add two numbers with tests"
```

Expected behavior:
1. Claude writes failing test
2. Claude implements add function using /goal iteration
3. Tests pass automatically
4. Claude reports success with passing tests

## Goal-Driven Skills Suite

All 5 skills are implemented and use the same safety configuration system:
- [x] `/tdd` - TDD with automatic iteration (this skill)
- [x] `/debug` - Systematic debugging with auto-iteration
- [x] `/build` - Full feature pipeline (brainstorm → implement → test)
- [x] `/pre-push` - Auto-fix quality issues before push
- [x] `/document` - Auto-complete documentation
