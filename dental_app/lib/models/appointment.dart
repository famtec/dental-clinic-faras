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

/// مدد الموعد المسموحة -- مطابقة حرفياً لـ APPOINTMENT_DURATION_CHOICES في
/// main.py (ربع ساعة حتى ٣ ساعات بخطوة ربع ساعة). أي قيمة أخرى يعيدها الخادم
/// إلى أقرب مدة مسموحة، فلا فائدة من إرسال غيرها.
const List<int> appointmentDurationChoices = [
  15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180,
];

/// القيمة الافتراضية نفسها في قاعدة البيانات وفي الخادم: أي موعد قديم (أو
/// أُنشئ من عميل لا يرسل المدة) يُعامَل كنصف ساعة.
const int defaultAppointmentDurationMinutes = 30;

/// التسميات العربية المختصرة -- نفس نصوص APPOINTMENT_DURATION_OPTIONS في
/// appointments.html حتى يقرأ الطبيب المدة بنفس الكلمات على الموقع والتطبيق.
const Map<int, String> appointmentDurationShortLabelsAr = {
  15: 'ربع ساعة',
  30: 'نصف ساعة',
  45: '45 دقيقة',
  60: 'ساعة',
  75: 'ساعة وربع',
  90: 'ساعة ونصف',
  105: 'ساعة و45 د',
  120: 'ساعتان',
  135: 'ساعتان وربع',
  150: 'ساعتان ونصف',
  165: 'ساعتان و45 د',
  180: 'ثلاث ساعات',
};

/// أقرب مدة مسموحة لأي قيمة واردة، وعند التساوي تُختار الأقصر -- نفس منطق
/// normalize_appointment_duration في main.py بالضبط، حتى لا يختلف ما يعرضه
/// التطبيق عمّا يخزّنه الخادم.
int normalizeAppointmentDuration(Object? value) {
  int? minutes;
  if (value is int) {
    minutes = value;
  } else if (value is num) {
    minutes = value.round();
  } else if (value is String) {
    minutes = int.tryParse(value.trim());
  }
  if (minutes == null) return defaultAppointmentDurationMinutes;
  if (appointmentDurationChoices.contains(minutes)) return minutes;
  if (minutes <= 0) return defaultAppointmentDurationMinutes;
  var best = appointmentDurationChoices.first;
  var bestDistance = (best - minutes).abs();
  for (final choice in appointmentDurationChoices) {
    final distance = (choice - minutes).abs();
    if (distance < bestDistance) {
      best = choice;
      bestDistance = distance;
    }
  }
  return best;
}

