import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هوية بصرية موحّدة للتطبيق -- نفس الألوان والتدرجات المستخدمة تماماً في
/// موقع العيادة (frontend_web/login.html و appointments.html وغيرها)، حتى
/// يشعر الطبيب أن التطبيق والموقع واجهتان لنظام واحد. لا تُضف ألوان جديدة
/// هنا بمعزل عن الموقع -- أي عنصر جديد يجب أن يستعير من نفس هذه اللوحة.
class AppColors {
  AppColors._();

  // هوية التدرج الأساسية (الرأس، الخلفيات الداكنة، الأزرار الرئيسية).
  static const navy900 = Color(0xFF1E1B4B);
  static const indigo800 = Color(0xFF312E81);
  static const indigo700 = Color(0xFF3730A3);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigoAccent = Color(0xFF4338CA);
  static const violet700 = Color(0xFF6D28D9);
  static const violet600 = Color(0xFF7C3AED);

  // الأخضر (نجاح / دفعات / تأكيد).
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald700text = Color(0xFF065F46);

  // الكهرماني (تنبيهات / قيد الانتظار).
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber800text = Color(0xFF92400E);
  static const amber900text = Color(0xFFB45309);
  // 2026-08-31: amber-900 الحقيقي في Tailwind (amber900text أعلاه قيمته
  // فعلياً amber-700 رغم اسمها -- أُبقيت كما هي دون تعديل تفادياً لكسر أي
  // استخدام قائم لها، وأُضيف هذا اللون الجديد بدلاً من إعادة تسميتها).
  // مستخدَم في عنوان لوحة "طلبات حجز جديدة" (bookingRequestsSection) لمطابقة
  // text-amber-900 في appointments.html بالموقع بدقّة.
  static const amber900 = Color(0xFF78350F);

  // الوردي/الأحمر (إلغاء / تخلف / نقص مخزون).
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  // 2026-08-30: rose500/red600 -- نفس لوني تدرّج أزرار "رفض"/"حذف" الحمراء
  // المملوءة في الموقع (from-rose-500 to-red-600 في appointments.html/
  // patient_record.html)، أُضيفا لبناء dangerButtonGradient أدناه.
  static const rose500 = Color(0xFFF43F5E);
  static const red600 = Color(0xFFDC2626);
  static const rose700text = Color(0xFFBE123C);
  static const rose800text = Color(0xFF9F1239);

  // البنفسجي (الوصفات الطبية).
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple200 = Color(0xFFE9D5FF);
  static const purple600 = Color(0xFF9333EA);

  // درجات الرمادي/السلايت (نصوص وحدود عامة).
  static const slate900 = Color(0xFF1E293B);
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate100 = Color(0xFFF1F5F9);
  static const pageBg = Color(0xFFF8FAFC);
  static const indigo50 = Color(0xFFEEF2FF);
  // 2026-08-30: indigo100/indigo200 -- درجتا الإندگو الفاتحتان المستخدمتان في
  // خلفية/حدود كبسولة أزرار appointment-action-btn (تعديل/حذف) في
  // appointments.html بالموقع (eef2ff -> e0e7ff بحدود c7d2fe)، بعد توحيد
  // الموقع لتصميم هذين الزرين 2026-08-29 على نفس عائلة الإندگو بدل التدرج
  // الأحمر/الأخضر الصريح السابق.
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  // emerald200 + emerald700 (Tailwind emerald-700 الحقيقي #047857) -- لون
  // حدود/نص زر "تذكير واتساب" appointment-action-btn في الموقع تماماً. لا
  // علاقة لها بـ emerald700text القائم أصلاً (قيمته 065F46 فعلياً، وهي
  // emerald-800 رغم الاسم، ومستخدَمة في سياقات أخرى غير هذا الزر -- تُركت
  // كما هي دون تعديل).
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald700 = Color(0xFF047857);

