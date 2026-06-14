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

## Scripts

| Script | Purpose |
|--------|---------|
| `gemini-ping.sh` | Cookie health check: sends "ping", expects "pong". Exit 0 = valid, 1 = expired. Use before any Gemini-dependent workflow. `--quiet` for silent mode. |
| `gemini-gen-image.sh` | One-command generate+download wrapper (convenience, not replacement for manual 3-step) |

## Agent Quick Path (manual — transparent, debuggable)

```
TRIGGER: user wants to generate/replace a diagram as raster image
1. GEMINI_SID=... GEMINI_TS=... gemini.py --json "prompt" -o result.json
2. Parse: python3 -c "import json; d=json.load(open('result.json')); print(d['images'][0]['url'])"
3. curl -sL -b "__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}" -o diagram.png "$URL"
4. Verify: file diagram.png  → must say "PNG image data"
5. patch() to replace <svg>...</svg> with <img src="diagram.png">
6. Clean orphaned SVG content (defs, rects, text, paths) after </svg>

Shorthand: gemini-gen-image.sh "prompt" -o diagram.png  (same 3 steps, auto-cookie)
```

## One-Command Wrapper

Use the gemini.py CLI to generate raster images via Gemini's Imagen on gemini.google.com. The chat API returns image URLs in `response.images` — download them with cookie auth.

## One-Command Wrapper (DEPRECATED — use manual path below)

The wrapper `scripts/gemini-gen-image.sh` has a ~60% failure rate (3/5 attempts failed in PIVKA-II session: 2× REQUEST_FAILED, 1× "No image"). Direct `gemini.py --json` succeeded 1/1 with the same prompts. **Prefer the manual 3-step path.** The wrapper is kept for reference but should NOT be the primary approach.

```bash
# Generate + download in one command
bash scripts/gemini-gen-image.sh "A dark-themed medical diagram showing..." --output diagram.png

# Auto-extracts cookies, calls gemini.py, parses JSON, downloads with auth
# Output: SUCCESS: diagram.png (227750 bytes, PNG image data)
```

The wrapper handles cookie extraction, JSON parsing, and verification automatically.

## Quick Reference

```bash
PY=/home/peter/.hermes/hermes-agent/.venv/bin/python3
GEMINI=/home/peter/.hermes/scripts/gemini/gemini.py
WRAPPER=/home/peter/.hermes/scripts/gemini/gemini-gemini.sh

# MANDATORY: Pre-flight auth health check before ANY Gemini workflow
bash /home/peter/.hermes/skills/research/gemini-image-generation/scripts/gemini-ping.sh --quiet
# Exit 0 = valid. Exit 1 = re-auth needed → run gemini-auth.py

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

See `references/gemini-auth-switching.md` in the screenshot-to-gemini skill for the complete WSL account switching workflow, including Firefox profile scanning, TS=None handling, and rate limit recovery.

The gemini_webapi uses browser cookies (`GEMINI_SID`, `GEMINI_TS`). To switch accounts:

1. Log into gemini.google.com with the desired account in Windows Firefox
2. Extract cookies: `$PY /home/peter/.hermes/scripts/gemini-auth.py`
3. Use the printed export statements inline or set env vars

```bash
# Inline (doesn't affect saved cookies):
GEMINI_SID="..." GEMINI_TS="..." $PY $GEMINI "prompt"

# Or save to .env for persistent use:
# Copy values into ~/.hermes/.env
```

Default cookies are in `~/.hermes/.env` (auto-loaded by Hermes).

### Account Switching Pitfall: TS=None on Alternate Accounts

When switching to a second Google account, `gemini-auth.py` frequently outputs `GEMINI_TS="None"` (the string `"None"`, not an empty string). This breaks the `gemini-gemini.sh` wrapper which calls `gemini-auth.py` internally and crashes with `TypeError: expected str, bytes or os.PathLike object, not NoneType` because Python `os.fsencode(None)` fails.

**Workaround:** When TS is `"None"` or empty, do NOT use the `gemini-gemini.sh` wrapper. Instead, use `gemini.py` directly with inline env vars:

```bash
# Set TS to empty string (not None) to avoid the crash:
export GEMINI_SID="g.a000_..."
export GEMINI_TS=""
$PY $GEMINI -p "your prompt" -m pro --thinking extended -o /tmp/output.md