String appointmentDurationLabel(int minutes) =>
    appointmentDurationShortLabelsAr[minutes] ?? '$minutes دقيقة';

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

  /// مدة الموعد بالدقائق (أُضيف 2026-09-17) -- كانت الشاشة تنشئ كل المواعيد
  /// بنصف ساعة ضمنياً لأن التطبيق لم يكن يرسل الحقل إطلاقاً. عليها يقوم
  /// عرض المدى (من ... إلى ...) وارتفاع البطاقة في جدول الساعات.
  final int durationMinutes;

  /// الطبيب المنفّذ للموعد في العيادة متعددة الأطباء (أُضيف 2026-09-17).
  /// **null = صاحب الحساب (الطبيب المدير)** لا "غير محدّد" -- نفس دلالة
  /// NULL في appointments.clinic_doctor_id على الخادم، فعيادة الطبيب الواحد
  /// كل مواعيدها null وهذا صحيح لا ناقص.
  final int? clinicDoctorId;

  /// اسم الطبيب المنفّذ كما يرسله الخادم مع كل موعد -- يُعرَض مباشرة بلا أن
  /// يحتاج التطبيق استدعاء /api/clinic-doctors (محروس بباقة العيادات فيعيد
  /// 403 لحساب Premium عادي). null لموعد الطبيب المدير.
  final String? clinicDoctorName;

  /// حالة المزامنة مع السيرفر -- 'synced' دائماً لأي موعد قادم فعلياً من
  /// الـ backend (fromJson). القيم الأخرى ('pending_create' / 'pending_update'
  /// / 'pending_delete') لا تظهر إلا لموعد أُنشئ/عُدِّل/حُذف أوفلاين وما زال
  /// بانتظار الاتصال بالإنترنت ليصل فعلياً للسيرفر -- انظر
  /// OfflineAwareApiService وLocalDb. أُضيف 2026-08-31 كجزء من دعم العمل بدون
  /// إنترنت (تجربة أولى بشاشة المواعيد).
  final String syncStatus;

  /// حرس الحالة الثلاثية في copyWith (عام لأن OfflineAwareApiService يحتاجه).
  ///
  /// `null` قيمة حقيقية للطبيب المنفّذ -- تعني "أعِد الموعد للطبيب المدير" --
  /// فلا يجوز أن تعني "لا تغيير" كما تفعل `??`. بدون هذا الحرس يصير إرجاع
  /// موعد من طبيب مساعد إلى المدير مستحيلاً بصمت، وهو نفس الفخّ المعروف على
  /// الخادم (model_fields_set في AppointmentUpdate).
  static const Object unchangedMarker = Object();

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
    this.durationMinutes = defaultAppointmentDurationMinutes,
    this.clinicDoctorId,
    this.clinicDoctorName,
    this.syncStatus = 'synced',
  });

  bool get isPendingSync => syncStatus != 'synced';

  String get statusLabel =>
      appointmentStatusLabelsAr[status.toLowerCase()] ?? status;

  String get durationLabel => appointmentDurationLabel(durationMinutes);

  /// دقائق بداية الموعد من منتصف الليل، مقروءة من النص "HH:MM" أولاً لا من
  /// appointmentDate -- الأخير قد يصل مزاحاً بتوقيت UTC، وهو الفخّ الموثّق في
  /// main.py عند update_appointment. null إن كان الوقت غير صالح.
  int? get startMinutes {
    final parts = appointmentTime.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0].trim());
      final minute = int.tryParse(parts[1].trim());
      if (hour != null && minute != null) return (hour * 60) + minute;
    }
    final date = appointmentDate;
    if (date == null) return null;
    return (date.hour * 60) + date.minute;
  }

  int? get endMinutes {
    final start = startMinutes;
    return start == null ? null : start + durationMinutes;
  }

  static String formatMinutes(int value) {
    final normalized = value % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// "10:00 — 11:30" أو "—" إن كان الوقت غير صالح.
  String get timeRangeLabel {
    final start = startMinutes;
    if (start == null) return '—';
    return '${formatMinutes(start)} — ${formatMinutes(start + durationMinutes)}';
  }

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
    final rawDoctorId = json['clinic_doctor_id'];
    final rawDoctorName = json['clinic_doctor_name'];
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
      // خادم قديم لا يرسل الحقل -> نصف ساعة، وهي نفس قيمته الافتراضية.
      durationMinutes: normalizeAppointmentDuration(json['duration_minutes']),
      clinicDoctorId: rawDoctorId is int
          ? rawDoctorId
          : (rawDoctorId is num
              ? rawDoctorId.round()
              : (rawDoctorId is String ? int.tryParse(rawDoctorId.trim()) : null)),
      clinicDoctorName: rawDoctorName is String && rawDoctorName.trim().isNotEmpty
          ? rawDoctorName.trim()
          : null,
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
    int? durationMinutes,
    // انظر unchangedMarker أعلاه: null هنا تعني "أرجِعه للطبيب المدير" فعلاً.
    Object? clinicDoctorId = unchangedMarker,
    Object? clinicDoctorName = unchangedMarker,
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
      durationMinutes: durationMinutes ?? this.durationMinutes,
      clinicDoctorId: identical(clinicDoctorId, unchangedMarker)
          ? this.clinicDoctorId
          : clinicDoctorId as int?,
      clinicDoctorName: identical(clinicDoctorName, unchangedMarker)
          ? this.clinicDoctorName
          : clinicDoctorName as String?,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
