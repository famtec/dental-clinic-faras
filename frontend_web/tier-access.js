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
