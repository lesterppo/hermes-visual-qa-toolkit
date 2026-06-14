---
name: clinical-slide-deck
description: Build evidence-based clinical slide decks from PubMed-verified data using a proven multi-tool pipeline of paper discovery, structured PICO extraction, GRADE rating, forest-plot generation, and dual HTML+PPTX output. Every statistic is backed by a PMID. Use for grand rounds, CME lectures, journal club presentations, and guideline summaries.
triggers:
  keywords:
    - clinical slide deck
    - grand rounds
    - medical presentation
    - evidence table
    - CME lecture
    - journal club
    - clinical evidence summary
    - guideline presentation
    - forest plot
    - GRADE rating
    - PICO extraction
    - slide deck
    - medical postgraduate
    - geriatrics presentation
    - medical visualization
    - clinical diagram
    - medical SVG
    - gemini image
    - generated diagram
    - medical diagram
    - Imagen
    - slide deck image
  context:
    - User asks to build a clinical or medical slide deck
    - User wants an evidence-based presentation with citations
    - User asks for a lecture or talk on a medical topic
    - User wants to compare clinical trial outcomes visually
    - User mentions forest plots or evidence grading
    - User asks for geriatrics/medical postgraduate meeting presentation
    - User wants diagrams or visualizations embedded in clinical slides
    - User asks to generate or add images/diagrams to a slide deck
---

# Clinical Slide Deck Builder

## Agent Quick Path

```
TRIGGER: user asks for medical slide deck
1. If well-covered topic: web_search (5-6 queries) → Gemini pre-build synthesis (single pro prompt)
   If niche topic: med-search-cli → PubMed (full pipeline, Phases 1-2d)
2. Build HTML: frontend-design dark theme (#0f1623, #c9a84c, Crimson Text + DM Sans)
3. slide-doctor.py deck.html → 7 checks → fix issues → re-run
4. screenshots.js --path deck.html → key slides → verify opacity/dimensions
5. gemini-gemini.sh -i slide_*.png → visual QA → fix → re-screenshot
6. gemini-gemini.sh -f deck.html → content accuracy review → apply fixes
7. If deck has abstract/mechanistic concepts: gemini-ping.sh → image audit (full deck) →
   batch generate with gemini-gen-image.sh (background parallel) → embed after h2 →
   slide-doctor.py + re-screenshot → Gemini visual QA on image slides
```

## Dependencies (auto-load chain)

This skill builds on:
- `med-search-cli` — paper discovery and full-text retrieval
- `frontend-design` — HTML slide deck aesthetics
- Supporting tools (all at `~/.hermes/scripts/`):
  - `med-extract.py` — structured PICO outcome extraction
  - `forest-plot.py` — SVG forest plots with OR/CI whiskers
  - `grade-evidence.py` — GRADE certainty rating per outcome
  - `slide-export.py` — dual HTML+PPTX output

Proven workflow for building citation-backed clinical slide decks.

## Decision Point: Full Pipeline vs Light Path

**Choose the FULL pipeline (Phases 1–2d) when:**
- The topic is a niche clinical question (e.g., "haemostatic powder for UGIB")
- You need to discover papers you don't already know about
- The user wants GRADE ratings, forest plots, or a .pptx export
- You need a systematic, exhaustive literature search

**Choose the LIGHT path when:**
- The topic is a well-known landmark trial or guideline update (e.g., "lecanemab CLARITY AD", "2023 Beers Criteria", "SPRINT trial")
- Key outcome data is publicly available via press releases, news articles, and review sites
- The user only asked for an HTML slide deck (no PPTX, no forest plots)
- Speed matters — the full pipeline takes 20+ tool calls; the light path takes 3–5

**Light path workflow (skip Phases 1–2d):**
**Light path workflow (skip Phases 1–2d):**
1. Use `web_search` (5–6 targeted queries) to gather key trial data: N, primary endpoint, effect sizes, p-values, safety rates, PMIDs across all topic domains
2. **Gemini pre-build synthesis:** Send a single structured prompt to Gemini (`-m pro --thinking extended -o /tmp/synthesis.md`) asking it to synthesize ALL search results into a structured evidence document covering epidemiology, pathophysiology, diagnosis, oral therapy, IV therapy, landmark trials, and all relevant special populations. Include specific trial names, numbers, and PMIDs. This consolidates scattered search results into one reference document before deck construction begins. See `references/gemini-pre-build-prompt.md` for the prompt template. **Note:** Use `gemini.py` directly with `-p "$(cat prompt.md)"` to avoid wrapper auth issues when GEMINI_TS is null (some accounts lack a TS cookie).
3. If needed, use `web_extract` on a comprehensive review article for supplementary data
4. Read the Gemini synthesis and use it as the primary reference while building the HTML deck
5. Pull PMIDs from the synthesis document and cite them on the reference slide
6. Skip forest plots, GRADE ratings, and PPTX export unless explicitly asked

The light path still produces PMID-backed, evidence-based decks. It trades exhaustive PubMed discovery for speed on well-covered topics. The full pipeline remains the gold standard for systematic evidence synthesis.

## Phase 1: Paper Discovery (med-search-cli)

Run 3 targeted searches for comprehensive coverage:

```bash
PY=/home/peter/.hermes/hermes-agent/.venv/bin/python3
MS=/home/peter/.hermes/scripts/med_search_cli_v2.py

# 1. Core RCTs and meta-analyses (the efficacy data)
$PY $MS search -q "TOPIC KEYWORDS" -m 8 -U "RCT,Meta-Analysis,Systematic Review" -f 2019-01-01 -S citations

# 2. Guideline and review search (the recommendations)
$PY $MS search -q "TOPIC guideline management" -m 5 -U "Practice Guideline,Systematic Review,Review" -S date

# 3. Subtype-specific search (e.g. malignancy, post-resection)
$PY $MS search -q "TOPIC SUBTYPE" -m 6 -U "RCT,Meta-Analysis" -f 2019-01-01 -S citations
```

**Selection criteria:**
- Keep RCTs from the last 5 years in reputable journals
- Keep meta-analyses that pool the RCTs you found
- Keep the most recent practice guideline
- Target 8-12 papers for a comprehensive 14-slide deck

## Phase 2: Data Extraction

**Option A: Manual extraction from abstracts (always works)**
Fetch papers individually with 1.5s delay to avoid NCBI rate limits. Use execute_code for the multi-call loop. Then extract key sentences with regex looking for percentages, p-values, OR, CI, and RR.

**Option B: gemini-cli synthesis (if authenticated)**

In WSL, use the auto-auth wrapper:
```bash
GEMINI_WRAPPER=/home/peter/.hermes/scripts/gemini/gemini-gemini.sh
$GEMINI_WRAPPER -f paper1.txt -f paper2.txt -f paper3.txt \
  "Extract precise outcome data: N, percentages, p-values, OR, CI. Output as JSON." \
  -o evidence.json
```

