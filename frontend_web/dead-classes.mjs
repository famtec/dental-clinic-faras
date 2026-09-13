/* =============================================================================
   عيادتي الرقمية — كشف الأصناف بلا قاعدة CSS
   يقارن كل صنف مستخدم في الـ HTML بكل محدِّد في tailwind.css المبني.
   الفائدة الأولى: يكشف فوراً أن البناء متأخّر عن التعديلات — وهو عطل صامت
   تماماً (لا خطأ في الكونسول، فقط تنسيق لا يُطبَّق) استمر ثمانية أيام دون أن يُلاحَظ.

   التشغيل من داخل frontend_web:
     node dead-classes.mjs

   يخرج بحالة 1 إن وُجد صنف تايلويندي بلا قاعدة — صالح كخطوة في CI.
   ============================================================================= */
import fs from 'fs';

const CSS_FILE = process.argv[2] || 'tailwind.css';
const PAGES = fs.readdirSync('.').filter((f) => f.endsWith('.html') && !f.includes('.bak'));

/* --- فكّ ترميز CSS: \\2c  ->  ","  و  \\:  ->  ":" -------------------------- */
function unescape(s) {
  let out = '', i = 0;
  while (i < s.length) {
    if (s[i] === '\\') {
      const m = /^\\([0-9a-fA-F]{1,6}) ?/.exec(s.slice(i));
      if (m) { out += String.fromCodePoint(parseInt(m[1], 16)); i += m[0].length; continue; }
      out += s[i + 1]; i += 2; continue;
    }
    out += s[i]; i += 1;
  }
  return out;
}

/* --- كل صنف يظهر في أي موضع من أي محدِّد، لا الصنف الأول فقط ----------------
   هذا بالضبط ما أخطأتُ فيه أول مرة: القاعدة .peer:checked~.peer-checked\:bg-x
   تبدأ بـ .peer، فمَن يقرأ الصنف الأول فقط يظنّ peer-checked:bg-x غير موجود. */
function classesInCss(css) {
  const found = new Set();
  let i = 0, buf = '';
  while (i < css.length) {
    const ch = css[i];
    if (ch === '{') {
      const sel = buf.trim(); buf = '';
      if (sel.startsWith('@')) {
        if (/^@(media|supports|container|layer|scope)/.test(sel)) { i++; continue; }  // ادخل فيها
        let d = 1; i++;
        while (i < css.length && d > 0) { if (css[i] === '{') d++; else if (css[i] === '}') d--; i++; }
        continue;
      }
      let j = 0;
      while (j < sel.length) {
        if (sel[j] === '.') {
          j++; let raw = '';
          while (j < sel.length) {
            const c = sel[j];
            if (c === '\\') {
              const m = /^\\([0-9a-fA-F]{1,6}) ?/.exec(sel.slice(j));
              if (m) { raw += sel.slice(j, j + m[0].length); j += m[0].length; continue; }
              raw += sel.slice(j, j + 2); j += 2; continue;
            }
            if (' .:>+~,#[]()"\''.includes(c)) break;
            raw += c; j++;
          }
          if (raw) found.add(unescape(raw));
          continue;
        }
        j++;
      }
      let d = 1; i++;
      while (i < css.length && d > 0) { if (css[i] === '{') d++; else if (css[i] === '}') d--; i++; }
      continue;
    }
    if (ch === '}') { buf = ''; i++; continue; }
    buf += ch; i++;
  }
  return found;
}

const built = classesInCss(fs.readFileSync(CSS_FILE, 'utf8'));

/* --- الأصناف المستخدمة، مع تجاهل ما تعرّفه كتلة <style> داخل الصفحة نفسها --- */
const used = new Map();     // class -> {count, pages:Set}
let inlineCss = '', pageJs = '';
for (const p of PAGES) {
  const t = fs.readFileSync(p, 'utf8');
  inlineCss += (t.match(/<style[^>]*>[\s\S]*?<\/style>/g) || []).join('\n');
  pageJs    += (t.match(/<script(?![^>]*\bsrc=)[^>]*>[\s\S]*?<\/script>/g) || []).join('\n');
  for (const m of t.matchAll(/class="([^"]*)"/g)) {
    for (const c of m[1].split(/\s+/)) {
      if (!c || c.includes('${')) continue;
      if (!used.has(c)) used.set(c, { count: 0, pages: new Set() });
      const e = used.get(c); e.count++; e.pages.add(p);
    }
  }
}
const inlineClasses = classesInCss(inlineCss);

/* الشكل التايلويندي فقط: خطّافات JS مثل .edit-appointment-btn ليست أعطالاً */
const TW = /^(?:(?:sm|md|lg|xl|2xl|hover|focus|active|group-hover|disabled|focus-within|peer-focus|peer-checked|first|last|odd|even|print|motion-safe|rtl|ltr|dark):)*[a-z]+(-.*)?$/;

/* خطّاف JS: الصنف يُستعلَم عنه أو يُضاف/يُحذف في سكربت الصفحة — ليس نمطاً */
for (const f of ['clinic-loader.js', 'mobile-shell.js', 'notification-badge.js', 'api-config.js'])
  if (fs.existsSync(f)) pageJs += '\n' + fs.readFileSync(f, 'utf8');
const isHook = (c) => new RegExp(`['"\\.\\s]${c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}['"\\s\\)]`).test(pageJs);

const dead = [];
for (const [c, e] of used) {
  if (built.has(c) || inlineClasses.has(c) || !TW.test(c)) continue;
  if (isHook(c)) continue;                       // خطّاف JS لا نمط
  dead.push({ cls: c, ...e });
}
dead.sort((a, b) => b.count - a.count);

const total = dead.reduce((s, d) => s + d.count, 0);
console.log(`\nفُحص ${used.size} صنفاً مستخدماً في ${PAGES.length} صفحة مقابل ${built.size} محدِّداً في ${CSS_FILE}`);
if (!dead.length) {
  console.log('✅ كل صنف تايلويندي مستخدم له قاعدة CSS. البناء محدَّث.\n');
} else {
  console.log(`\n❌ ${dead.length} صنفاً بلا أي قاعدة CSS (${total} موضع استخدام):\n`);
  for (const d of dead) console.log(`   ×${String(d.count).padEnd(3)} ${d.cls.padEnd(44)} ${[...d.pages].join(', ')}`);
  console.log('\n   الغالب أن السبب بناء متأخّر. جرّب:');
  console.log('     npx --yes tailwindcss@3.4.19 -i ./tailwind-input.css -o ./tailwind.css --minify');
  console.log('   ثم أعد التشغيل. ما يبقى بعد ذلك اسم صنف خاطئ أو غير معرَّف يحتاج تدخّلاً يدوياً.\n');
  process.exitCode = 1;
}
