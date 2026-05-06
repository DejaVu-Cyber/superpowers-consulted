---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

Execute plan by dispatching a fresh isolated implementation agent per task, with two-stage review after each: spec compliance review first (Codex for an independent second opinion, local review-agent fallback), then code quality review.

**Why isolated agents:** You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Core principle:** Fresh isolated agent per task + two-stage review (spec then quality) = high quality, fast iteration

## When to Use

```dot
digraph when_to_use {
    "Have implementation plan?" [shape=diamond];
    "Tasks mostly independent?" [shape=diamond];
    "Stay in this session?" [shape=diamond];
    "subagent-driven-development" [shape=box];
    "executing-plans" [shape=box];
    "Manual execution or brainstorm first" [shape=box];

    "Have implementation plan?" -> "Tasks mostly independent?" [label="yes"];
    "Have implementation plan?" -> "Manual execution or brainstorm first" [label="no"];
    "Tasks mostly independent?" -> "Stay in this session?" [label="yes"];
    "Tasks mostly independent?" -> "Manual execution or brainstorm first" [label="no - tightly coupled"];
    "Stay in this session?" -> "subagent-driven-development" [label="yes"];
    "Stay in this session?" -> "executing-plans" [label="no - parallel session"];
}
```

**vs. Executing Plans (parallel session):**
- Same session (no context switch)
- Fresh isolated agent per task (no context pollution)
- Two-stage review after each task: spec compliance first, then code quality
- Faster iteration (no human-in-loop between tasks)

## The Process

```dot
digraph process {
    rankdir=TB;

    subgraph cluster_per_task {
        label="Per Task";
        "Dispatch implementer agent (./implementer-prompt.md)" [shape=box];
        "Implementer agent asks questions?" [shape=diamond];
        "Answer questions, provide context" [shape=box];
        "Implementer agent implements, tests, commits, self-reviews" [shape=box];
        "Run spec reviewer (Codex if available, local reviewer agent fallback — ./spec-reviewer-prompt.md)" [shape=box];
        "Spec reviewer confirms code matches spec?" [shape=diamond];
        "Implementer agent fixes spec gaps" [shape=box];
        "Dispatch code quality reviewer agent (./code-quality-reviewer-prompt.md)" [shape=box];
        "Code quality reviewer agent approves?" [shape=diamond];
        "Implementer agent fixes quality issues" [shape=box];
        "Mark task complete in task tracker" [shape=box];
    }

    "Read plan, extract all tasks with full text, note context, create task tracker" [shape=box];
    "More tasks remain?" [shape=diamond];
    "Offer final review: 3-way / local-only / skip" [shape=diamond];
    "3-way review: local reviewer agent + Codex + Gemini vs plan" [shape=box];
    "Dispatch final code reviewer agent for entire implementation" [shape=box];
    "Synthesize all review perspectives" [shape=box];
    "Use superpowers:finishing-a-development-branch" [shape=box style=filled fillcolor=lightgreen];

    "Read plan, extract all tasks with full text, note context, create task tracker" -> "Dispatch implementer agent (./implementer-prompt.md)";
    "Dispatch implementer agent (./implementer-prompt.md)" -> "Implementer agent asks questions?";
    "Implementer agent asks questions?" -> "Answer questions, provide context" [label="yes"];
    "Answer questions, provide context" -> "Dispatch implementer agent (./implementer-prompt.md)";
    "Implementer agent asks questions?" -> "Implementer agent implements, tests, commits, self-reviews" [label="no"];
    "Implementer agent implements, tests, commits, self-reviews" -> "Run spec reviewer (Codex if available, local reviewer agent fallback — ./spec-reviewer-prompt.md)";
    "Run spec reviewer (Codex if available, local reviewer agent fallback — ./spec-reviewer-prompt.md)" -> "Spec reviewer confirms code matches spec?";
    "Spec reviewer confirms code matches spec?" -> "Implementer agent fixes spec gaps" [label="no"];
    "Implementer agent fixes spec gaps" -> "Run spec reviewer (Codex if available, local reviewer agent fallback — ./spec-reviewer-prompt.md)" [label="re-review with prior findings + new SHA"];
    "Spec reviewer confirms code matches spec?" -> "Dispatch code quality reviewer agent (./code-quality-reviewer-prompt.md)" [label="yes"];
    "Dispatch code quality reviewer agent (./code-quality-reviewer-prompt.md)" -> "Code quality reviewer agent approves?";
    "Code quality reviewer agent approves?" -> "Implementer agent fixes quality issues" [label="no"];
    "Implementer agent fixes quality issues" -> "Dispatch code quality reviewer agent (./code-quality-reviewer-prompt.md)" [label="re-review"];
    "Code quality reviewer agent approves?" -> "Mark task complete in task tracker" [label="yes"];
    "Mark task complete in task tracker" -> "More tasks remain?";
    "More tasks remain?" -> "Dispatch implementer agent (./implementer-prompt.md)" [label="yes"];
    "More tasks remain?" -> "Offer final review: 3-way / local-only / skip" [label="no"];
    "Offer final review: 3-way / local-only / skip" -> "3-way review: local reviewer agent + Codex + Gemini vs plan" [label="3-way"];
    "Offer final review: 3-way / local-only / skip" -> "Dispatch final code reviewer agent for entire implementation" [label="local-only"];
    "Offer final review: 3-way / local-only / skip" -> "Use superpowers:finishing-a-development-branch" [label="skip"];
    "3-way review: local reviewer agent + Codex + Gemini vs plan" -> "Synthesize all review perspectives";
    "Dispatch final code reviewer agent for entire implementation" -> "Use superpowers:finishing-a-development-branch";
    "Synthesize all review perspectives" -> "Use superpowers:finishing-a-development-branch";
}
```