Gemini auth in WSL requires the direct-cookie-extraction wrapper because browser-cookie3 cannot find Windows Firefox profiles from WSL. See gemini-cli skill references/wsl-auth.md for details.

**Critical:** Every number on every slide must trace to a specific PMID.

## Phase 2b: Automated PICO Extraction

Instead of manual regex, use the structured extractor:

```bash
PY=/home/peter/.hermes/hermes-agent/.venv/bin/python3
$PY /home/peter/.hermes/scripts/med-extract.py /tmp/papers.json
```

This returns structured JSON with:
- Haemostasis rates (comparison: TC-325 vs control with p-values)
- Rebleeding rates (by time window: day_7, day_14, day_30)
- Effect sizes (OR/RR/HR with 95% CI and p-values)
- Adverse event data (presence/absence, rates)
- Sample size per study

## Phase 2c: GRADE Evidence Rating

Rate each paper's evidence certainty:

```bash
$PY /home/peter/.hermes/scripts/grade-evidence.py /tmp/papers.json
```

Returns GRADE certainty (High/Moderate/Low/Very Low) with per-domain scores for risk of bias, inconsistency, imprecision, and publication bias.

## Phase 2d: Forest Plot Generation

Generate publication-quality forest plots for evidence slides:

```bash
$PY /home/peter/.hermes/scripts/forest-plot.py /tmp/effect_sizes.json \
  --title "30-Day Rebleeding: TC-325 vs Standard Therapy" \
  -o forest_rebleeding.svg
```

The SVG is dark-themed and can be embedded directly in the HTML slide deck via `<img src="forest_rebleeding.svg">`. For .pptx export, convert to PNG first:
```bash
rsvg-convert forest_rebleeding.svg -o forest_rebleeding.png
```

## Phase 2e: Visualization Generation (Inline SVGs + Open-Access Images)

For slide decks that need diagrams, pathway illustrations, mechanism-of-action schematics, or clinical workflow visualizations, create **inline SVG diagrams** that match the deck's dark theme. Use separate SVG files (via `write_file`) then embed them. This avoids external image link rot and copyright issues.

**SVG diagram types proven useful:**
1. **Pathway/cascade diagrams** — APP → Aβ → oligomers → plaques → tau → neurodegeneration
2. **Mechanism-of-action comparisons** — side-by-side antibody diagrams showing binding targets
3. **Pathophysiology schematics** — normal vessel → CAA vessel → antibody → ARIA-E/ARIA-H
4. **Clinical workflow timelines** — pre-screening → biomarker → safety → decision → monitoring → stop
5. **Trial results bar charts** — % slowing of decline across multiple endpoints with trial labels
6. **Brain/regional anatomy diagrams** — brain regions affected, Braak staging, biomarker trajectories

**SVG design rules (must match deck theme):**
- ViewBox: 960×540 (16:9 ratio)
- Background: `#0f1623` (match deck `--bg-slide`)
- Card fills: `#1a2540`, borders: `rgba(201,168,76,0.15)`
- Title font: Crimson Text, gold (`#c9a84c`); body: DM Sans
- Color coding: blue=`#4a90d9` (lecanemab), teal=`#2dd4bf` (donanemab), red=`#ef4444` (risk), green=`#22c55e` (safe), amber=`#f59e0b` (caution)
- Use gradients, rounded rects (rx=6–10), soft shadows, and dashed borders for visual polish
- Include source attribution text at bottom (e.g., "Adapted from Hardy & Higgins 1992")

**Open-access medical image sources (no copyright issues):**
- **Neurotorium:** CC BY 4.0. AD brain diagrams with plaques/tangles. `https://neurotorium.org/image/alzheimers-disease-brain-with-amyloid-plaque-and-neurofibillary-tangles/`
- **Wikimedia Commons:** Public domain. Brain cross-sections, PET scans. `https://upload.wikimedia.org/wikipedia/commons/2/25/Cerebro_corte_frontal_Alzheimer.jpg`
- Always include proper attribution: source name, license type, adapted-from reference
- NEVER hotlink images you don't have rights to verify — use only CC0, CC BY, or public domain

### Gemini-Generated Raster Images (SVG Replacement Fallback)

When inline SVGs have persistent rendering issues (misplaced arrows, broken marker defs, complex
layout bugs), replace them with raster PNG images generated by Gemini's Imagen (see gemini-cli
skill for the image generation workflow):

1. Generate: `gemini.py --json "Generate a professional dark-themed medical diagram..." -o result.json`
2. Download with cookies: `curl -sL -b "cookies" -o slideXX-diagram.png "<url from result.json>"`
3. Replace SVG: swap the entire `<svg>...</svg>` block for `<img src="slideXX-diagram.png" style="max-width:100%;height:auto;border-radius:8px">`
4. Remove orphaned SVG internals: when using `patch()` to replace `<svg` opening tag, also delete
   all orphaned SVG elements (defs, rects, text, paths) that remain after the slide's closing `</div>`

**Pitfall:** After replacing the SVG opening tag with `<img>`, the slide div may close prematurely
while the SVG content continues. Use `execute_code` to find the `</svg>` boundary and clean up all
orphaned elements. Verify div balance (375/375, 0 delta) after cleanup.

**Template SVG files** are saved in the skill's `references/` directory:
- `references/svg-pathway-template.svg` — pathway/cascade diagram template with bracketed placeholders
- `references/svg-mechanism-comparison-template.svg` — side-by-side two-drug MoA comparison template

To reuse: read the SVG via `skill_view`, search-replace the `[BRACKETED]` labels with topic-specific text, embed in HTML with `width="100%" height="auto"`.

## Phase 2f: Programmatic Slide Insertion & Renumbering

When inserting new slides into an existing deck, you MUST renumber all `data-slide="N"` attributes to keep them sequential. The nav dots and slide counter depend on this.

### ⚠ CRITICAL: NEVER use non-greedy regex to find slide boundaries

This pattern **will break your HTML**:
```python
# BROKEN — DO NOT USE
pattern = r'(<div class="slide[^"]*" data-slide="N"[^>]*>.*?</div>\s*</div>)'
```

The `.*?` (non-greedy) stops at the FIRST `</div>` inside the slide's content — not the slide's actual closing tag. This splits slides into orphaned fragments. The extra `</div>` tags cause browsers to close parent containers prematurely, making **all subsequent slides invisible**. This is what happened with the lecanemab/donanemab deck: slides after "Baseline MRI" were blank because an orphaned `</div>` from a broken insertion closed the slides container.

### Correct approach: Extract, fix, and rebuild at SLIDE + SECTION DIVIDER markers

When the deck uses BOTH `<!-- SLIDE N: Title -->` and `<!-- SECTION DIVIDER -->` markers, the split regex must match both. Missing the section dividers causes them to be absorbed into adjacent slide content, breaking structure.

