import 'dart:convert';

class Patient {
  final int id;
  final String fullName;
  final String phone;
  final String? gender;
  final DateTime? birthDate;
  final String? medicalHistory;
  final double totalTreatmentCost;
  final double paidAmount;
  final String? chartStateRaw;

  /// حالة المزامنة مع السيرفر -- 'synced' دائماً لأي مريض قادم فعلياً من
  /// الـ backend (fromJson). القيم الأخرى ('pending_create' / 'pending_update')
  /// لا تظهر إلا لمريض أُنشئ/عُدِّلت بياناته الأساسية أو مخطط أسنانه أوفلاين
  /// وما زال بانتظار الاتصال بالإنترنت ليصل فعلياً للسيرفر -- انظر
  /// OfflineAwareApiService وLocalDb. أُضيف 2026-09-02 (توسيع دعم العمل بدون
  /// إنترنت من المواعيد إلى المرضى/مخطط الأسنان).
  final String syncStatus;

  const Patient({
    required this.id,
    required this.fullName,
    required this.phone,
    this.gender,
    this.birthDate,
    this.medicalHistory,
    required this.totalTreatmentCost,
    required this.paidAmount,
    this.chartStateRaw,
    this.syncStatus = 'synced',
  });

  bool get isPendingSync => syncStatus != 'synced';

  double get remainingBalance {
    final remaining = totalTreatmentCost - paidAmount;
    return remaining < 0 ? 0 : remaining;
  }

  /// العمر التقريبي بالسنوات محسوباً من تاريخ الميلاد -- قد يكون تاريخ
  /// الميلاد قيمة افتراضية مزروعة لمرضى أُنشئوا من نموذج لا يجمع تاريخ ميلاد
  /// حقيقياً (نفس سلوك الموقع تماماً، وليس خطأً في التطبيق).
  int? get age {
    final date = birthDate;
    if (date == null) return null;
    final now = DateTime.now();
    var years = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      years -= 1;
    }
    return years < 0 ? null : years;
  }

  /// حالة كل سن مفتاحه Palmer (UR1..LL8) وقيمته اسم الحالة (decay/filling/...)
  /// -- فارغة إن لم يُسجَّل أي تعديل على مخطط أسنان هذا المريض بعد.
  Map<String, String> get chartState {
    final raw = chartStateRaw;
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
    } catch (_) {
      // chart_state تالف أو بصيغة غير متوقعة -- نتجاهله بصمت ونعرض مخططاً فارغاً
      // بدل تعطيل الشاشة بالكامل.
    }
    return const {};
  }

  Patient copyWith({
    String? fullName,
    String? phone,
    String? gender,
    DateTime? birthDate,
    String? medicalHistory,
    double? totalTreatmentCost,
    double? paidAmount,
    String? chartStateRaw,
    String? syncStatus,
  }) {
    return Patient(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      totalTreatmentCost: totalTreatmentCost ?? this.totalTreatmentCost,
      paidAmount: paidAmount ?? this.paidAmount,
      chartStateRaw: chartStateRaw ?? this.chartStateRaw,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory Patient.fromJson(Map<String, dynamic> json) {
    DateTime? birthDate;
    final rawBirthDate = json['birth_date'];
    if (rawBirthDate is String && rawBirthDate.isNotEmpty) {
      birthDate = DateTime.tryParse(rawBirthDate);
    }
    return Patient(
      id: json['id'] as int,
      fullName: (json['full_name'] as String?)?.trim() ?? 'بدون اسم',
      phone: (json['phone'] as String?)?.trim() ?? '',
      gender: json['gender'] as String?,
      birthDate: birthDate,
      medicalHistory: json['medical_history'] as String?,
      totalTreatmentCost:
          (json['total_treatment_cost'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      chartStateRaw: json['chart_state'] as String?,
    );
  }
}
