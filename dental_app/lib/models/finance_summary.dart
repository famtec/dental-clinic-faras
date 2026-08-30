/// ملخص التقرير المالي لشهر محدد (أو الإجمالي الكلي) -- يطابق استجابة
/// GET /api/finance/summary حرفياً (انظر get_finance_summary في main.py
/// وfinance.html بالموقع).
class FinanceSummary {
  final double totalIncome;
  final double totalExpenses;
  final double netProfit;
  final double totalRevenue;
  final double openingBalanceIncome;
  final bool allTime;
  final int? year;
  final int? month;
  // 2026-08-29: تاريخ يوم محدد -- موجود فقط عند اختيار "اليوم" من القائمة
  // المنسدلة (day في get_finance_summary بـ main.py)، غير ذلك يبقى null.
  final int? day;

  const FinanceSummary({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netProfit,
    required this.totalRevenue,
    required this.openingBalanceIncome,
    required this.allTime,
    this.year,
    this.month,
    this.day,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0.0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0.0,
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      openingBalanceIncome: (json['opening_balance_income'] as num?)?.toDouble() ?? 0.0,
      allTime: json['all_time'] as bool? ?? false,
      year: json['year'] as int?,
      month: json['month'] as int?,
      day: json['day'] as int?,
    );
  }
}