```python
import re

# Step 0: Find header (everything up to and including <div id="slides">)
header_end = html.find('<div id="slides">') + len('<div id="slides">') + 1
header = html[:header_end]

# Find footer (nav + script)
nav_start = html.find('\n<div id="nav">')
footer = html[nav_start:]

# Body is header_end → nav_start
body = html[header_end:nav_start]

# Step 1: Split the body at BOTH SLIDE and SECTION DIVIDER markers
# MUST include both patterns or section dividers get absorbed
pattern = r'(<!-- SLIDE \d+:.*?-->|<!-- SECTION DIVIDER -->)'
parts = re.split(pattern, body)
# parts alternates: [leading_whitespace, marker0, content0, marker1, content1, ...]

# Step 2: Build marker-content pairs
blocks = []
for i in range(1, len(parts), 2):
    marker = parts[i]
    content = parts[i+1] if i+1 < len(parts) else ''
    
    # Fix div balance per block
    opens = len(re.findall(r'<div\b', content))
    closes = len(re.findall(r'</div>', content))
    if opens > closes:
        content = content.rstrip() + '\n' + ('</div>\n' * (opens - closes))
    elif closes > opens:
        for _ in range(closes - opens):
            idx = content.rfind('</div>')
            if idx > 0:
                j = idx - 1
                while j >= 0 and content[j] in ' \t\n\r':
                    j -= 1
                content = content[:j+1]
    blocks.append((marker, content))

# Step 3: Insert new blocks at desired positions (block indices)
# New blocks are created as <!-- SLIDE ### --> markers with content
for pos, new_block_content in insertions:
    blocks.insert(pos + 1, ("<!-- SLIDE ### -->", new_block_content))

# Step 4: Rebuild with sequential data-slide numbering
# First pass: assign sequential numbers in marker-content output
counter = 0
output_parts = []
for marker, content in blocks:
    counter += 1
    content_renumbered = re.sub(
        r'data-slide="\d+"', 
        f'data-slide="{counter}"', 
        content, count=1
    )
    output_parts.append(marker)
    output_parts.append('\n')
    output_parts.append(content_renumbered)

body_rebuilt = ''.join(output_parts)

# Step 5: Post-rebuild data-slide cleanup
# New blocks have data-slide="###" which the first pass misses.
# Second pass: sequential find-and-replace on ALL data-slide attributes
matches = list(re.finditer(r'data-slide="([^"]*)"', full_html))
counter = 0
offset = 0
for m in matches:
    counter += 1
    start = m.start() + offset
    end = m.end() + offset
    new_val = f'data-slide="{counter}"'
    full_html = full_html[:start] + new_val + full_html[end:]
    offset += len(new_val) - len(m.group(0))

# Step 6: Update nav counter
full_html = re.sub(
    r'<span id="counter">.*?</span>', 
    f'<span id="counter">1 / {counter}</span>', 
    full_html
)

# Step 7: Assemble final HTML
full_html = header + body_rebuilt + footer
```

**Why the two-pass data-slide renumbering is needed:** The first pass replaces `data-slide="DIGITS"` in original blocks. New blocks have `data-slide="###"` which doesn't match `\d+`. The post-rebuild sequential find-and-replace catches ALL remaining attributes regardless of original format.

**Why splitting at markers works:** By splitting at `<!-- SLIDE` and `<!-- SECTION DIVIDER` comment markers (not regex div matching), each block is a discrete slide regardless of internal structure. Rebalancing divs per-block fixes any drift from broken insertions.

### ⚠ CRITICAL: patch() must NOT include surrounding `<!-- SLIDE` markers in old_string

When using `patch()` to delete orphaned content between slides, the `old_string` must start and end at the *exact orphaned content boundaries* — never include the preceding slide's closing `</div>` or the following `<!-- SLIDE` marker. If your old_string spans from inside a legitimate slide through orphaned content to the next marker, you will **delete the legitimate slide**.

```python
# BROKEN — deletes slide 12 alongside orphaned content:
old_string = """</svg>
    </div>
  </div>
</div>

      <div class="flex-1">  <!-- orphaned -->
        <div class="card card-accent">...</div>
      </div>

<!-- SECTION DIVIDER -->  <!-- ← DO NOT include this marker -->

# CORRECT — targets only the orphaned block:
old_string = """</div>

      <div class="flex-1">  <!-- orphaned starts here -->
        <div class="card card-accent">...</div>
      </div>

"""  # ← ends cleanly, next marker NOT included
```

**Always verify the patch diff** before continuing — if the diff shows lines being removed that contain `<!-- SLIDE` or `<div class="slide"`, you've hit this trap. Undo and narrow the old_string.

### CSS layout rules for slides with large content (SVGs, images, tables)

```css
/* Default slide: flex-start, not center */
.slide {
  justify-content: flex-start;  /* NOT center — prevents overflow from hiding content */
  overflow-y: auto;
}

/* Only title slides and section dividers get centering */
.title-slide, .section-divider {
  justify-content: center !important;
}
```

When `justify-content: center` is used on a slide whose content exceeds the viewport height, the browser centers the content vertically — pushing the top portion ABOVE the visible area. With `overflow-y: auto`, the user sees a blank slide. **Always use flex-start for content slides.**

### SVG embedding checklist

Every inline SVG in the deck MUST have:
```html
<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="auto" viewBox="0 0 960 540" ...>
```
- `width="100%"` — prevents SVG from rendering at an unbounded natural size that overflows
- `height="auto"` — maintains aspect ratio from viewBox
- Wrap in: `<div style="max-width:100%;overflow:hidden">`

### SVG arrowhead pitfalls

Two common SVG arrow bugs discovered and fixed in the anti-amyloid deck:

**Bug 1: `<defs>` marker defined AFTER elements that reference it**
SVG requires `<marker>` and other `<defs>` to be defined BEFORE they are referenced by `url(#id)`. If the `<defs><marker id="arrowhead">...</marker></defs>` block appears at the END of the SVG (after `<line marker-end="url(#arrowhead)">` elements), browsers cannot resolve the reference during initial render — arrows appear as plain lines without arrowheads.

**Fix:** Always place all `<marker>` definitions inside the `<defs>` block at the TOP of the SVG, before any elements that use them.

**Bug 2: Flow arrows missing `marker-end` attribute**
Plain `<path>` or `<line>` elements do NOT get arrowheads automatically. Every directional flow arrow needs:
```xml
<line ... marker-end="url(#arrowhead)"/>
<path ... marker-end="url(#arrowhead)"/>
```

**Bug 3: Missing horizontal progression arrows between columns**
When a diagram shows a process flowing through columns (e.g., Normal Vessel → CAA-Affected Vessel → Antibody Binding), add short horizontal arrows between column edges to show the direction of progression:
```xml
<!-- From Normal vessel right edge (~x=300) to CAA vessel left edge (~x=350) -->
<line x1="305" y1="175" x2="345" y2="175" stroke="#c9a84c" stroke-width="2" marker-end="url(#arrowhead)"/>
```

