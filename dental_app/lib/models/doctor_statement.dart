import 'clinic_doctor.dart';

/// كشف حساب طبيب واحد -- GET /api/clinic-doctors/{id}/statement. أُضيف
/// 2026-09-18 مع شاشة "الأطباء والنسب" في التطبيق.
///
/// الردّ خريطة مركّبة لا قائمة: {doctor, period, materials, earnings,
/// payouts}. تُقرأ هنا كلّها في صنف واحد لأن الشاشة تعرضها معاً، وتفكيكها
/// إلى نداءات منفصلة كان سيُظهر الحركات قبل مجاميعها أو بعدها.
///
/// حساب الرصيد المستحق **لا يُعاد حسابه هنا**: يأتي جاهزاً من الخادم
/// (balance_due في doctor) لأنه تراكمي على كل الفترات، ولو جُمع في الواجهة
/// من حركات الفترة المعروضة لأظهر رصيداً كاذباً لكل شهر.

/// حركة استحقاق واحدة: دفعة حصّلها الطبيب من مريض ونسبته منها.
class DoctorEarningRow {
  final int id;
  final int? patientId;
  final String? patientName;
  final int? invoiceId;
  final String? description;
  final double grossAmount;
  final double appliedPercent;
  final double doctorShare;
  final double clinicShare;
  final DateTime? earnedAt;

  /// وقت آخر تعديل على الحركة. وجوده يعني أن النسبة أو المبلغ عُدِّلا بعد
  /// التسجيل، والموقع يضع شارة "معدَّلة" لأجله -- إخفاؤه يجعل رقماً معدَّلاً
  /// يبدو كأنه الأصلي.
  final DateTime? adjustedAt;

  const DoctorEarningRow({
    required this.id,
    this.patientId,
    this.patientName,
    this.invoiceId,
    this.description,
    this.grossAmount = 0,
    this.appliedPercent = 0,
    this.doctorShare = 0,
    this.clinicShare = 0,
    this.earnedAt,
    this.adjustedAt,
  });

  bool get isAdjusted => adjustedAt != null;

  factory DoctorEarningRow.fromJson(Map<String, dynamic> json) {
    return DoctorEarningRow(
      id: _int(json['id']) ?? 0,
      patientId: _int(json['patient_id']),
      patientName: _text(json['patient_name']),
      invoiceId: _int(json['invoice_id']),
      description: _text(json['description']),
      grossAmount: _money(json['gross_amount']),
      appliedPercent: _money(json['applied_percent']),
      doctorShare: _money(json['doctor_share']),
      clinicShare: _money(json['clinic_share']),
      earnedAt: _date(json['earned_at']),
      adjustedAt: _date(json['adjusted_at']),
    );
  }
}

/// تسوية مسدَّدة: مبلغ سُلِّم فعلاً للطبيب.
class DoctorPayoutRow {
  final int id;
  final double amount;
  final String? note;
  final DateTime? paidAt;

  const DoctorPayoutRow({
    required this.id,
    this.amount = 0,
    this.note,
    this.paidAt,
  });

  factory DoctorPayoutRow.fromJson(Map<String, dynamic> json) {
    return DoctorPayoutRow(
      id: _int(json['id']) ?? 0,
      amount: _money(json['amount']),
      note: _text(json['note']),
      paidAt: _date(json['paid_at']),
    );
  }
}

/// مادة استُهلكت في فاتورة من فواتير الطبيب -- تكلفة على العيادة لا على
/// حصة الطبيب، ولذلك تُعرَض مستقلّة عن الحركات ولا تُخصم منها.
class DoctorMaterialRow {
  final int id;
  final int? invoiceId;
  final int? patientId;
  final String itemName;
  final int quantity;
  final double unitCost;
  final double totalCost;
  final DateTime? createdAt;

  const DoctorMaterialRow({
    required this.id,
    this.invoiceId,
    this.patientId,
    this.itemName = '',
    this.quantity = 0,
    this.unitCost = 0,
    this.totalCost = 0,
    this.createdAt,
  });

  factory DoctorMaterialRow.fromJson(Map<String, dynamic> json) {
    return DoctorMaterialRow(
      id: _int(json['id']) ?? 0,
      invoiceId: _int(json['invoice_id']),
      patientId: _int(json['patient_id']),
      itemName: _text(json['item_name']) ?? '',
      quantity: _int(json['quantity']) ?? 0,
      unitCost: _money(json['unit_cost']),
      totalCost: _money(json['total_cost']),
      createdAt: _date(json['created_at']),
    );
  }
}

/// مجاميع الفترة المعروضة وحدها (لا التراكمية).
class DoctorStatementPeriod {
  final int? year;
  final int? month;
  final int? day;
  final bool allTime;
  final double collected;
  final double doctorShare;
  final double clinicShare;
  final double paidOut;
  final double materialsCost;

  const DoctorStatementPeriod({
    this.year,
    this.month,
    this.day,
    this.allTime = false,
    this.collected = 0,
    this.doctorShare = 0,
    this.clinicShare = 0,
    this.paidOut = 0,
    this.materialsCost = 0,
  });

  factory DoctorStatementPeriod.fromJson(Map<String, dynamic> json) {
    final rawAll = json['all_time'];
    return DoctorStatementPeriod(
      year: _int(json['year']),
      month: _int(json['month']),
      day: _int(json['day']),
      allTime: rawAll is bool ? rawAll : rawAll == 1 || rawAll == 'true',
      collected: _money(json['collected']),
      doctorShare: _money(json['doctor_share']),
      clinicShare: _money(json['clinic_share']),
      paidOut: _money(json['paid_out']),
      materialsCost: _money(json['materials_cost']),
    );
  }
}

class DoctorStatement {
  final ClinicDoctor doctor;
  final DoctorStatementPeriod period;
  final List<DoctorEarningRow> earnings;
  final List<DoctorPayoutRow> payouts;
  final List<DoctorMaterialRow> materials;

  const DoctorStatement({
    required this.doctor,
    required this.period,
    this.earnings = const [],
    this.payouts = const [],
    this.materials = const [],
  });

  factory DoctorStatement.fromJson(Map<String, dynamic> json) {
    final doctorJson = json['doctor'];
    return DoctorStatement(
      doctor: doctorJson is Map<String, dynamic>
          ? ClinicDoctor.fromJson(doctorJson)
          : const ClinicDoctor(id: 0, fullName: ''),
      period: json['period'] is Map<String, dynamic>
          ? DoctorStatementPeriod.fromJson(json['period'] as Map<String, dynamic>)
          : const DoctorStatementPeriod(),
      earnings: _rows(json['earnings'], DoctorEarningRow.fromJson),
      payouts: _rows(json['payouts'], DoctorPayoutRow.fromJson),
      materials: _rows(json['materials'], DoctorMaterialRow.fromJson),
    );
  }
}

List<T> _rows<T>(Object? value, T Function(Map<String, dynamic>) build) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().map(build).toList();
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// نفس احتراز ClinicDoctor._money: JSON قد يعيد 0 كـ int، وقراءته
/// `as double` تُسقِط الشاشة كلها.
double _money(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : 0;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return 0;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// تواريخ الخادم تصل بصيغة ISO بلا لاحقة منطقة زمنية (naive، بتوقيت دمشق --
/// انظر _damascus_now في main.py). parse يقرأها كوقت محلي وهو الصواب هنا:
/// إضافة Z كانت ستُزيح تسوية مسجَّلة الساعة 1 ظهراً إلى يوم آخر.
DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}
