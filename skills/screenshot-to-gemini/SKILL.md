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

# Screenshot-to-Gemini Workflow

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

## Screenshot Script

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

### Step 1: Screenshot the deck

```bash
cd /tmp && node screenshots.js
# Output: /tmp/slide_01.png, /tmp/slide_02.png, ...
# Logs: total slides, per-slide title + opacity + dimensions
```

### Step 2: Send to Gemini for visual review

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
6. **WSL headless only** -- `--no-sandbox` required. No display server available.