**Verification:** Grep the SVG for `marker-end` — every directional arrow path should have one. Grep for `marker id=` — the definition must appear BEFORE the first usage in SVG source order.

### Gemini Image Audit — Identifying Which Slides Need Generated Images

After the deck is structurally complete, use Gemini to audit which slides would benefit from generated raster images (Imagen) replacing text-heavy explanations:

```bash
$WRAPPER -f /path/to/deck.html \
  "You are reviewing a 60-slide clinical deck on [topic]. Audit the entire deck and identify specific slides that NEED generated images or diagrams to help learners understand complex concepts.

For each slide that needs an image, specify:
1. The slide title/number and concept
2. What the image should show (detailed description)
3. Why text alone is insufficient

Focus on concepts that are: mechanistic (pathways), spatial (anatomical), comparative (side-by-side), or algorithmic (decision trees).

Return a ranked list. Be specific about what to generate." \
  -m pro --thinking extended -o /tmp/gemini-image-audit.md
```

Then generate images for the top-ranked slides using the gemini-image-generation skill (`gemini-gen-image.sh`). Embed by inserting `<img>` after the target slide's `<h2>` heading — using `execute_code` with `html.find('<h2>')` to locate the insertion point. Always verify div balance after every insertion.

**Token-efficient batching:** Generate all images in parallel with background processes. Use the gemini-gen-image.sh wrapper (handles auth extraction, generation, download, and verification in one call). Always run `gemini-ping.sh --quiet` before any generation batch — cookies expire across sessions and wasted prompts on expired auth are pure token waste.

**Typical audit yield:** 3–5 slides flagged for image generation per 60-slide deck. Common candidates: pathway diagrams, staging/progression timelines, anatomical distributions, and diagnostic algorithms. The iron deficiency deck audit produced 31 candidates across 60 slides; 7 were implemented (all HIGH-priority GENERATED types).

When asking Gemini to fix or regenerate an SVG, it frequently **truncates the output** — cutting off content mid-SVG and omitting the closing `</svg>` tag. To prevent this:

1. Always include "Return the COMPLETE SVG from `<svg>` to `</svg>`. Do NOT truncate. Include every element verbatim."
2. Even with this instruction, verify the output: the last line must be `</svg>` and all original content (boxes, labels, text) must be present
3. If truncated, tell Gemini "Your SVG was incomplete — it cut off after [last visible element]. Return the FULL SVG." and try again
4. For simple fixes (moving a marker, adding an attribute), doing the patch manually is more reliable than Gemini regeneration

```html
<!-- DO: graceful text fallback -->
<img src="..." onerror="this.outerHTML='<p class=small>[Image unavailable — see caption]</p>'">

<!-- DON'T: display:none makes the entire image area vanish silently -->
<img src="..." onerror="this.style.display='none'">
```

## Phase 2f.5: Structural Integrity Check (slide-doctor.py)

Before declaring a deck ready, run the automated integrity checker:

```bash
PY=~/.hermes/hermes-agent/.venv/bin/python3
$PY scripts/slide-doctor.py deck.html
# Exit 0 = clean, 1 = issues found
# --json for machine-readable output
```

slide-doctor.py performs 6 checks:
1. Overall div balance (<div> vs </div>)
2. Tag-type balance (table, ul, ol — catches </ul>-instead-of-</table> cascading invisibility)
3. Sequential data-slide numbering
4. Per-slide div balance
5. Orphaned content between slides
6. SVG marker defs placement

**Known false positive:** The per-slide check on the last slide typically reports 4 opens, 5 closes (or opens+1 = closes). This is a boundary artifact — the closing `</div>` for `<div id="slides">` falls within the last slide's section range because there's no next `<!-- SLIDE` marker. If the overall div balance is 0 delta and all other checks pass, this per-slide imbalance is harmless. Do NOT add extra `<div>` tags to the last slide to "fix" it — that would break the overall balance.

Run after every structural edit. The check takes <0.5s on a 66-slide deck.

## Phase 2g: Screenshot Verification (Browser Rendering QA)

After structural fixes, capture browser screenshots to verify real rendering — div balances and tag counts can mask DOM nesting bugs:

```bash
# One-time setup: install playwright chromium (cached persistently)
cd /tmp && npm install playwright && npx playwright install chromium

# Run the screenshot script (captures key slides with visibility diagnostics)
# Script lives in the screenshot-to-gemini skill
node ~/.hermes/skills/devops/screenshot-to-gemini/scripts/screenshots.js \
  --path deck.html --slides 1-5,35-40,66 --output /tmp/qa/
```

The script outputs per-slide visibility info (opacity, dimensions, title) and saves PNGs to `/tmp/slide_NN.png`. 

**Send screenshots to Gemini for visual QA:**
```bash
$WRAPPER -i /tmp/slide_35.png -i /tmp/slide_36.png ... \
  "Review these slides for visibility, layout, typography, and theme consistency." \
  -m pro -o /tmp/visual-qa.md
```

**⚠ CRITICAL: Gemini may hallucinate code-level issues from prior conversation context when reviewing screenshots.** If Gemini says "the SVG markers are missing" but the slide now uses an `<img>` tag (raster image), it's hallucinating from earlier chat history. Always follow up with a direct "describe exactly what you see in this image" prompt to verify. Cross-reference both responses — the hallucination-free one is authoritative.

## Phase 2h: Gemini QA Review (Content Accuracy &amp; Design Critique)

After building the slide deck, send it to Gemini for a formal review. This catches data errors (wrong ARIA rates, outdated regulatory status, incorrect trial numbers) that are easy to miss in self-review.

```bash
WRAPPER=/home/peter/.hermes/scripts/gemini/gemini-gemini.sh
$WRAPPER -f /path/to/slide-deck.html \
  "You are a senior academic [specialty] reviewing a slide deck for a postgraduate meeting. Provide a thorough critique covering:

1. CONTENT ACCURACY: Are all clinical trial statistics correct? Verify ARIA rates, CDR-SB numbers, patient selection criteria, drug costs against published literature. Flag any numbers that seem off.

2. CLINICAL BALANCE: Does the deck fairly represent controversies? Is the specialty perspective appropriately weighted?

3. DESIGN & READABILITY: Evaluate theme, fonts, color coding, table layouts, stat boxes, and slide density. Are there slides with too much text?

4. OMISSIONS: What important content is missing that the target audience would expect?

5. STRUCTURE: Does the slide flow make logical sense? Should any slides be reordered, merged, or split?

Be specific and actionable. For each issue, state the slide number and suggest the exact fix." \
  -m pro --thinking extended -o /tmp/gemini-review.md
```

**Known Gemini limitation:** Gemini sometimes only reads the first ~9 slides of a deck and reports "the HTML truncated." If this happens, send the remaining slides in a second pass:

```bash
$WRAPPER -f /path/to/slide-deck.html \
  "You reviewed slides 1-9 earlier due to truncation. Now please review slides 10-N focusing on [remaining topics]..." \
  -m pro --thinking extended -o /tmp/gemini-review-2.md
```

