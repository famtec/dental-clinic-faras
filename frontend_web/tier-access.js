/*
 * tier-access.js -- نقطة الحقيقة الوحيدة للباقات في الواجهة (2026-09-14)
 * =====================================================================
 * توأم كتلة الباقات في main.py. القاعدة الملزمة هي نفسها هنا:
 * **لا تقارن الباقة بسلسلة نصية في أي صفحة.** استخدم ClinicTier.hasPremium()
 * و ClinicTier.hasDoctors() حصراً.
 *
 * السبب ليس نظرياً: قبل هذا الملف كانت تسع صفحات تكرّر `userTier === 'premium'`
 * بالمساواة الحرفية. إضافة باقة أعلى فوق ذلك النمط كانت ستُنتج خللاً صامتاً
 * في كل صفحة على حدة -- مشترك "باقة العيادات" يدفع أكثر ثم يجد المخزن
 * مقفلاً أمامه لأنه ببساطة لا يساوي السلسلة "premium".
 *
 * ملاحظة أمنية: هذا الملف يقرّر ما يُعرَض فقط، لا ما يُسمَح به. الحارس
 * الفعلي في main.py (require_premium_user_by_email / require_premium_doctor_user)
 * ولا يُغني هذا عنه إطلاقاً -- تعديل localStorage في المتصفح لا يفتح شيئاً.
 */
(function () {
  'use strict';

  var TIER_PREMIUM = 'premium';
  var TIER_PREMIUM_PLUS = 'premium_plus';

  /* "standard" لم تعد باقة تُباع (وُحِّدت الباقات 2026-09-14). تبقى مرادفاً
     قديماً يُترجم إلى premium -- رفعاً لا تخفيضاً: من اشترك سابقاً لا يجوز
     أن يرى صلاحيات أقل مما يراه مشترك اليوم. */
  var LEGACY_ALIASES = { standard: TIER_PREMIUM };

  var LEVELS = {};
  LEVELS[TIER_PREMIUM] = 1;
  LEVELS[TIER_PREMIUM_PLUS] = 2;

  var BADGE_LABELS = {};
  BADGE_LABELS[TIER_PREMIUM] = 'Premium';
  BADGE_LABELS[TIER_PREMIUM_PLUS] = 'Premium Plus';

  var ARABIC_NAMES = {};
  ARABIC_NAMES[TIER_PREMIUM] = 'الباقة الفخمة (Premium)';
  ARABIC_NAMES[TIER_PREMIUM_PLUS] = 'باقة العيادات (Premium Plus)';

  function normalize(tier) {
    var value = String(tier == null ? '' : tier).trim().toLowerCase();
    return LEGACY_ALIASES[value] || value;
  }

  function level(tier) {
    return LEVELS[normalize(tier)] || 0;
  }

  function currentTier() {
    try {
      return localStorage.getItem('user_tier') || '';
    } catch (err) {
      return '';
    }
  }

  window.ClinicTier = {
    PREMIUM: TIER_PREMIUM,
    PREMIUM_PLUS: TIER_PREMIUM_PLUS,
    normalize: normalize,
    level: level,
    current: currentTier,

    /* كل المزايا المدفوعة عدا إدارة الأطباء. */
    hasPremium: function (tier) {
      return level(arguments.length ? tier : currentTier()) >= 1;
    },

    /* إدارة العيادة متعددة الأطباء وحساب النسب -- باقة العيادات وحدها. */
    hasDoctors: function (tier) {
      return level(arguments.length ? tier : currentTier()) >= 2;
    },

    /* نص الشارة في الترويسة. لا يعيد "Standard" أبداً بعد التوحيد. */
    badgeLabel: function (tier) {
      var key = normalize(arguments.length ? tier : currentTier());
      return BADGE_LABELS[key] || 'غير مفعّلة';
    },

    arabicName: function (tier) {
      var key = normalize(arguments.length ? tier : currentTier());
      return ARABIC_NAMES[key] || 'باقة غير مفعّلة';
    }
  };
})();

/*
 * ClinicActivation.confirmReplacement -- تنبيه قبل إدخال رمز تفعيل (2026-09-25)
 * ============================================================================
 * الرمز الجديد يحلّ محلّ القديم على الخادم (apply_activation_key في main.py):
 * أيام الاشتراك السارية تسقط والمدة الجديدة تبدأ من اليوم. قبل أي ترقية أو
 * تجديد تسأل الصفحة الخادمَ (/api/auth/activation-preview) عمّا سيحدث، فإن
 * كان هناك اشتراك سارٍ تعرض رسالته الجاهزة وتنتظر تأكيد الطبيب.
 *
 * يعيد Promise<boolean>: true = تابِع، false = ألغى الطبيب. تعذّر المعاينة
 * (شبكة، رمز خاطئ) لا يوقف شيئاً: الطلب الفعلي بعدها يعرض خطأه كالمعتاد.
 */
