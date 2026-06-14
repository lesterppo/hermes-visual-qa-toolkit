---
name: screenshot-to-gemini
description: "Take browser screenshots of HTML slide decks via headless Playwright, then send to Gemini for visual QA review. Verifies rendering, catches blank slides, checks layout, validates diagrams. Pipeline: screenshot, Gemini analysis, fix, re-screenshot."
triggers:
  keywords:
    - screenshot
    - visual review
    - browser screenshot
    - slide deck review
    - rendering defect
    - blank slide
    - visual QA
  context:
    - User wants to verify HTML rendering in a real browser
    - User reports blank slides or visual defects
    - User wants Gemini to review slide deck appearance
---

# Screenshot-to-Gemini

## Scripts

| Script | Purpose |
|--------|---------|
| `screenshots.js` | Capture PNGs with per-slide diagnostics + `--diff` pixel comparison + `--agent` compact output. Self-tests chromium on startup with clear install instructions if missing. |
| `gemini-batch-review.sh` | Chunked Gemini review (batches of 3) with conversation continuation + automatic hallucination guard (cross-verifies QA responses against "describe what you see"). |

## Agent Quick Path (token-efficient)

```
TRIGGER: user wants visual verification of an HTML slide deck

// Step 1 — ALWAYS run this first (0 LLM tokens, 3-15 seconds)
1. node scripts/screenshots.js --path deck.html --slides 1,15,30,N --output /tmp/qa/ --agent
   → {"ok":true,"total":52,"captured":4,"blanks":[],"diffs":[]}
   → If "ok":true and "blanks":[] → DECK IS VERIFIED. Skip to structural fixes if any.
   → If "blanks":[37,38] → those slides have opacity/zero-size issues. Check div balance.

// Step 2 — structural check if blanks found (0 LLM tokens)
2. slide-doctor.py deck.html → check div balance, tag-type balance on blank slides
   Fix issues with patch(), re-run screenshots.js --agent

// Step 3 — Gemini visual QA ONLY if needed (~18K tokens per call, use sparingly)
3. IF user reports visual defects that --agent doesn't catch (layout, color, overlap)
   OR IF images were added and need visual verification
   THEN: gemini-gemini.sh -i /tmp/qa/slide_*.png -m pro "QA review" -o /tmp/visual-qa.md
   Do NOT run this speculatively when --agent says {"ok":true}
```

**Token cost by verification method:**
| Method | Tokens | Time | Catches |
|--------|--------|------|---------|
| `screenshots.js --agent` | 0 | 3s | Blanks, zero-size, opacity cascade |
| `slide-doctor.py` | 0 | <1s | Div balance, tag-type, orphans, integrity |
| Gemini visual QA (6 imgs) | ~18K | 60-90s | Layout, color, typography, overflow |
| Gemini cross-verify | ~18K | 60-90s | Hallucination check — skip by default |

**Escalation rule:** If `screenshots.js --agent` returns `{"ok":true}` AND `slide-doctor.py` is all clean, the deck is structurally verified. Gemini visual QA adds ~18K tokens — reserve for user-requested reviews or post-image-embedding verification.

## Prerequisites

Take browser screenshots of HTML pages and send them to Gemini for visual analysis. Uses Playwright (headless Chromium) for rendering and the gemini.py CLI for review.

## Prerequisites

- Node.js + npm (for Playwright)
- Playwright with Chromium installed (one-time setup)
- Gemini browser-cookie auth (see gemini-cli skill)

## One-Time Setup

```bash
# Install Playwright + Chromium (~377MB, cached)
cd /tmp && npm install playwright
npx playwright install chromium
# Binary cached at ~/.cache/ms-playwright/chromium-*/
```

After setup, `node screenshots.js` runs in under 15 seconds.

## Screenshot Script (CLI args)

```bash
node scripts/screenshots.js \
  --path ~/deck.html \           # required: HTML file (absolute or relative)
  --slides 1-5,35-40,66 \       # optional: slide numbers/ranges (default: all)
  --output /tmp/screenshots/ \   # optional: output dir (default: /tmp)
  --diff \                       # optional: compare against baseline
  --baseline /tmp/baseline/      # required with --diff: baseline directory
```

Outputs per-slide diagnostics: title, opacity, dimensions, and status (ok/BLANK/ZERO-SIZE).
Writes `screenshots.json` with structured results for downstream tooling.

### --diff mode (regression detection)

```bash
# First run: save baseline
node scripts/screenshots.js --path deck.html --slides all --output /tmp/baseline/

# After changes: compare against baseline
node scripts/screenshots.js --path deck.html --slides all --output /tmp/current/ \
  --diff --baseline /tmp/baseline/
```

Reports per-slide file size changes. Slides with >1KB difference flagged as CHANGED.
For pixel-level diffing, upgrade to Playwright's `expect(page).toHaveScreenshot()`.

## Screenshot Script (basic)

Save as `screenshots.js` (see `scripts/screenshots.js` in this skill):

