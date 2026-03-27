# Augmented Superpowers Workflow

Enhance the superpowers workflow with role-based multi-perspective review, Linear ticket decomposition, and Symphony integration for parallel agent execution.

## Motivation

The current superpowers flow (brainstorm → spec → plan → subagent execution → finish branch) is a single-agent, single-session pipeline. It works well for focused features but doesn't leverage:

- **Multiple perspectives** on design decisions — different concerns (product fit, architecture soundness, testability, user experience) benefit from structured examination through different lenses
- **Parallel execution** via Symphony — for larger work, multiple agents working on isolated tickets in worktrees is faster and more reliable than sequential subagent tasks
- **Linear as a coordination layer** — tickets with acceptance criteria, dependency graphs, and human comments provide better tracking and communication than local plan files alone

This design adds these capabilities while keeping the existing workflow intact for simple work.

## New Skill: `role-based-review`

A composable skill that dispatches review prompts through different "lenses" to a pool of AI providers. Callable from any skill at any review point.

### Inputs

- **Artifact** — file path or inline content to review
- **Roles** — which lenses to apply (subset of: product, architecture, QA, UX)
- **Context** — brief description of what's being reviewed and why

### Role Definitions

Each role has 3-4 defined responsibilities that shape its review prompt.

**Product:**
- Challenge whether scope matches the problem — too ambitious or too timid?
- Identify what users would expect that's missing
- Flag anything built for hypothetical future needs rather than current value

**Architecture:**
- Surface hidden assumptions and unstated dependencies
- Trace data flow end-to-end, flag where it's unclear
- Identify where the design breaks under edge cases or load

**QA:**
- Verify every requirement has a testable assertion
- Identify missing error paths and boundary conditions
- Rewrite anything vague into concrete, autonomously verifiable acceptance criteria

**UX:**
- Walk the user journey step by step, flag confusion points
- Check error states — what does the user see when things go wrong?
- Validate that the happy path is actually happy (no unnecessary friction)

### Dynamic Role Selection

The calling skill suggests which roles are relevant based on what's being built:

| Work Type | Suggested Roles |
|-----------|----------------|
| New user-facing feature | product, architecture, QA, UX |
| API/backend work | product, architecture, QA |
| Pure refactor/infrastructure | architecture, QA |
| Bug fix | QA (+ architecture if systemic) |

The suggestion is presented to the user: *"I'd suggest reviewing through architecture and QA lenses. Want to add or skip any?"* User always has final say.

### Provider Pool

Available providers: Claude subagent, Codex CLI, Gemini CLI.

**Assignment strategy: preferred-provider-per-role with fallback chain.** Each role has a preferred provider based on documented strengths, not arbitrary round-robin:

| Role | Preferred | Fallback | Final Fallback |
|------|-----------|----------|----------------|
| Architecture | Codex | Gemini | Claude subagent |
| QA | Codex | Gemini | Claude subagent |
| Product | Gemini | Codex | Claude subagent |
| UX | Gemini | Codex | Claude subagent |

- Check provider availability before assignment (Codex CLI installed? Gemini CLI installed?)
- If preferred provider is unavailable or fails, move to next in fallback chain
- Claude subagent is always available as final fallback
- When multiple roles share a provider, run them in parallel
- If all external providers fail, all roles fall back to Claude subagents — still works, just less diverse

**Transparency:** Report to the user which provider handled which role. If fallback occurred, note it — the user should know when they got same-provider redundancy instead of multi-provider diversity.

### Output

Synthesized findings grouped by role with provider attribution. The calling skill decides what to do with the results — role-based-review does not make decisions, it surfaces perspectives.

### Implementation

- `skills/role-based-review/SKILL.md` — skill definition and dispatch logic
- `skills/role-based-review/roles/` — one markdown prompt template per role (`product.md`, `architecture.md`, `qa.md`, `ux.md`)
- Provider dispatch reuses `consulting-other-ais/scripts/consult.sh` for Codex/Gemini, Agent tool for Claude subagents

## New Skill: `decompose-to-tickets`

Takes an approved spec (and optional plan for large projects) and creates Linear tickets with acceptance criteria, testing guidance, and dependency mapping.

### Inputs

- Spec file path (required)
- Plan file path (optional — present for large/complex projects)
- Linear project/team context

### Process

**1. Identify work units.** Read the spec (and plan if present) and extract discrete tickets. Each ticket should be:
- Implementable independently given its dependencies are complete
- Scoped to 1-3 files changed
- Testable in isolation

