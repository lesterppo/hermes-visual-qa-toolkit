#!/usr/bin/env bash
# pre-commit-slide-doctor.sh — Block commits if HTML slide decks fail integrity checks.
# Install: ln -s ../../scripts/pre-commit-slide-doctor.sh .git/hooks/pre-commit
#
# Scans staged .html files, runs slide-doctor.py on each.
# Blocks commit if any deck has issues (exit code 1+).
# Override: SKIP_SLIDE_DOCTOR=1 git commit

set -euo pipefail

if [ "${SKIP_SLIDE_DOCTOR:-0}" = "1" ]; then
    exit 0
fi

DOCTOR="$HOME/.hermes/skills/creative/clinical-slide-deck/scripts/slide-doctor.py"
PYTHON="${PYTHON:-$HOME/.hermes/hermes-agent/.venv/bin/python3}"

if [ ! -f "$DOCTOR" ]; then
    echo "slide-doctor: SKIP (script not found at $DOCTOR)"
    exit 0
fi

# Get staged HTML files
FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.html$' || echo "")

if [ -z "$FILES" ]; then
    exit 0
fi

ISSUES=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    
    echo "slide-doctor: $file"
    if "$PYTHON" "$DOCTOR" "$file" --agent 2>/dev/null; then
        echo "  ✓ clean"
    else
        echo "  ✗ ISSUES FOUND — run: slide-doctor.py $file"
        ISSUES=$((ISSUES + 1))
    fi
done <<< "$FILES"

if [ $ISSUES -gt 0 ]; then
    echo ""
    echo "Commit blocked: $ISSUES HTML file(s) fail integrity checks."
    echo "Fix issues or override: SKIP_SLIDE_DOCTOR=1 git commit"
    exit 1
fi

exit 0
