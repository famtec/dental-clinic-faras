class Patient {
  final int id;
  final String fullName;
  final String phone;
  final String? gender;
  final double totalTreatmentCost;
  final double paidAmount;

  const Patient({
    required this.id,
    required this.fullName,
    required this.phone,
    this.gender,
    required this.totalTreatmentCost,
    required this.paidAmount,
  });

  double get remainingBalance {
    final remaining = totalTreatmentCost - paidAmount;
    return remaining < 0 ? 0 : remaining;
  }

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as int,
      fullName: (json['full_name'] as String?)?.trim() ?? 'بدون اسم',
      phone: (json['phone'] as String?)?.trim() ?? '',
      gender: json['gender'] as String?,
      totalTreatmentCost:
          (json['total_treatment_cost'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
