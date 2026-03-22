---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write implementation plans that capture **decisions**, not code. The implementing agent is capable — it can read files, understand patterns, write tests, and figure out implementation details. What it can't do is make architectural decisions, know scope boundaries, or understand constraints that aren't in the code.

Your plan should answer: *what* to build, *where* to put it, *how the pieces connect*, and *what not to do*. Let the implementer figure out the code.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Granularity

Each task should be a coherent unit of work that produces a testable result. A task might be:
- "Implement the token refresh module with retry logic"
- "Add validation middleware for the /users endpoint"
- "Create the database migration and model for audit logs"

A task should NOT be a single TDD micro-step like "write the failing test" or "run the test." The implementer follows TDD discipline on its own — the plan doesn't need to spell out every red-green-refactor cycle.

**Right-size a task:** Small enough that a single agent can hold the context. Large enough to be a meaningful, committable unit. Typically 1-3 files changed.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py` (specifically: the `authenticate()` method)
- Test: `tests/exact/path/to/test_file.py`

**What to build:**
[1-3 sentences describing the component's purpose and behavior]

**Interface:**
```python
def refresh_token(token: str, max_retries: int = 3) -> TokenResult:
    """Refresh an expired auth token with retry logic.
    Returns TokenResult with new token or raises AuthError after exhausting retries."""
```

**Behavior to test:**
- Successful refresh returns new token with updated expiry
- Expired refresh token raises `AuthError`
- Retries on transient network errors up to `max_retries`
- Does NOT retry on 401 (invalid credentials — distinct from expired)

**Constraints:**
- Must use the existing `HttpClient` from `src/http.py`, not raw requests
- Token storage goes through `TokenStore` interface, not direct file I/O
- Follow the retry pattern in `src/jobs/retry.py` (exponential backoff)

**Depends on:** Task 1 (TokenStore interface)
````

## What Goes in the Plan vs. What Doesn't

**Include — decisions the implementer shouldn't make alone:**
- Exact file paths and what each file is responsible for
- Interface signatures (function/class/API contracts)
- What behaviors to test (assertions, not full test code)
- Constraints and gotchas (things they'd get wrong without being told)
- Dependencies between tasks
- Which existing code to reuse or follow as a pattern
- What is explicitly OUT of scope for each task

**Omit — things the implementer can figure out by reading the codebase:**
- Full implementation code (they'll write better code after reading actual files)
- Full test code (they can follow existing test patterns)
- Exact git commands and commit messages
- Step-by-step TDD ceremony (the test-driven-development skill handles this)
- Boilerplate they can infer from surrounding code

**The test:** If you deleted the plan and just gave someone the spec + file structure + interface contracts + constraints, could they build it? If yes, the plan has the right level of detail. If they'd make wrong architectural choices, add more guidance on *decisions*. If they'd write the wrong code, that's what tests and review catch — not the plan.

## When to Include Code

Sometimes a code snippet IS the clearest way to communicate a decision. Use code when:

- The interface signature captures a design decision (parameters, return types, error types)
- A data structure defines the shape of something (schema, config format)
- A non-obvious algorithm or pattern needs to be specified (not "add validation" but not full implementation either — show the approach)
- An existing codebase pattern should be followed (show a 5-line example from the codebase, say "follow this pattern")

Don't include code just to be thorough. Include it when it communicates a decision more precisely than prose.

## Remember
- Exact file paths always
- Decisions, interfaces, and constraints — not complete code
- Behavior to test, not full test implementations
- Reference existing code patterns the implementer should follow
- DRY, YAGNI, TDD, frequent commits

## Plan Review Loop

After writing the complete plan, offer a combined review:

> "Plan written. How would you like it reviewed?"
>
> 1. **3-way review** — subagent + Codex + Gemini (recommended for complex plans)
> 2. **Subagent only** — standard plan-document-reviewer
> 3. **Skip review** — go straight to execution handoff

**If 3-way review:** Run the plan-document-reviewer subagent and external AI consultations in parallel. The subagent uses the plan-document-reviewer-prompt.md template. External AIs get the plan and spec file paths and a plan critique prompt via consulting-other-ais (focus: task structure, ordering, missed dependencies, unnecessary complexity). Synthesize all findings into a single list of issues, noting which reviewer raised each one.

**If subagent only:** Dispatch plan-document-reviewer subagent as usual (see plan-document-reviewer-prompt.md). Provide path to the plan document and spec document. Never send your session history.

**For both paths:**
1. If ❌ Issues Found: fix the issues, re-review (re-run whichever reviewers were used)
2. If ✅ Approved: proceed to execution handoff
3. If loop exceeds 3 iterations, surface to human for guidance

**Review loop guidance:**
- Same agent that wrote the plan fixes it (preserves context)
- Reviewers are advisory — explain disagreements if you believe feedback is incorrect

## Execution Handoff

After saving the plan:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Ready to execute?"**

**Execution path depends on harness capabilities:**

**If harness has subagents (Claude Code, etc.):**
- **REQUIRED:** Use superpowers:subagent-driven-development
- Do NOT offer a choice - subagent-driven is the standard approach
- Fresh subagent per task + two-stage review

**If harness does NOT have subagents:**
- Execute plan in current session using superpowers:executing-plans
- Batch execution with checkpoints for review