## Platform Adapters

Follow this workflow by capability, not literal tool name.

Claude Code:
- Use Task/Agent for implementer and reviewer agents.
- Use TodoWrite for the task tracker.
- Use the prompt templates in this directory as dispatched agent prompts.

Codex:
- Read `../using-superpowers/references/codex-tools.md` before dispatching agents.
- Use `update_plan` for the task tracker.
- Use `spawn_agent` with `agent_type: worker` for implementation tasks. Give each worker explicit ownership of the task files/modules, tell it it is not alone in the codebase, and tell it not to revert others' edits.
- Use `spawn_agent` with `agent_type: explorer` for read-only reviewer fallbacks. Use `worker` only if asking the reviewer to patch issues directly.
- Use `wait_agent` only when the next controller step needs that result, and `close_agent` after integrating the result.

## Model Selection

Use the least powerful model that can handle each role to conserve cost and increase speed.

**Mechanical implementation tasks** (isolated functions, clear specs, 1-2 files): use a fast, cheap model. Most implementation tasks are mechanical when the plan is well-specified.

**Integration and judgment tasks** (multi-file coordination, pattern matching, debugging): use a standard model.

**Architecture, design, and review tasks**: use the most capable available model.

**Task complexity signals:**
- Touches 1-2 files with a complete spec → cheap model
- Touches multiple files with integration concerns → standard model
- Requires design judgment or broad codebase understanding → most capable model

## Handling Implementer Status

Implementer agents report one of four statuses. Handle each appropriately:

**DONE:** Proceed to spec compliance review.

**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.

**NEEDS_CONTEXT:** The implementer needs information that wasn't provided. Provide the missing context and re-dispatch.

**BLOCKED:** The implementer cannot complete the task. Assess the blocker:
1. If it's a context problem, provide more context and re-dispatch with the same model
2. If the task requires more reasoning, re-dispatch with a more capable model
3. If the task is too large, break it into smaller pieces
4. If the plan itself is wrong, escalate to the human

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

## Spec Compliance Review (Per Task)

Spec review runs as a stateless, one-shot review against the current HEAD of the implementer's work. Codex is preferred for an independent second opinion outside the main session's context; a local isolated reviewer agent is the fallback.

**Provider selection (once per run):**

1. At skill start, run `skills/consulting-other-ais/scripts/consult.sh check`
2. If Codex is available → use Codex path for all per-task spec reviews
3. If not → use local reviewer-agent path

Cache the choice. Don't re-probe per task.

**Review round (same for both providers):**

Invoke with the prompt in `./spec-reviewer-prompt.md`, substituting:
- Task requirement text
- Implementer's report
- BASE_SHA (before implementer started) and HEAD_SHA (current)
- Prior findings — `(none — first review)` initially, or previous round's issue list on re-review

The reviewer reads code from the repo directly. Don't paste file contents.

**Re-review after implementer fix:**

Stateless — start a fresh provider call. Pass the *same* task text, the *new* HEAD_SHA, and the *previous round's findings* as `PRIOR_FINDINGS` so the reviewer verifies each item was resolved, not just that the code compiles.

Loop until reviewer returns ✅, then proceed to code quality review.

**Fallback mid-run:** if a Codex call returns soft-failure language despite `consult.sh`'s auto-retry, switch to the local reviewer-agent path for the rest of the run.

## Linear Ticket Tracking

