#!/usr/bin/env bash
# dispatch.sh — Execution-mode dispatch to Codex / Gemini for autonomous-feature-development.
#
# Distinct from consult.sh (advisory): this lets the external AI EDIT FILES.
# Codex runs with workspace-write (or danger-full-access fallback).
# Gemini runs with yolo approval mode (same as consult, but prompted to write).
#
# The execution preamble:
#   - Forbids the AI from invoking its own skills / workflow plugins
#   - Allows non-interactive task-relevant plugins (github, linear, notion, filesystem)
#   - Demands a STATUS protocol line as the last line of output
#
# Usage:
#   dispatch.sh <codex|gemini> "Task prompt with TASK/FILES/SPEC/HARNESS/TRIGGERS/AUTONOMY"
#
# Environment variables (inherits consult.sh defaults where applicable):
#   DISPATCH_CODEX_MODEL    - Codex model (default: $CONSULT_CODEX_MODEL or gpt-5.4)
#   DISPATCH_GEMINI_MODEL   - Gemini model (default: $CONSULT_GEMINI_MODEL or gemini-3.1-pro-preview)
#   DISPATCH_TIMEOUT        - Timeout in seconds (default: 1800 — execution can take longer than consult)
#   DISPATCH_OUTPUT_DIR     - Where to save results (default: /tmp/dispatch-results)
#   DISPATCH_CODEX_SANDBOX  - Codex sandbox (default: workspace-write, fallback danger-full-access)

set -euo pipefail

# --- Configuration ---
CODEX_MODEL="${DISPATCH_CODEX_MODEL:-${CONSULT_CODEX_MODEL:-gpt-5.4}}"
GEMINI_MODEL="${DISPATCH_GEMINI_MODEL:-${CONSULT_GEMINI_MODEL:-gemini-3.1-pro-preview}}"
TIMEOUT="${DISPATCH_TIMEOUT:-1800}"
OUTPUT_DIR="${DISPATCH_OUTPUT_DIR:-/tmp/dispatch-results}"
CODEX_SANDBOX="${DISPATCH_CODEX_SANDBOX:-workspace-write}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Execution-mode preamble.
# Differences from consult.sh CONSULT_PREAMBLE:
#   - Allows file edits (this is execution, not consultation)
#   - Forbids skill / workflow invocation (predictable behavior)
#   - Allows non-interactive task-relevant plugins (github, linear, notion, filesystem)
#   - Mandates STATUS protocol line as last line
DISPATCH_PREAMBLE="IMPORTANT — You are executing a task as part of an autonomous feature development workflow. Read the TASK / FILES / SPEC / HARNESS / TRIGGERS / AUTONOMY block carefully and implement the task by editing files in place.

Rules:
  1. Do NOT invoke skills, plugins that initiate workflows, or commands like brainstorming / planning / writing-plans / superpowers. Do NOT use any \"Skill\" tool. Just do the work.
  2. You MAY use non-interactive task-relevant plugins (github, linear, notion, filesystem reads, etc.) when they help complete the task.
  3. Run the harness command yourself before claiming DONE. If the harness fails, attempt to fix once. If the second attempt also fails, return BLOCKED — do not loop.
  4. If the harness reveals new validatable surface (a new endpoint, command, behavior), append a step to the spec's \"Validation harness\" section describing how to verify it.
  5. End your response with EXACTLY ONE line in this format, on its own line, as the very last line:

     STATUS: DONE — <one-line summary>
     STATUS: DONE_WITH_CONCERNS — <concerns>
     STATUS: NEEDS_INPUT — <question for human>
     STATUS: BLOCKED — <what blocked you>
     STATUS: ESCALATE — <which trigger fired>

When referencing files, use plain paths (src/auth.py:42), not file:// URLs.

"

# --- Functions ---

die() { echo "ERROR: $*" >&2; exit 1; }

check_provider() {
    command -v "$1" >/dev/null 2>&1
}

require_provider() {
    if ! check_provider "$1"; then
        die "$1 CLI not found. Install it or check your PATH."
    fi
}

# Codex must run inside a trusted git repo (same constraint as consult.sh).
codex_repo_flags() {
    local target
    target=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$target" && -d "$target/.git" ]]; then
        echo "--cd $target"
    else
        echo "--skip-git-repo-check"
    fi
}

# Filter CLI boilerplate (mirrors consult.sh::filter_output).
filter_output() {
    sed \
        -e '/^Codex /d' \
        -e '/^codex$/d' \
        -e '/^⠋/d' -e '/^⠙/d' -e '/^⠹/d' -e '/^⠸/d' \
        -e '/^⠼/d' -e '/^⠴/d' -e '/^⠦/d' -e '/^⠧/d' \
        -e '/^⠇/d' -e '/^⠏/d' \
        -e '/^Gemini /d' \
        -e '/^gemini$/d' \
        -e '/^✦ /d' \
        -e '/^╭/d' -e '/^│/d' -e '/^╰/d' \
        -e '/^┌/d' -e '/^└/d' \
        -e '/^Model:/d' \
        -e '/^Sandbox:/d' \
        -e '/^Working directory:/d' \
        -e '/^Session:/d' \
        -e '/^\[.*spinner\]/d' \
        -e '/^Thinking\.\.\./d' \
        -e '/^Reading /d' \
        -e '/^Searching /d' \
        -e '/^exec$/d' \
        -e '/^tokens used$/d' \
        -e '/^[0-9,]*$/d'
}