**When a plan exists:** Ticket extraction is largely mechanical — the plan already contains structured tasks with files, interfaces, and dependencies. Export them with minimal generation.

**When no plan exists:** Ticket creation is generative — decompose the spec into implementable units. For specs with more than ~8 tickets, generate in batches to avoid quality degradation.

**2. For each ticket, generate:**

- **Title** — clear, imperative (e.g., "Add user authentication middleware")
- **Description** — what to build, with a reference back to the spec for broader context
- **Acceptance criteria** — concrete, autonomously verifiable assertions. Written so an unattended agent can confirm them without human input. Not "implement X" but "when Y happens, Z is observable via [specific command/check]"
- **Testing guidance** — specific validation commands (e.g., `pytest tests/test_auth.py -k test_login`), edge cases to cover
- **File scope** — which files this ticket touches
- **Blocked by** — which other tickets must complete first

**3. Map the dependency graph.** Identify the critical path and parallel groups:

```
Ticket 1: Set up data models
Ticket 2: Add API endpoints       [blocked by 1]
Ticket 3: Write migration script  [blocked by 1]
Ticket 4: Add validation layer    [blocked by 2]
Ticket 5: Integration tests       [blocked by 2, 3]

Parallel groups: [1] → [2, 3] → [4, 5]
```

**4. Mandatory QA role review.** Before creating tickets in Linear, run the QA lens from `role-based-review` on the full ticket set. QA verifies:
- Every acceptance criterion is actually autonomously verifiable
- No gaps between spec requirements and ticket coverage
- Dependencies are correct and complete
- Testing commands are concrete and executable

**5. Create tickets in Linear.** Create all tickets in **"Planned"** state with blocking relationships set up. The "Planned" state is in the same category as "Backlog" in Linear — Symphony ignores it.

**6. User reviews in Linear.** Give the user the Linear project link:

> *"Tickets are in Planned with dependencies set up. Review and adjust them in Linear — it's easier to visualize dependencies and edit there. When you're done, let me know:*
> - *If you changed anything significant, I'll re-read the tickets*
> - *Otherwise just say 'good to go'"*

If user reports changes → re-read tickets from Linear, acknowledge the diff. If user says good to go → proceed to execution recommendation.

**7. Execution recommendation.** Based on ticket complexity and count:

- **Small, independent work** → *"This is small enough to run locally with subagents. Want to do that, or send to Symphony?"*
- **Moderate complexity or 6+ tickets** → *"I'd recommend Symphony for parallel execution here. Want to go that route, or keep it local?"*
- **Large/complex** → *"This is a big one — Symphony with parallel dispatch would work well. Want to proceed that way?"*

User always decides.

### Execution Paths

**Symphony path:**
- Verify/create SYMPHONY-WORKFLOW.md (see Workflow Validation below)
- Offer CLI shortcut: *"Move tickets from Planned to Todo when ready — Symphony will pick them up. Want me to move them now, or will you do it from Linear?"*
- Symphony handles execution from there — superpowers is done

**Local path:**
- Hand off to `subagent-driven-development` with plan/spec as the task source (not Linear tickets)
- As each task completes, the orchestrating skill closes the corresponding Linear ticket
- Human comments on Linear tickets are available for followup context

**Both paths:** Tickets always exist in Linear for tracking, acceptance criteria, human comments, and closure. The difference is what the executor reads for implementation instructions.

### Implementation

- `skills/decompose-to-tickets/SKILL.md` — skill definition
- Ticket template in the skill directory for consistent formatting
- Uses Linear MCP tools for ticket creation and dependency setup
- Calls `role-based-review` for mandatory QA check

## Workflow Validation

When the Symphony execution path is chosen, verify that SYMPHONY-WORKFLOW.md exists and is correctly configured.

### Checks

1. **Workflow file exists** in the project root
2. **`project_slug` matches** the Linear project where tickets were created
3. **Linear project states** include all states referenced in `active_states` and `terminal_states`
4. **"Planned" state exists** in the Linear project (so tickets can be created there)
5. **Basic sanity** — workspace root exists, hooks reference valid paths/repos

### Verification Stamp

After all checks pass, add a verification marker to SYMPHONY-WORKFLOW.md:

```yaml
# superpowers-verified: 2026-03-27 | states:Backlog,Planned,Todo,In Progress,In Review,Done,Canceled | project:my-project-slug
```

The stamp includes a hash of the validated state configuration (state names + project slug), not just a date. On future runs:
- If the stamp exists and the hash matches current Linear state → skip validation
- If the stamp exists but the hash doesn't match → re-validate (states changed since last check)
- If no stamp → full validation

