# Hermes Skills

Reusable skills for the Hermes AI Agent. Each skill is a self-contained workflow with triggers, step-by-step instructions, pitfalls, and verification checklists.

## Skills in this repo

### clinical-slide-deck
Build evidence-based clinical slide decks from PubMed-verified data. HTML + PPTX output with inline SVGs, forest plots, and GRADE ratings. Covers paper discovery, PICO extraction, evidence grading, and dual-format export.

### gemini-image-generation
Generate raster images (medical diagrams, illustrations) via Gemini Imagen on gemini.google.com using browser-cookie auth. Replaces broken SVGs with high-quality PNGs. Includes account switching workflow.

### screenshot-to-gemini
Take browser screenshots of HTML pages via headless Playwright, then send to Gemini for visual QA review. Detects blank slides, layout issues, opacity cascade bugs. Full pipeline: screenshot -> Gemini analysis -> fix -> re-screenshot.

## Structure

Each skill is a directory under `skills/` containing:
- `SKILL.md` — Trigger conditions, workflow steps, commands, pitfalls, verification
- `scripts/` — Executable scripts referenced by the skill
- `references/` — Templates, examples, API docs
- `assets/` — Images, fonts, static files

## Usage

Skills are loaded by Hermes Agent automatically when trigger keywords or context match. To install:

```bash
cp -r skills/* ~/.hermes/skills/
```

## Privacy

All skills are sanitized before upload:
- No API keys, tokens, or cookies
- No email addresses or usernames
- No browser profile paths or machine-specific identifiers
- Home directory paths use `~` placeholder