(function () {
  'use strict';

  function endpoint() {
    return typeof window.apiUrl === 'function'
      ? window.apiUrl('/api/auth/activation-preview')
      : '/api/auth/activation-preview';
  }

  function showConfirm(message) {
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.setAttribute('role', 'dialog');
      overlay.setAttribute('aria-modal', 'true');
      overlay.style.cssText =
        'position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;' +
        'padding:16px;background:rgba(15,12,40,.55);backdrop-filter:blur(3px);direction:rtl;';
      var card = document.createElement('div');
      card.style.cssText =
        'width:100%;max-width:440px;background:#fff;color:#1e1b3a;border-radius:20px;padding:22px 22px 18px;' +
        'box-shadow:0 24px 60px rgba(30,24,80,.35);font-family:inherit;text-align:right;';
      var title = document.createElement('div');
      title.textContent = 'تنبيه قبل التفعيل';
      title.style.cssText = 'font-size:17px;font-weight:800;margin-bottom:10px;color:#b45309;';
      var body = document.createElement('div');
      body.textContent = message;
      body.style.cssText = 'font-size:14px;line-height:1.9;color:#374151;margin-bottom:18px;';
      var actions = document.createElement('div');
      actions.style.cssText = 'display:flex;gap:10px;justify-content:flex-start;';
      var ok = document.createElement('button');
      ok.type = 'button';
      ok.textContent = 'متابعة التفعيل';
      ok.style.cssText =
        'border:0;border-radius:12px;padding:10px 18px;font-weight:800;font-size:14px;cursor:pointer;color:#fff;' +
        'background:linear-gradient(135deg,#6d28d9,#4f46e5);font-family:inherit;';
      var cancel = document.createElement('button');
      cancel.type = 'button';
      cancel.textContent = 'إلغاء';
      cancel.style.cssText =
        'border:1px solid #d1d5db;border-radius:12px;padding:10px 18px;font-weight:700;font-size:14px;' +
        'cursor:pointer;background:#fff;color:#374151;font-family:inherit;';
      actions.appendChild(ok);
      actions.appendChild(cancel);
      card.appendChild(title);
      card.appendChild(body);
      card.appendChild(actions);
      overlay.appendChild(card);

      function close(result) {
        document.removeEventListener('keydown', onKey, true);
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
        resolve(result);
      }
      function onKey(e) {
        if (e.key === 'Escape') { e.preventDefault(); close(false); }
      }
      ok.addEventListener('click', function () { close(true); });
      cancel.addEventListener('click', function () { close(false); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(false); });
      document.addEventListener('keydown', onKey, true);
      document.body.appendChild(overlay);
      cancel.focus();
    });
  }

  window.ClinicActivation = {
    confirmReplacement: function (activationCode, email) {
      return fetch(endpoint(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          activation_code: String(activationCode || '').trim(),
          email: String(email || '').trim().toLowerCase() || null
        })
      })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (data) {
          if (!data || !data.will_cancel_previous || !data.message) return true;
          return showConfirm(data.message);
        })
        .catch(function () { return true; });
    }
  };
})();

/* ============================================================================
 * دور الحساب (2026-09-25): مالك العيادة أو طبيب مساعد بحساب دخول خاص.
 *
 * للعرض فقط -- الصلاحيات الفعلية يفرضها الخادم (StaffAccessMiddleware في
 * main.py) ويرفض كل ما ليس للمساعد بـ 403. هنا نمنع المساعد من رؤية ما
 * سيُرفض: صفحات المالك تُحوَّل إلى المرضى، وروابطها وأزرار المال تُخفى.
 * ========================================================================== */
(function () {
  var OWNER_ONLY_PAGES = [
    'finance.html', 'inventory.html', 'doctors.html',
    'treatment_catalog.html', 'profile.html', 'qr.html'
  ];

  function read(key) {
    try {
      return localStorage.getItem(key) || '';
    } catch (e) {
      return '';
    }
  }

  var staff = read('user_role') === 'staff';

  window.ClinicRole = {
    isStaff: function () { return staff; },
    staffDoctorId: function () { return staff ? read('staff_doctor_id') : ''; },
    ownerOnlyPage: function (href) {
      return OWNER_ONLY_PAGES.indexOf(String(href || '').toLowerCase()) !== -1;
    }
  };

  if (!staff) return;

  var page = (window.location.pathname.split('/').pop() || 'index.html').toLowerCase();
  if (OWNER_ONLY_PAGES.indexOf(page) !== -1) {
    window.location.replace('index.html');
    return;
  }

  document.documentElement.classList.add('is-staff');
  var hidden = OWNER_ONLY_PAGES.map(function (p) { return 'html.is-staff a[href="' + p + '"]'; }).concat([
    'html.is-staff #backupBtn',
    'html.is-staff #restoreBackupBtn',
    'html.is-staff [data-owner-only]',
    'html.is-staff form[data-invoice-payment-form]',
    'html.is-staff .invoice-cost-edit-btn',
    'html.is-staff .invoice-cost-delete-btn',
    'html.is-staff .invoice-payment-edit-btn',
    'html.is-staff .invoice-payment-delete-btn',
    'html.is-staff [data-delete-invoice-material]',
    'html.is-staff .finance-edit-btn',
    'html.is-staff .finance-delete-btn'
  ]);
  var style = document.createElement('style');
  style.textContent = hidden.join(',\n') + ' { display: none !important; }\n' +
    'html:not(.is-staff) [data-staff-only] { display: none !important; }';
  (document.head || document.documentElement).appendChild(style);
})();
