#!/usr/bin/env bash
# gemini-ping.sh — Health check: are Gemini cookies valid?
# Exit 0 = cookies work, 1 = expired/missing.
#
# Usage: gemini-ping.sh [--quiet]

set -euo pipefail

GEMINI_PY="${GEMINI_PY:-$HOME/.hermes/scripts/gemini/gemini.py}"
PYTHON="${PYTHON:-$HOME/.hermes/hermes-agent/.venv/bin/python3}"
QUIET="${1:-}"

# Check env vars
if [ -z "${GEMINI_SID:-}" ] || [ -z "${GEMINI_TS:-}" ]; then
    # Try extracting from Firefox
    eval "$($PYTHON $HOME/.hermes/scripts/gemini-auth.py 2>/dev/null)" || true
    if [ -z "${GEMINI_SID:-}" ]; then
        [ "$QUIET" != "--quiet" ] && echo "FATAL: No Gemini cookies. Login to gemini.google.com in Firefox."
        exit 1
    fi
fi

# Quick ping
RESULT=$(GEMINI_SID="$GEMINI_SID" GEMINI_TS="$GEMINI_TS" \
    "$PYTHON" "$GEMINI_PY" "Reply with exactly one word: pong" 2>/dev/null || echo "FAILED")

if echo "$RESULT" | grep -qi "pong"; then
    [ "$QUIET" != "--quiet" ] && echo "OK — Gemini cookies valid"
    exit 0
else
    [ "$QUIET" != "--quiet" ] && echo "EXPIRED — Gemini cookies stale. Re-login to gemini.google.com in Firefox."
    exit 1
fi
