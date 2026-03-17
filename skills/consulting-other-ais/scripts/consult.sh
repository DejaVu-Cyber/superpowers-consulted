#!/usr/bin/env bash
# consult.sh — Lightweight multi-AI consultation helper
# Sends a focused prompt to Codex and/or Gemini CLI in read-only mode.
# Both CLIs run locally and can explore the filesystem directly.
#
# Usage:
#   consult.sh codex "Your prompt here"
#   consult.sh gemini "Your prompt here"
#   consult.sh both "Your prompt here"
#
# The prompt should contain file paths for the AI to examine,
# not file contents. The CLIs will read files themselves.
#
# Environment variables:
#   CONSULT_CODEX_MODEL    - Codex model (default: gpt-5.4)
#   CONSULT_GEMINI_MODEL   - Gemini model (default: gemini-3.1-pro-preview)
#   CONSULT_TIMEOUT        - Timeout in seconds (default: 180)
#   CONSULT_OUTPUT_DIR     - Where to save results (default: /tmp/consult-results)

set -euo pipefail

# --- Configuration ---
CODEX_MODEL="${CONSULT_CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${CONSULT_GEMINI_MODEL:-gemini-3.1-pro-preview}"
TIMEOUT="${CONSULT_TIMEOUT:-180}"
OUTPUT_DIR="${CONSULT_OUTPUT_DIR:-/tmp/consult-results}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Functions ---

die() { echo "ERROR: $*" >&2; exit 1; }

check_provider() {
    local provider="$1"
    if ! command -v "$provider" >/dev/null 2>&1; then
        die "$provider CLI not found. Install it or check your PATH."
    fi
}

run_codex() {
    local prompt="$1"
    local outfile="${OUTPUT_DIR}/codex-${TIMESTAMP}.md"

    check_provider codex

    echo "Consulting Codex (model: ${CODEX_MODEL}, read-only)..." >&2

    local result
    if result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        codex exec --model "$CODEX_MODEL" --sandbox read-only 2>/dev/null); then
        echo "$result" > "$outfile"
        echo "Codex result saved to: ${outfile}" >&2
        echo "$result"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            die "Codex timed out after ${TIMEOUT}s"
        else
            die "Codex failed (exit code: ${exit_code})"
        fi
    fi
}

run_gemini() {
    local prompt="$1"
    local outfile="${OUTPUT_DIR}/gemini-${TIMESTAMP}.md"

    check_provider gemini

    echo "Consulting Gemini (model: ${GEMINI_MODEL}, plan/read-only)..." >&2

    local result
    if result=$(printf '%s' "$prompt" | timeout "$TIMEOUT" \
        env NODE_NO_WARNINGS=1 gemini -p "" -o text --approval-mode plan -m "$GEMINI_MODEL" 2>/dev/null); then
        echo "$result" > "$outfile"
        echo "Gemini result saved to: ${outfile}" >&2
        echo "$result"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            die "Gemini timed out after ${TIMEOUT}s"
        else
            die "Gemini failed (exit code: ${exit_code})"
        fi
    fi
}

# --- Main ---

[[ $# -ge 2 ]] || die "Usage: consult.sh <codex|gemini|both> \"prompt\""

provider="$1"
prompt="$2"

mkdir -p "$OUTPUT_DIR"

case "$provider" in
    codex)
        run_codex "$prompt"
        ;;
    gemini)
        run_gemini "$prompt"
        ;;
    both)
        # Run both in parallel, collect results
        codex_out="${OUTPUT_DIR}/codex-${TIMESTAMP}.md"
        gemini_out="${OUTPUT_DIR}/gemini-${TIMESTAMP}.md"

        run_codex "$prompt" > "$codex_out" 2>&1 &
        codex_pid=$!

        run_gemini "$prompt" > "$gemini_out" 2>&1 &
        gemini_pid=$!

        codex_ok=true
        gemini_ok=true

        wait "$codex_pid" || codex_ok=false
        wait "$gemini_pid" || gemini_ok=false

        echo ""
        echo "=== CODEX RESPONSE ==="
        if $codex_ok && [[ -s "$codex_out" ]]; then
            cat "$codex_out"
        else
            echo "(Codex consultation failed or produced no output)"
        fi

        echo ""
        echo "=== GEMINI RESPONSE ==="
        if $gemini_ok && [[ -s "$gemini_out" ]]; then
            cat "$gemini_out"
        else
            echo "(Gemini consultation failed or produced no output)"
        fi
        ;;
    *)
        die "Unknown provider: $provider. Use: codex, gemini, or both"
        ;;
esac
