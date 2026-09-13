/* =============================================================================
   عيادتي الرقمية — فحص بصري آلي بعد كل مرحلة
   يلتقط الاثنتي عشرة صفحة عند 390 / 768 / 1280، ويقارنها بخطّ أساس محفوظ،
   ويرصد ثلاثة أعطال لا تُرى في اللقطة وحدها:
     · تمرير أفقي (أشيع عطل استجابة، وأصعبه ملاحظةً)
     · مساحات لمس أصغر من ٤٤px على الجوال
     · أخطاء الكونسول

   فحصُ «الأصناف بلا CSS» في ملف منفصل: dead-classes.mjs — يعمل على الملفات
   مباشرة لا داخل المتصفح، فهو أدقّ ولا يحتاج خادماً.

   التشغيل:
     npm i -D playwright pixelmatch pngjs      # مرة واحدة
     npx playwright install chromium           # مرة واحدة

     node visual-check.mjs --base              # قبل أي تعديل: يحفظ خطّ الأساس
     node visual-check.mjs                     # بعد كل مرحلة: يقارن

   يفترض خادماً محلياً على المنفذ 8000 يخدم مجلد frontend_web:
     python -m http.server 8000                # من داخل frontend_web
   ============================================================================= */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

const BASE_URL = process.env.BASE_URL || 'http://localhost:8000';
const ROOT     = process.cwd();
const BASE_DIR = path.join(ROOT, '.visual', 'baseline');
const CUR_DIR  = path.join(ROOT, '.visual', 'current');
const DIFF_DIR = path.join(ROOT, '.visual', 'diff');
const SAVE_BASELINE = process.argv.includes('--base');
const THRESHOLD_PCT = 0.35;   // نسبة البكسلات المختلفة المسموح بها قبل اعتبارها انحداراً

const PAGES = [
  'landing.html', 'login.html', 'register.html', 'index.html',
  'patient_record.html', 'appointments.html', 'finance.html', 'inventory.html',
  'profile.html', 'booking.html', 'qr.html', 'contact_developer.html',
];
const WIDTHS = [390, 768, 1280];

for (const d of [BASE_DIR, CUR_DIR, DIFF_DIR]) fs.mkdirSync(d, { recursive: true });

/* --- المقارنة البصرية ------------------------------------------------------ */
function compare(name) {
  const a = path.join(BASE_DIR, name), b = path.join(CUR_DIR, name);
  if (!fs.existsSync(a)) return { status: 'no-baseline' };
  const imgA = PNG.sync.read(fs.readFileSync(a));
  const imgB = PNG.sync.read(fs.readFileSync(b));
  if (imgA.width !== imgB.width || imgA.height !== imgB.height) {
    return { status: 'size-changed', detail: `${imgA.width}x${imgA.height} → ${imgB.width}x${imgB.height}` };
  }
  const diff = new PNG({ width: imgA.width, height: imgA.height });
  const n = pixelmatch(imgA.data, imgB.data, diff.data, imgA.width, imgA.height, { threshold: 0.12 });
  const pct = (n / (imgA.width * imgA.height)) * 100;
  if (pct > 0) fs.writeFileSync(path.join(DIFF_DIR, name), PNG.sync.write(diff));
  return { status: pct > THRESHOLD_PCT ? 'changed' : 'ok', pct: pct.toFixed(2) };
}

/* --- التشغيل --------------------------------------------------------------- */
const browser = await chromium.launch();
const problems = [];
let checked = 0;

for (const pageName of PAGES) {
  for (const width of WIDTHS) {
    const ctx  = await browser.newContext({ viewport: { width, height: 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    const consoleErrors = [];
    page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 120)); });
    page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e).slice(0, 120)));

    try {
      await page.goto(`${BASE_URL}/${pageName}`, { waitUntil: 'networkidle', timeout: 20000 });
    } catch { /* الشبكة قد لا تهدأ بسبب نداءات API — نكمل على أي حال */ }
    await page.waitForTimeout(1200);

    const label = `${pageName.replace('.html', '')}-${width}`;
    const file  = `${label}.png`;
    checked++;

    // ١) تمرير أفقي
    const overflow = await page.evaluate(() => ({
      scrollW: document.documentElement.scrollWidth,
      clientW: document.documentElement.clientWidth,
      culprits: [...document.querySelectorAll('*')]
        .filter((el) => el.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
        .slice(0, 3)
        .map((el) => (el.id ? '#' + el.id : el.tagName.toLowerCase() + '.' + String(el.className).split(' ')[0])),
    }));
    if (overflow.scrollW > overflow.clientW + 1) {
      problems.push(`⟵⟶  تمرير أفقي   ${label}  (${overflow.scrollW}px > ${overflow.clientW}px)  المشتبَه: ${overflow.culprits.join(' , ')}`);
    }

    // ٢) مساحات لمس أصغر من ٤٤px على الجوال
    if (width === 390) {
      const small = await page.evaluate(() =>
        [...document.querySelectorAll('button, a[href], input[type=checkbox], [role=button]')]
          .filter((el) => { const r = el.getBoundingClientRect();
                            return r.width > 0 && r.height > 0 && (r.height < 44 || r.width < 44); })
          .slice(0, 5)
          .map((el) => (el.id ? '#' + el.id : el.tagName.toLowerCase()) +
                       ` ${Math.round(el.getBoundingClientRect().width)}×${Math.round(el.getBoundingClientRect().height)}`));
      if (small.length) problems.push(`👆  مساحة لمس < 44px  ${label}  →  ${small.join(' , ')}`);
    }

    // ٣) أخطاء الكونسول
    if (consoleErrors.length) problems.push(`⚠️  خطأ كونسول   ${label}  →  ${consoleErrors[0]}`);

    // ٤) اللقطة
    await page.screenshot({ path: path.join(SAVE_BASELINE ? BASE_DIR : CUR_DIR, file), fullPage: true });
    if (!SAVE_BASELINE) {
      const r = compare(file);
      if (r.status === 'changed')      problems.push(`🖼️  تغيّر بصري   ${label}  (${r.pct}% من البكسلات) → .visual/diff/${file}`);
      if (r.status === 'size-changed') problems.push(`📏  تغيّر الارتفاع ${label}  ${r.detail}`);
    }
    await ctx.close();
  }
}
await browser.close();

console.log(`\nفُحصت ${checked} لقطة (${PAGES.length} صفحات × ${WIDTHS.length} عروض)`);
if (SAVE_BASELINE) {
  console.log(`✅ حُفظ خطّ الأساس في ${BASE_DIR}`);
} else if (!problems.length) {
  console.log('✅ لا انحدار: لا تمرير أفقي، ولا مساحات لمس صغيرة، ولا أخطاء كونسول، ولا فروق بصرية فوق الحدّ.');
} else {
  console.log(`\n❌ ${problems.length} ملاحظة:\n`);
  problems.forEach((p) => console.log('   ' + p));
  console.log('\n   ملاحظة: «تغيّر بصري» متوقّع بعد كل مرحلة — المطلوب أن تكون الصفحات المتغيّرة هي التي');
  console.log('   قصدتَ تغييرها فقط. راجع صور .visual/diff/ وقارنها بنطاق المرحلة قبل أن تعتبرها عطلاً.');
  process.exitCode = 1;
}
