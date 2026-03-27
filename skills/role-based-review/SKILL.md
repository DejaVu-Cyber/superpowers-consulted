---
name: role-based-review
description: "Dispatch review prompts through different role lenses (product, architecture, QA, UX) to a pool of AI providers for multi-perspective feedback"
---

# Role-Based Review

Dispatch review prompts through different "lenses" to available AI providers for multi-perspective feedback. This is a composable tool called by other skills (brainstorming, decompose-to-tickets, writing-plans) — not a standalone workflow. The calling skill decides what to review, which roles matter, and what to do with the findings.

## Inputs

The calling skill provides:

- **Artifact to review** — file path to the document, plan, spec, or diff being reviewed
- **Roles to use** — a subset of: `product`, `architecture`, `QA`, `UX`
- **Context string** — brief description of what the artifact is and what kind of feedback matters

## Dynamic Role Selection

Suggest roles based on the type of work, then confirm with the user.

| Work Type | Suggested Roles |
|-----------|----------------|
| New user-facing feature | product, architecture, QA, UX |
| API/backend work | product, architecture, QA |
| Pure refactor/infrastructure | architecture, QA |
| Bug fix | QA (+ architecture if systemic) |

Present the suggestion:

> I'd suggest reviewing through **[roles]** lenses. Want to add or skip any?

Wait for confirmation before proceeding.

## Provider Pool and Assignment

Each role has a preferred provider with a fallback chain. Claude subagent is always the final fallback.

| Role | Preferred | Fallback | Final Fallback |
|------|-----------|----------|----------------|
| Architecture | Codex | Gemini | Claude subagent |
| QA | Codex | Gemini | Claude subagent |
| Product | Gemini | Codex | Claude subagent |
| UX | Gemini | Codex | Claude subagent |

Check availability before assigning:

```bash
"$CONSULT_SCRIPT" check
```

If the preferred provider is unavailable or fails, move to the next in the chain. If neither external provider is available, use Claude subagent for all roles.

## Dispatch Process

### 1. Find the consult script

Read `~/.claude/plugins/installed_plugins.json`, find the `superpowers` entry's `installPath`, then construct:

```bash
CONSULT_SCRIPT="<installPath>/skills/consulting-other-ais/scripts/consult.sh"
```

### 2. Check provider availability

```bash
"$CONSULT_SCRIPT" check
```

Only assign providers that are actually available.

### 3. Present the plan and get approval

Before dispatching anything, show the user:

> Here's the review plan:
>
> | Role | Provider | Artifact |
> |------|----------|----------|
> | Architecture | Codex | path/to/artifact |
> | QA | Codex | path/to/artifact |
> | Product | Gemini | path/to/artifact |
>
> Estimated cost: ~$0.01-0.15 per external provider.
>
> Go ahead? [Yes / Adjust / Skip]

Wait for approval. The user may reassign providers, drop roles, or cancel.

### 4. Build prompts from role templates

For each role, read the template from `roles/<role>.md` (relative to this skill's directory). Each template contains `{{artifact_path}}` and `{{context}}` placeholders — substitute them with the actual values.

### 5. Dispatch reviews

**For external providers (Codex, Gemini):** Send the populated prompt via `consult.sh`:

```bash
"$CONSULT_SCRIPT" codex "$POPULATED_PROMPT"
"$CONSULT_SCRIPT" gemini "$POPULATED_PROMPT"
```

**For Claude subagents:** Read the role template, substitute placeholders, and dispatch via the Agent tool with the populated prompt.

**Run all dispatches in parallel where possible.** Multiple Bash tool calls can run concurrently; subagent calls can run alongside external provider calls.

### 6. Handle failures

If an external provider fails, retry with the next provider in the fallback chain. If all external providers fail for a role, fall back to Claude subagent. Track which provider actually handled each role — this matters for the synthesis.

## Synthesize Results

Group findings by role with provider attribution:

> **Product lens (Gemini):**
> [findings]
>
> **Architecture lens (Codex):**
> [findings]
>
> **QA lens (Codex):**
> [findings]
>
> **My synthesis:**
> - **Agreements:** [themes that multiple lenses flagged]
> - **Tensions:** [where lenses disagree or pull in different directions]
> - **Recommendation:** [what I'd prioritize given all perspectives]

Don't just relay — synthesize. Highlight where lenses agree, where they conflict, and what you'd recommend.

## Transparency

Always tell the user:

- **Which provider handled which role** — include in the per-role headers
- **If any fallback occurred** — e.g., "Architecture review fell back from Codex to Gemini (Codex unavailable)"
- **Same-provider redundancy** — if multiple roles landed on the same provider due to fallbacks, note it: "Both architecture and QA were reviewed by Gemini since Codex was unavailable — you're getting one provider's perspective for both"
- **Cost** — external providers cost ~$0.01-0.15 each via the user's API keys

## Constraints

- **Reuse `consult.sh`** — do not create new scripts for dispatching
- **User approval required** — never dispatch without explicit go-ahead
- **This is a tool, not a gate** — the calling skill decides what to do with findings; this skill reports, it doesn't block
- **Don't paste file contents in prompts** — give paths; external providers read files themselves
