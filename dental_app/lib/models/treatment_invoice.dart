class InvoicePayment {
  final int id;
  final double amount;
  final String description;
  final DateTime createdAt;
  final bool isOpeningBalance;

  const InvoicePayment({
    required this.id,
    required this.amount,
    required this.description,
    required this.createdAt,
    required this.isOpeningBalance,
  });

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
  });

  bool get isOpen => status == 'open';

  double get progress {
    if (totalCost <= 0) return 0;
    final ratio = paidAmount / totalCost;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
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
}