**Common corrections Gemini catches:**
- Outdated regulatory status (e.g., EMA approved donanemab Jul 2025, not rejected Mar 2025)
- Wrong ARIA rates (e.g., lecanemab APOE4 homozygote ARIA-E is ~33%, not ~22%)
- Missing references (FDA prescribing information, MCID primary sources)
- Overly dense text slides that should be bulletized for projection

Apply Gemini's fixes immediately and re-verify div balance afterward.

### Two-Round Gemini QA Pattern (recommended for structural fixes)

When Gemini reports structural issues (missing closing tags, orphaned content, div nesting), use a **two-round review**:

1. **Round 1:** Send the deck for structural review. Apply fixes.
2. **Round 2:** Send the fixed deck back with a `-c` conversation continuation plus your structural verification report (div counts, depth-tracked closings). Ask Gemini to confirm all issues are resolved before declaring the deck "ready."

```bash
# Round 1
$WRAPPER -c /tmp/gemini-review.json --new -f deck.html \
  "Review this HTML slide deck for rendering defects..." \
  -m pro --thinking extended -o /tmp/gemini-r1.md

# Apply fixes...

# Round 2 (continuation)
$WRAPPER -c /tmp/gemini-review.json -f deck.html \
  "SECOND REVIEW: I've applied your fixes. Structural verification shows N/N div balance,
   all slides depth-tracked closed. Confirm all issues are resolved." \
  -m pro --thinking extended -o /tmp/gemini-r2.md
```

**Caveat:** Gemini sometimes reports slides as "missing closing tags" when they are actually properly closed (verified by depth tracking). Trust your own structural verification — if div balance is 0 delta and depth tracking confirms each slide's matching close, the file is correct regardless of what Gemini says about specific slides. Do NOT blindly add closing tags that would unbalance the div count.

## Phase 3: Slide Deck Construction

### Option A: HTML (single-file, frontend-design aesthetic)

Use the frontend-design skill for visual direction. Key design rules for clinical decks:
- Dark medical theme (navy/slate background with gold academic accent)
- Crimson Text for headings, DM Sans for body
- Evidence table slides with HTML tables and PMID citations in every row
- Stat boxes for headline numbers
- CSS comparison bars for TC-325 vs SET comparisons
- Key message boxes (bordered left-accent blocks)
- Inline SVG forest plots in a `.forest-container` div for evidence slides
- Final reference slide with full bibliography including PMIDs and GRADE ratings

### Option B: PPTX (slide-export.py)

Generate a .pptx for clinical settings from a structured JSON spec:

```bash
$PY /home/peter/.hermes/scripts/slide-export.py slides_spec.json \
  --forest-png forest_rebleeding.png \
  -o presentation.pptx
```

The JSON spec uses block types: text, bullets, stat_box, key_message, table, image.
See `slide-export.py` for the full schema.

**Important:** python-pptx does NOT support SVG images. Forest plots must be converted to PNG first:
```bash
rsvg-convert forest_rebleeding.svg -o forest_rebleeding.png
# Or if rsvg-convert is unavailable:
# Use forest-plot.py --light flag and convert with any image tool
```

### Slide Structure Templates

**Compact template (15 slides)** — for time-constrained talks, journal clubs:
1. Title
2. Clinical background and scope of problem
3. What is the intervention (mechanism of action)
4. Key RCT evidence table
5. Meta-analysis evidence table
6. Forest plot (inline SVG) with interpretation
7. Deep-dive on strongest indication
8. Secondary indication
9. Guideline recommendations
10. Application technique and practical tips
11. Comparative agents and armamentarium
12. Cost-effectiveness, limitations, unanswered questions
13. GRADE Summary of Findings table
14. Full reference list with PMIDs
15. Take-home messages (5 key points)

**Expanded template (50–70 slides)** — for comprehensive postgraduate lectures, grand rounds:
1–2. Title + disclosures/agenda
3. Section divider: Disease Burden & Unmet Need
4–6. Epidemiology, natural history, current standard of care gap
7. Section divider: Biology & Rationale
8–10. Pathway biology, biomarkers (ATN framework), genetic evidence
11. Section divider: Historical Context (if applicable — e.g., aducanumab story)
12–13. Prior therapies, lessons from failed/controversial trials
14. Section divider: Mechanisms of Action
15–16. Molecular pharmacology deep dive, dosing & stop rules
17. Section divider: Pivotal Trial 1
18–21. Full trial design, primary + secondary results, subgroups, long-term extension
22. Section divider: Pivotal Trial 2
23–25. Full trial design, results, tau stratification, subgroup insights
26. Section divider: Head-to-Head Comparison
27–28. Comprehensive comparison table, cross-trial caveats
29. Section divider: Safety Deep Dive (ARIA)
30–33. Pathophysiology, APOE4 risk gradient, baseline MRI, management algorithm
34. Section divider: Risk Mitigation (if applicable — e.g., modified titration)
35. Modified dosing results
36. Section divider: Patient Selection
37–38. Inclusion/exclusion tables, geriatric-specific caveats (frailty, multimorbidity, polypharmacy)
39. Section divider: Clinical Workflow
40–41. Pre-treatment step-by-step, on-treatment monitoring schedule
42. Section divider: Long-Term Outcomes
43. Real-world evidence, unanswered questions
44. Section divider: Controversies
45–47. MCID debate, surrogate endpoints, regulatory divergence, cost-effectiveness
48. Section divider: Pipeline
49. Next-generation therapies, prevention trials
50. Section divider: Case Vignettes
51–53. 3 cases (ideal candidate, complex geriatric, APOE4 homozygote dilemma)
54. Section divider: Take-Home Messages
55–56. Key messages (4–6 points)
57–58. References (1–2 slides)
59. Closing / Thank You

**Between sections, insert visualization slides:**
- After biology: cascade pathway SVG + open-access brain pathology images
- After MoA: mechanism comparison SVG
- After trial results: bar chart comparison SVG
- After ARIA: pathophysiology SVG
- After workflow: clinical timeline SVG
- After long-term: brain regions + Braak staging SVG

## Token Efficiency Patterns Discovered

