---
name: gemini-image-generation
description: Generate raster images via Gemini Imagen on gemini.google.com using browser-cookie auth. Replaces broken SVGs or creates new diagrams from text prompts. Uses the gemini.py CLI which returns image URLs in response.images — download with cookie auth.
triggers:
  keywords:
    - gemini image
    - generate image
    - imagen
    - gemini diagram
    - gemini illustration
    - replace SVG with image
  context:
    - User wants to generate a medical/scientific diagram
    - User wants to replace a broken SVG with a generated PNG
    - User wants raster images instead of vector graphics
    - User's Gemini account supports Imagen
---

# Gemini Image Generation

## Agent Quick Path

```
TRIGGER: user wants to generate/replace a diagram as raster image
1. gemini-gen-image.sh "detailed prompt" --output diagram.png
   (auto-extracts cookies, calls gemini.py, downloads image)
2. Replace SVG: patch() old <svg>...</svg> with <img src="diagram.png">
3. Clean orphaned SVG content: find </svg> boundary, delete all SVG internals
4. Verify: grep -c 'marker-end' deck.html (should be zero for replaced slides)
```

## Prerequisites

Use the gemini.py CLI to generate raster images via Gemini's Imagen on gemini.google.com. The chat API returns image URLs in `response.images` — download them with cookie auth.

## One-Command Wrapper

Instead of the manual 2-step process, use `scripts/gemini-gen-image.sh`:

```bash
# Generate + download in one command
bash scripts/gemini-gen-image.sh "A dark-themed medical diagram showing..." --output diagram.png

# Auto-extracts cookies, calls gemini.py, parses JSON, downloads with auth
# Output: SUCCESS: diagram.png (227750 bytes, PNG image data)
```

The wrapper handles cookie extraction, JSON parsing, and verification automatically.

## Quick Reference

```bash
PY=~/.hermes/hermes-agent/.venv/bin/python3
GEMINI=~/.hermes/scripts/gemini/gemini.py
WRAPPER=~/.hermes/scripts/gemini/gemini-gemini.sh

# Generate an image (CLI writes image URLs to --json output)
$PY $GEMINI --json \
  "Generate a professional dark-themed medical diagram showing..." \
  -o /tmp/image-result.json

# Parse the image URL and download with cookies
# (The lh3.googleusercontent.com CDN requires cookie auth)
```

## Workflow

### Step 1: Generate the image

```bash
$PY $GEMINI --json \
  "Detailed prompt describing the diagram..." \
  -o /tmp/result.json
```

The response JSON contains:
```json
{"ok": true, "text": "", "images": [{"url": "https://lh3.googleusercontent.com/gg-dl/...", "alt": "watermarked_img_....png"}]}
```

**Prompt tips for medical/scientific diagrams:**
- Specify dark theme: "Dark navy background (#0f1623), gold academic accents (#c9a84c)"
- Describe layout: "Three columns showing...", "Left side shows..., right side shows..."
- Request style: "Clean scientific illustration style", "Professional medical diagram"
- List key elements: "Arrows showing flow, labeled regions, color coding (green=safe, red=risk)"

### Step 2: Download the image

The Google CDN URL requires the same cookies used for generation:

```bash
SID="<your_SID_value>"
TS="<your_TS_value>"
curl -sL -b "__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}" \
  -o output.png \
  "<image_url_from_json>"
```

Verify: `file output.png` should show "PNG image data".

### Step 3: Embed in HTML

Save the image alongside the HTML file and reference with a relative path:

```html
<img src="diagram.png" alt="Description" style="max-width:100%;height:auto;border-radius:8px">
```

Replace the SVG block entirely — not just the `<svg>` opening tag. Remove the entire `<svg>...</svg>` block including orphaned internals.

## Account Switching

The gemini_webapi uses browser cookies (`GEMINI_SID`, `GEMINI_TS`). To switch accounts:

1. Log into gemini.google.com with the desired account in Windows Firefox
2. Extract cookies: `$PY ~/.hermes/scripts/gemini-auth.py`
3. Use the printed export statements inline or set env vars

```bash
# Inline (doesn't affect saved cookies):
GEMINI_SID="..." GEMINI_TS="..." $PY $GEMINI "prompt"

# Or save to .env for persistent use:
# Copy values into ~/.hermes/.env
```

Default cookies are in `~/.hermes/.env` (auto-loaded by Hermes).

## Known Limitations

- Generated images are ~512px wide, watermarked ("Imagen" watermark in corner)
- Image generation may fail for complex multi-panel layouts — simplify the prompt
- Some prompts return text instead of images — add "Generate an image:" prefix
- The `--json` output flag is required to capture image URLs
- Standard `-o result.md` (non-JSON) doesn't capture images

## Pitfalls

1. **SVG replacement must be complete** — Replacing only the `<svg>` opening tag leaves orphaned SVG internals (defs, rects, text) that break the DOM. Delete the entire `<svg>...</svg>` block including orphaned content.

2. **Image CDN requires cookie auth** — Direct `curl` without cookies returns an HTML login page (2.5KB), not the image. Always pass `-b "__Secure-1PSID=...; __Secure-1PSIDTS=..."`.

3. **Account limits** — Free Gemini accounts have image generation rate limits. If one account hits the limit, switch to another (see Account Switching above).

4. **Image reference paths** — Save images in the same directory as the HTML and use relative paths (`src="image.png"` not absolute). This keeps the deck portable.

5. **Gemini QA hallucination risk** — After replacing SVGs with generated PNGs, Gemini may still hallucinate the old SVG issues when reviewing screenshots in a multi-turn conversation. Always verify visual QA with a direct "describe exactly what you see in this image" prompt and cross-reference responses.
