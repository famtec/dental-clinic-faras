/**
 * mobile-shell.js
 * ----------------
 * غلاف التنقّل الخاص بوضع الجوال لكل صفحات لوحة التحكم.
 *
 * قبل هذا الملف كان التنقّل على الجوال يتم عبر زر "هامبرغر" يفتح قائمة
 * منسدلة طويلة من أعلى الشاشة (#mobileMenuToggle + #mobileMenuDropdown):
 * كل انتقال بين الصفحات يحتاج ضغطتين، والقائمة تغطي المحتوى، وأزرار مثل
 * "نسخة احتياطية" لم تكن تظهر على الجوال إطلاقاً لأنها موجودة في الترويسة
 * المكتبية وحدها (md:block).
 *
 * ما يفعله هذا الملف بدلاً من ذلك:
 *   1. يخفي زر الهامبرغر والقائمة المنسدلة على الجوال (يبقيان كما هما في
 *      الـ DOM حتى لا ينكسر أي سكربت آخر يشير إليهما).
 *   2. يحقن شريط تنقّل سفلياً ثابتاً بأربع صفحات أساسية + زر "المزيد".
 *   3. يحقن لوحة منزلقة من الأسفل لزر "المزيد" فيها بطاقة الطبيب وبقية
 *      الروابط وأي أزرار إضافية موجودة في ترويسة الصفحة نفسها.
 *
 * الأزرار الإضافية لا يُعاد تنفيذ منطقها هنا: يتم استنساخ شكلها فقط، وأي
 * ضغطة عليها تُمرَّر إلى الزر الأصلي في الترويسة عبر .click()، فتبقى كل
 * معالجات الأحداث القائمة (النسخ الاحتياطي، الاسترجاع، تسجيل الخروج...)
 * تعمل كما هي دون أي تعديل على صفحاتها.
 *
 * شارة طلبات الحجز الحمراء تظهر تلقائياً على تبويب "المواعيد" لأن
 * notification-badge.js يبحث عن كل a[href="appointments.html"] في الصفحة.
 *
 * أدرجه بعد api-config.js في كل صفحة من صفحات لوحة التحكم:
 *   <script src="mobile-shell.js"></script>
 *
 * لا يعمل إطلاقاً على الشاشات المكتبية (كل عناصره md:hidden عبر CSS).
 *
 * ---------------------------------------------------------------------------
 * طبقة iOS (2026-09-10)
 * ---------------------------------------------------------------------------
 * أُضيفت في نهاية هذا الملف طبقة تعمل على أجهزة أبل وحدها (iPhone/iPad):
 *
 *   1. تضيف `viewport-fit=cover` إلى وسم viewport. بدونه تُرجِع كل دوال
 *      env(safe-area-inset-*) صفراً على iPhone -- وهذا ما كان يحدث فعلاً:
 *      الحشوة المكتوبة أدناه `calc(14px + env(safe-area-inset-bottom))` كانت
 *      تنفّذ 14px بدل 48px، فيقع الشريط السفلي تحت مؤشر الصفحة.
 *   2. تضيف theme-color بلون الترويسة و apple-touch-icon.
 *   3. تحقن أنماطاً تعطي الشريط والصفيحة والقوائم قياسات iOS الحقيقية
 *      (49pt + مساحة المؤشر، صفوف بفواصل تبدأ من بداية النصّ، حقول 17px
 *      حتى لا يكبّر Safari الشاشة عند اللمس) مع الحفاظ على ألوان الموقع
 *      وأسطحه وخطّه كما هي حرفاً بحرف.
 *
 * كل شيء محصور بالصنف `html.is-ios`: لا سطر منه يظهر على أندرويد أو المكتب.
 */
