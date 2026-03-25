#!/usr/bin/env bash
# consult.sh — Lightweight multi-AI consultation helper
# Sends a focused prompt to Codex and/or Gemini CLI in read-only mode.
# Both CLIs run locally and can explore the filesystem directly.
#
# Usage:
#   consult.sh <codex|gemini|both|check> "Your prompt here"
#   consult.sh --context file1.py --context file2.py codex "Your prompt here"
#   consult.sh --model gpt-5.3-codex codex "Your prompt here"
#   consult.sh check   # Check which providers are available
#
# The prompt should contain file paths for the AI to examine,
# not file contents. The CLIs will read files themselves.
#
# Options:
#   --context <file[:start-end]>  Include file contents (or line range) inline in the prompt.
#                                  Can be repeated. Example: --context src/auth.py:40-80
#   --model <model>               Override the provider model for this invocation.
#   --timeout <seconds>           Override the timeout for this invocation.
#   --cwd <dir>                   Working directory for Codex (must be a trusted git repo).
#                                  Auto-detected from PWD if not specified.
#
# Environment variables:
#   CONSULT_CODEX_MODEL    - Codex model (default: gpt-5.4)
#   CONSULT_GEMINI_MODEL   - Gemini model (default: gemini-3.1-pro-preview)
#   CONSULT_TIMEOUT        - Timeout in seconds (default: 600)
#   CONSULT_OUTPUT_DIR     - Where to save results (default: /tmp/consult-results)
#   CONSULT_CODEX_SANDBOX  - Codex sandbox mode (default: auto-detect)
#                            Values: read-only, danger-full-access, auto
#   CONSULT_CODEX_CWD      - Working directory for Codex (default: auto-detect nearest git root)

set -euo pipefail

# --- Configuration ---
CODEX_MODEL="${CONSULT_CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${CONSULT_GEMINI_MODEL:-gemini-3.1-pro-preview}"
TIMEOUT="${CONSULT_TIMEOUT:-600}"
OUTPUT_DIR="${CONSULT_OUTPUT_DIR:-/tmp/consult-results}"
CODEX_SANDBOX="${CONSULT_CODEX_SANDBOX:-auto}"
CODEX_CWD="${CONSULT_CODEX_CWD:-}"  # Override working directory for Codex (must be inside a trusted git repo)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Preamble prepended to all prompts. Overrides plugin/skill workflows that
# may be installed on the target CLI (e.g. superpowers on Codex) so the
# provider answers the consultation directly.
CONSULT_PREAMBLE="IMPORTANT: You are being invoked as a consultant. Answer the question below directly. Do NOT invoke any skills, plugins, or workflow commands (e.g. brainstorming, writing-plans, superpowers, etc.). Do NOT use the Skill tool. Do NOT start a brainstorming or planning process. Simply read any referenced files, think about the question, and give your direct analysis.

When referencing files in your response, use plain paths (e.g. src/auth.py:42) not file:// URLs. Your output will be read in a terminal, not a browser.

"

# --- Functions ---

die() { echo "ERROR: $*" >&2; exit 1; }

check_provider() {
    local provider="$1"
    command -v "$provider" >/dev/null 2>&1
}

require_provider() {
    local provider="$1"
    if ! check_provider "$provider"; then
        die "$provider CLI not found. Install it or check your PATH."
    fi
}

# Build extra Codex CLI flags for working directory / git repo handling.
# Codex requires running inside a trusted git repo. We use:
#   --cd <DIR>               when we can find a git root
#   --skip-git-repo-check    when we can't (lets Codex run anywhere)
#
# Priority: --cwd flag > CONSULT_CODEX_CWD env > nearest git root from PWD > skip check.
# Returns the flags as a string (may be empty, one flag, or two).
codex_repo_flags() {
    local target=""

    # Explicit override takes priority
    if [[ -n "$CODEX_CWD" ]]; then
        target="$CODEX_CWD"
    else
        # Try to find the nearest git root from current directory
        target=$(git rev-parse --show-toplevel 2>/dev/null) || true
    fi

    if [[ -n "$target" && -d "$target/.git" ]]; then
        echo "--cd $target"
    else
        # No git repo found — skip the check so Codex doesn't refuse to run
        echo "--skip-git-repo-check"
    fi
}