```javascript
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  
  await page.goto('file:///ABSOLUTE/PATH/TO/deck.html', { 
    waitUntil: 'networkidle', timeout: 15000 
  });
  
  const totalSlides = await page.evaluate(() => document.querySelectorAll('.slide').length);
  console.log(`Total slides: ${totalSlides}`);
  
  // Customize which slides to screenshot
  const targets = [1,2,3,4,5];  // slide numbers (1-indexed)
  
  for (const n of targets) {
    const idx = n - 1;
    await page.evaluate((i) => {
      document.querySelectorAll('.slide').forEach(s => s.classList.remove('active'));
      const slide = document.querySelectorAll('.slide')[i];
      if (slide) { slide.classList.add('active'); slide.scrollTop = 0; }
    }, idx);
    await page.waitForTimeout(400);
    
    const info = await page.evaluate((i) => {
      const s = document.querySelectorAll('.slide')[i];
      if (!s) return 'MISSING';
      const style = window.getComputedStyle(s);
      const h2 = s.querySelector('h2');
      const title = h2 ? h2.textContent.substring(0, 60) : '(no h2)';
      return `${title} | opacity:${style.opacity} | ${s.offsetWidth}x${s.offsetHeight}`;
    }, idx);
    
    await page.screenshot({ path: `/tmp/slide_${String(n).padStart(2,'0')}.png` });
    console.log(`Slide ${n}: ${info}`);
  }
  
  await browser.close();
})().catch(e => console.error('ERROR:', e.message));
```

## Workflow

### Step 1: Screenshot with --agent (zero tokens, always first)

```bash
node scripts/screenshots.js --path deck.html --slides 1,15,30,52 --output /tmp/qa/ --agent
# → {"ok":true,"total":52,"captured":4,"blanks":[],"diffs":[]}
```

If output is clean (`"ok":true`, `"blanks":[]`), the deck renders correctly. **Stop here.** Only continue if blanks found or user requests visual review.

### Step 2: Gemini visual QA (escalation only, ~18K tokens)

```bash
GEMINI=~/.hermes/scripts/gemini/gemini-gemini.sh
$GEMINI \
  -i /tmp/slide_01.png -i /tmp/slide_37.png -i /tmp/slide_38.png \
  -m pro --thinking extended \
  "You are a QA reviewer. Review each slide for visibility, layout, images, typography, color." \
  -o /tmp/gemini-review.md
```

### Step 3: Cross-verify with direct image analysis

Gemini's QA mode sometimes hallucinates code-level issues from context. Always verify:

```bash
$GEMINI \
  -i /tmp/slide_38.png -i /tmp/slide_50.png \
  -m pro \
  "Describe ONLY what you actually SEE in these images. Be specific." \
  -o /tmp/gemini-visual-check.md
```

### Step 4: Fix and re-screenshot

Apply fixes to the HTML, then re-run the screenshot script.

## Diagnostic Patterns

**Detecting blank slides** -- opacity 0 or dimensions 0x0:
```
Slide 37: ARIA Management | opacity:0 | 0x0  <- BLANK!
```

**Detecting opacity cascade** -- slides after position N all near opacity 0:
```
Slide 36: normal | opacity:0.987
Slide 37: blank  | opacity:0.001  <- parent opacity leaked
```

**Detecting overflow** -- slide width exceeds viewport (1280):
```
Slide 12: ... | 1450x720  <- horizontal overflow
```

## Pitfalls

1. **RTK filtering** -- RTK plugin filters Playwright output. Use `RTK_MODE=off` for raw logs.
2. **Terminal security** -- Write script to file first, then `node /tmp/screenshots.js`.
3. **Absolute paths** -- Use `file://~/deck.html`. Relative paths fail headless.
4. **Chromium install timeout** -- First install: `timeout=300`. Subsequent: instant.
5. **Gemini hallucination** -- QA mode may describe SVG fixes for images that don't exist. Cross-verify.
6. **Nav counter stuck at "1 / N" is a false positive.** The screenshots.js script activates slides by directly toggling the CSS `active` class — it does NOT call the deck's `showSlide()` JavaScript function. The nav counter only updates when `showSlide()` runs (triggered by keyboard or button clicks in a real browser). In static screenshots, the counter always shows "1 / N". Gemini visual QA will flag this as a "broken counter" — ignore it. Verify navigation works by checking that per-slide `data-slide` attributes are sequential and the JS `showSlide()` function exists in the source.
7. **Navigation counter frozen in screenshots (visual artifact, NOT a real bug).** The `screenshots.js` script activates slides by directly toggling CSS classes (`.classList.add('active')`) rather than calling the deck's `showSlide(n)` function. Because the JS variable `current` is never updated, the nav counter `<span id="counter">` shows "1 / N" for every slide. The hardcoded `<p class="slide-num">` in the bottom-right corner updates correctly. **Do not report this as a rendering defect — it is a screenshot artifact.** In real browser use, arrow keys and prev/next buttons call `showSlide()` which updates the counter correctly. Verify by opening the HTML file directly in a browser and clicking through slides.
