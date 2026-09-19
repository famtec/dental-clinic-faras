/// طبيب مساعد في عيادة متعددة الأطباء. أُضيف 2026-09-17 بالحقول الأساسية
/// (اختيار الطبيب المنفّذ للموعد وعمود جدول الساعات)، ووُسّع 2026-09-18
/// بحقول النسبة والأرقام المالية لشاشة "الأطباء والنسب".
///
/// الحقول المالية كلها **اختيارية بقيمة صفر افتراضية** عن قصد: نفس الصنف
/// يُقرأ من ردّين مختلفين. جدول الساعات يستدعي fetchClinicDoctors ولا يحتاج
/// إلا الاسم والاختصاص، وشاشة الأطباء تستدعي fetchClinicDoctorsDetailed
/// فتقرأ الأرقام نفسها من نفس المسار. لو كانت الأرقام required لاضطر جدول
/// الساعات لحمل صنف ثانٍ مكرّر لنفس الجدول في الخادم.
///
/// وحدة النسبة: **نسبة مئوية من المبلغ المحصّل فعلاً من المريض** لا من قيمة
/// الفاتورة -- هذا قرار الخادم (_apply_doctor_earning في main.py) وليس
/// اختياراً معروضاً، فلا يجوز تحويله في الواجهة إلى نسبة من الفاتورة.
///
/// المصدر: GET /api/clinic-doctors -- وهو مسار **محروس بباقة العيادات
/// (Premium Plus)** فيعيد 403 لحساب Premium عادي. ذلك ليس خطأً بل الحالة
/// الطبيعية لأغلب العيادات: قائمة فارغة تعني عيادة بطبيب واحد، فيختفي اختيار
/// الطبيب من واجهة المواعيد كلياً بدل أن يظهر فارغاً. شاشة الأطباء وحدها
/// تُظهر بطاقة "الميزة تحتاج باقة العيادات" لأن 403 هناك هو جواب السؤال.
class ClinicDoctor {
  final int id;
  final String fullName;
  final String? phone;
  final String? specialty;
  final double commissionPercent;
  final bool isActive;
  final String? notes;

  /// أرقام الفترة المطلوبة (الشهر الحالي افتراضياً من طرف الخادم).
  final double periodCollected;
  final double periodDoctorShare;
  final double periodClinicShare;

  /// أرقام تراكمية. الرصيد المستحق لا معنى له إلا تراكمياً: ما استحقّه
  /// الطبيب منذ البداية ناقص ما سُلِّم له فعلاً، بصرف النظر عن الشهر
  /// المعروض -- فلا تُعرَض هذه الثلاثة داخل شارة الفترة.
  final double totalDoctorShare;
  final double totalPaidOut;
  final double balanceDue;

  const ClinicDoctor({
    required this.id,
    required this.fullName,
    this.phone,
    this.specialty,
    this.commissionPercent = 0,
    this.isActive = true,
    this.notes,
    this.periodCollected = 0,
    this.periodDoctorShare = 0,
    this.periodClinicShare = 0,
    this.totalDoctorShare = 0,
    this.totalPaidOut = 0,
    this.balanceDue = 0,
  });

  /// الاسم بلا بادئة "د." -- للشرائح الضيقة وترويسات الأعمدة.
  String get shortName {
    final cleaned = fullName.replaceFirst(RegExp(r'^د\.\s*'), '').trim();
    if (cleaned.isEmpty) return fullName;
    final parts = cleaned.split(RegExp(r'\s+'));
    return parts.isEmpty ? cleaned : parts.first;
  }

  /// حرفان للأفاتار المربّع (نفس نمط ترويسة العمود في appointments.html).
  String get initials {
    final cleaned = fullName.replaceFirst(RegExp(r'^د\.\s*'), '').trim();
    if (cleaned.isEmpty) return 'ع';
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'ع';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return parts[0].substring(0, 1) + parts[1].substring(0, 1);
  }

  /// النسبة بلا أصفار زائدة: 40 لا 40.0، و37.5 تبقى 37.5.
  String get commissionLabel {
    final rounded = commissionPercent.roundToDouble();
    if ((commissionPercent - rounded).abs() < 0.005) {
      return rounded.toStringAsFixed(0);
    }
    return commissionPercent
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  ClinicDoctor copyWith({
    String? fullName,
    String? phone,
    String? specialty,
    double? commissionPercent,
    bool? isActive,
    String? notes,
  }) {
    return ClinicDoctor(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      specialty: specialty ?? this.specialty,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      periodCollected: periodCollected,
      periodDoctorShare: periodDoctorShare,
      periodClinicShare: periodClinicShare,
      totalDoctorShare: totalDoctorShare,
      totalPaidOut: totalPaidOut,
      balanceDue: balanceDue,
    );
  }

  /// يقرأ int أو num أو نصاً -- الخادم يرسل الأرقام المالية كـ float، لكن
  /// JSON قد يعيد 0 كـ int، وهو ليس double في Dart فيرفع خطأ صنف لو قُرئ
  /// بـ `as double`. هذا سبب مباشر لتعطّل شاشة كامل لا مجرد احتراز.
  static double _money(Object? value) {
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

  static String? _optionalText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  factory ClinicDoctor.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawActive = json['is_active'];
    return ClinicDoctor(
      id: rawId is int
          ? rawId
          : (rawId is num ? rawId.round() : int.parse(rawId.toString())),
      fullName: (json['full_name'] as String?)?.trim() ?? '',
      phone: _optionalText(json['phone']),
      specialty: _optionalText(json['specialty']),
      commissionPercent: _money(json['commission_percent']),
      isActive: rawActive is bool ? rawActive : rawActive != 0,
      notes: _optionalText(json['notes']),
      periodCollected: _money(json['period_collected']),
      periodDoctorShare: _money(json['period_doctor_share']),
      periodClinicShare: _money(json['period_clinic_share']),
      totalDoctorShare: _money(json['total_doctor_share']),
      totalPaidOut: _money(json['total_paid_out']),
      balanceDue: _money(json['balance_due']),
    );
  }
}