# For files, use -f for documents and -p for the prompt text:
$PY $GEMINI -f deck.html -p "review this deck..." -m pro --thinking extended -o /tmp/review.md

# For image generation, use --json:
$PY $GEMINI --json -p "Generate an image: ..." -o /tmp/result.json
```

**Verification:** After setting `GEMINI_TS=""`, test with a simple `$PY $GEMINI "ping"` — must return `pong` before proceeding.

## Known Limitations

- Generated images are ~512px wide, watermarked ("Imagen" watermark in corner)
- Image generation may fail for complex multi-panel layouts — simplify the prompt
- Some prompts return text instead of images — add "Generate an image:" prefix
- The `--json` output flag is required to capture image URLs
- Standard `-o result.md` (non-JSON) doesn't capture images

## Pitfalls

1. **Wrapper script is unreliable — prefer direct gemini.py** — `gemini-gen-image.sh` fails ~60% of the time (3/5 attempts in PIVKA-II session). Failure modes: `REQUEST_FAILED` ("silently aborted by Google") or "No image in Gemini response" (prompt didn't trigger image mode). In the same session, direct `gemini.py --json` succeeded 1/1 with the same prompt. **Always prefer the manual 3-step workflow:** gemini.py --json → parse URL → curl download. If a background wrapper attempt fails, kill it and retry with direct gemini.py.

2. **SVG replacement must be complete** — Replacing only the `<svg>` opening tag leaves orphaned SVG internals (defs, rects, text) that break the DOM. Delete the entire `<svg>...</svg>` block including orphaned content.

3. **Image CDN requires cookie auth** — Direct `curl` without cookies returns an HTML login page (2.5KB), not the image. Always pass `-b "__Secure-1PSID=...; __Secure-1PSIDTS=..."`.

4. **Account capability vs rate limit** — When Gemini returns "I can try to find an image... but can't create it right now" this means the account **lacks Imagen capability** — NOT a rate limit or auth issue. The ping check verifies auth but NOT image capability. If one account fails consistently after 2 attempts, switch accounts.

   **Confirmed working:** A Google account without TS cookie (GEMINI_TS="") via Windows Firefox. 4/4 images generated successfully in MDR-TB deck session using direct gemini.py workflow.

5. **Image reference paths** — Save images in the same directory as the HTML and use relative paths (`src="image.png"` not absolute). This keeps the deck portable.

6. **Gemini QA hallucination risk** — After replacing SVGs with generated PNGs, Gemini may still hallucinate the old SVG issues when reviewing screenshots in a multi-turn conversation. Always verify visual QA with a direct "describe exactly what you see in this image" prompt and cross-reference responses.

7. **Auth expiry mid-session (< 30 min possible)** — Cookies can expire in under 30 minutes even after a fresh extraction. The first image generation in a session MUST be preceded by `gemini-ping.sh --quiet`. If auth fails (exit 1), re-extract cookies with `gemini-auth.py`. A wasted generation prompt on expired auth costs tokens with no output. In the PIVKA-II session: ping passed at the start, but all 3 image generations failed 12 seconds later due to auth expiry between ping and generation.

8. **Batch generation saves wall-clock time** — For decks needing 3+ images, start all generations as parallel background processes (`terminal(background=true, notify_on_complete=true)`). All 3 will complete in parallel (~30s) instead of sequentially (~90s). Verify each with `file output.png` → must say "PNG image data".

9. **Embed images with single patch() or execute_code pass** — After all images are generated, embed them into the deck in ONE pass (find target, insert `<img>` tag). Multiple separate patch() calls multiply token overhead with no benefit.

10. **MANDATORY: Prefix prompt with "Generate an image:"** — Without this prefix, Gemini may respond with text instead of triggering Imagen. This is the single most common cause of "No image in Gemini response" failures. Always start image-generation prompts with "Generate an image:" followed by the detailed description.

11. **gemini-gemini.sh wrapper crashes with null TS** — When `gemini-auth.py` extracts cookies and `GEMINI_TS` is `None` (some Google accounts have no TS cookie), the `gemini-gemini.sh` wrapper calls `gemini-auth.py` internally which crashes with `TypeError: expected str, bytes or os.PathLike object, not NoneType`. **Workaround:** Use `gemini.py` directly: `GEMINI_SID=... GEMINI_TS="" gemini.py -p "$(cat prompt.md)" -m pro -o out.md`. Skip the wrapper entirely for accounts with null TS. The `-f` flag on gemini.py attaches a document; the prompt text itself goes via `-p` or positional args.

12. **Passing prompt text from a file to gemini.py** — The `-f` flag on `gemini.py` attaches a file as a **document** (like PDF, CSV, context material), NOT as prompt text. Using `-f prompt.md` alone causes "Prompt cannot be empty." To pass a file's content as the prompt text, use shell substitution: `-p "$(cat /path/to/prompt.md)"`. The wrapper `gemini-gemini.sh` handles `-f` differently — it can accept `-f file` as context alongside a positional prompt string. **Pattern for pre-build synthesis:** `$PY $GEMINI -p "$(cat /tmp/synthesis-prompt.md)" -m pro --thinking extended -o /tmp/synthesis.md`. **Pattern for deck review with file context:** `$PY $GEMINI -f deck.html -p "review this deck..." -m pro --thinking extended -o /tmp/review.md`.

13. **`-f` silently drops large files — use `-p "$(cat ...)"` for multi-file or >30KB input** — The `-f` flag has a per-file size limit (~30KB observed: 65KB clinical-slide-deck SKILL.md was silently dropped while 4KB and 7KB files were attached). When sending multiple files or large files for cross-check/review, concatenate them into the prompt text: `-p "$(cat file1.md file2.md)\n\n---\n\nYOUR INSTRUCTION HERE"`. This bypasses the attachment limit entirely and guarantees all content reaches Gemini. **Pattern for multi-file cross-check:** `$PY $GEMINI -p "$(cat skill1.md skill2.md skill3.md)\n\n---\n\nCROSS-CHECK these files for consistency...\" -m pro --thinking extended -o /tmp/crosscheck.md`. The downside is that prompt text cannot contain binary data (images, PDFs) — for those, `-f` remains the only option but keep each file under ~30KB.