# If consult.sh probed sandbox already this session and got danger-full-access,
# don't try workspace-write — bwrap is broken on this host. Just skip ahead.
maybe_downgrade_codex_sandbox() {
    if [[ -f "/tmp/.consult-sandbox-ok" ]]; then
        local cached
        cached=$(cat "/tmp/.consult-sandbox-ok" 2>/dev/null || true)
        if [[ "$cached" == "danger-full-access" && "$CODEX_SANDBOX" == "workspace-write" ]]; then
            echo "Note: bwrap sandbox known broken (cached probe). Using danger-full-access for codex execution." >&2
            CODEX_SANDBOX="danger-full-access"
        fi
    fi
}

# Detect failure phrases that mean Codex couldn't actually do the work
# even though it returned exit 0 (mirrors consult.sh patterns).
codex_output_is_empty_response() {
    local output="$1"
    [[ "$output" == *"I can't give a faithful"* ]] ||
    [[ "$output" == *"I was unable to read"* ]] ||
    [[ "$output" == *"I couldn't read"* ]] ||
    [[ "$output" == *"I can't read"* ]] ||
    [[ "$output" == *"sandbox is rejecting"* ]] ||
    [[ "$output" == *"shell access is being blocked"* ]] ||
    [[ "$output" == *"Failed RTM_NEWADDR"* ]]
}

run_codex() {
    local prompt="$1"
    local outfile="${OUTPUT_DIR}/codex-${TIMESTAMP}.md"
    local errlog="${OUTPUT_DIR}/codex-${TIMESTAMP}.stderr.log"

    require_provider codex
    maybe_downgrade_codex_sandbox

    local repo_flags
    repo_flags=$(codex_repo_flags)

    echo "Dispatching to Codex (model: ${CODEX_MODEL}, timeout: ${TIMEOUT}s, sandbox: ${CODEX_SANDBOX}, flags: ${repo_flags})..." >&2

    local result exit_code=0
    result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        codex exec --model "$CODEX_MODEL" --sandbox "$CODEX_SANDBOX" $repo_flags 2>"$errlog" \
        | filter_output) || exit_code=$?

    # Fallback: if workspace-write produced soft-failure output, retry with danger-full-access
    if [[ $exit_code -eq 0 && "$CODEX_SANDBOX" == "workspace-write" ]] && codex_output_is_empty_response "$result"; then
        echo "Codex couldn't operate with workspace-write. Retrying with danger-full-access..." >&2
        CODEX_SANDBOX="danger-full-access"
        echo "danger-full-access" > "/tmp/.consult-sandbox-ok"
        exit_code=0
        result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
            codex exec --model "$CODEX_MODEL" --sandbox "$CODEX_SANDBOX" $repo_flags 2>"$errlog" \
            | filter_output) || exit_code=$?
    fi

    if [[ $exit_code -eq 0 && -n "$result" ]]; then
        echo "$result" > "$outfile"
        echo "Codex output saved to: ${outfile}" >&2
        echo "$result"
    elif [[ $exit_code -eq 124 ]]; then
        echo "Codex stderr log: ${errlog}" >&2
        die "Codex timed out after ${TIMEOUT}s"
    else
        echo "Codex stderr log: ${errlog}" >&2
        die "Codex failed (exit code: ${exit_code}). Check stderr log for details."
    fi
}

run_gemini() {
    local prompt="$1"
    local outfile="${OUTPUT_DIR}/gemini-${TIMESTAMP}.md"
    local errlog="${OUTPUT_DIR}/gemini-${TIMESTAMP}.stderr.log"

    require_provider gemini

    echo "Dispatching to Gemini (model: ${GEMINI_MODEL}, timeout: ${TIMEOUT}s, yolo/auto-approve)..." >&2

    local result exit_code=0
    result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        env NODE_NO_WARNINGS=1 gemini -p "" -o text --approval-mode yolo -m "$GEMINI_MODEL" 2>"$errlog" \
        | filter_output) || exit_code=$?

    if [[ $exit_code -eq 0 && -n "$result" ]]; then
        echo "$result" > "$outfile"
        echo "Gemini output saved to: ${outfile}" >&2
        echo "$result"
    elif [[ $exit_code -eq 124 ]]; then
        echo "Gemini stderr log: ${errlog}" >&2
        die "Gemini timed out after ${TIMEOUT}s"
    else
        echo "Gemini stderr log: ${errlog}" >&2
        die "Gemini failed (exit code: ${exit_code}). Check stderr log for details."
    fi
}

# --- Argument parsing ---

[[ $# -ge 2 ]] || die "Usage: dispatch.sh <codex|gemini> \"task prompt\""

provider="$1"
shift
prompt="$1"

# Prepend execution-mode preamble
prompt="${DISPATCH_PREAMBLE}${prompt}"

mkdir -p "$OUTPUT_DIR"

case "$provider" in
    codex)
        run_codex "$prompt"
        ;;
    gemini)
        run_gemini "$prompt"
        ;;
    *)
        die "Unknown provider: $provider. Use codex or gemini."
        ;;
esac