# Filter CLI boilerplate from output.
# Codex and Gemini CLIs include startup banners, progress indicators,
# box-drawing characters, and other noise that isn't part of the actual response.
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
        -e '/^[[:space:]]*$/{ N; /^[[:space:]]*\n[[:space:]]*$/d; }' \
        -e '/^\[.*spinner\]/d' \
        -e '/^Thinking\.\.\./d' \
        -e '/^Reading /d' \
        -e '/^Searching /d' \
        -e '/^exec$/d' \
        -e '/^tokens used$/d' \
        -e '/^[0-9,]*$/d'
}

# Detect whether the bwrap sandbox works on this system.
# Returns 0 if bwrap sandbox is functional, 1 if broken.
# Caches the result for the session in a temp file.
detect_codex_sandbox() {
    local cache_file="/tmp/.consult-sandbox-probe-$$"

    # If user explicitly set a sandbox mode, use it
    if [[ "$CODEX_SANDBOX" != "auto" ]]; then
        echo "$CODEX_SANDBOX"
        return
    fi

    # Check cached probe result (valid for this shell session)
    if [[ -f "/tmp/.consult-sandbox-ok" ]]; then
        cat "/tmp/.consult-sandbox-ok"
        return
    fi

    echo "Probing Codex sandbox compatibility..." >&2

    # Probe: ask Codex to actually read a file in read-only mode.
    # A trivial "reply with X" prompt doesn't test filesystem access.
    local probe_file="/etc/hostname"
    local expected_content
    expected_content=$(cat "$probe_file" 2>/dev/null || echo "")

    if [[ -z "$expected_content" ]]; then
        # Fallback: if /etc/hostname doesn't exist, skip probe and use safe default
        echo "danger-full-access" > "/tmp/.consult-sandbox-ok"
        echo "Sandbox probe: skipped (no probe file), using danger-full-access." >&2
        echo "danger-full-access"
        return
    fi

    local repo_flags
    repo_flags=$(codex_repo_flags)

    local probe_result probe_exit=0
    probe_result=$(printf '%s' "Read the file $probe_file and reply with ONLY its contents, nothing else." | timeout 45 \
        codex exec --model "$CODEX_MODEL" --sandbox read-only --ephemeral $repo_flags 2>/dev/null) || probe_exit=$?

    if [[ $probe_exit -eq 0 && "$probe_result" == *"$expected_content"* ]]; then
        echo "read-only" > "/tmp/.consult-sandbox-ok"
        echo "Sandbox probe: read-only works (verified file read)." >&2
        echo "read-only"
    else
        echo "danger-full-access" > "/tmp/.consult-sandbox-ok"
        echo "Sandbox probe: read-only can't read files, using danger-full-access." >&2
        echo "danger-full-access"
    fi
}

