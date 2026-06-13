#!/usr/bin/env bash
# Pre-push hook: scan staged files for PII before allowing push.
# Install: ln -s ../../scripts/pre-push-pii-scan.sh .git/hooks/pre-push
#
# Blocks pushes containing:
#   - Gemini tokens (g.a000..., sidts-...)
#   - API keys (sk-..., key-...)
#   - Windows profile paths (/mnt/c/Users/.../Firefox/Profiles/...)
#   - Email addresses (@gmail.com, @outlook.com, etc.)
#
# Override with: SKIP_PII_SCAN=1 git push

set -euo pipefail

if [ "${SKIP_PII_SCAN:-0}" = "1" ]; then
    exit 0
fi

# Get list of files being pushed (new + modified)
FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || echo "")

if [ -z "$FILES" ]; then
    # No staged files? Check what would be pushed
    REMOTE="${1:-origin}"
    BRANCH="${2:-HEAD}"
    FILES=$(git diff --name-only "$REMOTE/$BRANCH"..HEAD 2>/dev/null || echo "")
fi

if [ -z "$FILES" ]; then
    exit 0
fi

ISSUES=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    
    # Check each pattern
    if grep -qE 'g\.a000[A-Za-z0-9_\-]{30,}' "$file" 2>/dev/null; then
        echo "PII BLOCKED: $file contains Gemini SID token (g.a000...)"
        ISSUES=$((ISSUES + 1))
    fi
    if grep -qE 'sidts-[A-Za-z0-9_\-]{20,}' "$file" 2>/dev/null; then
        echo "PII BLOCKED: $file contains Gemini TS token (sidts-...)"
        ISSUES=$((ISSUES + 1))
    fi
    if grep -qE 'sk-[A-Za-z0-9]{20,}' "$file" 2>/dev/null; then
        echo "PII BLOCKED: $file contains API key (sk-...)"
        ISSUES=$((ISSUES + 1))
    fi
    if grep -qE '/mnt/c/Users/[^/]+/.*[Ff]irefox/.*[Pp]rofiles/' "$file" 2>/dev/null; then
        echo "PII BLOCKED: $file contains Firefox profile path"
        ISSUES=$((ISSUES + 1))
    fi
    if grep -qE '[A-Za-z0-9._%+-]+@(gmail|outlook|yahoo|protonmail|hotmail)\.com' "$file" 2>/dev/null; then
        echo "PII BLOCKED: $file contains email address"
        ISSUES=$((ISSUES + 1))
    fi
done <<< "$FILES"

if [ $ISSUES -gt 0 ]; then
    echo ""
    echo "Push blocked: $ISSUES PII pattern(s) found."
    echo "Sanitize these files or override with SKIP_PII_SCAN=1 git push"
    exit 1
fi

exit 0
