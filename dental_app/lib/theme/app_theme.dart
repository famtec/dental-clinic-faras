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

  static const loginBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy900, indigo800, Color(0xFF5B21B6)],
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