# Build context block from --context file arguments.
# Supports file.py (whole file) or file.py:40-80 (line range).
build_context_block() {
    local context_block=""
    for spec in "${CONTEXT_FILES[@]}"; do
        local file="${spec%%:*}"
        local range="${spec#*:}"

        if [[ ! -f "$file" ]]; then
            echo "WARNING: Context file not found: $file" >&2
            continue
        fi

        context_block+=$'\n--- Context: '"$spec"$' ---\n'
        if [[ "$range" != "$spec" && "$range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            context_block+=$(sed -n "${start},${end}p" "$file")
        else
            context_block+=$(cat "$file")
        fi
        context_block+=$'\n--- End: '"$spec"$' ---\n'
    done
    echo "$context_block"
}

# Check if Codex output indicates a sandbox failure (bwrap error).
# Some responses come back "successfully" (exit 0) but contain only
# error messages about sandbox failures instead of actual analysis.
codex_output_is_sandbox_failure() {
    local output="$1"
    [[ "$output" == *"bwrap"* && "$output" == *"RTM_NEWADDR"* ]] ||
    [[ "$output" == *"sandbox is rejecting"* ]] ||
    [[ "$output" == *"Failed RTM_NEWADDR"* ]] ||
    [[ "$output" == *"couldn't read"*"sandbox error"* ]] ||
    [[ "$output" == *"Not inside a trusted directory"* ]]
}

# Check if Codex output indicates it couldn't actually do the work.
# Codex sometimes returns exit 0 but admits it failed to read files.
# Only matches explicit failure admissions — not short successful answers.
codex_output_is_empty_response() {
    local output="$1"
    [[ "$output" == *"I can't give a faithful review"* ]] ||
    [[ "$output" == *"I was unable to read"* ]] ||
    [[ "$output" == *"I couldn't read"* ]] ||
    [[ "$output" == *"I can't read"* ]] ||
    [[ "$output" == *"paste the contents"* && "$output" == *"couldn't read"* ]] ||
    [[ "$output" == *"sandbox is rejecting"* ]] ||
    [[ "$output" == *"shell access is being blocked"* ]]
}

run_codex() {
    local prompt="$1"
    local outfile="${2:-${OUTPUT_DIR}/codex-${TIMESTAMP}.md}"
    local errlog="${OUTPUT_DIR}/codex-${TIMESTAMP}.stderr.log"

    require_provider codex

    # Detect best sandbox mode
    local sandbox
    sandbox=$(detect_codex_sandbox)

    # Codex must run inside a trusted git repo — use --cd or --skip-git-repo-check
    local repo_flags
    repo_flags=$(codex_repo_flags)

    echo "Consulting Codex (model: ${CODEX_MODEL}, timeout: ${TIMEOUT}s, sandbox: ${sandbox}, flags: ${repo_flags})..." >&2

    local result exit_code=0
    result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        codex exec --model "$CODEX_MODEL" --sandbox "$sandbox" $repo_flags 2>"$errlog" \
        | filter_output) || exit_code=$?

    # Check for sandbox failure or soft failure (exit 0 but couldn't read files).
    # If sandbox isn't already danger-full-access, retry with it.
    if [[ $exit_code -eq 0 && "$sandbox" != "danger-full-access" ]]; then
        if codex_output_is_sandbox_failure "$result" || codex_output_is_empty_response "$result"; then
            echo "Codex couldn't read files with sandbox '$sandbox'. Retrying with danger-full-access..." >&2
            echo "danger-full-access" > "/tmp/.consult-sandbox-ok"
            sandbox="danger-full-access"

            exit_code=0
            result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
                codex exec --model "$CODEX_MODEL" --sandbox "$sandbox" $repo_flags 2>"$errlog" \
                | filter_output) || exit_code=$?
        fi
    fi

    # After retry (or if already on danger-full-access), check for remaining failures
    if [[ $exit_code -eq 0 ]] && codex_output_is_empty_response "$result"; then
        echo "WARNING: Codex still couldn't complete the task after sandbox fallback." >&2
        echo "Consider using --context to inline file contents." >&2
    fi

    if [[ $exit_code -eq 0 && -n "$result" ]]; then
        echo "$result" > "$outfile"
        echo "Codex result saved to: ${outfile}" >&2
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
    local outfile="${2:-${OUTPUT_DIR}/gemini-${TIMESTAMP}.md}"
    local errlog="${OUTPUT_DIR}/gemini-${TIMESTAMP}.stderr.log"

    require_provider gemini

    echo "Consulting Gemini (model: ${GEMINI_MODEL}, timeout: ${TIMEOUT}s, yolo/auto-approve)..." >&2

    local result exit_code=0
    result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        env NODE_NO_WARNINGS=1 gemini -p "" -o text --approval-mode yolo -m "$GEMINI_MODEL" 2>"$errlog" \
        | filter_output) || exit_code=$?

    if [[ $exit_code -eq 0 && -n "$result" ]]; then
        echo "$result" > "$outfile"
        echo "Gemini result saved to: ${outfile}" >&2
        echo "$result"
    elif [[ $exit_code -eq 124 ]]; then
        echo "Gemini stderr log: ${errlog}" >&2
        die "Gemini timed out after ${TIMEOUT}s"
    else
        echo "Gemini stderr log: ${errlog}" >&2
        die "Gemini failed (exit code: ${exit_code}). Check stderr log for details."
    fi
}

show_availability() {
    local any_available=false
    if check_provider codex; then
        local ver
        ver=$(codex --version 2>/dev/null || echo 'unknown version')
        local sandbox
        sandbox=$(detect_codex_sandbox)
        echo "codex: available ($ver, sandbox: $sandbox)"
        any_available=true
    else
        echo "codex: not installed"
    fi
    if check_provider gemini; then
        local ver
        ver=$(gemini --version 2>/dev/null || echo 'unknown version')
        echo "gemini: available ($ver)"
        any_available=true
    else
        echo "gemini: not installed"
    fi
    if ! $any_available; then
        echo ""
        echo "No providers available. Install codex or gemini CLI to use consultations."
        exit 1
    fi
}

# --- Argument Parsing ---