When this skill is invoked from the `decompose-to-tickets` local execution path, Linear tickets exist for each task. After each task is marked complete (both reviews passed):

1. Find the corresponding Linear ticket (match by task title or ticket identifier from the plan)
2. Move the ticket to "Done" state using Linear MCP tools, the `linear` skill, or `curl` with `$LINEAR_API_KEY`
3. Post a brief completion comment to the ticket referencing the commit or PR

This keeps Linear in sync without making it the source of truth for implementation. The plan/spec files remain the implementation source — Linear is the tracking layer.

**If Linear is unavailable** (API error, missing key, network issues), log a warning and continue execution. Ticket closure is tracking, not a gate — never block implementation progress on a Linear API failure.

**If invoked directly from a plan** (without decompose-to-tickets in the chain), skip this section entirely — there are no Linear tickets to close.

## Prompt Templates

- `./implementer-prompt.md` - Dispatch isolated implementer agent
- `./spec-reviewer-prompt.md` - Dispatch spec compliance reviewer
- `./code-quality-reviewer-prompt.md` - Dispatch code quality reviewer

## Example Workflow

```
You: I'm using Subagent-Driven Development to execute this plan.

[Read plan file once: docs/superpowers/plans/feature-plan.md]
[Extract all 5 tasks with full text and context]
[Create task tracker with all tasks]

Task 1: Hook installation script

[Get Task 1 text and context (already extracted)]
[Dispatch isolated implementation agent with full task text + context]

Implementer: "Before I begin - should the hook be installed at user or system level?"

You: "User level (~/.config/superpowers/hooks/)"

Implementer: "Got it. Implementing now..."
[Later] Implementer:
  - Implemented install-hook command
  - Added tests, 5/5 passing
  - Self-review: Found I missed --force flag, added it
  - Committed

[Run spec compliance review via Codex (or local reviewer agent if Codex unavailable)]
Spec reviewer: ✅ Spec compliant - all requirements met, nothing extra

[Get git SHAs, dispatch code quality reviewer]
Code reviewer: Strengths: Good test coverage, clean. Issues: None. Approved.

[Mark Task 1 complete]

Task 2: Recovery modes

[Get Task 2 text and context (already extracted)]
[Dispatch isolated implementation agent with full task text + context]

Implementer: [No questions, proceeds]
Implementer:
  - Added verify/repair modes
  - 8/8 tests passing
  - Self-review: All good
  - Committed

[Run spec compliance review via Codex]
Spec reviewer: ❌ Issues:
  - Missing: Progress reporting (spec says "report every 100 items")
  - Extra: Added --json flag (not requested)

[Implementer fixes issues]
Implementer: Removed --json flag, added progress reporting

[Re-review via Codex — new HEAD_SHA + prior findings passed in]
Spec reviewer: ✅ Spec compliant now — both prior findings RESOLVED

[Dispatch code quality reviewer]
Code reviewer: Strengths: Solid. Issues (Important): Magic number (100)

[Implementer fixes]
Implementer: Extracted PROGRESS_INTERVAL constant

[Code reviewer reviews again]
Code reviewer: ✅ Approved

[Mark Task 2 complete]

...

[After all tasks]

You: All tasks complete. How would you like the final review?
  1. 3-way review — local reviewer agent + Codex + Gemini review against plan
  2. Local reviewer only — local code reviewer
  3. Skip final review

User: 1

[local reviewer agent dispatched with full implementation range]
[Codex + Gemini consulted in parallel with plan compliance prompt]

local reviewer agent: Clean architecture, all tests pass, minor naming nit
Codex: All 5 plan tasks implemented. Task 3 spec says "retry 3 times" but code retries twice.
Gemini: Plan says "log to structured JSON" but logging uses plain text in task 4.

You: Two plan deviations found:
  - Task 3: retry count is 2, plan says 3 → fix
  - Task 4: plain text logging, plan says structured JSON → fix

[Fix both, re-run tests]
Done!
```

## Final Review: Plan Compliance

After all tasks are complete, offer a final review that checks the entire implementation against the original plan and spec. This catches cross-task issues and plan deviations that per-task reviews miss.

### Offer the Review

```
All tasks complete. How would you like the final review?

1. **3-way review** — local reviewer agent reviews code quality while Codex + Gemini
   review implementation against the plan (recommended for non-trivial plans)
2. **Local reviewer only** — local code reviewer for the full implementation
3. **Skip** — Proceed directly to finishing the branch

Which option?
```

### Option 1: 3-Way Plan Compliance Review

Run in parallel:

**A. Local reviewer agent** — Standard final code review. Dispatch with `requesting-code-review/code-reviewer.md` template, using the BASE_SHA from before the first task and HEAD_SHA from after the last.