  // 2026-08-30: ألوان بطاقات نافذة "تحديث حالة السن" الثماني (تسوس/حشوة/
  // فينير/تاج تلبيسة/لبية عصب/جسر/زراعة/مقلوع) -- منقولة بالحرف من ألوان
  // Tailwind الفعلية لهذه البطاقات في toothStatusModal بـ patient_record.html
  // بالموقع (كل بطاقة bg-*-50 + border-*-200|300 + text-*-700)، حتى تُطابق
  // شبكة البطاقات الملوّنة الجديدة في نافذة اختيار حالة السن بالتطبيق تصميم
  // الموقع تماماً. لا علاقة لهذه الألوان بألوان النقاط التمييزية
  // (decay/filling/...) في dental_chart.dart، فتلك بالفعل مطابقة أصلاً.
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red700 = Color(0xFFB91C1C);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue700 = Color(0xFF1D4ED8);
  static const amber300 = Color(0xFFFCD34D);
  static const amber700 = Color(0xFFB45309);
  static const purple700 = Color(0xFF7E22CE);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange300 = Color(0xFFFDBA74);
  static const orange700 = Color(0xFFC2410C);
  static const pink50 = Color(0xFFFDF2F8);
  static const pink200 = Color(0xFFFBCFE8);
  static const pink700 = Color(0xFFBE185D);
  static const slate700 = Color(0xFF334155);

  // السماوي (توهّج التبويب النشط في شريط التنقل السفلي + شارات "Live") --
  // مضاف بعد تدقيق تصميم الموقع 2026-08-29: كان غائباً عن لوحة التطبيق رغم
  // أنه لون التمييز الأساسي لكل عنصر تنقل نشط في نسخة الويب.
  static const cyan300 = Color(0xFF67E8F9);
  static const cyan400 = Color(0xFF22D3EE);
  // 2026-08-31: cyan500 -- Tailwind cyan-500 الحقيقي (#06B6D4)، مستخدَم في
  // شريط قوة كلمة المرور (password strength bar) بمرحلة "جيدة" في
  // register.html بالموقع تماماً (bg-cyan-500). لا علاقة له بـ cyan400
  // القائم أصلاً (توهّج التبويب النشط).
  static const cyan500 = Color(0xFF06B6D4);

  // 2026-08-31: مجموعة ألوان جديدة لإعادة تصميم شاشتَي تسجيل الدخول/تفعيل
  // الحساب في تطبيق الجوال لتطابق login.html/register.html بالموقع بالحرف --
  // منقولة مباشرة من قيم Tailwind الفعلية المستخدمة في هذين الملفين
  // (حقول الإدخال، شريط قوة كلمة المرور، تنبيه Caps Lock).
  static const indigo500 = Color(0xFF6366F1); // focus:border-indigo-500
  static const rose400 = Color(0xFFFB7185); // شريط القوة: ضعيفة
  static const rose600 = Color(0xFFE11D48); // نص "كلمة المرور ضعيفة"
  static const amber400 = Color(0xFFFBBF24); // شريط القوة: متوسطة
  static const amber600 = Color(0xFFD97706); // نص "Caps Lock مفعل" + "متوسطة"