CONTEXT_FILES=()
MODEL_OVERRIDE=""
TIMEOUT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            [[ $# -ge 2 ]] || die "--context requires a file path argument"
            CONTEXT_FILES+=("$2")
            shift 2
            ;;
        --model)
            [[ $# -ge 2 ]] || die "--model requires a model name argument"
            MODEL_OVERRIDE="$2"
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 ]] || die "--timeout requires a number of seconds"
            TIMEOUT_OVERRIDE="$2"
            shift 2
            ;;
        --sandbox)
            [[ $# -ge 2 ]] || die "--sandbox requires a mode (read-only, danger-full-access, auto)"
            CODEX_SANDBOX="$2"
            shift 2
            ;;
        --cwd)
            [[ $# -ge 2 ]] || die "--cwd requires a directory path"
            CODEX_CWD="$2"
            shift 2
            ;;
        --*)
            die "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -ge 1 ]] || die "Usage: consult.sh [options] <codex|gemini|both|check> \"prompt\""

provider="$1"
shift

# Apply overrides after provider is known
if [[ -n "$TIMEOUT_OVERRIDE" ]]; then
    TIMEOUT="$TIMEOUT_OVERRIDE"
fi

# Handle check command (no prompt needed)
if [[ "$provider" == "check" ]]; then
    show_availability
    exit 0
fi

[[ $# -ge 1 ]] || die "Usage: consult.sh [options] <codex|gemini|both> \"prompt\""
prompt="$1"

# Apply model override — for 'both', applies to whichever provider matches
if [[ -n "$MODEL_OVERRIDE" ]]; then
    case "$provider" in
        codex) CODEX_MODEL="$MODEL_OVERRIDE" ;;
        gemini) GEMINI_MODEL="$MODEL_OVERRIDE" ;;
        both)
            echo "WARNING: --model with 'both' applies to both providers. Use env vars for per-provider models." >&2
            CODEX_MODEL="$MODEL_OVERRIDE"
            GEMINI_MODEL="$MODEL_OVERRIDE"
            ;;
    esac
fi

# Append inline context if --context files were provided
if [[ ${#CONTEXT_FILES[@]} -gt 0 ]]; then
    context_block=$(build_context_block)
    prompt="${prompt}${context_block}"
fi

# Prepend the consultation preamble to override any plugin workflows
prompt="${CONSULT_PREAMBLE}${prompt}"

mkdir -p "$OUTPUT_DIR"

case "$provider" in
    codex)
        run_codex "$prompt"
        ;;
    gemini)
        run_gemini "$prompt"
        ;;
    both)
        # Validate both providers exist BEFORE spawning backgrounds
        codex_available=true
        gemini_available=true
        check_provider codex || codex_available=false
        check_provider gemini || gemini_available=false

        if ! $codex_available && ! $gemini_available; then
            die "Neither codex nor gemini CLI is available."
        fi

        codex_out="${OUTPUT_DIR}/codex-${TIMESTAMP}.md"
        gemini_out="${OUTPUT_DIR}/gemini-${TIMESTAMP}.md"

        codex_ok=false
        gemini_ok=false
        codex_pid=""
        gemini_pid=""

        # For both mode, probe sandbox once before spawning (avoids double probe)
        if $codex_available; then
            detect_codex_sandbox > /dev/null
        fi

        # Spawn available providers in parallel
        if $codex_available; then
            run_codex "$prompt" "$codex_out" > /dev/null &
            codex_pid=$!
        else
            echo "WARNING: codex not available, skipping." >&2
        fi

        if $gemini_available; then
            run_gemini "$prompt" "$gemini_out" > /dev/null &
            gemini_pid=$!
        else
            echo "WARNING: gemini not available, skipping." >&2
        fi

        # Wait for spawned providers
        if [[ -n "$codex_pid" ]]; then
            wait "$codex_pid" && codex_ok=true || true
        fi
        if [[ -n "$gemini_pid" ]]; then
            wait "$gemini_pid" && gemini_ok=true || true
        fi

        # Output results
        if $codex_available; then
            echo ""
            echo "=== CODEX RESPONSE ==="
            if $codex_ok && [[ -s "$codex_out" ]]; then
                cat "$codex_out"
            else
                echo "(Codex consultation failed or produced no output)"
            fi
        fi

        if $gemini_available; then
            echo ""
            echo "=== GEMINI RESPONSE ==="
            if $gemini_ok && [[ -s "$gemini_out" ]]; then
                cat "$gemini_out"
            else
                echo "(Gemini consultation failed or produced no output)"
            fi
        fi
        ;;
    *)
        die "Unknown provider: $provider. Use: codex, gemini, both, or check"
        ;;
esac
