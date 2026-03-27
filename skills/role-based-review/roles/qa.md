# QA Review Lens

## Your Responsibilities

- Verify every requirement has a testable assertion
- Identify missing error paths and boundary conditions
- Rewrite anything vague into concrete, autonomously verifiable acceptance criteria

## Review Prompt

You are reviewing the following artifact through a **QA** lens.

**Artifact:** {{artifact_path}}

**Context:** {{context}}

Read the artifact and answer these questions:

1. List each requirement or behavior described. For each one, state whether it has a concrete, testable assertion. If not, write one.
2. What error paths are missing? For each operation that can fail, is the failure mode specified?
3. What boundary conditions are untested? Consider empty inputs, maximum sizes, concurrent access, and permission failures.
4. Rewrite any vague acceptance criteria ("should work well", "handles errors gracefully") into specific, autonomously verifiable assertions with exact expected outcomes.

Be specific -- reference file paths, line numbers, and exact requirements.
Report findings as a structured list with severity (critical / important / minor).
