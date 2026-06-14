# AGENTS.md — Hermes Skills Repo

For AI coding assistants working with this repository.

## What this repo is

A collection of reusable skills for the Hermes AI Agent. Each skill is a
procedural memory — a proven workflow for a recurring task type. Skills are
discovered by trigger keywords/context and loaded at runtime.

## Skill format

Every skill is a directory under `skills/<name>/` with `SKILL.md` at minimum:

```markdown
---
name: skill-name
description: One-line summary
triggers:
  keywords: [word1, word2]
  context: [When user asks for X]
---

# Skill Title

## Prerequisites
## Workflow (numbered steps with exact commands)
## Pitfalls
## Verification Checklist
```

## Privacy rules for commits

BEFORE committing any skill:

1. **No tokens or cookies** — Replace `GEMINI_SID=...` with `<your_SID>`
2. **No API keys** — Replace `sk-...` with `<your_key>`
3. **No profile paths** — Replace `/mnt/c/Users/Name/...` with `<browser_profile>`
4. **No email addresses** — Use `user@example.com` placeholder
5. **No machine-specific paths** — Use `~` for home directory

Run before commit: `grep -rE '(g\.a000|sidts-|sk-[A-Za-z0-9]{20,}|/mnt/c/Users/)' skills/` should produce NO output.

## Skills in this repo

| Skill | Category | What it does |
|-------|----------|--------------|
| clinical-slide-deck | creative | Medical slide decks from PubMed with token-efficient pipeline |
| gemini-image-generation | research | Imagen image gen via browser cookies (robust wrapper + token patterns) |
| screenshot-to-gemini | devops | Browser screenshots -> Gemini QA with hallucination guard |

## Reference files

- `skills/clinical-slide-deck/references/template.css` — Complete CSS with static-nav pattern (never overlaps content). Copy the entire block into `<style>` tag.
- `skills/clinical-slide-deck/references/template.html` — HTML skeleton with correct DOM structure. Copy and fill in slides.
- `skills/clinical-slide-deck/scripts/slide-doctor.py` — HTML integrity checker (8 checks including file corruption detection)

## Cross-references between skills

- `clinical-slide-deck` -> `gemini-image-generation` (replace SVGs, generate diagrams)
- `clinical-slide-deck` -> `screenshot-to-gemini` (visual QA after building deck)
- `screenshot-to-gemini` -> `gemini-cli` (external, for sending images to Gemini)
- `gemini-image-generation` -> `gemini-cli` (external, for cookie auth)

## Known tool limitations (documented in skills)

- `gemini.py -f` silently drops files over ~30KB — use `-p "$(cat file.md)"` instead
- `execute_code` write_file corrupts HTML (2-char strip) — use native `write_file`/`patch`
- `browser_vision` fails on DeepSeek — route through gemini-fallback skill
