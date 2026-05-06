# Spec Compliance Reviewer Prompt Template

Use this template when running a spec compliance review.

**Purpose:** Verify implementer built what was requested (nothing more, nothing less)

**Provider selection:** Prefer Codex for a second-opinion independent of the main session. Fall back to a local isolated reviewer agent if Codex is unavailable.

## Availability Check

Run once at skill start (or on first use):

```bash
skills/consulting-other-ais/scripts/consult.sh check
```

- `codex: available` → use Codex path (below)
- `codex: not available` → use local reviewer-agent fallback

Cache the result for the rest of the run.

## Prompt Body (shared by both paths)

The review prompt is identical regardless of provider. Substitute `{{PRIOR_FINDINGS}}` with either the previous round's findings (re-review) or the literal string `(none — first review)` on the initial pass.

```
You are reviewing whether an implementation matches its specification.
Answer the review question directly. Do not invoke skills or start a brainstorming
or planning workflow.

## What Was Requested

[FULL TEXT of task requirements]

## Implementation Under Review

- Branch base SHA: <BASE_SHA>
- Current HEAD SHA: <HEAD_SHA>
- Diff command: `git diff <BASE_SHA>..<HEAD_SHA>`
- Relevant files: [paths the implementer touched]

## Implementer's Report

[From implementer's report — claims, files changed, tests run]

## Prior Review Findings

{{PRIOR_FINDINGS}}

## CRITICAL: Do Not Trust the Report

The implementer may be optimistic or incomplete. Verify everything by reading the
actual code at HEAD_SHA, not by trusting claims.

**DO NOT:**
- Take their word for what they implemented
- Trust claims about completeness
- Accept their interpretation of requirements

**DO:**
- Read the actual code
- Compare implementation to requirements line by line
- Check for missing pieces they claimed to implement
- Look for extra features they didn't mention
- On re-review: verify each prior finding is actually resolved

## Your Job

Check three things:

**Missing requirements** — did they implement everything requested? Anything skipped, partial, or claimed-but-not-actually-built?

**Extra/unneeded work** — anything built that wasn't requested? Over-engineering? Scope creep?

**Misunderstandings** — did they solve the right problem the right way?

## Output Format

- ✅ Spec compliant — if everything matches after code inspection
- ❌ Issues found — list each with file:line reference and which requirement it violates

On re-review, also state explicitly for each prior finding:
- RESOLVED — fix verified in code
- NOT RESOLVED — still present, explain why
- PARTIALLY RESOLVED — explain what's still missing

Use plain `path:line` references, not file:// URLs.
```

## Codex Path

Invoke via `consult.sh`:

```bash
skills/consulting-other-ais/scripts/consult.sh codex "$(cat <<'EOF'
<prompt body from above, with substitutions>
EOF
)"
```

Codex reads files directly from the repo — do not paste file contents; give paths and SHAs.

Each review round is a fresh stateless call. For re-review, pass the previous round's findings inline via `{{PRIOR_FINDINGS}}` and the new HEAD_SHA. No conversation thread needed.

If Codex returns soft-failure language ("I can't read", "paste the contents") despite `consult.sh`'s auto-retry, treat it as unavailable for this review and fall back to the local reviewer-agent path for the remainder of the run.

## Local Reviewer-Agent Fallback

When Codex is unavailable:

```
Isolated reviewer agent:
  description: "Review spec compliance for Task N"
  prompt: |
    <prompt body from above, with substitutions>
```

Same prompt body. Re-review = new Task dispatch with prior findings in `{{PRIOR_FINDINGS}}` and updated SHAs.

Platform adapters:
- Claude Code: use Task/Agent with `general-purpose`.
- Codex: use `spawn_agent` with `agent_type: explorer` because this is read-only.
