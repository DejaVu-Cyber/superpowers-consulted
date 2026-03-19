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
#
# Environment variables:
#   CONSULT_CODEX_MODEL    - Codex model (default: gpt-5.4)
#   CONSULT_GEMINI_MODEL   - Gemini model (default: gemini-3.1-pro-preview)
#   CONSULT_TIMEOUT        - Timeout in seconds (default: 600)
#   CONSULT_OUTPUT_DIR     - Where to save results (default: /tmp/consult-results)

set -euo pipefail

# --- Configuration ---
CODEX_MODEL="${CONSULT_CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${CONSULT_GEMINI_MODEL:-gemini-3.1-pro-preview}"
TIMEOUT="${CONSULT_TIMEOUT:-600}"
OUTPUT_DIR="${CONSULT_OUTPUT_DIR:-/tmp/consult-results}"
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

# Filter CLI boilerplate from output.
# Codex and Gemini CLIs include startup banners, progress indicators,
# box-drawing characters, and other noise that isn't part of the actual response.
filter_output() {
    sed \
        -e '/^Codex /d' \
        -e '/^codex /d' \
        -e '/^⠋/d' -e '/^⠙/d' -e '/^⠹/d' -e '/^⠸/d' \
        -e '/^⠼/d' -e '/^⠴/d' -e '/^⠦/d' -e '/^⠧/d' \
        -e '/^⠇/d' -e '/^⠏/d' \
        -e '/^Gemini /d' \
        -e '/^gemini /d' \
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
        -e '/^Searching /d'
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

run_codex() {
    local prompt="$1"
    local outfile="${2:-${OUTPUT_DIR}/codex-${TIMESTAMP}.md}"
    local errlog="${OUTPUT_DIR}/codex-${TIMESTAMP}.stderr.log"

    require_provider codex

    echo "Consulting Codex (model: ${CODEX_MODEL}, timeout: ${TIMEOUT}s, read-only)..." >&2

    local result exit_code=0
    result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        codex exec --model "$CODEX_MODEL" --sandbox read-only 2>"$errlog" \
        | filter_output) || exit_code=$?

    if [[ $exit_code -eq 0 && -n "$result" ]]; then
        echo "$result" > "$outfile"
        echo "Codex result saved to: ${outfile}" >&2
        echo "$result"
    elif [[ $exit_code -eq 124 ]]; then
        echo "Codex stderr log saved to: ${errlog}" >&2
        die "Codex timed out after ${TIMEOUT}s"
    else
        echo "Codex stderr log saved to: ${errlog}" >&2
        die "Codex failed (exit code: ${exit_code})"
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
        echo "Gemini stderr log saved to: ${errlog}" >&2
        die "Gemini timed out after ${TIMEOUT}s"
    else
        echo "Gemini stderr log saved to: ${errlog}" >&2
        die "Gemini failed (exit code: ${exit_code})"
    fi
}

show_availability() {
    local any_available=false
    if check_provider codex; then
        local ver
        ver=$(codex --version 2>/dev/null || echo 'unknown version')
        echo "codex: available ($ver)"
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