### Workflow Creation

If no SYMPHONY-WORKFLOW.md exists, offer to create one:

> *"This project doesn't have a Symphony workflow file yet. Want me to create one? I'll need to know: repo URLs, workspace root, adapter preference (Codex/Claude)."*

Generate a starter workflow using the standard template, tailored to the current project.

## Modifications to Existing Skills

### Brainstorming

Minimal, targeted changes:

**Replace generic external AI reviews with `role-based-review` calls:**
- Step 6 (design challenge round): Instead of sending a generic "challenge this design" prompt, invoke `role-based-review` with dynamically selected roles. This replaces the design challenge and multi-perspective question enrichment with a more structured mechanism.
- Step 8 (spec review loop): The 3-way review option becomes `role-based-review` with QA + architecture lenses alongside the existing spec-document-reviewer subagent.

**Add size/complexity assessment before transition (between steps 9 and 10):**

After the user approves the spec, assess whether a plan is needed:

- **Use a plan when:** cross-file architectural decisions need to be locked down, interfaces between components are unclear, there are deep dependency chains, migrations or data-model risk, or implementation decisions remain unresolved
- **Skip the plan when:** the work is a set of independent, well-scoped changes where each ticket's implementation is straightforward from the spec alone

Present the assessment: *"This involves [reason]. I'd recommend [writing a plan first / going straight to tickets]. What do you think?"*

- If plan recommended → invoke `writing-plans` as before
- If plan not needed → invoke `decompose-to-tickets` directly from the spec

### Writing Plans

One change to terminal handoff:

- After plan approval, hand off to `decompose-to-tickets` instead of directly to execution skills
- The plan becomes input to ticket decomposition — its structured tasks map nearly 1:1 to tickets

Everything else about writing-plans stays the same — it still captures architectural decisions, file decomposition, interface contracts, task ordering, and dependencies.

### Subagent-Driven Development

One addition for the local execution path:

- When executing from tickets, the skill still reads the plan/spec files for implementation details
- As each task completes, close the corresponding Linear ticket
- This keeps local execution independent of Linear API availability for implementation, while maintaining Linear as the tracking layer

## The Complete Flow

```
BRAINSTORM
  ├─ Explore context, clarify questions
  ├─ Propose approaches, present design
  ├─ Role-based review of design (dynamic roles, provider pool)
  │   └─ User picks which feedback to incorporate
  ├─ Write spec (design + architecture decisions)
  ├─ Role-based review of spec (QA + architecture lenses)
  ├─ User reviews spec
  └─ COMPLEXITY ASSESSMENT
      ├─ Simple/well-scoped → skip plan, go to DECOMPOSE
      └─ Complex/cross-cutting → go to WRITE PLAN

WRITE PLAN (only when complexity warrants it)
  ├─ Capture task ordering, dependencies, cross-cutting decisions
  ├─ Plan review
  └─ Hand off to DECOMPOSE

DECOMPOSE TO TICKETS
  ├─ Read spec (+ plan if it exists)
  ├─ Generate tickets (mechanical from plan, generative from spec)
  ├─ QA role review (mandatory) — are criteria autonomously verifiable?
  ├─ Create tickets in Linear in "Planned" state with dependencies
  ├─ User reviews in Linear, reports back
  ├─ EXECUTION RECOMMENDATION
  │   ├─ Symphony path:
  │   │   ├─ Verify/create SYMPHONY-WORKFLOW.md (with state hash stamp)
  │   │   └─ Move tickets to Todo (or user does it from Linear)
  │   └─ Local path:
  │       ├─ Subagents read plan/spec for implementation
  │       └─ Close Linear tickets as tasks complete
  └─ Done
```

## What Doesn't Change

- **`consulting-other-ais`** — still the low-level mechanism for talking to Codex/Gemini. `role-based-review` calls it.
- **`dispatching-parallel-agents`** — still available for non-ticket parallel work
- **`finishing-a-development-branch`** — still used for local execution path completion
- **SYMPHONY-WORKFLOW.md format** — unchanged; superpowers validates it, doesn't own it
- **Symphony itself** — no changes; it polls Linear and dispatches agents as before

## What Each New Skill Owns

| Skill | Inputs | Outputs | Depends On |
|-------|--------|---------|------------|
| `role-based-review` | artifact + roles + context | synthesized findings by role | `consulting-other-ais` (Codex/Gemini), Agent tool (Claude subagents) |
| `decompose-to-tickets` | spec path + optional plan path | Linear tickets in Planned state | `role-based-review` (QA lens), Linear MCP tools |
