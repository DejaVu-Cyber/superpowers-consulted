# Superpowers-Consulted

Fork of [obra/superpowers](https://github.com/obra/superpowers) that adds multi-AI consultation via Codex CLI and Gemini CLI.

## What This Fork Adds

The `consulting-other-ais` skill and its integration into existing superpowers workflows. Everything else is upstream superpowers.

### consulting-other-ais Skill

Core addition: `skills/consulting-other-ais/` with `SKILL.md` (instructions) and `scripts/consult.sh` (bash helper).

`consult.sh` sends focused prompts to Codex and/or Gemini CLI. Both run locally and read files directly — don't paste file contents, give paths.

### Integration Points

External AI consultation is woven into existing skills as **optional** choices (never mandatory):

- **brainstorming** — Multi-perspective question enrichment (step 4) and design challenge round (after design approval, one round of pushback)
- **writing-plans** — 3-way plan review (subagent + Codex + Gemini)
- **subagent-driven-development** — 3-way final plan compliance review after all tasks complete
- **finishing-a-development-branch** — External AI review of branch diff before merge/PR

## Codex CLI Gotchas

Codex is the most fragile provider. Known issues and mitigations built into `consult.sh`:

1. **Trusted directory requirement** — Codex refuses to run outside a git repo. Script uses `--cd <DIR>` when a git root is found, `--skip-git-repo-check` when not.

2. **bwrap sandbox failure on Linux 6.2+** — AppArmor blocks unprivileged user namespaces. Script auto-detects via file-read probe and falls back to `danger-full-access`. Fix: AppArmor profile for bwrap (see README).

3. **Plugin interference** — If Codex has superpowers installed, it tries to brainstorm instead of answering. Fixed via `CONSULT_PREAMBLE` prepended to all prompts.

4. **Soft failures** — Codex sometimes exits 0 but admits it couldn't read files. Script detects phrases like "I can't read", "paste the contents", etc. and auto-retries with `danger-full-access`.

5. **file:// URLs in output** — Preamble instructs providers to use plain `path:line` references.

## Gemini CLI Notes

- Uses `--approval-mode yolo` (not `plan`). `plan` mode restricts reads to cwd only, which breaks cross-project consultation.
- Generally more reliable than Codex — no sandbox issues, no plugin interference.

## Version Bumping

Three files must be updated in sync:
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

## Plugin Installation

This repo is registered as a local development plugin. The `installed_plugins.json` entry points `installPath` directly at this source directory (not the cache). Claude Code may still create cached copies — if script path issues arise, check that invocations resolve to the source directory, not stale cache versions.

## Writing Plans Philosophy

Plans focus on **decisions**, not code. The implementing agent can read files, follow patterns, and write code. What it needs from a plan:
- What to build and what NOT to build (scope boundaries)
- File structure and decomposition (which files, which responsibility)
- Interface contracts (function signatures, data structures)
- Behaviors to test (assertions, not full test code)
- Constraints and gotchas (things the agent would get wrong without being told)
- Task ordering and dependencies

Code in plans only when it communicates a decision more precisely than prose.
