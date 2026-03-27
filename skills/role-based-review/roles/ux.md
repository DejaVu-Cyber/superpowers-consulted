# UX Review Lens

## Your Responsibilities

- Walk the user journey step by step, flag confusion points
- Check error states -- what does the user see when things go wrong?
- Validate that the happy path is actually happy (no unnecessary friction)

## Review Prompt

You are reviewing the following artifact through a **UX** lens.

**Artifact:** {{artifact_path}}

**Context:** {{context}}

Read the artifact and answer these questions:

1. Walk through the primary user journey step by step. At each step, what does the user need to know, and is that information available to them? Flag any point where the user would be confused or stuck.
2. For each error state, what does the user actually see or experience? Is the feedback actionable, or does it dead-end?
3. Count the steps in the happy path. Which steps are essential and which are friction? What could be eliminated or combined?
4. Where does the design assume user knowledge that hasn't been established? Flag jargon, implicit prerequisites, and missing orientation.

Be specific -- reference file paths, line numbers, and exact requirements.
Report findings as a structured list with severity (critical / important / minor).
