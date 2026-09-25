/// دفعة سجّلها طبيب مساعد وتنتظر تأكيد الطبيب المدير (2026-09-25).
///
/// **ليست دفعة بعد**: لا تدخل المدفوع على الفاتورة ولا المالية ولا نسبة
/// الطبيب قبل أن يؤكّد المدير استلام المبلغ -- انظر PendingPayment في
/// models.py على الخادم.
class PendingPayment {
  final int id;
  final int invoiceId;
  final int patientId;
  final int clinicDoctorId;
  final String? staffName;
  final String? patientName;
  final String? invoiceTitle;
  final double amount;
  final String? description;

  /// pending | confirmed | rejected
  final String status;
  final DateTime recordedAt;
  final DateTime? reviewedAt;
  final String? reviewNote;

  const PendingPayment({
    required this.id,
    required this.invoiceId,
    required this.patientId,
    required this.clinicDoctorId,
    required this.amount,
    required this.status,
    required this.recordedAt,
    this.staffName,
    this.patientName,
    this.invoiceTitle,
    this.description,
    this.reviewedAt,
    this.reviewNote,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isRejected => status == 'rejected';

  factory PendingPayment.fromJson(Map<String, dynamic> json) {
    return PendingPayment(
      id: _int(json['id']) ?? 0,
      invoiceId: _int(json['invoice_id']) ?? 0,
      patientId: _int(json['patient_id']) ?? 0,
      clinicDoctorId: _int(json['clinic_doctor_id']) ?? 0,
      staffName: _text(json['staff_name']),
      patientName: _text(json['patient_name']),
      invoiceTitle: _text(json['invoice_title']),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: _text(json['description']),
      status: _text(json['status']) ?? 'pending',
      recordedAt: DateTime.tryParse('${json['recorded_at'] ?? ''}') ?? DateTime.now(),
      reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}'),
      reviewNote: _text(json['review_note']),
    );
  }

  /// تخزين مؤقت (cache_kv) مع الفاتورة فقط.
  Map<String, dynamic> toJson() => {
        'id': id,
        'invoice_id': invoiceId,
        'patient_id': patientId,
        'clinic_doctor_id': clinicDoctorId,
        'staff_name': staffName,
        'patient_name': patientName,
        'invoice_title': invoiceTitle,
        'amount': amount,
        'description': description,
        'status': status,
        'recorded_at': recordedAt.toIso8601String(),
        'reviewed_at': reviewedAt?.toIso8601String(),
        'review_note': reviewNote,
      };
}

/// عدد الدفعات المعلّقة ومجموعها.
class PendingSummary {
  final int count;
  final double amount;

  const PendingSummary({this.count = 0, this.amount = 0});
}

/// شهر مالي مُقفل مع لقطة أرقامه لحظة الإقفال.
class ClosedPeriod {
  final int year;
  final int month;
  final DateTime? closedAt;
  final double totalIncome;
  final double totalExpenses;
  final double netProfit;
  final double doctorsShare;

  const ClosedPeriod({
    required this.year,
    required this.month,
    this.closedAt,
    this.totalIncome = 0,
    this.totalExpenses = 0,
    this.netProfit = 0,
    this.doctorsShare = 0,
  });

  factory ClosedPeriod.fromJson(Map<String, dynamic> json) {
    return ClosedPeriod(
      year: _int(json['year']) ?? 0,
      month: _int(json['month']) ?? 0,
      closedAt: DateTime.tryParse('${json['closed_at'] ?? ''}'),
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0,
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0,
      doctorsShare: (json['doctors_share'] as num?)?.toDouble() ?? 0,
    );
  }
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
