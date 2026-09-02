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
 */
(function () {
  'use strict';

  var NAV_HEIGHT_PX = 86;

  var ICONS = {
    patients:
      '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>',
    appointments:
      '<rect x="3" y="4" width="18" height="18" rx="2"></rect><path d="M16 2v4"></path><path d="M8 2v4"></path><path d="M3 10h18"></path>',
    finance:
      '<line x1="18" y1="20" x2="18" y2="10"></line><line x1="12" y1="20" x2="12" y2="4"></line><line x1="6" y1="20" x2="6" y2="14"></line>',
    inventory:
      '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path><polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline><line x1="12" y1="22.08" x2="12" y2="12"></line>',
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
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><polyline points="16 17 21 12 16 7"></polyline><line x1="21" y1="12" x2="9" y2="12"></line>'
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
    { href: 'profile.html', label: 'حسابي', hint: 'بيانات العيادة', icon: 'profile', tone: 'indigo' },
    { href: 'qr.html', label: 'رمز الحجز', hint: 'مشاركة QR', icon: 'qr', tone: 'cyan' },
    { href: 'contact_developer.html', label: 'تواصل مع المطور', hint: 'دعم فني', icon: 'developer', tone: 'pink' }
  ];

  /* أزرار الترويسة المعروفة، لإعطائها أيقونة ووصفاً مناسبين عند استنساخها. */
  var KNOWN_BUTTONS = {
    backupBtn: { label: 'نسخة احتياطية', hint: 'تصدير البيانات', icon: 'backup', tone: 'cyan' },
    restoreBackupBtn: { label: 'استرجاع نسخة', hint: 'استيراد ملف', icon: 'restore', tone: 'emerald' }
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.MobileShell = { open: openSheet, close: closeSheet };
})();