**B. External AIs vs plan** — Use `consulting-other-ais` to send Codex and Gemini a plan compliance prompt. The prompt should include:

- Path to the plan file
- Path to the spec file (if separate)
- The git diff range (base..HEAD) or instruct them to run `git diff <base>..<head>`
- A focused compliance question

**Plan compliance prompt template:**

```
Review this implementation against its plan and spec.

Plan: [path/to/plan.md]
Spec: [path/to/spec.md]
Implementation diff: run `git diff <BASE_SHA>..<HEAD_SHA>`

For each task in the plan, verify:
1. Was it implemented? (yes/no/partial)
2. Does it match the spec's requirements exactly?
3. Any deviations — intentional simplifications, missing edge cases, or scope creep?

Also check cross-cutting concerns:
- Are all plan tasks accounted for?
- Do the pieces integrate correctly?
- Any spec requirements that no task covers?

Be specific — reference plan task numbers, spec sections, and code file:line.
Output a task-by-task compliance table, then list any issues.
```

**Synthesize** — Present all three perspectives with clear attribution:

```
**Local reviewer agent (code quality):**
[summary — strengths, issues by severity, assessment]

**Codex (plan compliance):**
[task-by-task status, deviations found]

**Gemini (plan compliance):**
[task-by-task status, deviations found]

**Synthesis:**
- Agreed: [what all reviewers confirm is solid]
- Plan deviations: [list with task numbers]
- Code issues: [from local reviewer agent]
- Recommendation: [fix list before proceeding, or ready to go]
```

If deviations are found, fix them before proceeding to `finishing-a-development-branch`. Re-run tests after fixes.

### Option 2: Local Reviewer Only

Dispatch the standard final code-reviewer agent. Use the full implementation range (BASE_SHA from before first task to current HEAD).

### Option 3: Skip

Proceed directly to `finishing-a-development-branch`.

## Advantages

**vs. Manual execution:**
- Isolated implementation agents follow TDD naturally
- Fresh context per task (no confusion)
- Parallel-safe (agents have explicit ownership boundaries)
- Implementation agent can ask questions (before AND during work)

**vs. Executing Plans:**
- Same session (no handoff)
- Continuous progress (no waiting)
- Review checkpoints automatic

**Efficiency gains:**
- No file reading overhead (controller provides full text)
- Controller curates exactly what context is needed
- Implementation agent gets complete information upfront
- Questions surfaced before work begins (not after)

**Quality gates:**
- Self-review catches issues before handoff
- Two-stage review: spec compliance, then code quality
- Review loops ensure fixes actually work
- Spec compliance prevents over/under-building
- Code quality ensures implementation is well-built

**Cost:**
- More isolated-agent invocations (implementer + 2 reviewers per task)
- Controller does more prep work (extracting all tasks upfront)
- Review loops add iterations
- But catches issues early (cheaper than debugging later)

## Red Flags

**Never:**
- Start implementation on main/master branch without explicit user consent
- Skip reviews (spec compliance OR code quality)
- Proceed with unfixed issues
- Dispatch multiple implementation agents in parallel (conflicts)
- Make the implementation agent read plan file (provide full text instead)
- Skip scene-setting context (the implementation agent needs to understand where task fits)
- Ignore implementation-agent questions (answer before letting them proceed)
- Accept "close enough" on spec compliance (spec reviewer found issues = not done)
- Skip review loops (reviewer found issues = implementer fixes = review again)
- Let implementer self-review replace actual review (both are needed)
- **Start code quality review before spec compliance is ✅** (wrong order)
- Move to next task while either review has open issues

**If implementation agent asks questions:**
- Answer clearly and completely
- Provide additional context if needed
- Don't rush them into implementation

**If reviewer finds issues:**
- Implementer (same isolated agent, when available) fixes them
- Reviewer reviews again
- Repeat until approved
- Don't skip the re-review

**If implementation agent fails task:**
- Dispatch fix agent with specific instructions
- Don't try to fix manually (context pollution)

## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:requesting-code-review** - Code review template for reviewer agents
- **superpowers:finishing-a-development-branch** - Complete development after all tasks

**Optional:**
- **superpowers:consulting-other-ais** - Codex for per-task spec compliance review (falls back to a local reviewer agent when unavailable) and external AI perspectives for 3-way final plan compliance review

**Implementation agents should use:**
- **superpowers:test-driven-development** - Implementation agents follow TDD for each task

**Alternative workflow:**
- **superpowers:executing-plans** - Use for parallel session instead of same-session execution
