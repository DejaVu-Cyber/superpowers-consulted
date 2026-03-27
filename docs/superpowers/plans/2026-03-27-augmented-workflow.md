# Augmented Workflow Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add role-based multi-perspective review, Linear ticket decomposition, and Symphony integration to the superpowers workflow.

**Architecture:** Two new skills (`role-based-review`, `decompose-to-tickets`) that compose with existing infrastructure (`consulting-other-ais/scripts/consult.sh`, Linear MCP tools, Agent tool). Three existing skills get surgical modifications to call the new skills at the right points.

**Tech Stack:** Markdown skill definitions, bash scripting (consult.sh extensions), Linear GraphQL API via MCP tools, existing Agent tool for Claude subagents.

---

## File Structure

### New files

```
skills/role-based-review/
  SKILL.md                    — Skill definition: dispatch logic, dynamic role selection, provider pool
  roles/
    product.md                — Product lens prompt template
    architecture.md           — Architecture lens prompt template
    qa.md                     — QA lens prompt template
    ux.md                     — UX lens prompt template

skills/decompose-to-tickets/
  SKILL.md                    — Skill definition: ticket generation, Linear creation, execution handoff
  ticket-template.md          — Template showing ticket structure for consistent formatting
  workflow-validation.md      — SYMPHONY-WORKFLOW.md verification checklist and stamp format
```

### Modified files

```
skills/brainstorming/SKILL.md             — Replace generic external AI with role-based-review; add complexity assessment
skills/writing-plans/SKILL.md             — Change terminal handoff to decompose-to-tickets
skills/subagent-driven-development/SKILL.md — Add Linear ticket closure after each task completion
```

---

## Task 1: Role Prompt Templates

**Files:**
- Create: `skills/role-based-review/roles/product.md`
- Create: `skills/role-based-review/roles/architecture.md`
- Create: `skills/role-based-review/roles/qa.md`
- Create: `skills/role-based-review/roles/ux.md`

**What to build:**
Four role prompt templates, each containing the role's defined responsibilities and a structured prompt that shapes how the provider reviews an artifact. These are the building blocks that `role-based-review/SKILL.md` assembles into review requests.

**Interface:**
Each template is a markdown file with this structure:

```markdown
# [Role Name] Review Lens

## Your Responsibilities
[3-4 bullet points defining what this role examines]

## Review Prompt

You are reviewing the following artifact through a **[role]** lens.

**Artifact:** {{artifact_path}}

**Context:** {{context}}

[Role-specific review questions derived from responsibilities]

Be specific — reference file paths, line numbers, and exact requirements.
Report findings as a structured list with severity (critical / important / minor).
```

The `{{artifact_path}}` and `{{context}}` placeholders are filled by the calling skill when constructing the actual prompt. They are documentation conventions, not runtime template variables — the skill reads the template and substitutes values when building the prompt string.

**Behavior to test:**
- Each template includes exactly the 3-4 responsibilities from the spec's role definitions
- Each template produces a review prompt that asks focused questions specific to its lens
- Templates do not overlap significantly — each lens covers distinct concerns
- Placeholders `{{artifact_path}}` and `{{context}}` are present and clearly marked

**Constraints:**
- Keep templates concise — under 40 lines each. The prompt should be focused enough that a provider can respond in a single pass.
- Do NOT include provider-specific instructions (no "you are Codex" or "you are Gemini") — templates are provider-agnostic.
- Do NOT include the consultation preamble — `consult.sh` already prepends that.
- Follow the prompt style from `skills/consulting-other-ais/SKILL.md` (lines 170-234) — context paragraph, file pointers, specific asks.

**Depends on:** Nothing

---

## Task 2: `role-based-review` Skill Definition

**Files:**
- Create: `skills/role-based-review/SKILL.md`

**What to build:**
The main skill definition that orchestrates multi-role, multi-provider review. This is a SKILL.md file (instructions for Claude, not executable code) that describes: how to select roles dynamically, how to assign providers from the preferred-per-role fallback chain, how to dispatch reviews in parallel, and how to synthesize results.

**Interface:**
The skill is invoked by other skills (brainstorming, decompose-to-tickets) that pass:
1. An artifact to review (file path)
2. Which roles to use (list)
3. Brief context string

The skill's SKILL.md instructs Claude to:
1. Check provider availability via `consult.sh check`
2. Suggest roles based on work type (table from spec), present to user for confirmation
3. Assign providers per the preferred-provider-per-role table:

| Role | Preferred | Fallback | Final Fallback |
|------|-----------|----------|----------------|
| Architecture | Codex | Gemini | Claude subagent |
| QA | Codex | Gemini | Claude subagent |
| Product | Gemini | Codex | Claude subagent |
| UX | Gemini | Codex | Claude subagent |

4. For each role assigned to an external provider: read the role template from `roles/<role>.md`, substitute artifact path and context, send via `consult.sh`
5. For each role assigned to Claude subagent: read the role template, dispatch via Agent tool
6. Run all dispatches in parallel where possible
7. If an external provider fails: retry with next in fallback chain
8. Synthesize findings grouped by role with provider attribution
9. Report to user if fallback occurred (transparency about diversity)

**Behavior to test:**
- Skill suggests appropriate roles for different work types
- Provider assignment follows preferred-per-role table, not round-robin
- Fallback chain works: preferred → fallback → Claude subagent
- All role dispatches that can run in parallel do run in parallel
- Output is synthesized (not raw relay) with role grouping and provider attribution
- User is told when same-provider redundancy occurred

**Constraints:**
- Must have YAML frontmatter with `name: role-based-review` and a description
- Reuse `consulting-other-ais/scripts/consult.sh` for external providers — do NOT create a new script
- Find the consult script via the plugin install path pattern from `consulting-other-ais/SKILL.md` (lines 108-120)
- User approval is required before dispatching (present the plan: which roles, which providers, what artifact)
- The skill is a tool, not a gate — calling skills decide what to do with findings

**Depends on:** Task 1 (role templates must exist to reference)

---

## Task 3: Ticket Template and Workflow Validation Guide

**Files:**
- Create: `skills/decompose-to-tickets/ticket-template.md`
- Create: `skills/decompose-to-tickets/workflow-validation.md`

**What to build:**
Two reference documents used by the `decompose-to-tickets` skill.

**ticket-template.md** — Shows the exact structure each Linear ticket should follow:

```markdown
## Ticket Structure

**Title:** [Imperative verb] [specific component/action]

**Description:**
[1-2 paragraphs: what to build and why, with reference to spec]

Spec: [path to spec file]
[Optional: Plan: path to plan file]

**Acceptance Criteria:**
- [ ] When [trigger], then [observable outcome via specific check]
- [ ] [Concrete assertion an unattended agent can verify]

**Testing Guidance:**
- Run: `[specific test command]`
- Edge cases: [list specific scenarios to cover]

**File Scope:**
- [path/to/file1.py]
- [path/to/file2.py]

**Blocked By:** [ticket identifiers, or "None"]
```

**workflow-validation.md** — Checklist for SYMPHONY-WORKFLOW.md verification:

```markdown
## Verification Checklist
1. File exists at project root
2. project_slug matches Linear project where tickets were created
3. Linear project states include all active_states and terminal_states
4. "Planned" state exists in the Linear project
5. Workspace root directory exists
6. Hooks reference valid paths/repos

## Stamp Format
# superpowers-verified: YYYY-MM-DD | states:<comma-separated> | project:<slug>

## When to Re-verify
- Stamp missing → full validation
- Stamp present but state list doesn't match current Linear states → re-validate
- Stamp present and matches → skip
```

**Behavior to test:**
- Ticket template includes all required fields from spec (title, description, acceptance criteria, testing guidance, file scope, blocked by)
- Acceptance criteria examples are autonomously verifiable (observable outcomes, not "implement X")
- Workflow validation covers all 6 checks from spec
- Stamp format includes state hash, not just date

**Constraints:**
- These are reference documents, not executable — they guide Claude's behavior when the skill is invoked
- Ticket template must emphasize autonomous verifiability — every criterion should be checkable without human input
- Workflow validation stamp format must include state names and project slug for hash comparison

**Depends on:** Nothing (can run in parallel with Task 1)

---

## Task 4: `decompose-to-tickets` Skill Definition

**Files:**
- Create: `skills/decompose-to-tickets/SKILL.md`

**What to build:**
The skill definition that takes a spec (and optional plan) and decomposes it into Linear tickets with acceptance criteria, dependency mapping, and execution handoff.

**Interface:**
The skill is invoked by brainstorming (for skip-plan path) or writing-plans (after plan approval). It receives:
1. Spec file path (required)
2. Plan file path (optional)

The SKILL.md instructs Claude to:

1. Read the spec (and plan if present)
2. Identify discrete work units — each independently implementable, scoped to 1-3 files, testable in isolation
3. When plan exists: extract tasks mechanically (plan already has structured tasks)
4. When no plan: generate tickets from spec; batch generation for 8+ tickets to avoid quality degradation
5. For each ticket: generate title, description (with spec reference), acceptance criteria (autonomously verifiable), testing guidance (concrete commands), file scope, dependencies
6. Map dependency graph and identify parallel groups
7. Run mandatory QA role review via `role-based-review` skill on the full ticket set
8. Ask user for Linear project/team if not already known
9. Create tickets in Linear in "Planned" state using Linear MCP tools (or the `linear` skill if available), set up blocking relationships
10. Give user the Linear project link, prompt for review:
    - "Changed anything significant?" → re-read tickets from Linear
    - "Good to go" → proceed to execution recommendation
11. Execution recommendation based on complexity:
    - Small/simple → suggest local, offer Symphony
    - Moderate (6+ tickets) → suggest Symphony, offer local
    - Large → suggest Symphony
12. **Symphony path:** verify/create SYMPHONY-WORKFLOW.md per `workflow-validation.md`, offer to move tickets from Planned to Todo
13. **Local path:** hand off to `subagent-driven-development` with plan/spec as task source

**Behavior to test:**
- Reads spec and optional plan correctly
- Mechanical extraction from plan vs generative decomposition from spec
- QA role review is always run before ticket creation (not optional)
- Tickets created in "Planned" state, not "Todo"
- Blocking relationships are set up in Linear
- User is prompted to review in Linear
- Re-reads tickets if user reports changes
- Execution recommendation scales with ticket count/complexity
- Symphony path includes workflow validation
- Local path hands off to subagent-driven-development with plan/spec files (not Linear tickets)
- Both paths: tickets exist in Linear for tracking

**Constraints:**
- Must have YAML frontmatter with `name: decompose-to-tickets` and a description
- Reference `ticket-template.md` for ticket structure
- Reference `workflow-validation.md` for Symphony workflow verification
- Use Linear MCP tools for ticket creation — check available tools at runtime (the `linear` skill or `mcp__notion__*` tools are NOT the Linear API; look for Linear-specific MCP tools or fall back to `curl` with `$LINEAR_API_KEY`)
- The mandatory QA review uses `role-based-review` with `roles: [qa]` — it is NOT optional and NOT presented as a choice to the user
- Acceptance criteria must follow the autonomously verifiable pattern from the ticket template — reject vague criteria during generation
- For the Symphony path: do NOT move tickets to Todo automatically without user confirmation
- For the local path: subagents read plan/spec files for implementation instructions, NOT Linear tickets

**Depends on:** Task 2 (role-based-review skill for QA check), Task 3 (ticket template and workflow validation)

---

## Task 5: Modify Brainstorming Skill

**Files:**
- Modify: `skills/brainstorming/SKILL.md` (specifically: steps 6, 8, and 10; the transition logic after step 9)

**What to build:**
Surgical modifications to brainstorming to use role-based-review and add the complexity assessment decision point.

**Changes:**

1. **Step 6 (design challenge round):** Replace the generic external AI challenge with a call to `role-based-review`. Instead of sending a raw "challenge this design" prompt, the skill should:
   - Suggest roles based on what's being designed (use the work-type table from the spec)
   - Present the suggestion to the user
   - Invoke role-based-review with the approved design as the artifact
   - Present synthesized findings with role attribution
   - User decides which feedback to incorporate
   - Still one round only

2. **Step 8 (spec review loop):** Replace the 3-way review option. The three choices become:
   - **Role-based review** — dispatch spec-document-reviewer subagent alongside `role-based-review` with QA + architecture lenses (recommended for non-trivial designs)
   - **Subagent only** — standard spec-document-reviewer (unchanged)
   - **Skip review**

3. **Between steps 9 and 10 (new: complexity assessment):** After user approves the spec, assess whether a plan is needed:
   - Evaluate: cross-file architectural decisions? Unclear interfaces? Deep dependency chains? Migration/data risk? Unresolved implementation decisions?
   - Present assessment: *"This involves [reason]. I'd recommend [writing a plan first / going straight to tickets]. What do you think?"*
   - If plan → invoke `writing-plans` (existing behavior)
   - If no plan → invoke `decompose-to-tickets` directly

4. **Step 10 (transition):** Update to reflect the two possible paths. The terminal state is now either `writing-plans` OR `decompose-to-tickets`, depending on the complexity assessment.