  /// تدرّج رأس بطاقة تسجيل الدخول/التفعيل الأبيض -- مطابق تماماً لِـ
  /// bg-gradient-to-r from-indigo-900 via-indigo-800 to-violet-700 في
  /// login.html/register.html بالموقع (فيزيائياً القيمة الأولى تظهر يساراً
  /// والأخيرة يميناً بغضّ النظر عن اتجاه RTL، تماماً كما تُرسم في CSS).
  static const authCardHeaderGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [indigo800, indigo700, violet700],
  );

  /// خلفية شريط التنقل السفلي الزجاجية الداكنة -- نفس عمق [navy900] لكن
  /// بتدرّج رأسي خفيف يحاكي أسلوب الهيدر العلوي/القائمة المنسدلة في الموقع
  /// (bg-[#1e1b4b]/85 + backdrop-blur).
  static const bottomNavGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xE61E1B4B), Color(0xF7141238)],
  );

  /// تدرّج بطاقة "Smart Stat" الزجاجية الداكنة المتوهّجة -- مطابق تماماً
  /// لبطاقات الإحصاء في index.html بالموقع (كحلي شبه أسود -> إنديغو ->
  /// بنفسجي غامق بزاوية قطرية).
  static const smartStatGradient = LinearGradient(
    begin: Alignment(-0.85, -1),
    end: Alignment(0.85, 1),
    colors: [Color(0xFF0F0D2B), indigoAccent, Color(0xFF4C1D95)],
  );

  static const heroGradient = LinearGradient(
    begin: Alignment(-0.9, -1),
    end: Alignment(0.9, 1),
    colors: [navy900, indigo800, violet700],
  );

  /// كبسولة التبويب النشط في الشريط السفلي -- مطابقة لـ
  /// linear-gradient(160deg, rgba(99,102,241,.95), rgba(139,92,246,.9))
  /// في ‎.mshell-tab[data-active="1"] بالموقع. `final` لا `const` لأن
  /// withValues() ليست ثابتة وقت الترجمة.
  static final navActiveGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      const Color(0xFF6366F1).withValues(alpha: .95),
      const Color(0xFF8B5CF6).withValues(alpha: .90),
    ],
  );

  static const primaryButtonGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [indigo600, violet600],
  );

  static const successButtonGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [emerald500, emerald600],
  );

  /// تدرّج أزرار "رفض"/"تخلّف عن الموعد" المملوءة -- مطابق تماماً لأزرار
  /// accept-request-btn/reject-request-btn في appointments.html بالموقع
  /// (from-rose-500 to-red-600)، أُضيف 2026-08-30 لاستبدال الزر المحدَّد
  /// الفارغ الذي كان مستخدَماً سابقاً في AppointmentActionButtons ولا يطابق
  /// تصميم الموقع الفعلي لهذه الأزرار.
  static const dangerButtonGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [rose500, red600],
  );

  static const loginBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy900, indigo800, Color(0xFF5B21B6)],
  );

  /// تدرّج خلفية كبسولتَي "تعديل"/"حذف" الفاتحتين -- مطابق تماماً لِـ
  /// .btn-edit-appointment/.btn-delete-appointment في appointments.html
  /// بالموقع (from #eef2ff to #e0e7ff)، أُضيف 2026-08-30 لتطبيق شكل الموقع
  /// نفسه على أزرار إجراءات بطاقة الموعد في تبويب "المواعيد" بالتطبيق.
  static const appointmentUtilityGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [indigo50, indigo100],
  );

  /// تدرّج خلفية كبسولة "تذكير واتساب" الفاتحة -- مطابق تماماً لِـ
  /// .btn-whatsapp-reminder في appointments.html بالموقع (from #ecfdf5 to
  /// #d1fae5)، نفس تاريخ الإضافة أعلاه.
  static const appointmentWhatsappGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [emerald50, emerald100],
  );

  /// تدرّج خلفية زر "رفض" الفاتح -- مطابق تماماً لِـ .btn-reject-request في
  /// appointments.html بالموقع (from #fff1f2 to #ffe4e6). أُضيف 2026-08-31
  /// لبطاقات "طلبات حجز جديدة" الجديدة في تبويب "المواعيد" بالتطبيق --
  /// الحالة الافتراضية الحقيقية لهذا الزر بالموقع هي كبسولة فاتحة كهذه، لا
  /// التدرج المملوء الأحمر (ذاك فقط حالة :hover لماوس سطح مكتب، لا تنطبق
  /// على تطبيق جوّال باللمس).
  static const appointmentRejectGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [rose50, rose100],
  );
}

