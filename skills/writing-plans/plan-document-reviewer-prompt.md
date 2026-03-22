# Plan Document Reviewer Prompt Template

Use this template when dispatching a plan document reviewer subagent.

**Purpose:** Verify the plan captures the right decisions and is actionable by an implementing agent.

**Dispatch after:** The complete plan is written.

```
Task tool (general-purpose):
  description: "Review plan document"
  prompt: |
    You are a plan document reviewer. Verify this plan is complete and ready for implementation by a capable agent.

    **Plan to review:** [PLAN_FILE_PATH]
    **Spec for reference:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | All spec requirements covered, no TODOs or placeholders |
    | Decisions | Architecture, decomposition, and interfaces are explicit — not left to the implementer |
    | Scope boundaries | Each task says what's IN and OUT of scope |
    | Constraints | Non-obvious gotchas, patterns to follow, things to avoid |
    | Testability | Behavior to test is specific enough to write assertions from |
    | Dependencies | Task ordering is correct, dependencies are stated |
    | File structure | Clear ownership — no file touched by multiple tasks without reason |

    ## Calibration

    **Only flag issues that would cause real problems during implementation.**

    An implementer building the wrong thing, making the wrong architectural choice,
    or getting stuck on an unstated constraint is an issue.

    The plan does NOT need:
    - Full implementation code (implementers read the codebase and write code)
    - Full test code (implementers follow existing test patterns)
    - Step-by-step TDD micro-instructions (the TDD skill handles ceremony)
    - Git commands or commit messages

    The plan DOES need:
    - Interface signatures when they encode design decisions
    - Specific behaviors to test (not "add tests" — what assertions?)
    - Constraints the implementer wouldn't know from reading code alone
    - References to existing patterns to follow

    Approve unless there are serious gaps — missing spec requirements,
    ambiguous interfaces, contradictory constraints, or tasks so vague
    they can't be acted on.

    ## Output Format

    ## Plan Review

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Task X]: [specific issue] - [why it would cause a problem during implementation]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Reviewer returns:** Status, Issues (if any), Recommendations
