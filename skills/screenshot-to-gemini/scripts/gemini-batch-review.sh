#!/usr/bin/env bash
# gemini-batch-review.sh — Chunked screenshot review with hallucination guard.
#
# Splits screenshots into batches of 3, sends each to Gemini with conversation
# continuation. After the QA review, runs a cross-verification pass to catch
# hallucinations (Gemini describing SVG bugs that don't exist in raster images).
#
# Usage:
#   gemini-batch-review.sh /tmp/slide_01.png /tmp/slide_35.png ... 
#   gemini-batch-review.sh --qa "Review these medical slides for defects" /tmp/slide_*.png
#
# Requires: gemini-gemini.sh, gemini-ping.sh (cookies must be valid)

set -euo pipefail

GEMINI="${GEMINI:-$HOME/.hermes/scripts/gemini/gemini-gemini.sh}"
PING="$HOME/.hermes/skills/research/gemini-image-generation/scripts/gemini-ping.sh"
TMPDIR="${TMPDIR:-/tmp}"
CHAT_FILE="$TMPDIR/gemini-batch-review-$$.json"
OUTPUT_DIR="$TMPDIR/gemini-review-$$"
BATCH_SIZE=3
QA_PROMPT=""
IMAGES=()

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --qa) QA_PROMPT="$2"; shift 2 ;;
        --batch-size) BATCH_SIZE="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -*) echo "Unknown flag: $1"; exit 1 ;;
        *) IMAGES+=("$1"); shift ;;
    esac
done

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "Usage: gemini-batch-review.sh [--qa 'prompt'] slide_*.png"
    exit 1
fi

# Pre-flight: cookie health check
if ! bash "$PING" --quiet 2>/dev/null; then
    echo "FATAL: Gemini cookies expired. Login to gemini.google.com in Firefox."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Default QA prompt
QA_PROMPT="${QA_PROMPT:-You are a QA reviewer for a clinical slide deck. Review each slide for: 1) VISIBILITY - any cutoff text, overlapping elements, blank areas? 2) LAYOUT - tables/cards properly aligned? 3) IMAGES - diagrams display correctly? 4) TYPOGRAPHY - fonts loading? 5) COLOR - dark theme consistent? For each issue, state slide number and precise description.}"

echo "=== Gemini Chunked Review ==="
echo "Images: ${#IMAGES[@]} | Batch size: $BATCH_SIZE | Output: $OUTPUT_DIR"
echo ""

# Phase 1: QA Review (batched)
TOTAL_BATCHES=$(( (${#IMAGES[@]} + BATCH_SIZE - 1) / BATCH_SIZE ))
NEW_FLAG="--new"

for ((b=0; b<TOTAL_BATCHES; b++)); do
    START=$((b * BATCH_SIZE))
    BATCH_IMAGES=("${IMAGES[@]:$START:$BATCH_SIZE}")
    
    IMG_FLAGS=""
    for img in "${BATCH_IMAGES[@]}"; do
        IMG_FLAGS="$IMG_FLAGS -i $img"
    done
    
    BATCH_LABEL="batch-$((b+1))of${TOTAL_BATCHES}"
    echo "[$BATCH_LABEL] Reviewing ${#BATCH_IMAGES[@]} images..."
    
    $GEMINI $NEW_FLAG $IMG_FLAGS -c "$CHAT_FILE" \
        -m pro --thinking extended \
        "$QA_PROMPT" \
        -o "$OUTPUT_DIR/qa-$((b+1)).md" 2>/dev/null
    
    NEW_FLAG=""  # Continue conversation after first batch
    echo "  → $OUTPUT_DIR/qa-$((b+1)).md"
done

# Phase 2: Hallucination guard — cross-verify
echo ""
echo "=== Cross-Verification (hallucination guard) ==="

for ((b=0; b<TOTAL_BATCHES; b++)); do
    START=$((b * BATCH_SIZE))
    BATCH_IMAGES=("${IMAGES[@]:$START:$BATCH_SIZE}")
    
    IMG_FLAGS=""
    for img in "${BATCH_IMAGES[@]}"; do
        IMG_FLAGS="$IMG_FLAGS -i $img"
    done
    
    echo "[verify batch $((b+1))] Describing actual visual content..."
    
    $GEMINI $IMG_FLAGS -m pro \
        "For each image, describe ONLY what you actually SEE — not what the code says. 
        List specific visible elements: arrows, labels, boxes, text. 
        If you see arrowheads on lines, say 'arrowheads visible'. 
        If lines have no arrowheads, say 'plain lines, no arrowheads'." \
        -o "$OUTPUT_DIR/verify-$((b+1)).md" 2>/dev/null
    
    echo "  → $OUTPUT_DIR/verify-$((b+1)).md"
done

# Phase 3: Compare QA vs verify for contradictions
echo ""
echo "=== Discrepancy Check ==="
HALLUCINATIONS=0
for ((b=0; b<TOTAL_BATCHES; b++)); do
    QA_FILE="$OUTPUT_DIR/qa-$((b+1)).md"
    VERIFY_FILE="$OUTPUT_DIR/verify-$((b+1)).md"
    
    if [ -f "$QA_FILE" ] && [ -f "$VERIFY_FILE" ]; then
        # Check if QA mentions SVG/arrowhead/marker fixes
        if grep -qi "svg\|marker\|arrowhead\|defs\|marker-end" "$QA_FILE" 2>/dev/null; then
            # Check if verify confirms actual rendering issues
            if grep -qi "arrowhead.*visible\|arrows.*visible\|no arrowhead\|plain line" "$VERIFY_FILE" 2>/dev/null; then
                echo "  Batch $((b+1)): QA mentions SVG/markers → cross-ref VERIFY for actual state"
            else
                echo "  Batch $((b+1)): ⚠ POTENTIAL HALLUCINATION — QA mentions SVG/markers but verify doesn't confirm"
                HALLUCINATIONS=$((HALLUCINATIONS + 1))
            fi
        fi
    fi
done

echo ""
if [ $HALLUCINATIONS -gt 0 ]; then
    echo "⚠ $HALLUCINATIONS potential hallucination(s) detected. Review verify-*.md against qa-*.md."
else
    echo "✓ No obvious hallucination patterns detected."
fi
echo ""
echo "All results: $OUTPUT_DIR/"