**Behavior to test:**
- Step 6 uses role-based-review instead of raw external AI prompts
- Step 8 offers role-based review as the enhanced option
- Complexity assessment happens after user approves spec, before any transition
- Both transition paths work: to writing-plans and to decompose-to-tickets
- Process flow diagram is updated to reflect new decision point

**Constraints:**
- Keep changes surgical — don't rewrite sections that aren't changing
- The existing multi-perspective questions step (after 2-3 exchanges) can remain as-is — it's a different use case (question enrichment vs design review)
- The visual companion section is untouched
- The "Design Challenge Round" section header and one-round-only constraint remain — just change what happens inside it
- Update the process flow `dot` diagram to include the complexity assessment decision point
- The hard gate ("Do NOT invoke any implementation skill") now needs to allow `decompose-to-tickets` as a valid terminal state alongside `writing-plans`

**Depends on:** Task 2 (role-based-review must exist to reference)

---

## Task 6: Modify Writing-Plans Skill

**Files:**
- Modify: `skills/writing-plans/SKILL.md` (specifically: the "Execution Handoff" section at the end)

**What to build:**
Change the terminal handoff from writing-plans to go to `decompose-to-tickets` instead of directly to execution skills.

**Changes:**

Replace the "Execution Handoff" section (lines 160-176) with:

```markdown
## Execution Handoff

After saving the plan:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Ready to decompose into tickets?"**

Invoke `superpowers:decompose-to-tickets` with:
- The spec file path (from the brainstorming phase)
- The plan file path (just written)

The decompose-to-tickets skill handles ticket creation, Linear integration, and execution path selection. Do NOT invoke subagent-driven-development or executing-plans directly — decompose-to-tickets makes that decision.
```

**Behavior to test:**
- Writing-plans no longer references subagent-driven-development or executing-plans as direct handoff targets
- The only terminal transition is to decompose-to-tickets
- Both spec and plan paths are passed to the next skill

**Constraints:**
- Only modify the "Execution Handoff" section — everything else stays the same
- The plan review loop is unchanged
- Keep it brief — decompose-to-tickets has its own detailed instructions

**Depends on:** Task 4 (decompose-to-tickets must exist to reference)

---

## Task 7: Modify Subagent-Driven Development Skill

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (specifically: add a section about Linear ticket closure)

**What to build:**
Add instructions for closing Linear tickets as tasks complete, for the local execution path.

**Changes:**

Add a new section after "Handling Implementer Status" (after line 126) titled "Linear Ticket Tracking":

```markdown
## Linear Ticket Tracking

When this skill is invoked from the `decompose-to-tickets` local execution path, Linear tickets exist for each task. After each task is marked complete (both reviews passed):

1. Find the corresponding Linear ticket (match by task title/number)
2. Move the ticket to "Done" state using Linear MCP tools or the Linear API
3. Post a brief completion comment to the ticket with PR/commit reference

This keeps Linear in sync without making it the source of truth for implementation. If Linear is unavailable, log a warning and continue — ticket closure is tracking, not a gate.

If the skill is invoked directly from a plan (without decompose-to-tickets), skip this section — no tickets to close.
```

**Behavior to test:**
- When invoked from decompose-to-tickets path: tickets get closed after each task
- When invoked directly from a plan: no ticket closure attempted
- Linear unavailability doesn't block execution
- Completion comments reference the actual work done

**Constraints:**
- This is an additive change — do NOT modify existing sections
- Linear ticket closure is best-effort, not a hard gate
- The skill still reads plan/spec files for implementation instructions, never Linear tickets
- Keep the new section concise (~15-20 lines)

**Depends on:** Task 4 (decompose-to-tickets defines the invocation path)

---

## Task Dependencies

```
Task 1: Role Templates              ─┐
                                      ├→ Task 2: role-based-review SKILL.md ─┐
Task 3: Ticket Template + Validation ─┤                                       ├→ Task 5: Modify Brainstorming
                                      └→ Task 4: decompose-to-tickets SKILL.md ─┤
                                                                                 ├→ Task 6: Modify Writing-Plans
                                                                                 └→ Task 7: Modify Subagent-Driven-Dev

Parallel groups:
  [1, 3] → [2, 4] → [5, 6, 7]
```

Tasks 1 and 3 can run in parallel (no dependencies).
Tasks 2 and 4 can run in parallel once their dependencies are met (2 needs 1; 4 needs 2 and 3).
Tasks 5, 6, and 7 can all run in parallel once tasks 2 and 4 are done.
