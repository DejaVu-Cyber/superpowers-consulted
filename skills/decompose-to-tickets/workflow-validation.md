# Workflow Validation Reference

This document defines how to verify that a project's `SYMPHONY-WORKFLOW.md` is correctly configured before creating tickets. Symphony polls Linear for tickets in specific states and dispatches AI agents to work on them in isolated workspaces. Misconfigured workflows cause tickets to be ignored or agents to fail.

## Verification Checklist

All 6 checks must pass before ticket creation proceeds.

### 1. SYMPHONY-WORKFLOW.md exists

Look for `SYMPHONY-WORKFLOW.md` at the project root. If it does not exist, stop and offer to create one (see "Missing Workflow File" below).

### 2. project_slug matches Linear project

The `project_slug` value in the workflow file must match the Linear project where tickets will be created. A mismatch means Symphony will poll the wrong project and never pick up the tickets.

### 3. Linear project states include all referenced states

Every state name listed in `active_states` and `terminal_states` in the workflow file must exist as a state in the actual Linear project. Missing states cause Symphony to skip tickets or fail to transition them.

### 4. "Planned" state exists in Linear project

Tickets are created in the "Planned" state. They stay there until the human moves them to "Todo", which triggers Symphony to pick them up. If "Planned" does not exist as a state in the Linear project, tickets have nowhere to land.

### 5. Workspace root directory exists

The workspace root specified in the workflow file must exist on the filesystem. Symphony creates isolated workspaces under this directory. If it does not exist, agent dispatch will fail.

### 6. Hook paths are valid

Any hooks referenced in the workflow file (`after_create`, `before_run`, `after_complete`, etc.) must point to files or repos that exist. Verify each path resolves to something real.

## Verification Stamp

After all checks pass, append a stamp to `SYMPHONY-WORKFLOW.md`:

```
# superpowers-verified: YYYY-MM-DD | states:Backlog,Planned,Todo,In Progress,In Review,Done,Canceled | project:<slug>
```

The stamp encodes the date, the full list of Linear project states, and the project slug. This allows future runs to detect drift without re-querying Linear.

## When to Validate

- **Stamp missing** -- Run full validation (all 6 checks).
- **Stamp present but state list does not match current Linear states** -- Re-validate. States may have been added, removed, or renamed in Linear since the last check.
- **Stamp present and state list matches** -- Skip validation. The workflow file is current.

## Missing Workflow File

When no `SYMPHONY-WORKFLOW.md` exists, offer to create one. Gather the following information:

- **Repository URLs** -- Which repos should agents have access to?
- **Workspace root** -- Absolute path where isolated workspaces will be created (e.g., `/home/user/workspaces/project-name`).
- **Adapter preference** -- Which AI adapter Symphony should use for dispatched agents.
- **Linear team ID** -- The team that owns the project in Linear.
- **Project slug** -- The Linear project slug for ticket polling.
- **State mappings** -- Which Linear states map to `active_states` (triggers agent work) and `terminal_states` (marks work complete).
