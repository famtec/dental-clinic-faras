/// نقطة الحقيقة الوحيدة للباقات في التطبيق -- 2026-09-14
/// =====================================================
/// توأم كتلة الباقات في `main.py` وملف `frontend_web/tier-access.js`. الثلاثة
/// يجب أن تبقى متطابقة المعنى: أي تعديل على مستويات الباقات يُطبَّق في
/// الثلاثة معاً.
///
/// القاعدة الملزمة: **لا تقارن الباقة بسلسلة نصية في أي شاشة.** استخدم
/// [ClinicTier.hasPremium] و [ClinicTier.hasDoctors] حصراً.
///
/// السبب ليس نظرياً: قبل هذا الملف كان التطبيق يكتب
/// `tier.toLowerCase() == 'premium'` في ثلاثة مواضع، فكان مشترك الباقة
/// الأعلى (premium_plus) يرى شارة "Standard" في الترويسة -- يدفع أكثر
/// ويُعرَض له أنه في أدنى باقة.
///
/// تنبيه أمني: هذا الملف يقرّر ما يُعرَض فقط، لا ما يُسمَح به. الحارس الفعلي
/// في الخادم (`require_premium_user_by_email` / `require_premium_doctor_user`)
/// ويرجع 403، وشاشة المخزن مثلاً تعتمد على ذلك الرد لا على فحص محلي --
/// وهو النمط الصحيح الذي يجب أن تتبعه أي شاشة مقيَّدة جديدة.
class ClinicTier {
  ClinicTier._();

  static const String premium = 'premium';
  static const String premiumPlus = 'premium_plus';

  /// "standard" لم تعد باقة تُباع (وُحِّدت الباقات 2026-09-14). تبقى مرادفاً
  /// قديماً يُترجم إلى premium -- رفعاً لا تخفيضاً: من اشترك سابقاً لا يجوز
  /// أن يرى صلاحيات أقل مما يراه مشترك اليوم.
  static const Map<String, String> _legacyAliases = {'standard': premium};

  static const Map<String, int> _levels = {premium: 1, premiumPlus: 2};

  static const Map<String, String> _badgeLabels = {
    premium: 'Premium',
    premiumPlus: 'Premium Plus',
  };

  static const Map<String, String> _arabicNames = {
    premium: 'الباقة الفخمة (Premium)',
    premiumPlus: 'باقة العيادات (Premium Plus)',
  };

  static String normalize(String? tier) {
    final value = (tier ?? '').trim().toLowerCase();
    return _legacyAliases[value] ?? value;
  }

  static int level(String? tier) => _levels[normalize(tier)] ?? 0;

  /// كل المزايا المدفوعة عدا إدارة الأطباء.
  static bool hasPremium(String? tier) => level(tier) >= 1;

  /// إدارة العيادة متعددة الأطباء وحساب النسب -- باقة العيادات وحدها.
  static bool hasDoctors(String? tier) => level(tier) >= 2;

  /// نص شارة الترويسة. لا يعيد "Standard" أبداً بعد التوحيد: الحسابات غير
  /// المفعّلة تُحجَب قبل الوصول لأي شاشة تعرض الشارة أصلاً.
  static String badgeLabel(String? tier) =>
      _badgeLabels[normalize(tier)] ?? 'غير مفعّلة';

  static String arabicName(String? tier) =>
      _arabicNames[normalize(tier)] ?? 'باقة غير مفعّلة';
}
