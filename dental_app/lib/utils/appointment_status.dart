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

AppointmentStatusStyle appointmentStatusStyle(String status) {
  switch (status.toLowerCase()) {
    case 'checked_in':
    case 'confirmed':
    case 'completed':
      return const AppointmentStatusStyle(
          AppColors.emerald100, AppColors.emerald700text);
    case 'no_show':
    case 'cancelled':
    case 'rejected':
      return const AppointmentStatusStyle(
          AppColors.rose100, AppColors.rose700text);
    case 'pending_confirmation':
      return const AppointmentStatusStyle(
          AppColors.purple100, AppColors.purple600);
    case 'pending':
    default:
      return const AppointmentStatusStyle(
          AppColors.amber100, AppColors.amber800text);
  }
}
