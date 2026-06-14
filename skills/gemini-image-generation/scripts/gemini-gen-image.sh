#!/usr/bin/env bash
# gemini-gen-image.sh — RELIABLE single-command Gemini Imagen wrapper
# Generates, downloads, and verifies an image in one call.
#
# Usage:
#   gemini-gen-image.sh "A dark-themed medical diagram..." --output diagram.png
#   gemini-gen-image.sh --prompt "prompt" -o out.png
#
# Features over the old wrapper:
#   - Auto-extracts cookies from Chrome (browser_cookie3) if env vars unset
#   - Handles TS=None gracefully (empty string, not None)
#   - Pre-flight ping before generation
#   - Falls back to Firefox if Chrome fails
#   - Verifies output with `file` command
#   - Returns JSON for agent consumption: {"ok":true,"path":"diagram.png","size":32000}
#
# Exit codes: 0=success, 1=auth failure, 2=generation failure, 3=download failure

set -euo pipefail

GEMINI_PY="${GEMINI_PY:-$HOME/.hermes/scripts/gemini/gemini.py}"
PYTHON="${PYTHON:-$HOME/.hermes/hermes-agent/.venv/bin/python3}"
OUTPUT=""
PROMPT=""
QUIET=false
TIMEOUT=90

usage() {
    cat <<EOF
Usage: gemini-gen-image.sh "prompt text" [--output out.png]
       gemini-gen-image.sh --prompt "text" -o out.png [--quiet]

Generates an image via Gemini Imagen, downloads it, verifies it.
EOF
    exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT="$2"; shift 2 ;;
        --prompt|-p) PROMPT="$2"; shift 2 ;;
        --quiet|-q) QUIET=true; shift ;;
        --help|-h) usage ;;
        *) PROMPT="$1"; shift ;;
    esac
done

[ -z "$PROMPT" ] && usage

OUTPUT="${OUTPUT:-/tmp/gemini-image-$(date +%s).png}"
TMP_JSON="/tmp/gemini-gen-$$.json"

# --- Step 0: Auth extraction ---
ensure_auth() {
    if [ -n "${GEMINI_SID:-}" ]; then
        return 0
    fi

    $QUIET || echo "[gemini-gen-image] Extracting cookies..."

    # Try Chrome first (more reliable in WSL)
    local cookies
    cookies=$("$PYTHON" -c "
import browser_cookie3, json, sys
try:
    cj = browser_cookie3.chrome(domain_name='.google.com')
    sid = None; ts = ''
    for c in cj:
        if c.name == '__Secure-1PSID': sid = c.value
        if c.name == '__Secure-1PSIDTS': ts = c.value
    if sid:
        print(f'export GEMINI_SID=\"{sid}\"')
        print(f'export GEMINI_TS=\"{ts or \"\"}\"')
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
        # Fallback: try Firefox
        cookies=$("$PYTHON" -c "
import browser_cookie3, sys
try:
    cj = browser_cookie3.firefox(domain_name='.google.com')
    sid = None; ts = ''
    for c in cj:
        if c.name == '__Secure-1PSID': sid = c.value
        if c.name == '__Secure-1PSIDTS': ts = c.value
    if sid:
        print(f'export GEMINI_SID=\"{sid}\"')
        print(f'export GEMINI_TS=\"{ts or \"\"}\"')
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
            echo '{"ok":false,"error":"No Gemini cookies found. Login at gemini.google.com in Chrome or Firefox first."}'
            exit 1
        }
    }

    eval "$cookies"
    $QUIET || echo "[gemini-gen-image] Cookies extracted successfully"
}

ensure_auth

# --- Step 1: Pre-flight ping ---
$QUIET || echo "[gemini-gen-image] Checking auth..."
GEMINI_SID="$GEMINI_SID" GEMINI_TS="${GEMINI_TS:-}" "$PYTHON" "$GEMINI_PY" "ping" 2>/dev/null | grep -qi "pong" || {
    echo '{"ok":false,"error":"Gemini auth expired. Re-login at gemini.google.com."}'
    exit 1
}

# --- Step 2: Generate image ---
$QUIET || echo "[gemini-gen-image] Generating image..."
GEMINI_SID="$GEMINI_SID" GEMINI_TS="${GEMINI_TS:-}" "$PYTHON" "$GEMINI_PY" --json -o "$TMP_JSON" "$PROMPT" 2>/dev/null || {
    echo '{"ok":false,"error":"Gemini generation failed (REQUEST_FAILED or timeout)"}'
    rm -f "$TMP_JSON"
    exit 2
}

# --- Step 3: Parse image URL ---
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
    echo '{"ok":false,"error":"No image in Gemini response. Add \"Generate an image:\" prefix to prompt."}'
    exit 2
}

# --- Step 4: Download with cookie auth ---
$QUIET || echo "[gemini-gen-image] Downloading..."
curl -sL --max-time 30 \
    -b "__Secure-1PSID=${GEMINI_SID}; __Secure-1PSIDTS=${GEMINI_TS:-}" \
    -o "$OUTPUT" "$IMAGE_URL" 2>/dev/null

# --- Step 5: Verify ---
if [ ! -s "$OUTPUT" ]; then
    echo '{"ok":false,"error":"Download failed — empty file"}'
    rm -f "$TMP_JSON"
    exit 3
fi

FILE_TYPE=$(file -b "$OUTPUT")
SIZE=$(wc -c < "$OUTPUT")

if echo "$FILE_TYPE" | grep -qi "png\|jpeg\|image"; then
    rm -f "$TMP_JSON"
    echo "{\"ok\":true,\"path\":\"$OUTPUT\",\"size\":$SIZE,\"type\":\"$FILE_TYPE\"}"
    exit 0
else
    echo "{\"ok\":false,\"error\":\"Downloaded file is not an image: $FILE_TYPE\",\"size\":$SIZE}"
    rm -f "$TMP_JSON"
    exit 3
fi