## Token Efficiency

This workflow is **token-expensive** — each image requires 3 tool calls (generate, parse, download) plus 1 embed call. For a deck needing 4 images, that's 16 tool calls (~8K input tokens each turn × 16 ≈ 128K tokens). Specific patterns that save tokens:

1. **Batch generates in parallel** — `terminal(background=true, notify_on_complete=true)` for each image. All complete in parallel (~30s) vs sequentially (~120s). Token cost is identical but wall-clock time drops 4×.

2. **Single-pass embed** — Use one `execute_code` block to embed all images at once. Multiple separate `patch()` calls each cost a full context round-trip (~8K tokens). One `execute_code` pass embeds all N images in one turn.

3. **Skip the wrapper** — `gemini-gen-image.sh` fails ~60% of the time. A failed wrapper attempt wastes: 1 terminal call + 1 read_file to check output + 1 retry = ~24K tokens per failure. Direct `gemini.py --json` succeeded 4/4 in MDR-TB session (0% failure rate).

4. **Pre-flight ping is mandatory** — A wasted generation prompt on expired auth costs tokens with zero output. `gemini-ping.sh --quiet` costs ~1K tokens. A failed generation costs ~8K tokens. Always ping first.

5. **Image size is fixed** — Gemini Imagen outputs are always 512×279 PNG (~30-45KB). Don't ask for larger sizes — it's a hard constraint of the free tier. Accept the size and use `max-width:90%` CSS to scale in-browser.

6. **Cookie extraction is fragile** — `gemini-auth.py` uses a hardcoded Firefox profile path that goes stale across sessions. When it fails (Python traceback + 1 tool call), manually set `GEMINI_SID`/`GEMINI_TS` env vars instead. In the WSL environment, Chrome cookies (`browser_cookie3.chrome()`) are more reliable than Firefox.

## Suggested Native Tool Integration

A single `gemini_generate_image(prompt, output_path)` core tool would collapse the 3-step pipeline into 1 call, saving ~16K tokens per image (parse + download calls eliminated). The tool would:
1. Accept a text prompt + output filename
2. Handle auth internally (env vars or browser cookies)
3. Generate via Imagen, download with cookie auth, verify `file` output
4. Return `{"ok": true, "path": "/home/peter/diagram.png", "size_bytes": 32000}`

This would turn 4 tool calls per image into 1 — a 4× token efficiency gain for the most common image generation pattern in slide deck workflows.
