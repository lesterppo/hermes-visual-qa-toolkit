#!/usr/bin/env node
/**
 * screenshots.js — Headless browser screenshot capture with pixel diffing.
 *
 * Usage:
 *   node screenshots.js --path deck.html [--slides 1-5,10] [--output /tmp/]
 *   node screenshots.js --path deck.html --diff --baseline ./baseline/
 *   node screenshots.js --path deck.html --agent     (compact JSON output)
 *
 * Requires: playwright (npm), chromium (~/.cache/ms-playwright/)
 * Optional: pixelmatch + pngjs (npm) for pixel-level --diff
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

// --- Self-test: verify chromium exists on startup ---
function selfTest() {
  const cacheDir = path.join(require('os').homedir(), '.cache', 'ms-playwright');
  if (!fs.existsSync(cacheDir)) {
    console.error('FATAL: Chromium not installed.');
    console.error('Run: cd /tmp && npm install playwright && npx playwright install chromium');
    process.exit(2);
  }
  const dirs = fs.readdirSync(cacheDir).filter(d => d.startsWith('chromium-'));
  if (dirs.length === 0) {
    console.error('FATAL: Chromium binary missing from ' + cacheDir);
    console.error('Run: npx playwright install chromium');
    process.exit(2);
  }
}

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
  for (const part of spec.split(',')) {
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

async function pixelDiff(currFile, baseFile) {
  try {
    const { PNG } = require('pngjs');
    const pixelmatch = require('pixelmatch');
    const img1 = PNG.sync.read(fs.readFileSync(baseFile));
    const img2 = PNG.sync.read(fs.readFileSync(currFile));
    if (img1.width !== img2.width || img1.height !== img2.height) {
      return { changed: true, diffPixels: -1, reason: `size mismatch: ${img1.width}x${img1.height} vs ${img2.width}x${img2.height}` };
    }
    const diff = new PNG({ width: img1.width, height: img1.height });
    const diffPixels = pixelmatch(img1.data, img2.data, diff.data, img1.width, img1.height, { threshold: 0.05 });
    return { changed: diffPixels > 100, diffPixels, reason: diffPixels > 100 ? `${diffPixels} pixels differ` : 'match' };
  } catch (e) {
    if (e.code === 'MODULE_NOT_FOUND') {
      return { changed: null, reason: 'pixelmatch not installed. Run: npm install pixelmatch pngjs' };
    }
    return { changed: null, reason: e.message };
  }
}

(async () => {
  selfTest();
  const opts = parseArgs();
  if (!opts.path) { console.error('Usage: node screenshots.js --path deck.html [--slides 1-5] [--output /tmp/]'); process.exit(1); }
  
  const htmlPath = opts.path.startsWith('file://') ? opts.path : `file://${path.resolve(opts.path)}`;
  if (!fs.existsSync(opts.output)) fs.mkdirSync(opts.output, { recursive: true });
  
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  
  await page.goto(htmlPath, { waitUntil: 'networkidle', timeout: 15000 });
  const totalSlides = await page.evaluate(() => document.querySelectorAll('.slide').length);
  
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
    const entry = { slide: n, file: filepath, ...info, status };
    results.push(entry);
    
    if (!opts.agent) console.log(`Slide ${n}: ${info.title.substring(0,50)} | op:${info.opacity.toFixed(3)} | ${info.width}x${info.height} | ${status}`);
  }
  
  // Pixel diff mode
  if (opts.diff && opts.baseline) {
    if (!opts.agent) console.log('\n--- Pixel diff against baseline ---');
    for (const r of results) {
      const baseFile = path.join(opts.baseline, path.basename(r.file));
      if (!fs.existsSync(baseFile)) {
        r.diff = { changed: null, reason: 'no baseline' };
        if (!opts.agent) console.log(`Slide ${r.slide}: NO BASELINE`);
        continue;
      }
      const diffResult = await pixelDiff(r.file, baseFile);
      r.diff = diffResult;
      if (!opts.agent) {
        const verdict = diffResult.changed === true ? 'CHANGED' : diffResult.changed === false ? 'same' : `SKIP (${diffResult.reason})`;
        console.log(`Slide ${r.slide}: ${verdict} — ${diffResult.reason}`);
      }
    }
  }
  
  await browser.close();
  
  // Write results
  const resultsPath = path.join(opts.output, 'screenshots.json');
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
  
  if (opts.agent) {
    const blanks = results.filter(r => r.status !== 'ok').map(r => r.slide);
    const diffs = results.filter(r => r.diff && r.diff.changed === true).map(r => r.slide);
    console.log(JSON.stringify({ ok: blanks.length === 0 && diffs.length === 0, total: totalSlides, captured: results.length, blanks, diffs }));
  } else {
    console.log(`\n${results.length} screenshots → ${opts.output}/ | results → ${resultsPath}`);
  }
})().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