/// ───────────────────────────────────────────────────────────────────────────
/// نظام «الليل النيلي» -- بنية واحدة، وضعان لونيان (2026-09-05)
/// ───────────────────────────────────────────────────────────────────────────
///
/// المستخدم اختار اتجاه «الليل النيلي» ثم طلب صراحةً: «لنجعله للوضع الليلي،
/// أما النهاري فأريده نفس التصميم تماماً بالضبط ولكن بألوان فاتحة وخلفية
/// بيضاء». لذلك لا يوجد هنا تصميمان بل **جدول تحويل ألوان** لبنية واحدة:
/// نفس المقاسات، نفس أنصاف الأقطار، نفس الحركات، ويتبدّل اللون وحده.
///
/// كل قيمة تعتمد على الوضع تعيش في [AppSurface] (ThemeExtension)، لا في
/// [AppColors]. ثوابت [AppColors] القديمة **لم تُمَسّ إطلاقاً** حتى تبقى كل
/// الشاشات التي لم تُهاجَر بعد تعمل حرفياً كما كانت -- الهجرة تجري شاشةً
/// شاشة، ومن يقرأ AppSurface يحصل على الوضعين، ومن يقرأ AppColors يبقى
/// فاتحاً كما كان. لا تُضِف لوناً يعتمد على الوضع إلى AppColors.
///
/// الوصول: `context.surface` (انظر الامتداد أسفل الملف). لا تستعمل
/// `Theme.of(context).extension<AppSurface>()!` مباشرةً -- الامتداد يرجع
/// النسخة الفاتحة عند الغياب بدل الانهيار.
@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  /// للتفريع النادر الذي لا يمكن التعبير عنه بتوكن (مثل اختيار Brightness
  /// لشريط الحالة). لا تستعمله لاختيار ألوان -- أضِف توكناً بدلاً من ذلك.
  final bool isDark;

  // خلفية الصفحة وكرات الضوء الثلاث (AtmosphereBackground).
  final Color pageBg;
  final Color orb1;
  final Color orb2;
  final Color orb3;

  // البطاقات العادية (SectionCard، بطاقة المريض، بطاقة الموعد...).
  final Color cardBg;
  final Color cardBorder;
  final Color cardBorderActive;
  final List<BoxShadow> cardShadow;

  // بطاقة الرأس (الرقم المالي + صفّ العدّادين) -- نفس البنية في الوضعين.
  final Color heroBg;
  final Color heroBorder;
  final List<BoxShadow> heroShadow;

  /// لون اللمعة التي تمرّ فوق بطاقة الرأس. أبيض شفاف ليلاً (تلمع على
  /// الزجاج الداكن)، نيليّ شفاف نهاراً (اللمعة البيضاء تختفي على الأبيض).
  final Color sheen;
  final Color heroWash;

  // النصوص.
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color heroCaption;
  final Color bigNumber;
  final Color bigNumberUnit;

  /// توهّج خلف الرقم الكبير -- ليلاً فقط؛ نهاراً null (لا معنى للتوهّج على
  /// الأبيض، والوزن يأتي من اللون نفسه).
  final Color? bigNumberGlow;

  // التمييز: سماوي ← نيلي في الوضعين. الفارق أن السلّم النهاري أغمق لأن
  // السماوي الفاتح على أبيض لا يحمل نصّاً مقروءاً (تباين أقل من 3:1).
  final LinearGradient accentGradient;

  /// لون النص/الأيقونة فوق [accentGradient]: داكن ليلاً، أبيض نهاراً.
  final Color onAccent;
  final Color accentGlow;
  final Color accentSolid;

  // صناديق الأيقونات الصغيرة داخل البطاقات.
  final Color iconBoxBg;
  final Color iconBoxBorder;
  final Color iconBoxFg;

  /// الفواصل الرفيعة (الحدّ العلوي لصفّ العدّادين، والفاصل الرأسي بينهما).
  final Color divider;

  // النقطة "الحيّة" النابضة بجانب عنوان بطاقة الرأس.
  final Color liveDot;
  final Color liveDotHalo;

  // الشريط السفلي العائم.
  final Color navBg;
  final Color navBorder;
  final List<BoxShadow> navShadow;
  final Color navInactive;

  // شرائح التصفية في حالتها الساكنة (النشطة تستعمل accentGradient).
  final Color chipBg;
  final Color chipBorder;
  final Color chipFg;

  // أزرار الإجراءات المربّعة داخل البطاقات (فتح الملف / اتصال / تعديل...).
  final Color actionBg;
  final Color actionBorder;

  // شارة الباقة.
  final Color tierFg;
  final Color tierBg;
  final Color tierBorder;

  // شارات الحالة المالية على بطاقة المريض.
  final Color pillDueFg;
  final Color pillDueBg;
  final Color pillDueBorder;
  final Color pillPaidFg;
  final Color pillPaidBg;
  final Color pillPaidBorder;
  final Color pillNoneFg;
  final Color pillNoneBg;
  final Color pillNoneBorder;

  // حقل البحث.
  final Color fieldBg;
  final Color fieldBorder;
  final Color fieldHint;

  /// خلفية الأوراق السفلية (bottom sheets) والنوافذ. **سطح مصمت لا زجاجي**:
  /// الورقة تطفو فوق طبقة تعتيم، والزجاج الشفّاف فوق تعتيم يعطي لوناً موحلاً
  /// ويُظهر المحتوى تحته مشوّشاً خلف النموذج.
  final Color sheetBg;

  /// السطح الكهرماني للتنبيهات القائمة بذاتها -- لوحة "طلبات حجز جديدة"
  /// أساساً. amber-50 المصمت يصير بقعة كريمية على سطح ‎#07061A، فالنسخة
  /// الليلية شفافية من نفس الكهرمان لا درجة فاتحة ثابتة.
  final Color warnBg;
  final Color warnBorder;
  final Color warnFg;

  const AppSurface({
    required this.isDark,
    required this.pageBg,
    required this.orb1,
    required this.orb2,
    required this.orb3,
    required this.cardBg,
    required this.cardBorder,
    required this.cardBorderActive,
    required this.cardShadow,
    required this.heroBg,
    required this.heroBorder,
    required this.heroShadow,
    required this.sheen,
    required this.heroWash,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.heroCaption,
    required this.bigNumber,
    required this.bigNumberUnit,
    required this.bigNumberGlow,
    required this.accentGradient,
    required this.onAccent,
    required this.accentGlow,
    required this.accentSolid,
    required this.iconBoxBg,
    required this.iconBoxBorder,
    required this.iconBoxFg,
    required this.divider,
    required this.liveDot,
    required this.liveDotHalo,
    required this.navBg,
    required this.navBorder,
    required this.navShadow,
    required this.navInactive,
    required this.chipBg,
    required this.chipBorder,
    required this.chipFg,
    required this.actionBg,
    required this.actionBorder,
    required this.tierFg,
    required this.tierBg,
    required this.tierBorder,
    required this.pillDueFg,
    required this.pillDueBg,
    required this.pillDueBorder,
    required this.pillPaidFg,
    required this.pillPaidBg,
    required this.pillPaidBorder,
    required this.pillNoneFg,
    required this.pillNoneBg,
    required this.pillNoneBorder,
    required this.fieldBg,
    required this.fieldBorder,
    required this.fieldHint,
    required this.sheetBg,
    required this.warnBg,
    required this.warnBorder,
    required this.warnFg,
  });

  /// الوضع النهاري -- خلفية بيضاء، بطاقات مصمتة بظلّ نيلي ناعم بدل الحدود
  /// الصلبة، وسلّم تمييز مُغمَّق (‎#06B6D4 → #4F46E5) ليحمل نصّاً أبيض.
  static final AppSurface light = AppSurface(
    isDark: false,
    pageBg: const Color(0xFFFFFFFF),
    orb1: const Color(0xFFA78BFA).withValues(alpha: .34),
    orb2: const Color(0xFF818CF8).withValues(alpha: .24),
    orb3: const Color(0xFF22D3EE).withValues(alpha: .20),
    cardBg: const Color(0xFFFFFFFF),
    cardBorder: const Color(0xFFE2E8F0).withValues(alpha: .90),
    cardBorderActive: const Color(0xFF818CF8).withValues(alpha: .50),
    cardShadow: [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: .035),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: const Color(0xFF4F46E5).withValues(alpha: .16),
        blurRadius: 26,
        offset: const Offset(0, 14),
      ),
    ],
    heroBg: const Color(0xFFFFFFFF),
    heroBorder: const Color(0xFFE2E8F0).withValues(alpha: .90),
    heroShadow: [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: .04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: const Color(0xFF4F46E5).withValues(alpha: .22),
        blurRadius: 46,
        offset: const Offset(0, 20),
      ),
    ],
    sheen: const Color(0xFF6366F1).withValues(alpha: .09),
    heroWash: const Color(0xFF7C3AED).withValues(alpha: .075),
    textPrimary: const Color(0xFF0F172A),
    textSecondary: const Color(0xFF64748B),
    textMuted: const Color(0xFF94A3B8),
    heroCaption: const Color(0xFF4F46E5),
    bigNumber: const Color(0xFF141034),
    bigNumberUnit: const Color(0xFF6366F1),
    bigNumberGlow: null,
    accentGradient: const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF06B6D4), Color(0xFF4F46E5)],
    ),
    onAccent: const Color(0xFFFFFFFF),
    accentGlow: const Color(0xFF4F46E5).withValues(alpha: .55),
    accentSolid: const Color(0xFF4F46E5),
    iconBoxBg: const Color(0xFFEEF2FF),
    iconBoxBorder: const Color(0xFFE0E7FF),
    iconBoxFg: const Color(0xFF4F46E5),
    divider: const Color(0xFFF1F5F9),
    liveDot: const Color(0xFF06B6D4),
    liveDotHalo: const Color(0xFF06B6D4).withValues(alpha: .16),
    navBg: const Color(0xFFFFFFFF),
    navBorder: const Color(0xFFE2E8F0).withValues(alpha: .90),
    navShadow: [
      BoxShadow(
        color: const Color(0xFF6366F1).withValues(alpha: .10),
        blurRadius: 30,
        offset: const Offset(0, -2),
      ),
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: .14),
        blurRadius: 36,
        offset: const Offset(0, 18),
      ),
    ],
    navInactive: const Color(0xFF94A3B8),
    chipBg: const Color(0xFFFFFFFF),
    chipBorder: const Color(0xFFE2E8F0),
    chipFg: const Color(0xFF475569),
    actionBg: const Color(0xFFF8FAFC),
    actionBorder: const Color(0xFFEEF2FF),
    tierFg: const Color(0xFFB45309),
    tierBg: const Color(0xFFFBBF24).withValues(alpha: .14),
    tierBorder: const Color(0xFFF59E0B).withValues(alpha: .42),
    pillDueFg: const Color(0xFFB45309),
    pillDueBg: const Color(0xFFFFFBEB),
    pillDueBorder: const Color(0xFFFDE68A),
    pillPaidFg: const Color(0xFF047857),
    pillPaidBg: const Color(0xFFECFDF5),
    pillPaidBorder: const Color(0xFFA7F3D0),
    pillNoneFg: const Color(0xFF64748B),
    pillNoneBg: const Color(0xFFF1F5F9),
    pillNoneBorder: const Color(0xFFE2E8F0),
    fieldBg: const Color(0xFFFFFFFF),
    fieldBorder: const Color(0xFFE2E8F0),
    fieldHint: const Color(0xFF94A3B8),
    sheetBg: const Color(0xFFFFFFFF),
    warnBg: const Color(0xFFFFFBEB),
    warnBorder: const Color(0xFFFDE68A),
    warnFg: const Color(0xFF92400E),
  );

  /// الوضع الليلي -- «الليل النيلي» كما اختاره المستخدم بلا تغيير: سطح
  /// ‎#07061A، بطاقات زجاجية شفّافة، وتمييز سماوي فاتح بنصّ داكن.
  static final AppSurface dark = AppSurface(
    isDark: true,
    pageBg: const Color(0xFF07061A),
    orb1: const Color(0xFF6D28D9).withValues(alpha: .55),
    orb2: const Color(0xFF312E81).withValues(alpha: .70),
    orb3: const Color(0xFF22D3EE).withValues(alpha: .16),
    cardBg: const Color(0xFFFFFFFF).withValues(alpha: .05),
    cardBorder: const Color(0xFFFFFFFF).withValues(alpha: .075),
    cardBorderActive: const Color(0xFF818CF8).withValues(alpha: .32),
    cardShadow: [
      BoxShadow(
        color: const Color(0xFF818CF8).withValues(alpha: .18),
        blurRadius: 34,
        offset: const Offset(0, 18),
      ),
    ],
    heroBg: const Color(0xFFFFFFFF).withValues(alpha: .06),
    heroBorder: const Color(0xFFFFFFFF).withValues(alpha: .10),
    heroShadow: [
      BoxShadow(
        color: const Color(0xFF7C3AED).withValues(alpha: .45),
        blurRadius: 50,
        offset: const Offset(0, 24),
      ),
    ],
    sheen: const Color(0xFFFFFFFF).withValues(alpha: .10),
    heroWash: const Color(0xFFA78BFA).withValues(alpha: .10),
    textPrimary: const Color(0xFFF1F5F9),
    textSecondary: const Color(0xFF8B8FC7),
    textMuted: const Color(0xFF7E83B8),
    heroCaption: const Color(0xFFA5B4FC),
    bigNumber: const Color(0xFFFFFFFF),
    bigNumberUnit: const Color(0xFFC4B5FD),
    bigNumberGlow: const Color(0xFFA78BFA),
    accentGradient: const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF67E8F9), Color(0xFF818CF8)],
    ),
    onAccent: const Color(0xFF061019),
    accentGlow: const Color(0xFF67E8F9).withValues(alpha: .75),
    accentSolid: const Color(0xFF818CF8),
    iconBoxBg: const Color(0xFF818CF8).withValues(alpha: .14),
    iconBoxBorder: const Color(0xFF818CF8).withValues(alpha: .22),
    iconBoxFg: const Color(0xFFA5B4FC),
    divider: const Color(0xFFFFFFFF).withValues(alpha: .09),
    liveDot: const Color(0xFF22D3EE),
    liveDotHalo: const Color(0xFF22D3EE).withValues(alpha: .35),
    navBg: const Color(0xFF15122F),
    navBorder: const Color(0xFFFFFFFF).withValues(alpha: .10),
    navShadow: [
      BoxShadow(
        color: const Color(0xFF7C3AED).withValues(alpha: .28),
        blurRadius: 40,
        offset: const Offset(0, -2),
      ),
    ],
    navInactive: const Color(0xFF7E83B8),
    chipBg: const Color(0xFFFFFFFF).withValues(alpha: .05),
    chipBorder: const Color(0xFFFFFFFF).withValues(alpha: .09),
    chipFg: const Color(0xFFA5B4FC),
    actionBg: const Color(0xFFFFFFFF).withValues(alpha: .06),
    actionBorder: const Color(0xFFFFFFFF).withValues(alpha: .09),
    tierFg: const Color(0xFFFCD34D),
    tierBg: const Color(0xFFFCD34D).withValues(alpha: .10),
    tierBorder: const Color(0xFFFCD34D).withValues(alpha: .42),
    pillDueFg: const Color(0xFFFBBF24),
    pillDueBg: const Color(0xFFFBBF24).withValues(alpha: .11),
    pillDueBorder: const Color(0xFFFBBF24).withValues(alpha: .26),
    pillPaidFg: const Color(0xFF34D399),
    pillPaidBg: const Color(0xFF34D399).withValues(alpha: .11),
    pillPaidBorder: const Color(0xFF34D399).withValues(alpha: .26),
    pillNoneFg: const Color(0xFF94A3B8),
    pillNoneBg: const Color(0xFF94A3B8).withValues(alpha: .10),
    pillNoneBorder: const Color(0xFF94A3B8).withValues(alpha: .22),
    fieldBg: const Color(0xFFFFFFFF).withValues(alpha: .05),
    fieldBorder: const Color(0xFFFFFFFF).withValues(alpha: .09),
    fieldHint: const Color(0xFF7E83B8),
    sheetBg: const Color(0xFF15122F),
    warnBg: const Color(0xFFFBBF24).withValues(alpha: .10),
    warnBorder: const Color(0xFFFBBF24).withValues(alpha: .30),
    warnFg: const Color(0xFFFCD34D),
  );

  // ThemeExtension يفرض copyWith/lerp. لا نحتاج نسخاً جزئياً (النسختان
  // ثابتتان ومعرَّفتان أعلاه)، والمزج التدريجي بين لوحتين متعاكستين ينتج
  // ألواناً وسطية موحلة، فالتبديل قطعيّ عند منتصف الانتقال -- وهذا هو
  // السلوك المقصود، لا نقص في التنفيذ.
  @override
  AppSurface copyWith() => this;

  @override
  AppSurface lerp(covariant AppSurface? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// الوصول المختصر لتوكنات الوضع الحالي. يرجع النسخة الفاتحة إن لم يكن
/// الامتداد مسجَّلاً في الـ Theme المحيط (شاشة تُبنى داخل Theme خاص بها، أو
/// اختبار widget بلا AppTheme) بدل أن ينهار بعلامة `!`.
extension AppSurfaceContext on BuildContext {
  AppSurface get surface =>
      Theme.of(this).extension<AppSurface>() ?? AppSurface.light;
}

/// خطّا الموقع بعد تحديث التوكنات في 2026-09-04: Noto Kufi Arabic للعناوين
/// والأرقام، و Noto Sans Arabic للمتن. كان التطبيق ما زال على Tajawal
/// (مطابقة 2026-09-02، أي قبل التحديث بيومين)، وهذا أحد أكبر أسباب شعور
/// المستخدم بأن التطبيق "متأخّر" عن الموقع.
///
/// [kufi] للأرقام والعناوين: يفعّل `FontFeature.tabularFigures` افتراضياً
/// حتى تصطفّ خانات المبالغ عمودياً في القوائم المالية -- وهو نصف سبب اختيار
/// Noto على الموقع أصلاً (Tajawal لا يملك وزن 600 ولا أرقاماً جدولية).
class AppType {
  AppType._();

  static TextStyle kufi({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    bool tabularFigures = true,
  }) {
    return GoogleFonts.notoKufiArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures:
          tabularFigures ? const <FontFeature>[FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.notoSansArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// مصدر الحقيقة الوحيد لوضع الإضاءة. يُحفَظ الاختيار في نفس
/// SharedPreferences التي تحفظ الجلسة، لكنه **لا يُمسَح عند تسجيل الخروج** --
/// وضع الإضاءة تفضيل جهاز لا تفضيل حساب.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  /// الافتراضي نهاري: هو الوضع الذي يستعمله الطبيب في ضوء العيادة.
  final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static const _kPrefKey = 'theme_mode';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPrefKey);
      if (saved == 'dark') {
        mode.value = ThemeMode.dark;
      } else if (saved == 'system') {
        mode.value = ThemeMode.system;
      } else if (saved == 'light') {
        mode.value = ThemeMode.light;
      }
    } catch (_) {
      // تعذّر قراءة التفضيل لا يمنع إقلاع التطبيق -- يبقى على النهاري.
    }
  }

  Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, value.name);
    } catch (_) {
      // الاختيار يبقى فعّالاً في هذه الجلسة حتى لو فشل الحفظ.
    }
  }
}

