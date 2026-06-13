const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  
  // CHANGE THIS to your HTML file path
  const htmlPath = 'file:///home/peter/anti-amyloid-therapies-alzheimers-slide-deck.html';
  
  await page.goto(htmlPath, { waitUntil: 'networkidle', timeout: 15000 });
  
  const totalSlides = await page.evaluate(() => document.querySelectorAll('.slide').length);
  console.log(`Total slides: ${totalSlides}`);
  
  // CHANGE THIS to select which slides to screenshot (1-indexed)
  const targets = [1,2,3,4,5, 35,36,37,38,39, 48,49,50,51, 64,65,66];
  
  for (const n of targets) {
    if (n > totalSlides) break;
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
  console.log('Done - screenshots in /tmp/slide_*.png');
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
