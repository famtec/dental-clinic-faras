/// حركة مالية واحدة (دفعة أو مصروف) كما يعيدها
/// GET /api/finance/transactions -- تُغذّي قسم "آخر الحركات" في الشاشة
/// المالية، نفس القسم المضاف لصفحة finance.html بالموقع.
///
/// المسار يعيد FinancialTransactionResponse من main.py، وحقوله هنا هي نفس
/// حقوله بالضبط. is_opening_balance مقروء رغم أن السيرفر يستبعد الأرصدة
/// الافتتاحية أصلاً من أي فترة محدّدة -- يبقى صحيحاً في وضع all_time.
class FinanceTransaction {
  final int id;
  final int? patientId;
  final String? doctorName;
  final double amount;

  /// "income" أو "expense" كما يخزّنها الـ backend حرفياً.
  final String type;
  final String description;
  final DateTime? createdAt;
  final bool isOpeningBalance;

  const FinanceTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    this.patientId,
    this.doctorName,
    this.createdAt,
    this.isOpeningBalance = false,
  });

  bool get isIncome => type.trim().toLowerCase() == 'income';

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    // يصل التاريخ من FastAPI بصيغة ISO بلا لاحقة منطقة زمنية، فيفسَّر
    // محلياً -- وهو المطلوب: الخادم يعمل بتوقيت دمشق ونعرض نفس اللحظة.
    return DateTime.tryParse('$value');
  }

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    return FinanceTransaction(
      id: (json['id'] as num?)?.toInt() ?? 0,
      patientId: (json['patient_id'] as num?)?.toInt(),
      doctorName: json['doctor_name'] as String?,
      amount: _toDouble(json['amount']),
      type: '${json['type'] ?? ''}',
      description: '${json['description'] ?? ''}',
      createdAt: _toDate(json['created_at']),
      isOpeningBalance: json['is_opening_balance'] == true,
    );
  }

  /// عكس [fromJson] -- لتخزين آخر "آخر الحركات" معروفة محلياً (cache_kv)
  /// وعرضها عند انقطاع الاتصال بدل قائمة فارغة مضلِّلة. أُضيف 2026-09-02.
  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'doctor_name': doctorName,
        'amount': amount,
        'type': type,
        'description': description,
        'created_at': createdAt?.toIso8601String(),
        'is_opening_balance': isOpeningBalance,
      };
}
