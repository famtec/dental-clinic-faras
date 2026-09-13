import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// لون خلفية/نص شارة حالة الموعد -- نفس منطق ألوان الحالات في صفحة
/// appointments.html بالموقع (أخضر لِما تم/دخل العيادة، كهرماني لقيد
/// الانتظار، بنفسجي لطلب حجز جديد، وردي لِما انتهى بالرفض/التخلف/الإلغاء).
class AppointmentStatusStyle {
  final Color background;
  final Color foreground;
  const AppointmentStatusStyle(this.background, this.foreground);
}

/// [isDark] يقلب اللوحة إلى نسخة شفافة من نفس اللون الدلالي. الدرجات
/// الفاتحة المصمتة (emerald100/amber100/rose100...) تصير بقعاً ساطعة على
/// سطح ‎#07061A، فالخلفية تصبح شفافية 12% من لون النص نفسه، والنصّ يرتفع
/// إلى الدرجة الفاتحة من العائلة. الدلالة (أخضر=تمّ، كهرماني=انتظار،
/// بنفسجي=طلب جديد، وردي=رفض/تخلّف) لا تتغيّر إطلاقاً.
AppointmentStatusStyle appointmentStatusStyle(String status,
    {bool isDark = false}) {
  AppointmentStatusStyle pair(Color lightBg, Color lightFg, Color darkFg) =>
      isDark
          ? AppointmentStatusStyle(darkFg.withValues(alpha: .12), darkFg)
          : AppointmentStatusStyle(lightBg, lightFg);

  switch (status.toLowerCase()) {
    case 'checked_in':
    case 'confirmed':
    case 'completed':
      return pair(AppColors.emerald100, AppColors.emerald700text,
          const Color(0xFF34D399));
    case 'no_show':
    case 'cancelled':
    case 'rejected':
      return pair(AppColors.rose100, AppColors.rose700text, AppColors.rose400);
    case 'pending_confirmation':
      return pair(AppColors.purple100, AppColors.purple600,
          const Color(0xFFC4B5FD));
    case 'pending':
    default:
      return pair(AppColors.amber100, AppColors.amber800text,
          AppColors.amber300);
  }
}