class AppTheme {
  AppTheme._();

  /// أُبقيت للتوافق مع أي استدعاء قديم لـ `AppTheme.theme`.
  static ThemeData get theme => light;

  static ThemeData get light => _build(AppSurface.light);

  static ThemeData get dark => _build(AppSurface.dark);

  static ThemeData _build(AppSurface surf) {
    final brightness = surf.isDark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.indigo600,
        brightness: brightness,
        primary: surf.accentSolid,
        secondary: AppColors.violet600,
        surface: surf.cardBg,
      ),
      scaffoldBackgroundColor: surf.pageBg,
      fontFamily: GoogleFonts.notoSansArabic().fontFamily,
    );
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[surf],
      textTheme: GoogleFonts.notoSansArabicTextTheme(base.textTheme)
          .apply(bodyColor: surf.textPrimary, displayColor: surf.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: surf.pageBg,
        foregroundColor: surf.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      dividerColor: surf.divider,
      cardTheme: CardThemeData(
        elevation: 0,
        color: surf.cardBg,
        surfaceTintColor: surf.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: surf.cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surf.fieldBg,
        hintStyle: TextStyle(color: surf.fieldHint),
        labelStyle: TextStyle(color: surf.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: surf.fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: surf.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: surf.accentSolid, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surf.navBg,
        indicatorColor: surf.accentSolid.withValues(alpha: .16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? surf.accentSolid : surf.navInactive,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? surf.accentSolid : surf.navInactive,
          );
        }),
      ),
    );
  }
}
