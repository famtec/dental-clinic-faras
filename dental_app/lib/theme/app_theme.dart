import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // السماوي (توهّج التبويب النشط في شريط التنقل السفلي + شارات "Live") --
  // مضاف بعد تدقيق تصميم الموقع 2026-08-29: كان غائباً عن لوحة التطبيق رغم
  // أنه لون التمييز الأساسي لكل عنصر تنقل نشط في نسخة الويب.
  static const cyan300 = Color(0xFF67E8F9);
  static const cyan400 = Color(0xFF22D3EE);

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
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.indigo600,
        primary: AppColors.indigo600,
        secondary: AppColors.violet600,
      ),
      scaffoldBackgroundColor: AppColors.pageBg,
      fontFamily: GoogleFonts.tajawal().fontFamily,
    );
    return base.copyWith(
      textTheme: GoogleFonts.tajawalTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy900,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.slate200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.slate300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.slate300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.indigo600, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.indigo50,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? AppColors.indigoAccent : AppColors.slate400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.indigoAccent : AppColors.slate400,
          );
        }),
      ),
    );
  }
}
