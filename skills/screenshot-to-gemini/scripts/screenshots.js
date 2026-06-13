#!/usr/bin/env node
/**
 * screenshots.js — Headless browser screenshot capture for HTML slide decks.
 *
 * Usage:
 *   node screenshots.js --path deck.html [--slides 1-5,10,15-20] [--output /tmp/]
 *
 * Parses slide numbers, navigates deck, captures PNGs with diagnostic logging.
 * Output: slide_01.png, slide_02.png, ... in --output dir.
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { path: null, slides: null, output: '/tmp', diff: false, baseline: null, agent: false };
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--path' && args[i+1]) opts.path = args[++i];
    else if (args[i] === '--slides' && args[i+1]) opts.slides = args[++i];
    else if (args[i] === '--output' && args[i+1]) opts.output = args[++i];
    else if (args[i] === '--diff') opts.diff = true;
    else if (args[i] === '--agent') opts.agent = true;
    else if (args[i] === '--baseline' && args[i+1]) opts.baseline = args[++i];
  }
  return opts;
}

function parseSlideList(spec, total) {
  if (!spec || spec === 'all') return Array.from({length: total}, (_, i) => i + 1);
  const result = [];
  const parts = spec.split(',');
  for (const part of parts) {
    if (part.includes('-')) {
      const [a, b] = part.split('-').map(Number);
      for (let i = a; i <= Math.min(b, total); i++) result.push(i);
    } else {
      const n = Number(part);
      if (n > 0 && n <= total) result.push(n);
    }
  }
  return [...new Set(result)].sort((a, b) => a - b);
}

(async () => {
  const opts = parseArgs();
  if (!opts.path) { console.error('Usage: node screenshots.js --path deck.html [--slides 1-5,10] [--output /tmp/]'); process.exit(1); }
  
  const htmlPath = opts.path.startsWith('file://') ? opts.path : `file://${path.resolve(opts.path)}`;
  if (!fs.existsSync(opts.output)) fs.mkdirSync(opts.output, { recursive: true });
  
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  
  await page.goto(htmlPath, { waitUntil: 'networkidle', timeout: 15000 });
  
  const totalSlides = await page.evaluate(() => document.querySelectorAll('.slide').length);
  console.log(`Total slides: ${totalSlides}`);
  
  const targets = parseSlideList(opts.slides, totalSlides);
  const results = [];
  
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
      if (!s) return { title: 'MISSING', opacity: 0, width: 0, height: 0 };
      const style = window.getComputedStyle(s);
      const h2 = s.querySelector('h2');
      return {
        title: h2 ? h2.textContent.substring(0, 60) : '(no h2)',
        opacity: parseFloat(style.opacity),
        width: s.offsetWidth,
        height: s.offsetHeight
      };
    }, idx);
    
    const filepath = path.join(opts.output, `slide_${String(n).padStart(2,'0')}.png`);
    await page.screenshot({ path: filepath });
    
    const status = info.opacity < 0.1 ? 'BLANK' : info.width === 0 ? 'ZERO-SIZE' : 'ok';
    console.log(`Slide ${n}: ${info.title.substring(0,50)} | op:${info.opacity.toFixed(3)} | ${info.width}x${info.height} | ${status}`);
    results.push({ slide: n, file: filepath, ...info, status });
  }
  
  // Diff mode: compare against baseline
  if (opts.diff && opts.baseline) {
    console.log('\n--- Diff against baseline ---');
    for (const r of results) {
      const baseFile = path.join(opts.baseline, path.basename(r.file));
      if (!fs.existsSync(baseFile)) {
        console.log(`Slide ${r.slide}: NO BASELINE (${baseFile})`);
        continue;
      }
      // Simple pixel-diff via Playwright's built-in comparator works on page, not files.
      // For file-based diff, use pixelmatch or imagemagick. Report baseline existence.
      const baseStat = fs.statSync(baseFile);
      const currStat = fs.statSync(r.file);
      const sizeDiff = Math.abs(currStat.size - baseStat.size);
      const pctChange = baseStat.size > 0 ? (sizeDiff / baseStat.size * 100).toFixed(1) : 'N/A';
      const verdict = sizeDiff > 1000 ? 'CHANGED' : 'same';
      console.log(`Slide ${r.slide}: ${verdict} (${pctChange}% size diff)`);
    }
  }
  
  await browser.close();
  
  // Write results JSON for downstream tooling
  const resultsPath = path.join(opts.output, 'screenshots.json');
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
  // Agent mode: minimal output
  if (opts.agent) {
    const summary = { ok: results.every(r => r.status === 'ok'), total: totalSlides, 
                      captured: results.length, blanks: results.filter(r => r.status !== 'ok').map(r => r.slide) };
    console.log(JSON.stringify(summary));
  } else {
    console.log(`\nResults: ${resultsPath}`);
    console.log(`Done - ${results.length} screenshots in ${opts.output}/`);
  }
  
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
