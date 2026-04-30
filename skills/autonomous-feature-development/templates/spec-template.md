# <Feature name>

<!--
Spec for autonomous-feature-development.
Single artifact — no separate plan, no tickets unless user asks.
All seven sections are required.
-->

## 1. Context

<!-- Why this work? What problem does it solve? Intended outcome? 1-3 short paragraphs. -->

## 2. Scope

**In scope:**
- <bullet>
- <bullet>

**Out of scope:**
- <bullet>

**Non-goals (explicit anti-scope):**
- <bullet — things this work explicitly will NOT do, even if they seem related>

## 3. File map

<!-- Files to create or modify, with one-line responsibility each.
     Reference reusable functions/utilities by file:line where they exist. -->

| Path | Action | Responsibility |
|------|--------|----------------|
| `path/to/file.py` | modify | <what it does in this feature> |
| `path/to/new.py` | create | <what it does> |

**Reused from existing code:**
- `<path:line>` — `<function_or_utility_name>` — used for `<purpose>`

## 4. Validation harness

<!-- Runnable proof the feature works end-to-end.
     Must be executable when the spec is approved — not aspirational.
     Executor may extend per-task: when a task adds new validatable surface,
     append a step here describing how to validate it. -->

**Global harness (run end-to-end at Phase 5):**

```bash
# Example: command that proves the whole feature works
<command-here>
```

**Per-task harness steps:** see Tasks section. Each task references which step proves it.

## 5. Escalation triggers

<!-- Concrete, enforceable conditions that force a human in the loop.
     Vague triggers don't count — push for measurable conditions. -->

**Functional triggers:**
- 2 consecutive harness failures on the same task
- <other concrete failure-mode trigger>

**Semantic triggers:**
- Spec is ambiguous on the current task
- Scope creep detected (work expanding beyond a Tasks-section task)
- <other concrete trigger>

**Resource triggers:**
- Subagent exceeded N tokens or M wall-clock minutes
- <other concrete budget>

**Domain triggers (always confirm regardless of autonomy):**
- Data loss risk (delete, drop, truncate, irreversible mutation)
- Production write
- Schema migration
- Credential or secret handling
- Deletion of files outside Scope
- <project-specific domain stops>

## 6. Autonomy

<!-- Filled in during Phase 3 after user negotiation. -->

**Global default:** `<strict | senior-dev | yolo>`

**Per-task overrides** (if any):

| Task | Autonomy |
|------|----------|
| Task <N> | `strict` |

## 7. Tasks

<!-- Ordered. Each task: intent, files touched, harness step that proves it,
     task-specific escalation notes if any, provider routing.
     Provider options: claude | codex | gemini -->

### Task 1 — <short title>

- **Intent:** <one paragraph: what this task delivers>
- **Files:** `<paths>`
- **Harness step:** <reference to or excerpt from section 4 — the runnable check that proves this task done>
- **Task-specific triggers:** <if any beyond global; otherwise: "none beyond global">
- **Provider:** `<claude | codex | gemini>` — `<reason for routing if non-default>`

### Task 2 — <short title>

- **Intent:** ...
- **Files:** ...
- **Harness step:** ...
- **Task-specific triggers:** ...
- **Provider:** ...
