/// إحصائيات بطاقات "الرئيسية" الثلاث -- تطابق PatientStatsResponse في
/// main.py حرفياً (GET /api/patients/stats)، وهي نفس نقطة النهاية ونفس
/// الحقول الثلاثة التي تغذّي بطاقات "SMART STAT" في index.html بالموقع:
/// إجمالي المرضى بالعيادة (total_patients) / المواعيد النشطة والمعلقة
/// (active_appointments) / المستحقات المالية بالخارج (pending_balances).
/// أُضيف 2026-08-31 لربط dashboard_screen.dart بنفس مصدر البيانات الحي بدل
/// الحساب المحلي القديم من مواعيد اليوم فقط.
class PatientStats {
  final int totalPatients;
  final int activeAppointments;
  final double pendingBalances;

  const PatientStats({
    required this.totalPatients,
    required this.activeAppointments,
    required this.pendingBalances,
  });

  factory PatientStats.fromJson(Map<String, dynamic> json) {
    return PatientStats(
      totalPatients: (json['total_patients'] as num?)?.toInt() ?? 0,
      activeAppointments: (json['active_appointments'] as num?)?.toInt() ?? 0,
      pendingBalances: (json['pending_balances'] as num?)?.toDouble() ?? 0,
    );
  }
}
