#!/usr/bin/env bash
# gemini-gen-image.sh — Generate an image via Gemini Imagen and download it.
#
# Usage:
#   gemini-gen-image.sh "A dark-themed medical diagram showing..." [--output diagram.png]
#   gemini-gen-image.sh --prompt "prompt text" --output out.png
#
# Uses gemini.py (browser-cookie auth) to generate, then curl with cookies to download.
# Requires: GEMINI_SID and GEMINI_TS env vars (or auto-extracted via gemini-auth.py).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_PY="${GEMINI_PY:-$HOME/.hermes/scripts/gemini/gemini.py}"
PYTHON="${PYTHON:-$HOME/.hermes/hermes-agent/.venv/bin/python3}"
OUTPUT=""
PROMPT=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        *) PROMPT="$1"; shift ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo "Usage: gemini-gen-image.sh 'prompt text' [--output out.png]"
    exit 1
fi

OUTPUT="${OUTPUT:-/tmp/gemini-generated-$(date +%s).png}"

# Ensure we have cookies
if [ -z "${GEMINI_SID:-}" ] || [ -z "${GEMINI_TS:-}" ]; then
    echo "Extracting Gemini cookies..."
    eval "$($PYTHON $HOME/.hermes/scripts/gemini-auth.py 2>/dev/null)" || {
        echo "ERROR: Could not extract Gemini cookies. Login to gemini.google.com first."
        exit 1
    }
fi

# Step 0: Pre-flight auth health check
echo "Checking Gemini auth..."
"$PYTHON" "$GEMINI_PY" "ping" 2>/dev/null | grep -q "pong" || {
    echo "ERROR: Gemini auth expired or invalid. Re-authenticate:"
    echo "  1. Login to gemini.google.com in Firefox"
    echo "  2. Run: python3 ~/.hermes/scripts/gemini-auth.py"
    exit 1
}

# Step 1: Generate image via Gemini
echo "Generating image via Gemini..."
TMP_JSON="/tmp/gemini-gen-$$.json"
"$PYTHON" "$GEMINI_PY" --json -o "$TMP_JSON" "$PROMPT" 2>/dev/null || {
    echo "ERROR: Gemini generation failed"
    exit 1
}

# Step 2: Parse image URL from response
IMAGE_URL=$("$PYTHON" -c "
import json, sys
with open('$TMP_JSON') as f:
    data = json.load(f)
images = data.get('images', [])
if not images:
    print('NO_IMAGE', file=sys.stderr)
    sys.exit(1)
print(images[0]['url'])
" 2>/dev/null) || {
    echo "ERROR: No image in Gemini response. Prompt may not have triggered image generation."
    echo "Response saved to $TMP_JSON"
    exit 1
}

# Step 3: Download image with cookie auth
echo "Downloading image..."
curl -sL -b "__Secure-1PSID=${GEMINI_SID}; __Secure-1PSIDTS=${GEMINI_TS}" \
    -o "$OUTPUT" "$IMAGE_URL" 2>/dev/null

# Step 4: Verify
if [ -s "$OUTPUT" ]; then
    FILE_TYPE=$(file -b "$OUTPUT")
    SIZE=$(wc -c < "$OUTPUT")
    if echo "$FILE_TYPE" | grep -qi "png\|jpeg\|image"; then
        echo "SUCCESS: $OUTPUT ($SIZE bytes, $FILE_TYPE)"
        echo "$OUTPUT"
    else
        echo "WARNING: Downloaded file may not be an image: $FILE_TYPE"
        echo "$OUTPUT"
    fi
else
    echo "ERROR: Download failed or empty file"
    exit 1
fi

rm -f "$TMP_JSON"