(function () {
  'use strict';

  var NAV_HEIGHT_PX = 86;
  /* على iOS: 49pt لصف التبويبات + مساحة مؤشر الصفحة من env() */
  var IOS_TAB_ROW_PX = 49;

  var ICONS = {
    patients:
      '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>',
    appointments:
      '<rect x="3" y="4" width="18" height="18" rx="2"></rect><path d="M16 2v4"></path><path d="M8 2v4"></path><path d="M3 10h18"></path>',
    finance:
      '<line x1="18" y1="20" x2="18" y2="10"></line><line x1="12" y1="20" x2="12" y2="4"></line><line x1="6" y1="20" x2="6" y2="14"></line>',
    inventory:
      '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path><polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline><line x1="12" y1="22.08" x2="12" y2="12"></line>',
    doctors:
      '<path d="M17 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2"></path><circle cx="10" cy="7" r="3.2"></circle><path d="M18 8v6"></path><path d="M21 11h-6"></path>',
    more: '<circle cx="5" cy="12" r="1.7"></circle><circle cx="12" cy="12" r="1.7"></circle><circle cx="19" cy="12" r="1.7"></circle>',
    profile:
      '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle>',
    developer:
      '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"></path>',
    qr: '<rect x="3" y="3" width="7" height="7" rx="1"></rect><rect x="14" y="3" width="7" height="7" rx="1"></rect><rect x="3" y="14" width="7" height="7" rx="1"></rect><path d="M14 14h3v3h-3z"></path><path d="M21 21h-3"></path>',
    backup:
      '<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2Z"></path><polyline points="17 21 17 13 7 13 7 21"></polyline><polyline points="7 3 7 8 15 8"></polyline>',
    restore:
      '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line>',
    action:
      '<circle cx="12" cy="12" r="9"></circle><path d="M12 8v8"></path><path d="M8 12h8"></path>',
    logout:
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><polyline points="16 17 21 12 16 7"></polyline><line x1="21" y1="12" x2="9" y2="12"></line>',
    trash:
      '<path d="M4 7h16"></path><path d="M9 7V5h6v2"></path><path d="M6 7l1 13h10l1-13"></path>',
    plus: '<path d="M12 5v14"></path><path d="M5 12h14"></path>',
    back: '<path d="M15 6l-6 6 6 6"></path>'
  };

  /* صفحات فرعية تُبقي تبويبها الأب مُضاءً في الشريط السفلي (ملف المريض
     يُفتح من لوحة المرضى، فمن الأصح أن يبقى تبويب "المرضى" هو النشط). */
  var CHILD_PAGES = { 'patient_record.html': 'index.html' };

  /* التبويبات الأربعة الأساسية في الشريط السفلي، بنفس ترتيب الترويسة. */
  var TABS = [
    { href: 'index.html', label: 'المرضى', icon: 'patients' },
    { href: 'appointments.html', label: 'المواعيد', icon: 'appointments' },
    { href: 'finance.html', label: 'المالية', icon: 'finance' },
    { href: 'inventory.html', label: 'المخزن', icon: 'inventory' }
  ];

  /* روابط تظهر داخل لوحة "المزيد" بدل الشريط السفلي. */
  var SHEET_LINKS = [
    { href: 'doctors.html', label: 'الأطباء والنسب', hint: 'حساب نسب الأطباء', icon: 'doctors', tone: 'violet' },
    { href: 'profile.html', label: 'حسابي', hint: 'بيانات العيادة', icon: 'profile', tone: 'indigo' },
    { href: 'qr.html', label: 'رمز الحجز', hint: 'مشاركة QR', icon: 'qr', tone: 'cyan' },
    { href: 'contact_developer.html', label: 'تواصل مع المطور', hint: 'دعم فني', icon: 'developer', tone: 'pink' }
  ];

  /* أزرار الترويسة المعروفة، لإعطائها أيقونة ووصفاً مناسبين عند استنساخها. */
  var KNOWN_BUTTONS = {
    backupBtn: { label: 'نسخة احتياطية', hint: 'تصدير البيانات', icon: 'backup', tone: 'cyan' },
    restoreBackupBtn: { label: 'استرجاع نسخة', hint: 'استيراد ملف', icon: 'restore', tone: 'emerald' }
  };

  /* عنوان كل صفحة كما يظهر في شريط iOS العلوي. */
  var PAGE_TITLES = {
    'index.html': 'المرضى',
    'appointments.html': 'المواعيد',
    'finance.html': 'المالية',
    'inventory.html': 'المخزن',
    'doctors.html': 'الأطباء والنسب',
    'patient_record.html': 'ملف المريض',
    'profile.html': 'حسابي',
    'qr.html': 'رمز الحجز',
    'contact_developer.html': 'تواصل مع المطور'
  };

  /* الإجراء الأساسي الذي يصير زرّ + في الترويسة. الضغط يُمرَّر إلى الزرّ
     الأصلي في الصفحة عبر .click()، فلا يُعاد تنفيذ أي منطق هنا. */
  var PRIMARY_ACTIONS = {
    'index.html': { id: 'addPatientBtn', label: 'مريض جديد' },
    'appointments.html': { id: 'openModalBtn', label: 'موعد جديد' }
  };

  /* صفحة فرعية: زرّ رجوع يحمل اسم صفحتها الأمّ بدل شعار العيادة. */
  var PARENT_PAGES = {
    'patient_record.html': { href: 'index.html', label: 'المرضى' }
  };

  var TONES = {
    indigo: { bg: '#eef2ff', color: '#4f46e5' },
    violet: { bg: '#f5f3ff', color: '#7c3aed' },
    cyan: { bg: '#ecfeff', color: '#0e7490' },
    emerald: { bg: '#ecfdf5', color: '#059669' },
    pink: { bg: '#fdf2f8', color: '#db2777' }
  };

  var sheetEl = null;
  var backdropEl = null;

  function svg(pathMarkup, size, stroke) {
    return (
      '<svg viewBox="0 0 24 24" width="' + size + '" height="' + size + '" fill="none" ' +
      'stroke="' + stroke + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' +
      'aria-hidden="true">' + pathMarkup + '</svg>'
    );
  }

  function currentPage() {
    return (window.location.pathname.split('/').pop() || 'index.html').toLowerCase();
  }

  /* الصفحة التي يجب أن يُضاء تبويبها: الصفحة نفسها، أو تبويبها الأب. */
  function activePage() {
    var page = currentPage();
    return CHILD_PAGES[page] || page;
  }

  function injectStyles() {
    if (document.getElementById('mobile-shell-styles')) return;
    var style = document.createElement('style');
    style.id = 'mobile-shell-styles';
    style.textContent = [
      /* لا شيء من هذا الغلاف يظهر على الشاشات المكتبية. */
      '@media (min-width: 768px){',
      '  #mobileShellNav,#mobileShellSheet,#mobileShellBackdrop{display:none !important;}',
      '}',
      '@media (max-width: 767.98px){',
      /* الهامبرغر والقائمة المنسدلة القديمة يبقيان في الـ DOM لكن مخفيين. */
      '  #mobileMenuToggle,#mobileMenuDropdown{display:none !important;}',
      '  body{padding-bottom:' + NAV_HEIGHT_PX + 'px !important;}',
      '}',

      '#mobileShellNav{position:fixed;inset-inline:0;bottom:0;z-index:70;display:flex;',
      'align-items:stretch;justify-content:space-between;gap:4px;',
      'padding:9px 10px calc(14px + env(safe-area-inset-bottom,0px));',
      'border-radius:26px 26px 0 0;border-top:1px solid rgba(255,255,255,.12);',
      'background:rgba(30,27,75,.96);backdrop-filter:blur(18px);',
      '-webkit-backdrop-filter:blur(18px);box-shadow:0 -14px 40px rgba(30,27,75,.35);',
      'font-family:inherit;}',

      '.mshell-tab{flex:1 1 0;display:flex;flex-direction:column;align-items:center;',
      'justify-content:center;gap:4px;min-height:56px;border-radius:18px;border:none;',
      'background:transparent;color:#a5b4fc;text-decoration:none;cursor:pointer;',
      'font-family:inherit;font-size:10.5px;font-weight:800;padding:0;',
      '-webkit-tap-highlight-color:transparent;transition:background .18s ease,color .18s ease;}',
      '.mshell-tab span{pointer-events:none;}',
      '.mshell-tab:active{transform:scale(.96);}',
      '.mshell-tab[data-active="1"]{color:#fff;',
      'background:linear-gradient(160deg,rgba(99,102,241,.95),rgba(139,92,246,.9));',
      'box-shadow:0 8px 22px rgba(99,102,241,.45);}',

      '#mobileShellBackdrop{position:fixed;inset:0;z-index:80;background:rgba(15,23,42,.58);',
      'backdrop-filter:blur(3px);-webkit-backdrop-filter:blur(3px);opacity:0;',
      'transition:opacity .22s ease;}',
      '#mobileShellBackdrop[data-open="1"]{opacity:1;}',

      '#mobileShellSheet{position:fixed;inset-inline:0;bottom:0;z-index:81;background:#fff;',
      'border-radius:30px 30px 0 0;box-shadow:0 -22px 60px rgba(15,23,42,.35);',
      'padding:10px 16px calc(20px + env(safe-area-inset-bottom,0px));',
      'max-height:88vh;overflow-y:auto;font-family:inherit;color:#1e293b;',
      'transform:translateY(100%);transition:transform .26s cubic-bezier(.22,1,.36,1);}',
      '#mobileShellSheet[data-open="1"]{transform:translateY(0);}',

      '.mshell-grabber{width:44px;height:5px;border-radius:999px;background:#cbd5e1;',
      'margin:0 auto 14px;}',

      '.mshell-doctor{display:flex;align-items:center;gap:12px;padding:13px;border-radius:24px;',
      'background:linear-gradient(160deg,rgba(31,41,55,.97),rgba(49,46,129,.96),rgba(76,29,149,.95));',
      'box-shadow:0 16px 36px rgba(67,56,202,.28);}',
      '.mshell-doctor-avatar{width:50px;height:50px;flex-shrink:0;border-radius:17px;',
      'border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.14);',
      'display:flex;align-items:center;justify-content:center;overflow:hidden;}',
      '.mshell-doctor-avatar img{width:100%;height:100%;object-fit:contain;padding:7px;box-sizing:border-box;}',
      '.mshell-doctor-name{font-size:15px;font-weight:800;color:#fff;}',
      '.mshell-doctor-sub{font-size:11.5px;font-weight:600;color:#c7d2fe;margin-top:3px;}',
      '.mshell-doctor-tier{flex-shrink:0;font-size:10.5px;font-weight:800;color:#fff;',
      'border:1px solid rgba(255,255,255,.2);background:rgba(255,255,255,.12);',
      'border-radius:999px;padding:5px 10px;}',

      '.mshell-tiles{margin-top:12px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px;}',
      '.mshell-tile{display:flex;align-items:center;gap:10px;min-height:66px;padding:10px 12px;',
      'border-radius:20px;background:#fff;border:1.5px solid #eef2f7;',
      'box-shadow:0 6px 16px rgba(148,163,184,.14);cursor:pointer;text-decoration:none;',
      'text-align:start;font-family:inherit;color:inherit;}',
      '.mshell-tile:active{transform:scale(.98);}',
      '.mshell-tile-icon{width:40px;height:40px;flex-shrink:0;border-radius:14px;',
      'display:flex;align-items:center;justify-content:center;}',
      '.mshell-tile-label{font-size:13px;font-weight:800;color:#1e293b;line-height:1.25;}',
      '.mshell-tile-hint{font-size:10.5px;font-weight:600;color:#94a3b8;margin-top:2px;}',

      '.mshell-logout{margin-top:11px;width:100%;display:flex;align-items:center;',
      'justify-content:center;gap:9px;height:52px;border-radius:20px;background:#fff1f2;',
      'border:1.5px solid #fecdd3;color:#be123c;font-size:13.5px;font-weight:800;',
      'font-family:inherit;cursor:pointer;}',
      '.mshell-logout:active{transform:scale(.98);}',

      '.mshell-foot{margin-top:12px;text-align:center;font-size:10.5px;font-weight:600;color:#cbd5e1;}',

      '@media (prefers-reduced-motion: reduce){',
      '  #mobileShellSheet,#mobileShellBackdrop{transition:none !important;}',
      '}'
    ].join('\n');
    document.head.appendChild(style);
  }

  /* ------------------------------------------------------------------ */
  /* الشريط السفلي                                                       */
  /* ------------------------------------------------------------------ */

  function buildNav() {
    var page = activePage();
    var nav = document.createElement('nav');
    nav.id = 'mobileShellNav';
    nav.setAttribute('aria-label', 'التنقّل السريع');

    TABS.forEach(function (tab) {
      var a = document.createElement('a');
      a.className = 'mshell-tab';
      a.href = tab.href;
      var active = page === tab.href;
      if (active) {
        a.setAttribute('data-active', '1');
        a.setAttribute('aria-current', 'page');
      }
      a.innerHTML =
        svg(ICONS[tab.icon], 22, 'currentColor') + '<span>' + tab.label + '</span>';
      nav.appendChild(a);
    });

    var moreBtn = document.createElement('button');
    moreBtn.type = 'button';
    moreBtn.id = 'mobileShellMoreBtn';
    moreBtn.className = 'mshell-tab';
    moreBtn.setAttribute('aria-haspopup', 'dialog');
    moreBtn.setAttribute('aria-expanded', 'false');
    moreBtn.setAttribute('aria-controls', 'mobileShellSheet');
    moreBtn.innerHTML = svg(ICONS.more, 22, 'currentColor') + '<span>المزيد</span>';
    /* التبويب نشط أيضاً حين تكون الصفحة الحالية إحدى صفحات لوحة "المزيد". */
    var inSheet = SHEET_LINKS.some(function (item) {
      return item.href === page;
    });
    if (inSheet) moreBtn.setAttribute('data-active', '1');
    moreBtn.addEventListener('click', openSheet);
    nav.appendChild(moreBtn);

    document.body.appendChild(nav);
  }

  /* ------------------------------------------------------------------ */
  /* لوحة "المزيد"                                                       */
  /* ------------------------------------------------------------------ */

  function tile(config) {
    var tone = TONES[config.tone] || TONES.indigo;
    var el = document.createElement(config.href ? 'a' : 'button');
    el.className = 'mshell-tile';
    if (config.href) {
      el.href = config.href;
    } else {
      el.type = 'button';
      el.addEventListener('click', config.onClick);
    }
    el.innerHTML =
      '<span class="mshell-tile-icon" style="background:' + tone.bg + '">' +
      svg(ICONS[config.icon] || ICONS.action, 18, tone.color) +
      '</span>' +
      '<span style="flex-grow:1;min-width:0;">' +
      '<span class="mshell-tile-label" style="display:block;">' + config.label + '</span>' +
      (config.hint
        ? '<span class="mshell-tile-hint" style="display:block;">' + config.hint + '</span>'
        : '') +
      '</span>';
    return el;
  }

  /**
   * أزرار إضافية موجودة في الترويسة المكتبية لهذه الصفحة تحديداً (مثل
   * "نسخة احتياطية" في ملف المريض). تُستنسخ شكلاً فقط، والضغط عليها
   * يُمرَّر إلى الزر الأصلي حتى تبقى معالجاته الأصلية هي التي تعمل.
   */
  function extraHeaderButtons() {
    var out = [];
    var header = document.querySelector('header');
    if (!header) return out;

    Array.prototype.slice
      .call(header.querySelectorAll('button[id]'))
      .forEach(function (btn) {
        if (btn.id === 'logoutBtn' || btn.id === 'mobileMenuToggle') return;
        var known = KNOWN_BUTTONS[btn.id];
        var label = known ? known.label : (btn.textContent || '').trim();
        if (!label) return;
        out.push({
          label: label,
          hint: known ? known.hint : '',
          icon: known ? known.icon : 'action',
          tone: known ? known.tone : 'violet',
          onClick: function () {
            closeSheet();
            /* تأخير بسيط حتى تُغلق اللوحة قبل أن يفتح الزر الأصلي نافذته. */
            window.setTimeout(function () {
              btn.click();
            }, 180);
          }
        });
      });

    return out;
  }

  function firstText(ids, fallback) {
    for (var i = 0; i < ids.length; i++) {
      var el = document.getElementById(ids[i]);
      if (el && (el.textContent || '').trim()) return (el.textContent || '').trim();
    }
    return fallback;
  }

  function refreshDoctorCard() {
    if (!sheetEl) return;
    var nameEl = sheetEl.querySelector('.mshell-doctor-name');
    var tierEl = sheetEl.querySelector('.mshell-doctor-tier');
    if (nameEl) nameEl.textContent = firstText(['clinicTitle', 'mobileClinicTitle'], 'عيادة الطبيب');
    if (tierEl) tierEl.textContent = firstText(['tierBadge', 'mobileTierBadge'], 'Standard');
  }

  function buildSheet() {
    backdropEl = document.createElement('div');
    backdropEl.id = 'mobileShellBackdrop';
    backdropEl.hidden = true;
    backdropEl.addEventListener('click', closeSheet);
    document.body.appendChild(backdropEl);

    sheetEl = document.createElement('div');
    sheetEl.id = 'mobileShellSheet';
    sheetEl.setAttribute('role', 'dialog');
    sheetEl.setAttribute('aria-modal', 'true');
    sheetEl.setAttribute('aria-label', 'قائمة المزيد');
    sheetEl.hidden = true;

    var logoSrc = '';
    var logoImg = document.getElementById('mobileClinicLogoImg') || document.getElementById('clinicLogoImg');
    if (logoImg && logoImg.getAttribute('src')) logoSrc = logoImg.getAttribute('src');

    sheetEl.innerHTML = [
      '<div class="mshell-grabber"></div>',
      '<div class="mshell-doctor">',
      '  <div class="mshell-doctor-avatar">',
      logoSrc
        ? '    <img src="' + logoSrc + '" alt="شعار العيادة" />'
        : '    ' + svg(ICONS.profile, 24, '#e0e7ff'),
      '  </div>',
      '  <div style="flex-grow:1;min-width:0;">',
      '    <div class="mshell-doctor-name">عيادة الطبيب</div>',
      '    <div class="mshell-doctor-sub">لوحة تحكم العيادة</div>',
      '  </div>',
      '  <div class="mshell-doctor-tier">Standard</div>',
      '</div>',
      '<div class="mshell-tiles"></div>'
    ].join('\n');

    var tiles = sheetEl.querySelector('.mshell-tiles');

    SHEET_LINKS.forEach(function (item) {
      tiles.appendChild(tile(item));
    });
    extraHeaderButtons().forEach(function (item) {
      tiles.appendChild(tile(item));
    });

    var logout = document.createElement('button');
    logout.type = 'button';
    logout.className = 'mshell-logout';
    logout.innerHTML = svg(ICONS.logout, 18, 'currentColor') + '<span>تسجيل الخروج</span>';
    logout.addEventListener('click', function () {
      closeSheet();
      var original =
        document.getElementById('logoutBtn') || document.getElementById('mobileLogoutBtn');
      if (original) {
        window.setTimeout(function () {
          original.click();
        }, 150);
      }
    });
    sheetEl.appendChild(logout);

    var foot = document.createElement('div');
    foot.className = 'mshell-foot';
    foot.textContent = 'عيادة أسنان رقمية';
    sheetEl.appendChild(foot);

    document.body.appendChild(sheetEl);
  }

  function openSheet() {
    if (!sheetEl) return;
    refreshDoctorCard();
    backdropEl.hidden = false;
    sheetEl.hidden = false;
    document.body.style.overflow = 'hidden';
    /* إطار واحد قبل تشغيل الانتقال حتى لا تقفز اللوحة دون حركة. */
    window.requestAnimationFrame(function () {
      backdropEl.setAttribute('data-open', '1');
      sheetEl.setAttribute('data-open', '1');
    });
    var btn = document.getElementById('mobileShellMoreBtn');
    if (btn) btn.setAttribute('aria-expanded', 'true');
  }

  function closeSheet() {
    if (!sheetEl || sheetEl.hidden) return;
    backdropEl.removeAttribute('data-open');
    sheetEl.removeAttribute('data-open');
    document.body.style.overflow = '';
    var btn = document.getElementById('mobileShellMoreBtn');
    if (btn) btn.setAttribute('aria-expanded', 'false');
    window.setTimeout(function () {
      if (sheetEl.getAttribute('data-open') === '1') return;
      sheetEl.hidden = true;
      backdropEl.hidden = true;
    }, 260);
  }


  /* ------------------------------------------------------------------ */
  /* طبقة iOS                                                            */
  /* ------------------------------------------------------------------ */

  /* iPadOS 13+ يعرّف نفسه MacIntel، فيُكشف بعدد نقاط اللمس. */
  var IS_IOS = (function () {
    var ua = navigator.userAgent || '';
    if (/iPad|iPhone|iPod/.test(ua)) return true;
    return navigator.platform === 'MacIntel' && (navigator.maxTouchPoints || 0) > 1;
  })();

  function ensureMeta(name, content) {
    if (document.querySelector('meta[name="' + name + '"]')) return;
    var meta = document.createElement('meta');
    meta.setAttribute('name', name);
    meta.setAttribute('content', content);
    document.head.appendChild(meta);
  }

  function ensureLink(rel, href) {
    if (document.querySelector('link[rel="' + rel + '"]')) return;
    var link = document.createElement('link');
    link.setAttribute('rel', rel);
    link.setAttribute('href', href);
    document.head.appendChild(link);
  }

  /**
   * الإصلاح الأهمّ: `viewport-fit=cover`. Safari لا يعطي قيماً حقيقية لدوال
   * env(safe-area-inset-*) إلا بوجوده، ولذلك كانت حشوة مؤشر الصفحة معطّلة
   * تماماً على iPhone. يُنفَّذ فوراً عند تحميل السكربت -- أي قبل أن يُبنى
   * الشريط السفلي أدناه -- فيولد الشريط بقياسه الصحيح من أول رسم.
   */
  function applyIosPlatformFixes() {
    var root = document.documentElement;
    if (root.classList) root.classList.add('is-ios');
    else if ((' ' + root.className + ' ').indexOf(' is-ios ') === -1) root.className += ' is-ios';

    var viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.setAttribute('name', 'viewport');
      viewport.setAttribute('content', 'width=device-width, initial-scale=1');
      document.head.appendChild(viewport);
    }
    var content = viewport.getAttribute('content') || 'width=device-width, initial-scale=1';
    if (content.indexOf('viewport-fit') === -1) {
      viewport.setAttribute('content', content.replace(/[\s,]+$/, '') + ', viewport-fit=cover');
    }

    /* لون ترويسة الموقع نفسه (brand-950) يصبغ شريط Safari العلوي. */
    ensureMeta('theme-color', '#1e1b4b');
    ensureLink('apple-touch-icon', '/logo.png');
  }

  /**
   * تُحقن بعد injectStyles() حتى تتقدّم عليها في التتالي.
   * لا لون ولا خطّ ولا سطح جديد هنا: القيم كلها من tailwind.config.js وصفحات
   * الموقع (زجاج panel-soft، ‎#e2e8f0 للفواصل، ‎#ecfdf5 للتطابق، نصف قطر 22).
   */
  function injectIosStyles() {
    if (document.getElementById('ios-shell-styles')) return;
    var style = document.createElement('style');
    style.id = 'ios-shell-styles';
    style.textContent = [
      'html.is-ios{-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent;}',
      'html.is-ios a,html.is-ios button,html.is-ios [role="button"],html.is-ios label,',
      'html.is-ios input,html.is-ios select,html.is-ios textarea{touch-action:manipulation;}',
      'html.is-ios .overflow-x-auto,html.is-ios #desktopChartScroller{-webkit-overflow-scrolling:touch;}',

      /* التأثيرات المعلّقة: على اللمس لا يوجد "خروج بالمؤشر" فيبقى الزر مرفوعاً. */
      '@media (hover: none){',
      '  html.is-ios .btn-open-file:hover,html.is-ios .btn-delete-patient:hover,',
      '  html.is-ios .row-action-btn:hover,html.is-ios .mshell-tile:hover,',
      '  html.is-ios .sort-dropdown-trigger:hover{transform:none !important;}',
      '}',

      '@media (max-width: 767.98px){',

      /* أي حقل خطّه أصغر من 16px يجعل Safari يكبّر الصفحة عند اللمس. */
      '  html.is-ios input,html.is-ios select,html.is-ios textarea{font-size:17px !important;}',

      /* شريط التبويبات بقياس iOS: صف 49pt ملتصق بالحافة + مساحة المؤشر. */
      '  html.is-ios body{padding-bottom:calc(' + IOS_TAB_ROW_PX + 'px + env(safe-area-inset-bottom,0px)) !important;}',
      /* الشريط: هندسة iOS (ملتصق بالحافة، زوايا صفر، خطّ شعري، صف 49pt)
         مع الإبقاء على كبسولة التبويب النشط المتدرّجة كما هي في الموقع —
         الحشوة 3px فوق وتحت تعطيها متنفّساً داخل الصف. */
      '  html.is-ios #mobileShellNav{',
      '    border-radius:0;',
      '    border-top:0.5px solid rgba(255,255,255,.18);',
      '    padding:3px calc(6px + env(safe-area-inset-right,0px))',
      '      calc(3px + env(safe-area-inset-bottom,0px)) calc(6px + env(safe-area-inset-left,0px));',
      '    box-shadow:0 -8px 24px rgba(30,27,75,.22);',
      '  }',
      '  html.is-ios .mshell-tab{min-height:' + (IOS_TAB_ROW_PX - 6) + 'px;}',

      /* الزرّ العائم يستند إلى الشريط الجديد لا إلى 96px الثابتة. */
      '  html.is-ios #addPatientFab{bottom:calc(' + (IOS_TAB_ROW_PX + 12) + 'px + env(safe-area-inset-bottom,0px));}',

      /* الصفيحة: تحتجز التمرير ولا تدع الإصبع يمرّر الصفحة خلفها. */
      '  html.is-ios #mobileShellSheet{max-height:88dvh;overscroll-behavior:contain;',
      '    -webkit-overflow-scrolling:touch;',
      '    padding-bottom:calc(20px + env(safe-area-inset-bottom,0px));}',

      /* الترويسة الثابتة: حشوة الحافة الآمنة (تساوي صفراً في وضع التصفّح
         العادي، وتصبح لها قيمة في الوضع الأفقي وعلى الشاشة الرئيسية). */
      '  html.is-ios .ios-fixed-header{padding-top:env(safe-area-inset-top,0px);',
      '    padding-inline:env(safe-area-inset-left,0px) env(safe-area-inset-right,0px);}',

      /* القوائم: بطاقة مجمّعة واحدة بدل بطاقة لكل صف — بنفس زجاج
         panel-soft ونصف قطره، والفاصل يبدأ من بداية النصّ. */
      '  html.is-ios #patientsMobileList,html.is-ios #appointmentsTableBody,',
      '  html.is-ios #financeMovesList{',
      '    gap:0 !important;border-radius:22px;overflow:hidden;',
      '    background:rgba(255,255,255,.92);',
      '    -webkit-backdrop-filter:blur(12px);backdrop-filter:blur(12px);',
      '    border:1px solid rgba(255,255,255,.7);',
      '    box-shadow:0 10px 26px rgba(148,163,184,.18);}',
      '  html.is-ios #patientsMobileList:empty,html.is-ios #appointmentsTableBody:empty,',
      '  html.is-ios #financeMovesList:empty{display:none;}',
      '  html.is-ios .patient-card,html.is-ios .appointment-row,html.is-ios .fin-move{',
      '    margin:0 !important;border:0 !important;border-radius:0 !important;',
      '    background-color:transparent !important;box-shadow:none !important;}',

      /* الفاصل مرسوم كخلفية لا كعنصر ::before: صف المواعيد شبكة (grid)،
         وأي عنصر زائف داخله يصبح خلية فيها ويُزيح التخطيط. */
      '  html.is-ios .patient-card + .patient-card,',
      '  html.is-ios .appointment-row + .appointment-row,',
      '  html.is-ios .fin-move + .fin-move{',
      '    background-image:linear-gradient(#e2e8f0,#e2e8f0) !important;',
      '    background-repeat:no-repeat !important;background-position:top left !important;}',
      '  html.is-ios .patient-card + .patient-card{background-size:calc(100% - 68px) 1px !important;}',
      '  html.is-ios .appointment-row + .appointment-row{background-size:calc(100% - 85px) 1px !important;}',
      '  html.is-ios .fin-move + .fin-move{background-size:calc(100% - 60px) 1px !important;}',

      /* حالة التطابق في البحث كانت حلقة ظلّ + حدّاً، وقد أُلغيا أعلاه. */
      '  html.is-ios .patient-card[data-matched="1"]{background-color:#ecfdf5 !important;}',

      /* ---- شريط iOS العلوي ----
         الترويسة القديمة تُخفى (وتبقى في الـ DOM لأن لوحة "المزيد" تقرأ منها)،
         و body يأخذ حشوة = المساحة الآمنة العلوية، فيصير ارتفاع الشريط
         (المساحة + 44 + 52) مطابقاً لِـ pt-24 التي تحجزها كل صفحة. */
      '  html.is-ios .ios-fixed-header{display:none !important;}',
      '  html.is-ios body{padding-top:env(safe-area-inset-top,0px);}',
      /* زرّ + في الترويسة يحلّ محلّ الزرّ العائم وزرّ الإضافة المضمَّن. */
      '  html.is-ios #addPatientFab{display:none !important;}',
      '  html.is-ios.ios-has-nav-action #openModalBtn{display:none !important;}',

      '  #iosNavBar{position:fixed;inset-inline:0;top:0;z-index:65;color:#fff;',
      '    background:rgba(30,27,75,.92);',
      '    -webkit-backdrop-filter:saturate(180%) blur(24px);backdrop-filter:saturate(180%) blur(24px);',
      '    border-bottom:0.5px solid rgba(255,255,255,.14);',
      '    box-shadow:0 8px 24px rgba(30,27,75,.18);font-family:inherit;}',
      '  .ios-safetop{height:env(safe-area-inset-top,0px);}',
      '  .ios-navrow{height:44px;display:flex;align-items:center;gap:10px;',
      '    padding-left:calc(16px + env(safe-area-inset-left,0px));',
      '    padding-right:calc(16px + env(safe-area-inset-right,0px));}',
      '  .ios-nav-lead{flex:0 0 auto;display:flex;align-items:center;min-width:32px;}',
      '  .ios-nav-logo{width:30px;height:30px;border-radius:10px;object-fit:contain;',
      '    border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.1);',
      '    padding:4px;box-sizing:border-box;}',
      '  .ios-nav-back{display:inline-flex;align-items:center;gap:3px;color:#fff;',
      '    text-decoration:none;font-size:17px;font-weight:500;}',
      '  .ios-nav-title-small{flex:1 1 0;min-width:0;text-align:center;color:#fff;',
      '    font-size:17px;font-weight:600;letter-spacing:-.2px;opacity:0;',
      '    transition:opacity .18s ease;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}',
      '  #iosNavBar[data-collapsed="1"] .ios-nav-title-small{opacity:1;}',
      '  .ios-nav-actions{flex:0 0 auto;display:flex;align-items:center;justify-content:flex-end;',
      '    gap:6px;min-width:32px;}',
      '  .ios-nav-btn{width:32px;height:32px;display:flex;align-items:center;justify-content:center;',
      '    border:none;background:transparent;color:#fff;padding:0;cursor:pointer;',
      '    -webkit-tap-highlight-color:transparent;}',
      '  .ios-nav-btn:active{opacity:.55;}',
      '  .ios-nav-large{height:52px;overflow:hidden;display:flex;align-items:flex-end;',
      '    padding-left:16px;padding-right:16px;color:#fff;',
      '    font-family:"Noto Kufi Arabic","Segoe UI",Tahoma,system-ui,sans-serif;',
      '    font-size:30px;font-weight:700;letter-spacing:-.5px;',
      '    transition:height .24s ease,opacity .18s ease,transform .24s ease;}',
      '  .ios-nav-large > span{display:block;padding-bottom:6px;white-space:nowrap;',
      '    overflow:hidden;text-overflow:ellipsis;}',
      '  #iosNavBar[data-collapsed="1"] .ios-nav-large{height:0;opacity:0;transform:translateY(-8px);}',

      /* شارة المدّة بعد انتقالها إلى سطر الإجراء. */
      '  html.is-ios .ap-cell-proc .ap-time-badge{display:inline-block !important;',
      '    background:#eef2ff !important;color:#4338ca !important;font-size:10.5px !important;',
      '    font-weight:700 !important;padding:1px 7px !important;border-radius:999px !important;}',

      /* التنبيهات المنبثقة (#toast) عند top:20px وz-index 60 — أي تحت الشريط
         الجديد. ترتفع فوقه كما ترتفع لافتات iOS فوق شريط التنقّل. */
      '  html.is-ios #toast{z-index:70 !important;',
      '    top:calc(12px + env(safe-area-inset-top,0px)) !important;}',

      /* ---- لوحة "المزيد": صفوف إعدادات بعمود واحد بدل بلاطتين ---- */
      '  html.is-ios .mshell-tiles{grid-template-columns:minmax(0,1fr) !important;gap:0 !important;',
      '    background:#fff;border:1.5px solid #eef2f7;border-radius:20px;overflow:hidden;',
      '    box-shadow:0 6px 16px rgba(148,163,184,.14);}',
      '  html.is-ios .mshell-tile{min-height:56px;position:relative;padding-inline-end:36px;',
      '    border-radius:0 !important;border:0 !important;box-shadow:none !important;}',
      '  html.is-ios .mshell-tile + .mshell-tile{border-top:1px solid #eef2f7 !important;}',
      /* السهم يتّجه يساراً: حدّ يسار + أسفل مُدوَّران 45 درجة (حدود فيزيائية لا منطقية). */
      '  html.is-ios .mshell-tile::after{content:"";position:absolute;inset-inline-end:16px;top:50%;',
      '    width:8px;height:8px;border-left:2px solid #cbd5e1;border-bottom:2px solid #cbd5e1;',
      '    transform:translateY(-50%) rotate(45deg);}',

      /* ---- السحب للحذف ---- */
      '  html.is-ios #patientsMobileList{position:relative;}',
      '  html.is-ios .patient-card[data-swiping]{background-color:#fff !important;}',
      '  .ios-swipe-delete{position:absolute;left:0;width:96px;display:none;',
      '    flex-direction:column;align-items:center;justify-content:center;gap:3px;',
      '    border:none;background:linear-gradient(160deg,#f43f5e,#e11d48);color:#fff;',
      '    font-family:inherit;font-size:12px;font-weight:700;cursor:pointer;',
      '    -webkit-tap-highlight-color:transparent;}',

      '}',

      /* الشريط العلوي للجوال وحده: على iPad العريض تبقى الترويسة الأصلية. */
      '@media (min-width: 768px){#iosNavBar{display:none !important;}}'
    ].join('\n');
    document.head.appendChild(style);
  }

  /* الترويسة الثابتة للجوال لا تحمل id، وتُعرَف بزرّ الهامبرغر داخلها. */
  function markFixedHeader() {
    var toggle = document.getElementById('mobileMenuToggle');
    if (!toggle || !toggle.closest) return;
    var header = toggle.closest('div.fixed');
    if (header) header.classList.add('ios-fixed-header');
  }


  /* ------------------------------------------------------------------ */
  /* شريط iOS العلوي (عنوان كبير ينطوي عند التمرير)                      */
  /* ------------------------------------------------------------------ */

  /**
   * يحلّ محلّ الترويسة الثابتة للجوال (تُخفى بالـ CSS، وتبقى في الـ DOM لأن
   * لوحة "المزيد" تقرأ منها اسم العيادة والباقة).
   *
   * ارتفاعه = env(safe-area-inset-top) + 44 + 52. والصفحات الثماني كلّها
   * تحجز pt-24 (96px = 44+52) لترويستها القديمة، و body يأخذ حشوة علوية
   * تساوي المساحة الآمنة — فيطابق المحتوى أسفل الشريط بالضبط بلا أي تعديل
   * على أي صفحة.
   */
  function buildIosNavBar() {
    if (document.getElementById('iosNavBar')) return;
    var page = currentPage();
    var title = PAGE_TITLES[page];
    if (!title) return;

    var bar = document.createElement('header');
    bar.id = 'iosNavBar';

    var safe = document.createElement('div');
    safe.className = 'ios-safetop';
    bar.appendChild(safe);

    var row = document.createElement('div');
    row.className = 'ios-navrow';

    /* الجهة الأمامية: زرّ رجوع في الصفحات الفرعية، وشعار العيادة في غيرها. */
    var lead = document.createElement('div');
    lead.className = 'ios-nav-lead';
    var parent = PARENT_PAGES[page];
    if (parent) {
      var back = document.createElement('a');
      back.className = 'ios-nav-back';
      back.href = parent.href;
      back.innerHTML = svg(ICONS.back, 17, 'currentColor') + '<span>' + parent.label + '</span>';
      lead.appendChild(back);
    } else {
      var logoImg = document.getElementById('mobileClinicLogoImg') || document.getElementById('clinicLogoImg');
      var src = logoImg && logoImg.getAttribute('src');
      if (src) {
        var img = document.createElement('img');
        img.className = 'ios-nav-logo';
        img.src = src;
        img.alt = 'شعار العيادة';
        lead.appendChild(img);
      }
    }
    row.appendChild(lead);

    var small = document.createElement('div');
    small.className = 'ios-nav-title-small';
    small.textContent = title;
    row.appendChild(small);

    var actions = document.createElement('div');
    actions.className = 'ios-nav-actions';
    var action = PRIMARY_ACTIONS[page];
    if (action && document.getElementById(action.id)) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'ios-nav-btn';
      btn.setAttribute('aria-label', action.label);
      btn.innerHTML = svg(ICONS.plus, 24, 'currentColor');
      btn.addEventListener('click', function () {
        var original = document.getElementById(action.id);
        if (original) original.click();
      });
      actions.appendChild(btn);
      /* الزرّ المضمَّن في الصفحة يُخفى فقط بعد التأكّد أن بديله في الترويسة
         موجود فعلاً — فلا تبقى الصفحة بلا طريقة للإضافة أبداً. */
      document.documentElement.classList.add('ios-has-nav-action');
    }
    row.appendChild(actions);
    bar.appendChild(row);

    var large = document.createElement('div');
    large.className = 'ios-nav-large';
    large.innerHTML = '<span>' + title + '</span>';
    bar.appendChild(large);

    document.body.appendChild(bar);

    /* في ملف المريض يصير العنوان اسم المريض حين يصل من السيرفر. */
    if (page === 'patient_record.html') {
      var tries = 0;
      var timer = window.setInterval(function () {
        tries++;
        var el = document.getElementById('patientName');
        var name = el && (el.textContent || '').trim();
        /* الصفحة تبدأ بشُرطة نائبة (— أو --) قبل وصول البيانات. */
        if (name && !/^[-–—.\s]+$/.test(name)) {
          large.innerHTML = '<span>' + name + '</span>';
          small.textContent = name;
          window.clearInterval(timer);
        } else if (tries > 20) {
          window.clearInterval(timer);
        }
      }, 400);
    }

    /* الانطواء: العنوان الكبير يختفي ويظهر العنوان الصغير في الوسط. */
    var collapsed = false;
    var queued = false;
    function onScroll() {
      if (queued) return;
      queued = true;
      window.requestAnimationFrame(function () {
        queued = false;
        var next = (window.pageYOffset || document.documentElement.scrollTop || 0) > 24;
        if (next === collapsed) return;
        collapsed = next;
        if (collapsed) bar.setAttribute('data-collapsed', '1');
        else bar.removeAttribute('data-collapsed');
      });
    }
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  /* ------------------------------------------------------------------ */
  /* السحب للحذف في قائمة المرضى                                         */
  /* ------------------------------------------------------------------ */

  /**
   * اصطلاح iOS: إجراءات الصف تُكشف بالسحب لا بزرّ دائم. في العربية جهة
   * الكشف هي الحافة اليسرى، فالسحب يكون نحو اليمين.
   *
   * زرّ الحذف الأصلي في الصف يبقى ظاهراً كما هو (حتى لا يفقد الطبيب طريقة
   * الحذف المعروفة له)، والسحب يستدعيه بنفسه عبر .click() — فلا منطق حذف
   * مكرّر هنا ولا تعديل على الصفحة.
   */
  function enableSwipeToDelete() {
    var list = document.getElementById('patientsMobileList');
    if (!list || !('ontouchstart' in window)) return;

    var OPEN_PX = 96;
    var panel = null;
    var row = null;
    var candidate = null;
    var startX = 0, startY = 0, dx = 0;
    var engaged = false, opened = false;

    function ensurePanel() {
      if (panel) return panel;
      panel = document.createElement('button');
      panel.type = 'button';
      panel.className = 'ios-swipe-delete';
      panel.innerHTML = svg(ICONS.trash, 20, 'currentColor') + '<span>حذف</span>';
      panel.addEventListener('click', function () {
        var target = row;
        var original = target && target.querySelector('.patient-card-delete');
        close();
        if (original) window.setTimeout(function () { original.click(); }, 140);
      });
      list.appendChild(panel);
      return panel;
    }

    function place() {
      panel.style.top = row.offsetTop + 'px';
      panel.style.height = row.offsetHeight + 'px';
    }

    function close() {
      if (row) {
        row.style.transform = '';
        row.removeAttribute('data-swiping');
      }
      if (panel) panel.style.display = 'none';
      row = null;
      candidate = null;
      engaged = false;
      opened = false;
      dx = 0;
    }

    list.addEventListener('touchstart', function (event) {
      if (event.touches.length !== 1) return;
      var card = event.target && event.target.closest ? event.target.closest('.patient-card') : null;
      if (opened && card !== row) { close(); return; }
      if (!card || opened) return;
      candidate = card;
      startX = event.touches[0].clientX;
      startY = event.touches[0].clientY;
      engaged = false;
      dx = 0;
    }, { passive: true });

    list.addEventListener('touchmove', function (event) {
      if (!candidate || event.touches.length !== 1) return;
      var mx = event.touches[0].clientX - startX;
      var my = event.touches[0].clientY - startY;

      if (!engaged) {
        /* نية عمودية = تمرير الصفحة: نتخلّى عن الصف ولا نمنع الحركة. */
        if (Math.abs(my) > 10 && Math.abs(my) >= Math.abs(mx)) { candidate = null; return; }
        if (mx < 12 || mx < Math.abs(my) * 1.5) return;
        engaged = true;
        row = candidate;
        row.setAttribute('data-swiping', '1');
        ensurePanel();
        place();
        panel.style.display = 'flex';
      }

      dx = Math.max(0, Math.min(OPEN_PX + 20, mx));
      row.style.transform = 'translateX(' + dx + 'px)';
      if (event.cancelable) event.preventDefault();
    }, { passive: false });

    list.addEventListener('touchend', function () {
      if (!engaged || !row) { candidate = null; return; }
      if (dx > OPEN_PX / 2) {
        opened = true;
        engaged = false;
        candidate = null;
        row.style.transition = 'transform .18s ease';
        row.style.transform = 'translateX(' + OPEN_PX + 'px)';
        window.setTimeout(function () { if (row) row.style.transition = ''; }, 200);
      } else {
        close();
      }
    }, { passive: true });

    /* أي لمسة خارج الصف المفتوح تُعيده، وكذلك التمرير أو إعادة رسم القائمة. */
    document.addEventListener('touchstart', function (event) {
      if (!opened) return;
      var inside = event.target && event.target.closest &&
        (event.target.closest('.ios-swipe-delete') || event.target.closest('.patient-card') === row);
      if (!inside) close();
    }, { passive: true });
    window.addEventListener('scroll', function () { if (opened) close(); }, { passive: true });
    /* إعادة رسم القائمة تُغلق الصف المفتوح — مع تجاهل إضافة لوحة الحذف
       نفسها إلى القائمة، وإلا أغلق المراقبُ السحبةَ في اللحظة التي تُنشأ فيها. */
    if (window.MutationObserver) {
      new MutationObserver(function (records) {
        for (var i = 0; i < records.length; i++) {
          var nodes = [].concat(
            [].slice.call(records[i].addedNodes),
            [].slice.call(records[i].removedNodes)
          );
          for (var j = 0; j < nodes.length; j++) {
            if (nodes[j] !== panel) { close(); return; }
          }
        }
      }).observe(list, { childList: true });
    }
  }


  /* ------------------------------------------------------------------ */
  /* مدّة الموعد في السطر الثانوي                                        */
  /* ------------------------------------------------------------------ */

  /**
   * عمود الوقت على الجوال ضيّق (62px)، فشارة المدّة كانت تُخفى فيه وتضيع
   * المعلومة تماماً. هنا تُنقل الشارة نفسها — لا نسخة منها — إلى جانب اسم
   * الإجراء فتقرأ "تنظيف وتلميع · نصف ساعة" كما في لوحة التصميم.
   *
   * نقل العنصر بعينه (لا استنساخه) يعني أنه لا يظهر مرّتين على أي عرض،
   * ولا حاجة لأي تعديل على appointments.html. المراقب يعيد التطبيق بعد كل
   * تحديث تلقائي للقائمة (كل 30 ثانية) وبعد كل تغيير يوم.
   */
  function inlineAppointmentDuration() {
    var body = document.getElementById('appointmentsTableBody');
    if (!body) return;

    function apply() {
      var rows = body.querySelectorAll('.appointment-row');
      for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row.getAttribute('data-ios-duration') === '1') continue;
        row.setAttribute('data-ios-duration', '1');

        var badge = row.querySelector('.ap-time-badge');
        var proc = row.querySelector('.ap-cell-proc span:not(.ap-label)');
        if (!badge || !proc) continue;

        /* إجراء فارغ (—): المدّة وحدها أنفع من شُرطة. */
        if (/^[-–—\s]*$/.test(proc.textContent || '')) proc.textContent = '';
        else proc.appendChild(document.createTextNode(' '));
        proc.appendChild(badge);
      }
    }

    apply();
    if (window.MutationObserver) {
      new MutationObserver(apply).observe(body, { childList: true, subtree: true });
    }
  }

  function init() {
    /* صفحات لا تملك قائمة تنقّل أصلاً (تسجيل الدخول، الحجز العام...) */
    if (!document.getElementById('mobileMenuDropdown')) return;
    if (document.getElementById('mobileShellNav')) return;

    injectStyles();
    buildNav();
    buildSheet();

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') closeSheet();
    });
  }

  function boot() {
    init();
    /* أنماط iOS تُحقن بعد أنماط الغلاف حتى تتقدّم عليها في التتالي. */
    if (IS_IOS) {
      markFixedHeader();
      injectIosStyles();
      buildIosNavBar();
      enableSwipeToDelete();
      inlineAppointmentDuration();
    }
  }

  /* إصلاحات وسوم الرأس تسبق كل شيء: يجب أن يصحّ viewport قبل أن يُبنى
     الشريط السفلي، وإلا وُلد بحشوة مؤشر صفحة تساوي صفراً. */
  if (IS_IOS) {
    if (document.head) applyIosPlatformFixes();
    else document.addEventListener('DOMContentLoaded', applyIosPlatformFixes);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  window.MobileShell = { open: openSheet, close: closeSheet };
})();