1. **Batch fetch fails, individual fetch with delay works.** NCBI rate-limits batch fetches. Fetch one at a time with 1.5s delay. Cache makes subsequent fetches instant.
2. **Abstracts contain 80% of the key numbers.** Full-text sections are ideal but abstract-only (fallback source) is sufficient for evidence tables in most cases.
3. **Use execute_code for multi-call orchestration.** 3 searches plus 9 fetches is 12 terminal calls. Batch them in execute_code with sleep delays.
4. **Gemini is optional.** The pipeline works perfectly with manual regex extraction from abstracts. Gemini adds synthesis quality but the core loop (search, fetch, extract, build deck) has no hard dependency on it.
5. **FTS5 cache-search needs query sanitization.** Hyphens in queries must be double-quoted. The med-search-cli script now handles this automatically (patched in this session).
6. **Embed SVGs, don't link them.** External image URLs can break. Inline SVGs never do. For open-access medical images (Neurotorium CC BY 4.0, Wikimedia Commons PD), use `<img>` with a fallback `onerror="this.style.display='none'"` so the slide degrades gracefully if the URL is unreachable.
7. **Light path beats full pipeline for landmark trials.** When covering a well-known topic (lecanemab, donanemab, SPRINT), web_search → extract data → build HTML is faster (3–5 calls) than the full PubMed pipeline (20+ calls). Reserve the full pipeline for niche topics where you truly need systematic discovery.
8. **Slide CSS layout: flex-start, never center for content slides.** `justify-content: center` pushes overflowed content above the visible viewport, creating blank slides. Reserve centering for `.title-slide` and `.section-divider` only (with `!important`). All content slides use `flex-start`.
9. **SVG sizing: width="100%" height="auto" is mandatory.** Without explicit dimensions, inline SVGs render at unbounded natural size, overflowing the slide and triggering the blank-slide bug. Wrap SVGs in `<div style="max-width:100%;overflow:hidden">`.
10. **Rebuild from <!-- SLIDE markers, never regex divs.** The `.*?</div>` non-greedy pattern is the single most destructive bug in this workflow. It matched internal `</div>` tags inside 7 slides and left orphaned HTML that broke every subsequent slide. Always split at `<!-- SLIDE` comment markers instead.
11. **Regex `class="slide([^"]*)"` matches `slide-inner` — false positive.** When counting slide divs with regex, `class="slide([^"]*)"` will match both `<div class="slide">` AND `<div class="slide-inner">`, doubling your count. Use `class="slide(?:\s[^"]*|)"` to require space-or-quote after "slide", excluding -inner variants. This avoids false alarms about "duplicate slide divs."
12. **execute_code read_file unreliable for large files.** The `read_file` tool inside `execute_code` may not return a `content` key for files > ~50KB. For div-balance analysis and rebuild scripts on large decks, use `terminal` with `python3 << 'PYEOF'` or the raw `read_file` tool with offset/limit pagination instead.
13. **Gemini image audit prevents wasted generations.** Running a full-deck audit before generating any images ensures you only generate images for slides that actually need them. The iron deficiency deck audit identified 31 candidates; only 7 HIGH-priority GENERATED types were implemented. Without the audit, images would have been generated ad-hoc for the wrong slides. Audit costs one Gemini pro prompt; wasted generations cost tokens + rate limits + embedding time.
14. **Gemini synthesis: use -p not -f for prompt text.** The -f flag on gemini.py attaches a file as a document, not as prompt text — using it alone produces "Prompt cannot be empty." Pass prompt content from a file with shell substitution: gemini.py -p "$(cat /tmp/prompt.md)" -m pro --thinking extended -o /tmp/synthesis.md. This works even with accounts that have null GEMINI_TS (which crash the gemini-gemini.sh wrapper).

## Pitfall: SVG Arrowhead Markers Must Precede References

SVG `<marker>` elements in `<defs>` must be defined BEFORE any element that references them via `url(#id)`. 
When `<defs>` appears at the bottom of an SVG (after all `<line marker-end="url(#arrowhead)">` elements), 
arrows render without arrowheads because the browser can't resolve forward references.

**Fix:** Always place `<marker>` definitions in the `<defs>` at the TOP of the SVG, before any content elements.

## Pitfall: SVG → Raster Image Replacement

When SVGs have intractable rendering issues, replace them with Gemini-generated raster images:

```bash
# 1. Generate via Gemini Imagen (see gemini-image-generation skill)
$PY $GEMINI --json "Generate a medical diagram showing..." -o /tmp/img.json

# 2. Download with cookie auth
curl -sL -b "__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}" -o diagram.png "<url>"

# 3. Replace ENTIRE SVG block (not just <svg> tag)
# Target the full <svg>...</svg> to avoid leaving orphaned SVG internals
```

Save the PNG alongside the HTML, reference with relative `<img src="diagram.png">`. 
Verify no orphaned `<defs>`, `<rect>`, or `<text>` elements remain after replacement.

### ⚠ SVG container-div replacement destroys slide structure

**DO NOT target the wrapping `<div>` that contains the SVG for replacement.** The SVG is often inside a container like `<div style="text-align:center;margin-bottom:16px;">`. If you replace this entire div (from its opening to its closing), and the slide's heading (`<h2>`) or content cards sit between the div and the SVG, the replacement will:

