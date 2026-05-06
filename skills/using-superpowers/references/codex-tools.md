# Codex Tool Mapping

Skills may mention Claude Code tool names or platform-neutral capabilities. Use this mapping when running them in Codex.

| Capability | Claude Code wording | Codex equivalent |
|------------|---------------------|------------------|
| Activate a skill | `Skill` tool | Native skill load; follow the loaded skill instructions |
| Track task progress | `TodoWrite` | `update_plan` |
| Dispatch an implementation agent | `Task` / `Agent` tool | `spawn_agent` with `agent_type: worker` |
| Dispatch a read-only reviewer/explorer | `Task` / `Agent` tool | `spawn_agent` with `agent_type: explorer` for codebase questions, `worker` only for edits |
| Dispatch multiple agents in parallel | Multiple `Task` calls | Multiple `spawn_agent` calls before waiting |
| Wait for agent output | Task result | `wait_agent` only when blocked on the result |
| Free agent resources | Task completes automatically | `close_agent` after integrating or discarding the result |
| Read/search files | `Read`, `Grep`, `Glob` | `exec_command` with `rg`, `sed`, `find`, etc.; use `multi_tool_use.parallel` for independent reads |
| Edit files | `Write`, `Edit`, `MultiEdit` | `apply_patch` for manual edits |
| Run commands | `Bash` | `exec_command` |
| Ask user for approval/input | Ask in chat / tool approval | Ask concise plain-text questions; use escalation parameters for privileged commands |

## Codex Agent Dispatch Rules

When a skill says to dispatch a subagent, treat it as a Codex `spawn_agent` call.

Implementation tasks:
- Use `agent_type: worker`.
- Give the worker clear file/module ownership.
- Tell the worker it is not alone in the codebase, must not revert edits made by others, and should adapt to existing changes.
- Ask the worker to edit files directly and list changed paths in its final response.

Review or exploration tasks:
- Use `agent_type: explorer` for read-only codebase questions.
- Use `agent_type: worker` only when the review task may make edits.
- Keep the question bounded and avoid duplicating work already assigned to another agent.

Coordination:
- Do not wait immediately after spawning unless the next local step is blocked.
- Do not redo delegated work locally; continue non-overlapping work.
- Close agents when their results are integrated or no longer needed.

## Subagent dispatch requires multi-agent support

Add to your Codex config (`~/.codex/config.toml`):

```toml
[features]
multi_agent = true
```

This enables `spawn_agent`, `wait`, and `close_agent` for skills like `dispatching-parallel-agents` and `subagent-driven-development`.
