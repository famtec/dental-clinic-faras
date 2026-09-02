/// حالات الموعد المعروفة في الـ backend (main.py) -- أي حالة أخرى تُعرض كما
/// هي بدون ترجمة عربية جاهزة (fallback آمن، لا يوقف عرض القائمة).
const Map<String, String> appointmentStatusLabelsAr = {
  'pending': 'قيد الانتظار',
  'pending_confirmation': 'طلب حجز جديد',
  'checked_in': 'دخل العيادة',
  'no_show': 'تخلّف عن الموعد',
  // القيم التالية لم تعد تُرسَل فعلياً من التطبيق بعد إصلاح مفردات الحالة
  // (كانت الشاشة القديمة ترسلها خطأً وهي غير مقبولة من الـ backend)، لكنها
  // تبقى هنا كترجمة احتياطية لأي بيانات قديمة قد تحمل هذه القيم.
  'confirmed': 'مؤكَّد',
  'completed': 'مكتمل',
  'cancelled': 'ملغى',
  'rejected': 'مرفوض',
};

class Appointment {
  final int id;
  final String patientName;
  final DateTime? appointmentDate;
  final String appointmentTime;
  final String procedureType;
  final String? notes;
  final String status;
  final String? patientPhone;
  // 2026-08-30: لازم لتصفية مواعيد مريض واحد من قائمة GET /api/appointments
  // الكاملة في شاشة "حالة المريض" -- مطابق لِـ isAppointmentForCurrentPatient()
  // في patient_record.html، التي تعتمد على patient_id أولاً (وتطابق الاسم
  // كبديل احتياطي فقط عند غيابه). قد يكون null لطلبات الحجز العام الواردة
  // من booking.html التي لم تُقبَل بعد.
  final int? patientId;

  /// حالة المزامنة مع السيرفر -- 'synced' دائماً لأي موعد قادم فعلياً من
  /// الـ backend (fromJson). القيم الأخرى ('pending_create' / 'pending_update'
  /// / 'pending_delete') لا تظهر إلا لموعد أُنشئ/عُدِّل/حُذف أوفلاين وما زال
  /// بانتظار الاتصال بالإنترنت ليصل فعلياً للسيرفر -- انظر
  /// OfflineAwareApiService وLocalDb. أُضيف 2026-08-31 كجزء من دعم العمل بدون
  /// إنترنت (تجربة أولى بشاشة المواعيد).
  final String syncStatus;

  const Appointment({
    required this.id,
    required this.patientName,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.procedureType,
    required this.status,
    this.notes,
    this.patientPhone,
    this.patientId,
    this.syncStatus = 'synced',
  });

  bool get isPendingSync => syncStatus != 'synced';

  String get statusLabel =>
      appointmentStatusLabelsAr[status.toLowerCase()] ?? status;

  bool get isToday {
    final date = appointmentDate;
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  factory Appointment.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    final rawDate = json['appointment_date'];
    if (rawDate is String && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate);
    }
    return Appointment(
      id: json['id'] as int,
      patientName: (json['patient_name'] as String?)?.trim() ?? '',
      appointmentDate: parsedDate,
      appointmentTime: (json['appointment_time'] as String?)?.trim() ?? '',
      procedureType: (json['procedure_type'] as String?)?.trim() ?? '',
      notes: json['notes'] as String?,
      status: (json['status'] as String?)?.trim() ?? 'pending',
      patientPhone: json['patient_phone'] as String?,
      patientId: json['patient_id'] as int?,
    );
  }

  Appointment copyWith({
    int? id,
    String? patientName,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? procedureType,
    String? notes,
    String? status,
    String? patientPhone,
    int? patientId,
    String? syncStatus,
  }) {
    return Appointment(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
      procedureType: procedureType ?? this.procedureType,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      patientPhone: patientPhone ?? this.patientPhone,
      patientId: patientId ?? this.patientId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