1. Remove the slide's `<h2>` heading (it was adjacent to the container div)
2. Leave orphaned content cards floating between slides
3. Cause those cards to be absorbed into the PREVIOUS slide (since the current slide's closing `</div>` was consumed)
4. Produce a slide with 7 opens / 6 closes — exactly one missing close

**Correct approach:** Target ONLY the `<svg ...>...</svg>` element itself. Leave all surrounding `<div>` wrappers, headings, and card structures intact. Then insert the `<img>` tag alongside or replacing just the `<svg>`:

```python
# CORRECT: find and replace only the SVG element
svg_start = html.find('<svg xmlns=')
svg_end = html.find('</svg>', svg_start) + len('</svg>')
old_svg = html[svg_start:svg_end]
new_img = f'<img src="diagram.png" alt="..." style="max-width:100%;height:auto;border-radius:8px">'
html = html.replace(old_svg, new_img)
```

This keeps the slide's heading, cards, and div structure intact. Verify div balance is 0 delta after replacement.

### Recovering from container-div destruction

If you already destroyed the slide structure by replacing the container div, the fix requires:

1. Identify which slide lost its heading (grep for expected `<h2>` — if it's missing, that slide was destroyed)
2. Reconstruct the lost slide content (heading, image, cards) as a standalone block
3. Fix the div imbalance on the preceding slide (it has 1 extra open from absorbing the orphaned cards)
4. Insert the reconstructed slide at the correct position
5. Re-renumber all `data-slide` attributes sequentially

This recovery took 4 iterations in the iron deficiency deck rebuild. **Prevention is far cheaper than recovery.**

## Pitfall: slide-doctor Per-Slide False Positive on Final Slide

When the last slide in a deck has no subsequent `<!-- SLIDE` marker, slide-doctor's per-slide check range extends to EOF and counts the `</div>` that closes `<div id="slides">` as an extra close within the final slide. This produces a false positive (e.g., "slide 40: 4 opens, 5 closes") even when the overall div balance is perfect. Trust the overall balance (delta=0) — the per-slide imbalance on the final slide is a boundary artifact, not a real structural issue.

## Pitfall: Gemini Image Gen Wrapper Unreliable — Prefer Direct gemini.py

The `gemini-gen-image.sh` wrapper fails ~60% of the time with REQUEST_FAILED or "No image in Gemini response". The direct 3-step workflow works reliably:

```bash
# 1. Generate with --json
GEMINI_SID=... GEMINI_TS=... gemini.py --json "Generate an image: ..." -o /tmp/img.json
# 2. Parse URL
URL=$(python3 -c "import json; d=json.load(open('/tmp/img.json')); print(d['images'][0]['url'])")
# 3. Download with cookies
curl -sL -b "__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}" -o output.png "$URL"
```

## Pitfall: Dense Workflow/Algorithm Slides Overflow 720px Viewport

When building step-by-step algorithm slides with vertical arrow flow (Step 1 → Step 2 → Step 3 → branching treatment cards → decision node → Step 4), the stacked cards + arrows easily exceed 720px height. Screenshots will be truncated — Gemini visual QA will report content as "missing" when it's simply below the fold.

**Fix — compact aggressively for algorithm slides:**
- Reduce card padding to `8px 16px` (from default 20px 24px)
- Reduce vertical arrows to `font-size:0.9rem; line-height:1; padding:0` (from 1.5rem/4px)
- Reduce card heading font to `1.0–1.05rem` and body to `0.85–0.95rem`
- Use `margin-bottom:4px` on cards, `margin:0` on `<p>` inside cards
- Set `gap:16px` on flex-rows instead of default 20px
- Prefer single-line text (avoid `<br>` breaks in algorithm cards)
- Add `style="font-size:0.9rem"` to the slide div itself as a global shrink

**Verify:** After compacting, re-screenshot the slide and confirm the bottom-most element is visible to Gemini before continuing. The iron deficiency deck required 3 iterations to fit a 7-element vertical flow into 720px.

## Pitfall: Fixed Navigation Bar Overlaps Bottom Content

The `#nav` bar (Prev / counter / Next) is `position: fixed; bottom: 20px` — it sits on top of slide content at the bottom of the viewport. On dense slides (embedded images, tables, take-home message cards), the nav bar obscures the last visible content.

**Symptoms:** Gemini visual QA reports "navigation overlay is sitting directly on top of the diagram" or "the last line of text is cut off by the navigation bar." Affected slides in PIVKA-II deck: slide 6 (prothrombin diagram obscured) and slide 37 (last take-home message clipped).

**Fix:** Increase `.slide` bottom padding to create clearance for the nav:
```css
.slide {
  padding: 48px 64px 72px 64px;  /* was 48px 64px — extra 24px bottom padding */
}
```
This pushes the last content line above the fixed nav bar. The 72px bottom padding provides ~24px of clearance between content and the 48px nav bar region. Verify with re-screenshot after applying.

## Pitfall: slide-doctor Per-Slide False Positive on Final Slide

When the last slide in a deck has no subsequent `<!-- SLIDE` marker, slide-doctor's per-slide check range extends to EOF and counts the `</div>` that closes `<div id=\"slides\">` as an extra close within the final slide. This produces a false positive (e.g., "slide 40: 4 opens, 5 closes") even when the overall div balance is perfect. Trust the overall balance (delta=0) — the per-slide imbalance on the final slide is a boundary artifact, not a real structural issue.

## Pitfall: Gemini Image Gen Wrapper Unreliable — Use Direct gemini.py

The `gemini-gen-image.sh` wrapper fails ~60% of the time with REQUEST_FAILED or "No image in Gemini response". The direct 3-step workflow works reliably:

```bash
# 1. Generate with --json
GEMINI_SID=... GEMINI_TS=... gemini.py --json \"Generate an image: ...\" -o /tmp/img.json
# 2. Parse URL
URL=$(python3 -c \"import json; d=json.load(open('/tmp/img.json')); print(d['images'][0]['url'])\")
# 3. Download with cookies
curl -sL -b \"__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}\" -o output.png \"$URL\"
## Pitfall: Dense Workflow/Algorithm Slides Overflow 720px Viewport

When building step-by-step algorithm slides with vertical arrow flow (Step 1 → Step 2 → Step 3 → branching treatment cards → decision node → Step 4), the stacked cards + arrows easily exceed 720px height. Screenshots will be truncated — Gemini visual QA will report content as "missing" when it's simply below the fold.

**Fix — compact aggressively for algorithm slides:**
- Reduce card padding to `8px 16px` (from default 20px 24px)
- Reduce vertical arrows to `font-size:0.9rem; line-height:1; padding:0` (from 1.5rem/4px)
- Reduce card heading font to `1.0–1.05rem` and body to `0.85–0.95rem`
- Use `margin-bottom:4px` on cards, `margin:0` on `<p>` inside cards
- Set `gap:16px` on flex-rows instead of default 20px
- Prefer single-line text (avoid `<br>` breaks in algorithm cards)
- Add `style="font-size:0.9rem"` to the slide div itself as a global shrink

**Verify:** After compacting, re-screenshot the slide and confirm the bottom-most element is visible to Gemini before continuing. The iron deficiency deck required 3 iterations to fit a 7-element vertical flow into 720px.

## Pitfall: Fixed Navigation Bar Overlaps Bottom Content

The `#nav` bar (Prev / counter / Next) is `position: fixed; bottom: 20px` — it sits on top of slide content at the bottom of the viewport. On dense slides (embedded images, tables, take-home message cards), the nav bar obscures the last visible content.

**Symptoms:** Gemini visual QA reports "navigation overlay is sitting directly on top of the diagram" or "the last line of text is cut off by the navigation bar." Affected slides in PIVKA-II deck: slide 6 (prothrombin diagram obscured) and slide 37 (last take-home message clipped).

**Fix:** Increase `.slide` bottom padding to create clearance for the nav:
```css
.slide {
  padding: 48px 64px 72px 64px;  /* was 48px 64px — extra 24px bottom padding */
}
```
This pushes the last content line above the fixed nav bar. The 72px bottom padding provides ~24px of clearance between content and the 48px nav bar region. Verify with re-screenshot after applying.

## Pitfall: slide-doctor Per-Slide False Positive on Final Slide

When the last slide in a deck has no subsequent `<!-- SLIDE` marker, slide-doctor's per-slide check range extends to EOF and counts the `</div>` that closes `<div id=\"slides\">` as an extra close within the final slide. This produces a false positive (e.g., "slide 40: 4 opens, 5 closes") even when the overall div balance is perfect. Trust the overall balance (delta=0) — the per-slide imbalance on the final slide is a boundary artifact, not a real structural issue.

## Pitfall: Gemini Image Gen Wrapper Unreliable — Use Direct gemini.py

The `gemini-gen-image.sh` wrapper fails ~60% of the time with REQUEST_FAILED or "No image in Gemini response". The direct 3-step workflow works reliably:

```bash
# 1. Generate with --json
GEMINI_SID=... GEMINI_TS=... gemini.py --json \"Generate an image: ...\" -o /tmp/img.json
# 2. Parse URL
URL=$(python3 -c \"import json; d=json.load(open('/tmp/img.json')); print(d['images'][0]['url'])\")
# 3. Download with cookies
curl -sL -b \"__Secure-1PSID=${SID}; __Secure-1PSIDTS=${TS}\" -o output.png \"$URL\"
```

Free-tier accounts have rate limits (~1-2 images per session before Gemini returns text-only). Always run `gemini-ping.sh --quiet` before any generation attempt — expired cookies waste prompts with no diagnostic message.

## Phase 2i: Combined Improvement Review (Gemini + Self-Analysis)

After the initial QA review, run a **two-source improvement pass** for maximum coverage:

1. **Send to Gemini for critique:** Use the Phase 2h review prompt with an added instruction to rank issues as HIGH/MEDIUM/LOW and identify missing clinical nuance, teaching gaps, and under-explored controversies.

2. **Concurrently, perform self-analysis:** Scan the deck yourself for missing topics. Use `execute_code` to programmatically list covered topics vs a checklist of expected domains for the clinical topic. Expect to find 5–15 missing subtopics — this is normal for a first draft.

3. **Merge findings into prioritized action plan.** The combined list will have items neither source would have found alone (e.g., Gemini catches content accuracy nuances; self-analysis catches structure gaps like "no Mentzer index for microcytic differential").

4. **Implement all ranked improvements.** For 60-slide decks, expect 10–15 new slides. Use the marker-based rebuild approach from Phase 2f. Budget 2–3 rebuild iterations (screenshot → fix → re-screenshot).

This two-source pattern caught 15 actionable improvements in the iron deficiency deck that a single-source review would have missed.

## Pitfall: `-f` flag means different things in different CLIs

**gemini-gemini.sh:** `-f file.md` reads the file content as the PROMPT text.
**gemini.py:** `-f file.html` ATTACHES the file as a document; prompt text must be passed separately via `-p "text"` or positional argument.

When using `gemini.py` directly (recommended for alternate accounts with TS=None), always pair `-f` with `-p`:

```bash
# CORRECT: attach deck as document, provide review instructions as prompt
$PY $GEMINI -f deck.html -p "review this deck for accuracy..." -m pro -o review.md

# WRONG: gemini.py -f deck.html alone → "Prompt cannot be empty"
```

When using the `gemini-gemini.sh` wrapper, `-f` alone is sufficient for reading files as prompts. This inconsistency is why the skill recommends `gemini.py` direct calls as the primary approach for Gemini synthesis and review tasks. 
Example: in the anti-amyloid deck, a `<table>` was closed with `</ul>`. The browser:
1. Ignores `</ul>` inside `<table>` (parse error)
2. Leaves `<table>` open → swallows subsequent `</div>` closing tags
3. Slide never closes → all later slides become children of the broken slide
4. When parent slide loses `.active` (opacity 0), ALL child slides inherit invisibility

**Symptoms:** Slides at and after position N are always blank, even though div counts appear balanced (opens/closes match — the mismatch is TAG TYPE, not count).

**Prevention:** Always run tag-type balance check alongside div balance:
```python
for tag in ['table', 'ul', 'ol']:
    assert html.count(f'<{tag}') == html.count(f'</{tag}>'), f'{tag} mismatch'
```

## Related Skills

- `med-search-cli` — paper discovery and full-text retrieval
- `frontend-design` — HTML slide deck aesthetics
- `gemini-image-generation` — generate raster diagram images via Gemini Imagen (browser-cookie auth)

## Verification Checklist

- [x] Every statistic on the deck traces to a specific PMID
- [x] Evidence table has study name, journal, N, and key numbers per row
- [x] At least one meta-analysis cited for pooled effect sizes
- [x] At least one guideline cited for recommendation context
- [x] Reference slide lists all PMIDs with full citations
- [x] GRADE rating shown for every cited paper
- [x] GRADE Summary of Findings table included for key outcomes
- [x] Forest plot (SVG) embedded on dedicated slide with interpretation
- [x] Cost-effectiveness / NMA data included where available
- [x] Slide deck is single-file HTML, opens directly in browser
- [x] Keyboard navigation works (arrows, space, home/end)
- [x] Dark theme with gold accent (no purple, no Inter font)
- [x] .pptx export available via slide-export.py
- [x] ALL slides render — no blank pages (verify by clicking through every slide)
- [x] Inline SVGs have `width="100%" height="auto"` — no overflow blank slides
- [x] Content slides use `justify-content: flex-start` (NOT center)
- [x] Div balance verified: total opens == total closes (use `execute_code` to count)
- [x] Tag-type balance verified: `<table>`=`</table>`, `<ul>`=`</ul>`, `<ol>`=`</ol>` — mismatched closing tags (e.g. `</ul>` for `<table>`) cause cascading invisibility
- [x] Per-slide div balance verified: no individual slide has mismatched divs
- [x] SVG arrowheads verified: `<marker>` defined in `<defs>` BEFORE first `url(#arrowhead)` reference; all flow arrows have `marker-end` attribute
- [x] All `data-slide` attributes are sequential 1..N (nav dots depend on this)
- [x] External images have `onerror` fallback text (not `display:none`)
- [x] Slide insertion used `<!-- SLIDE` marker approach, not regex div matching
- [x] Gemini QA review completed — content accuracy, regulatory status, and data rates verified
- [x] All Gemini corrections applied and div balance re-verified

## Environment

All tools at /home/peter/.hermes/scripts/
Python venv at /home/peter/.hermes/hermes-agent/.venv/
Set MED_SEARCH_EMAIL for PubMed access.
Gemini auth optional (pipeline works without it).

## Reference Files

- `references/haemostatic-powder-ugib-example.md` — complete worked example with all 12 PMIDs, extracted outcome data, GRADE ratings, forest plot data, and token budget from the June 2026 haemostatic powder pipeline run. Use as a template for new clinical topics.
- `references/gemini-review-example-anti-amyloid.md` — Gemini QA review output showing typical corrections: outdated regulatory data, wrong ARIA rates, missing references. Use as a template for what to expect from Gemini reviews.
- `references/svg-pathway-template.svg` — dark-themed pathway/cascade diagram template with placeholder labels. Replace bracketed text for any pathway (amyloid cascade, coagulation cascade, signal transduction, etc.)
- `references/svg-mechanism-comparison-template.svg` — side-by-side two-drug mechanism-of-action comparison template. Left panel (blue) for Drug A, right panel (teal) for Drug B, with antibody Y-shape icons and bullet points.
- `references/svg-workflow-template.svg` — 4-phase clinical workflow timeline template with numbered phases, three middle items, and four bottom outcomes. Generic enough for pre-treatment, screening, monitoring, or any sequential clinical pathway.
- `references/svg-hepcidin-ferroportin-template.svg` — reusable 2-source → regulator → destination pathway diagram with upregulator/downregulator panels and clinical implication footer. Replace all `[BRACKETED]` labels. Used for hepcidin axis, coagulation cascades, inflammatory pathways, or any dual-source regulated system with inhibitory control.
