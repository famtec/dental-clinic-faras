class InvoicePayment {
  final int id;
  final double amount;
  final String description;
  final DateTime createdAt;
  final bool isOpeningBalance;

  /// 'synced' لأي دفعة قادمة فعلياً من السيرفر. 'pending' لدفعة سُجِّلت
  /// أوفلاين ولا تزال بانتظار الاتصال لترسَل فعلياً -- انظر
  /// OfflineAwareApiService.addInvoicePayment. أُضيف 2026-09-02.
  final String syncStatus;

  const InvoicePayment({
    required this.id,
    required this.amount,
    required this.description,
    required this.createdAt,
    required this.isOpeningBalance,
    this.syncStatus = 'synced',
  });

  bool get isPendingSync => syncStatus != 'synced';

  factory InvoicePayment.fromJson(Map<String, dynamic> json) {
    return InvoicePayment(
      id: json['id'] as int,
      amount: (json['amount'] as num).toDouble(),
      description: (json['description'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isOpeningBalance: json['is_opening_balance'] as bool? ?? false,
    );
  }

  /// عكس [fromJson] -- تُستخدم فقط لتخزين آخر نسخة معروفة من فواتير مريض
  /// محلياً (cache_kv) لعرضها عند انقطاع الاتصال، وليس لإرسالها للسيرفر.
  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'is_opening_balance': isOpeningBalance,
      };
}

/// فاتورة علاج مستقلة لمريض واحد -- تكلفتها ودفعاتها الخاصة بها فقط (انظر
/// شرح models.TreatmentInvoice في main.py). "status" يُشتق دائماً من طرف
/// السيرفر: "open" ما زال عليها متبقي، "closed" سُدِّدت بالكامل.
class TreatmentInvoice {
  final int id;
  final int patientId;
  final String title;
  final double totalCost;
  final double paidAmount;
  final double remainingAmount;
  final String status;
  final DateTime createdAt;
  final List<InvoicePayment> payments;

  /// 'synced' لفاتورة قادمة فعلياً من السيرفر. 'pending_create' لفاتورة
  /// أُنشئت أوفلاين ولم تصل للسيرفر بعد، 'pending_update' لفاتورة مزامَنة
  /// أصلاً لكن عليها دفعة/تعديل جديد ما زال بانتظار الاتصال -- انظر
  /// OfflineAwareApiService. أُضيف 2026-09-02.
  final String syncStatus;

  const TreatmentInvoice({
    required this.id,
    required this.patientId,
    required this.title,
    required this.totalCost,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.createdAt,
    required this.payments,
    this.syncStatus = 'synced',
  });

  bool get isOpen => status == 'open';

  bool get isPendingSync => syncStatus != 'synced';

  double get progress {
    if (totalCost <= 0) return 0;
    final ratio = paidAmount / totalCost;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  TreatmentInvoice copyWith({
    double? paidAmount,
    double? remainingAmount,
    String? status,
    List<InvoicePayment>? payments,
    String? syncStatus,
  }) {
    return TreatmentInvoice(
      id: id,
      patientId: patientId,
      title: title,
      totalCost: totalCost,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      createdAt: createdAt,
      payments: payments ?? this.payments,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory TreatmentInvoice.fromJson(Map<String, dynamic> json) {
    final rawPayments = json['payments'] as List? ?? const [];
    return TreatmentInvoice(
      id: json['id'] as int,
      patientId: json['patient_id'] as int,
      title: (json['title'] as String?)?.trim() ?? '',
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (json['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] as String?)?.trim() ?? 'open',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      payments: rawPayments
          .map((item) => InvoicePayment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  /// عكس [fromJson] -- تخزين مؤقت (cache_kv) فقط، انظر تعليق InvoicePayment.toJson.
  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'title': title,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'remaining_amount': remainingAmount,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'payments': payments.map((p) => p.toJson()).toList(),
      };
}
