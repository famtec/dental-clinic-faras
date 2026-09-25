import 'dart:async';
import 'dart:convert';

import '../models/appointment.dart';
import '../models/finance_summary.dart';
import '../models/finance_transaction.dart';
import '../models/inventory_item.dart';
import '../models/patient.dart';
import '../models/patient_stats.dart';
import '../models/treatment_invoice.dart';
import 'api_service.dart';
import 'appointment_reminder_service.dart';
import 'connectivity_service.dart';
import 'local_db.dart';
import 'offline_sync_status.dart';

/// نسخة من ApiService تعمل بدون إنترنت. بدأت 2026-08-31 بشاشة المواعيد
/// وحدها (تجربة أولى)، ثم وُسِّعت 2026-09-02 لتغطي المرضى/مخطط الأسنان/
/// المخزون/الفواتير أيضاً (بطلب المستخدم "ابني نفس النمط على جميع
/// الشاشات..."). الفكرة العامة، مطابقة لكل الكيانات:
///
/// - القراءة: تحاول السيرفر أولاً كالمعتاد؛ عند نجاحها تُحدَّث النسخة
///   المحلية وتُرجَع؛ عند فشلها بسبب انقطاع اتصال فعلي (لا رفض حقيقي من
///   السيرفر) تُقرَأ آخر نسخة محفوظة محلياً بدل رمي خطأ يوقف الشاشة.
/// - الكتابة: تحاول السيرفر أولاً؛ عند فشلها بانقطاع اتصال، تُطبَّق التغييرات
///   محلياً فوراً (فيراها الطبيب مباشرة) وتُسجَّل بقائمة انتظار (outbox) لتُرسَل
///   تلقائياً بمجرد عودة الشبكة، دون أي إجراء إضافي من الطبيب.
///
/// كيانان لهما جدول محلي مدمَج حقيقي (نفس بنية المواعيد بالضبط) لأن قوائمهما
/// تحتاج عرضاً كاملاً أوفلاين حتى بعد إغلاق الشاشة وإعادة فتحها: المرضى
/// (patients، ويحمل عمود chart_state فمخطط الأسنان جزء منه) والمخزون
/// (inventory_items). أما فواتير العلاج/دفعاتها والتقرير المالي/آخر
/// الحركات/إحصائيات المرضى فحقولها محسوبة من طرف السيرفر (متبقٍ/صافي
/// ربح/...)، فتخزينها محلياً بجدول مدمَج مماثل يعني إعادة بناء تلك الحسابات
/// هنا أيضاً -- خطر حقيقي على دقة الأرقام المالية. بدلاً من ذلك:
/// - القراءة منها تُخزَّن مؤقتاً (cache_kv، آخر استجابة ناجحة فقط) وتُعرض كما
///   هي عند انقطاع الاتصال (بلا أي تعديل عليها).
/// - الكتابة عليها (فاتورة/دفعة/مصروف جديد، أو تعديل دفعة) تمر عبر outbox
///   فقط، وتُعيد نسخة **تقديرية** محسوبة من آخر بيانات معروفة (محلياً أو من
///   outbox نفسه) لعرضها فوراً في الشاشة الحالية؛ الأرقام النهائية الدقيقة
///   تصل فعلياً بعد المزامنة (أول فتح تالٍ للشاشة بعد عودة الاتصال).
///
/// حالتان مستثناتان صراحة من الدعم الأوفلاين (بنفس فلسفة respondToBooking
/// أدناه -- حالات نادرة، أوضح كخطأ صريح من محاولة دعمها بمنطق هش): إنشاء
/// فاتورة أو تسجيل دفعة لمريض أُنشئ هو نفسه أوفلاين ولم يُزامَن بعد (تعديل
/// مخطط أسنانه ممنوع للسبب نفسه)، لأن ربطها الصحيح بالمريض الحقيقي على
/// السيرفر يحتاج مزامنة المريض أولاً.
///
/// **مهم**: التمييز بين "انقطاع اتصال" و"رفض حقيقي من السيرفر" يعتمد على
/// ApiException.statusCode كما في النسخة الأصلية (انظر [_isConnectivityFailure]).
class OfflineAwareApiService extends ApiService {
  OfflineAwareApiService(super.authStorage) {
    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      OfflineSyncStatus.instance.isOnline.value = online;
      if (online) unawaited(_trySync());
    });
    // شبكة صافرة بلا اعتماد كلي على أحداث connectivity_plus (قد تُفوَّت حالات
    // نادرة) -- محاولة مزامنة كل دقيقتين إن كانت هناك عمليات معلّقة أصلاً.
    _periodicTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_trySync());
    });
  }

  final LocalDb _db = LocalDb.instance;
  final ConnectivityService _connectivity = ConnectivityService();
  late final StreamSubscription<bool> _connectivitySub;
  late final Timer _periodicTimer;
  bool _syncing = false;

  void dispose() {
    _connectivitySub.cancel();
    _periodicTimer.cancel();
  }

  /// انقطاع اتصال حقيقي (لا رفض من السيرفر) -- نفس القاعدة الموضّحة أعلى
  /// الملف.
  bool _isConnectivityFailure(ApiException e) => e.statusCode == null;

  Future<void> _refreshPendingCount() async {
    OfflineSyncStatus.instance.pendingCount.value = await _db.countPendingOps();
    OfflineSyncStatus.instance.failedCount.value = await _db.countFailedOps();
  }

  // ===========================================================================
  // مواعيد -- كما كانت منذ 2026-08-31، بلا أي تعديل جوهري (انظر
  // _applyAppointmentOp أدناه لمكان انتقال منطق المزامنة نفسه بلا تغيير).
  // ===========================================================================

  /// تذكيرات المواعيد تُعاد جدولتها من كل قائمة مواعيد تُجلب (2026-09-25) --
  /// نقطة واحدة تمرّ بها كل الشاشات، أونلاين أو من النسخة المحلية.
  List<Appointment> _withReminders(List<Appointment> appointments) {
    unawaited(AppointmentReminderService.instance.sync(appointments));
    return appointments;
  }

  @override
  Future<List<Appointment>> fetchAppointments() async {
    try {
      final fresh = await super.fetchAppointments();
      await _db.replaceServerAppointments(fresh);
      OfflineSyncStatus.instance.isOnline.value = true;
      unawaited(_trySync());
      return _withReminders(await _db.getAllAppointmentsMerged());
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      OfflineSyncStatus.instance.isOnline.value = false;
      return _withReminders(await _db.getAllAppointmentsMerged());
    }
  }

  @override
  Future<Appointment> createAppointment({
    required int patientId,
    required String date,
    required String time,
    required String description,
    String? patientNameHint,
    String? patientPhoneHint,
    int? durationMinutes,
    int? clinicDoctorId,
    // اسم الطبيب المنفّذ -- للعرض وحده على الموعد المؤقّت أثناء انتظار
    // المزامنة: الخادم هو من يرسل الاسم عادةً، ولا يوجد خادم الآن.
    String? clinicDoctorNameHint,
  }) async {
    try {
      final created = await super.createAppointment(
        patientId: patientId,
        date: date,
        time: time,
        description: description,
        durationMinutes: durationMinutes,
        clinicDoctorId: clinicDoctorId,
      );
      await _db.upsertAppointment(created.copyWith(syncStatus: 'synced'));
      return created;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final localId = _db.nextLocalId();
      final placeholder = Appointment(
        id: localId,
        patientName: patientNameHint ?? '',
        appointmentDate: DateTime.tryParse(date),
        appointmentTime: time,
        procedureType: description,
        status: 'pending',
        patientPhone: patientPhoneHint,
        patientId: patientId,
        durationMinutes:
            normalizeAppointmentDuration(durationMinutes),
        clinicDoctorId: clinicDoctorId,
        clinicDoctorName: clinicDoctorNameHint,
        syncStatus: 'pending_create',
      );
      await _db.upsertAppointment(placeholder);
      await _db.enqueue(
        entityType: 'appointment',
        operation: 'create',
        targetId: localId,
        payload: {
          'patient_id': patientId,
          'date': date,
          'time': time,
          'description': description,
          'duration_minutes': normalizeAppointmentDuration(durationMinutes),
          'clinic_doctor_id': clinicDoctorId,
        },
      );
      await _refreshPendingCount();
      return placeholder;
    }
  }

  @override
  Future<Appointment> updateAppointment(
    int appointmentId, {
    required DateTime appointmentDateTime,
    required String time,
    required String description,
    int? durationMinutes,
    int? clinicDoctorId,
    bool sendClinicDoctor = true,
    String? clinicDoctorNameHint,
  }) async {
    try {
      final updated = await super.updateAppointment(
        appointmentId,
        appointmentDateTime: appointmentDateTime,
        time: time,
        description: description,
        durationMinutes: durationMinutes,
        clinicDoctorId: clinicDoctorId,
        sendClinicDoctor: sendClinicDoctor,
      );
      await _db.upsertAppointment(updated.copyWith(syncStatus: 'synced'));
      return updated;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getAppointment(appointmentId);
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
      final effectiveDuration = durationMinutes ??
          existing?.durationMinutes ??
          defaultAppointmentDurationMinutes;
      final placeholder = (existing ??
              Appointment(
                id: appointmentId,
                patientName: '',
                appointmentDate: appointmentDateTime,
                appointmentTime: time,
                procedureType: description,
                status: 'pending',
              ))
          .copyWith(
        appointmentDate: appointmentDateTime,
        appointmentTime: time,
        procedureType: description,
        durationMinutes: effectiveDuration,
        // sendClinicDoctor == false تعني "لا تلمس الطبيب"، فلا يُمرَّر المفتاح
        // للـ copyWith أصلاً ويبقى ما هو عليه. أما تمريره بـ null فيعني
        // "أعِده للمدير" فعلاً -- انظر Appointment._unchanged.
        clinicDoctorId:
            sendClinicDoctor ? clinicDoctorId : Appointment.unchangedMarker,
        clinicDoctorName: sendClinicDoctor
            ? clinicDoctorNameHint
            : Appointment.unchangedMarker,
        syncStatus: keepCreateStatus ? 'pending_create' : 'pending_update',
      );
      await _db.upsertAppointment(placeholder);
      if (!keepCreateStatus) {
        await _db.enqueue(
          entityType: 'appointment',
          operation: 'update',
          targetId: appointmentId,
          payload: {
            'appointment_date': appointmentDateTime.toIso8601String(),
            'appointment_time': time,
            'description': description,
            'duration_minutes': effectiveDuration,
            // مفتاح منفصل يميّز "أُرسِل الطبيب صراحةً" من "لم يُرسَل"، فتبقى
            // الحالة الثلاثية سليمة عبر الـ outbox أيضاً لا في الطلب وحده.
            'send_clinic_doctor': sendClinicDoctor,
            'clinic_doctor_id': clinicDoctorId,
          },
        );
      }
      await _refreshPendingCount();
      return placeholder;
    }
  }

  @override
  Future<void> deleteAppointment(int appointmentId) async {
    try {
      await super.deleteAppointment(appointmentId);
      await _db.deleteAppointmentRow(appointmentId);
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      if (appointmentId < 0) {
        await _db.deleteAppointmentRow(appointmentId);
        await _db.cancelPendingOpsFor(appointmentId);
      } else {
        await _db.markAppointmentPendingDelete(appointmentId);
        await _db.enqueue(
          entityType: 'appointment',
          operation: 'delete',
          targetId: appointmentId,
          payload: const {},
        );
      }
      await _refreshPendingCount();
    }
  }

  @override
  Future<void> updateAppointmentStatus(int appointmentId, String status) async {
    try {
      await super.updateAppointmentStatus(appointmentId, status);
      await _db.updateAppointmentStatusLocal(appointmentId, status,
          syncStatus: 'synced');
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getAppointment(appointmentId);
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
      await _db.updateAppointmentStatusLocal(
        appointmentId,
        status,
        syncStatus: keepCreateStatus ? 'pending_create' : 'pending_update',
      );
      if (!keepCreateStatus) {
        await _db.enqueue(
          entityType: 'appointment',
          operation: 'status',
          targetId: appointmentId,
          payload: {'status': status},
        );
      }
      await _refreshPendingCount();
    }
  }

  @override
  Future<void> respondToBooking(int appointmentId, String decision) async {
    try {
      await super.respondToBooking(appointmentId, decision);
      await _db.deleteAppointmentRow(appointmentId);
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      throw const ApiException(
          'قبول/رفض طلبات الحجز يحتاج اتصالاً بالإنترنت حالياً. حاول عند عودة الشبكة.');
    }
  }

  // ===========================================================================
  // مرضى + مخطط الأسنان -- أُضيف 2026-09-02.
  // ===========================================================================

  @override
  Future<List<Patient>> fetchPatients() async {
    try {
      final fresh = await super.fetchPatients();
      await _db.replaceServerPatients(fresh);
      OfflineSyncStatus.instance.isOnline.value = true;
      unawaited(_trySync());
      return await _db.getAllPatientsMerged();
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      OfflineSyncStatus.instance.isOnline.value = false;
      return await _db.getAllPatientsMerged();
    }
  }

  /// بطاقات الإحصائيات فوق قائمة المرضى -- قراءة بسيطة بلا كيان قابل
  /// للتعديل، فتُخزَّن مؤقتاً (cache_kv) وتُعرض كما هي عند انقطاع الاتصال
  /// بدل "--" الفارغة التي كانت تظهر سابقاً؛ الشاشة أصلاً تتجاهل أي فشل هنا
  /// بصمت (انظر _loadStats في patients_list_screen.dart) فلا حاجة لأي تمييز
  /// بين أنواع الفشل.
  @override
  Future<PatientStats> fetchPatientStats() async {
    const cacheKey = 'patient_stats';
    try {
      final fresh = await super.fetchPatientStats();
      await _db.setCache(cacheKey, json.encode(fresh.toJson()));
      return fresh;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final cached = await _db.getCache(cacheKey);
      if (cached == null) rethrow;
      return PatientStats.fromJson(json.decode(cached) as Map<String, dynamic>);
    }
  }

  @override
  Future<Patient> createPatient({
    required String fullName,
    required String phone,
    DateTime? birthDate,
    String? gender,
    String? medicalHistory,
    int? clinicDoctorId,
    String? clinicDoctorNameHint,
  }) async {
    try {
      final created = await super.createPatient(
        fullName: fullName,
        phone: phone,
        birthDate: birthDate,
        gender: gender,
        medicalHistory: medicalHistory,
        clinicDoctorId: clinicDoctorId,
      );
      await _db.upsertPatient(created.copyWith(syncStatus: 'synced'));
      return created;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final localId = _db.nextLocalId();
      final placeholder = Patient(
        id: localId,
        fullName: fullName,
        phone: phone,
        gender: gender,
        birthDate: birthDate,
        medicalHistory: medicalHistory,
        totalTreatmentCost: 0,
        paidAmount: 0,
        clinicDoctorId: clinicDoctorId,
        clinicDoctorName: clinicDoctorId == null ? null : clinicDoctorNameHint,
        syncStatus: 'pending_create',
      );
      await _db.upsertPatient(placeholder);
      await _db.enqueue(
        entityType: 'patient',
        operation: 'create',
        targetId: localId,
        payload: {
          'full_name': fullName,
          'phone': phone,
          if (birthDate != null) 'birth_date': _formatDate(birthDate),
          'gender': gender,
          'medical_history': medicalHistory,
          'clinic_doctor_id': clinicDoctorId,
        },
      );
      await _refreshPendingCount();
      return placeholder;
    }
  }

  @override
  Future<Patient> updatePatient(
    int patientId, {
    required String fullName,
    required String phone,
    required String medicalHistory,
    DateTime? birthDate,
    int? clinicDoctorId,
    bool sendClinicDoctor = false,
    String? clinicDoctorNameHint,
  }) async {
    try {
      final updated = await super.updatePatient(
        patientId,
        fullName: fullName,
        phone: phone,
        medicalHistory: medicalHistory,
        birthDate: birthDate,
        clinicDoctorId: clinicDoctorId,
        sendClinicDoctor: sendClinicDoctor,
      );
      await _db.upsertPatient(updated.copyWith(syncStatus: 'synced'));
      return updated;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getPatientLocal(patientId);
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
      final placeholder = (existing ??
              Patient(
                id: patientId,
                fullName: fullName,
                phone: phone,
                totalTreatmentCost: 0,
                paidAmount: 0,
              ))
          .copyWith(
        fullName: fullName,
        phone: phone,
        medicalHistory: medicalHistory,
        birthDate: birthDate,
        clinicDoctorId:
            sendClinicDoctor ? clinicDoctorId : Patient.unchangedMarker,
        clinicDoctorName: sendClinicDoctor
            ? (clinicDoctorId == null ? null : clinicDoctorNameHint)
            : Patient.unchangedMarker,
        syncStatus: keepCreateStatus ? 'pending_create' : 'pending_update',
      );
      await _db.upsertPatient(placeholder);
      if (!keepCreateStatus) {
        await _db.enqueue(
          entityType: 'patient',
          operation: 'update',
          targetId: patientId,
          payload: {
            'full_name': fullName,
            'phone': phone,
            'medical_history': medicalHistory,
            if (birthDate != null) 'birth_date': _formatDate(birthDate),
            if (sendClinicDoctor) 'clinic_doctor_id': clinicDoctorId,
          },
        );
      }
      await _refreshPendingCount();
      return placeholder;
    }
  }

  /// تحديث مخطط الأسنان -- ممنوع صراحة لمريض أُنشئ أوفلاين ولم يُزامَن بعد
  /// (معرّفه سالب مؤقت): ربطه الصحيح بالمريض الحقيقي على السيرفر يحتاج
  /// مزامنة المريض أولاً، ودعم ذلك بمنطق إعادة توجيه مثل الفواتير أدناه غير
  /// مبرَّر لحالة نادرة (إنشاء مريض وتخطيط أسنانه فوراً بينما الجهاز أوفلاين).
  @override
  Future<Patient> updatePatientChart(
    int patientId,
    Map<String, String> chartState,
  ) async {
    if (patientId < 0) {
      // المريض نفسه أُنشئ أوفلاين ولم يُزامَن بعد (معرّف محلي مؤقت سالب) --
      // لا يمكن استدعاء endpoint المخطط لمريض غير موجود على السيرفر بعد.
      // بدل رفض التعديل كلياً (كما كان سابقاً)، نحفظه على سجل المريض المحلي
      // نفسه فقط، بلا أي عملية outbox منفصلة من نوع patient_chart: مزامنة
      // *إنشاء* هذا المريض لاحقاً (_applyPatientOp، حالة create أدناه) تتحقق
      // أصلاً من chartStateRaw المحلي وتُرسله للسيرفر فور نجاح الإنشاء --
      // فتصل بيانات المخطط تلقائياً مع أول مزامنة، دون تعقيد إضافي هنا ودون
      // أي عملية outbox يتيمة تحمل معرّفاً سالباً لن يُعاد ربطه لاحقاً.
      final existing = await _db.getPatientLocal(patientId);
      final placeholder = (existing ??
              Patient(
                id: patientId,
                fullName: '',
                phone: '',
                totalTreatmentCost: 0,
                paidAmount: 0,
              ))
          .copyWith(chartStateRaw: json.encode(chartState));
      await _db.upsertPatient(placeholder);
      return placeholder;
    }
    try {
      final updated = await super.updatePatientChart(patientId, chartState);
      await _db.upsertPatient(updated.copyWith(syncStatus: 'synced'));
      return updated;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getPatientLocal(patientId);
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
      final placeholder = (existing ??
              Patient(
                id: patientId,
                fullName: '',
                phone: '',
                totalTreatmentCost: 0,
                paidAmount: 0,
              ))
          .copyWith(
        chartStateRaw: json.encode(chartState),
        syncStatus: keepCreateStatus ? 'pending_create' : 'pending_update',
      );
      await _db.upsertPatient(placeholder);
      // عملية "chart" لا تحمل payload فعلياً -- وقت المزامنة تُقرأ أحدث نسخة
      // محلية لمخطط هذا المريض مباشرة (انظر _applyPatientChartOp)، لا القيمة
      // المحفوظة هنا وقت الإنشاء، حتى تصل دائماً آخر حالة حتى لو تراكمت عدة
      // تعديلات أوفلاين متتالية (تسجيل عدة أسنان قبل عودة الاتصال).
      await _db.enqueue(
        entityType: 'patient_chart',
        operation: 'chart',
        targetId: patientId,
        payload: const {},
      );
      await _refreshPendingCount();
      return placeholder;
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ===========================================================================
  // مخزون -- أُضيف 2026-09-02، نفس نمط المواعيد بالضبط (لا تبعية على أي كيان
  // آخر، فلا تعقيد إعادة توجيه كالفواتير أدناه).
  // ===========================================================================

  @override
  Future<List<InventoryItem>> fetchInventory() async {
    try {
      final fresh = await super.fetchInventory();
      await _db.replaceServerInventoryItems(fresh);
      unawaited(_trySync());
      return await _db.getAllInventoryItemsMerged();
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      return await _db.getAllInventoryItemsMerged();
    }
  }

  @override
  Future<InventoryItem> createInventoryItem({
    required String itemName,
    required int quantity,
    int minAlertQuantity = 5,
    double? unitCost,
  }) async {
    try {
      final created = await super.createInventoryItem(
        itemName: itemName,
        quantity: quantity,
        minAlertQuantity: minAlertQuantity,
        unitCost: unitCost,
      );
      await _db.upsertInventoryItem(created.copyWith(syncStatus: 'synced'));
      return created;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final localId = _db.nextLocalId();
      final placeholder = InventoryItem(
        id: localId,
        doctorEmail: '',
        itemName: itemName,
        quantity: quantity,
        minAlertQuantity: minAlertQuantity,
        unitCost: unitCost ?? 0,
        updatedAt: DateTime.now(),
        syncStatus: 'pending_create',
      );
      await _db.upsertInventoryItem(placeholder);
      await _db.enqueue(
        entityType: 'inventory',
        operation: 'create',
        targetId: localId,
        payload: {
          'item_name': itemName,
          'quantity': quantity,
          'min_alert_quantity': minAlertQuantity,
          'unit_cost': unitCost ?? 0,
        },
      );
      await _refreshPendingCount();
      return placeholder;
    }
  }

  @override
  Future<InventoryItem> updateInventoryItem(
    int itemId, {
    String? itemName,
    int? quantity,
    int? minAlertQuantity,
    double? unitCost,
  }) async {
    try {
      final updated = await super.updateInventoryItem(
        itemId,
        itemName: itemName,
        quantity: quantity,
        minAlertQuantity: minAlertQuantity,
        unitCost: unitCost,
      );
      await _db.upsertInventoryItem(updated.copyWith(syncStatus: 'synced'));
      return updated;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getInventoryItemLocal(itemId);
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
      final placeholder = (existing ??
              InventoryItem(
                id: itemId,
                doctorEmail: '',
                itemName: itemName ?? '',
                quantity: quantity ?? 0,
                minAlertQuantity: minAlertQuantity ?? 5,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
        itemName: itemName,
        quantity: quantity,
        minAlertQuantity: minAlertQuantity,
        unitCost: unitCost,
        updatedAt: DateTime.now(),
        syncStatus: keepCreateStatus ? 'pending_create' : 'pending_update',
      );
      await _db.upsertInventoryItem(placeholder);
      if (!keepCreateStatus) {
        await _db.enqueue(
          entityType: 'inventory',
          operation: 'update',
          targetId: itemId,
          payload: {
            if (itemName != null) 'item_name': itemName,
            if (quantity != null) 'quantity': quantity,
            if (minAlertQuantity != null) 'min_alert_quantity': minAlertQuantity,
            if (unitCost != null) 'unit_cost': unitCost,
          },
        );
      }
      await _refreshPendingCount();
      return placeholder;
    }
  }

  @override
  Future<void> deleteInventoryItem(int itemId) async {
    try {
      await super.deleteInventoryItem(itemId);
      await _db.deleteInventoryItemRow(itemId);
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      if (itemId < 0) {
        await _db.deleteInventoryItemRow(itemId);
        await _db.cancelPendingOpsFor(itemId);
      } else {
        final existing = await _db.getInventoryItemLocal(itemId);
        if (existing != null) {
          await _db.upsertInventoryItem(existing.copyWith(syncStatus: 'pending_delete'));
        }
        await _db.enqueue(
          entityType: 'inventory',
          operation: 'delete',
          targetId: itemId,
          payload: const {},
        );
      }
      await _refreshPendingCount();
    }
  }

  // ===========================================================================
  // فواتير العلاج + الدفعات + المصاريف + التقرير المالي -- أُضيف 2026-09-02.
  // انظر الشرح المطوَّل أعلى الملف لسبب عدم وجود جدول محلي مدمَج هنا.
  // ===========================================================================

  @override
  Future<List<TreatmentInvoice>> fetchPatientInvoices(int patientId) async {
    final cacheKey = 'patient_invoices:$patientId';
    try {
      final fresh = await super.fetchPatientInvoices(patientId);
      await _db.setCache(cacheKey, json.encode(fresh.map((i) => i.toJson()).toList()));
      return fresh;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      return await _cachedInvoices(patientId);
    }
  }

  Future<List<TreatmentInvoice>> _cachedInvoices(int patientId) async {
    final cached = await _db.getCache('patient_invoices:$patientId');
    if (cached == null) return const [];
    final decoded = json.decode(cached) as List;
    return decoded
        .map((item) => TreatmentInvoice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TreatmentInvoice?> _cachedInvoice(int patientId, int invoiceId) async {
    final all = await _cachedInvoices(patientId);
    for (final invoice in all) {
      if (invoice.id == invoiceId) return invoice;
    }
    return null;
  }

  /// كل الدفعات المعلَّقة (أوفلاين ولم تُزامَن بعد) المسجَّلة على فاتورة معيّنة،
  /// مستخرَجة مباشرة من outbox نفسه (لا نسخة محلية منفصلة لها) -- تُستخدَم
  /// لبناء نسخة تقديرية من الفاتورة تُعرض فوراً في addInvoicePayment أدناه.
  Future<({List<InvoicePayment> payments, double total})> _pendingPaymentsFor(
      int invoiceId) async {
    final ops = await _db.getPendingOpsByEntity('invoice_payment');
    final payments = <InvoicePayment>[];
    double total = 0;
    for (final op in ops) {
      final payload = json.decode(op['payload'] as String) as Map<String, dynamic>;
      if (payload['invoice_id'] != invoiceId) continue;
      final amount = (payload['amount'] as num).toDouble();
      total += amount;
      payments.add(InvoicePayment(
        id: op['target_id'] as int,
        amount: amount,
        description: (payload['description'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(op['created_at'] as int),
        isOpeningBalance: payload['is_opening_balance'] == true,
        syncStatus: 'pending',
      ));
    }
    return (payments: payments, total: total);
  }

  @override
  Future<TreatmentInvoice> createInvoice(
    int patientId, {
    required String title,
    required double totalCost,
    int? catalogItemId,
    int? clinicDoctorId,
    bool sendClinicDoctor = false,
    List<InvoiceMaterialInput>? materials,
  }) async {
    if (patientId < 0) {
      throw const ApiException(
          'يجب أن تتم مزامنة بيانات هذا المريض أولاً (بعد عودة الاتصال بالإنترنت) قبل إنشاء فاتورة له أوفلاين.');
    }
    try {
      return await super.createInvoice(
        patientId,
        title: title,
        totalCost: totalCost,
        catalogItemId: catalogItemId,
        clinicDoctorId: clinicDoctorId,
        sendClinicDoctor: sendClinicDoctor,
        materials: materials,
      );
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      // خصم المواد **لا يُؤجَّل** عن قصد: هو حركة مخزن حقيقية يفحص الخادم
      // كفايتها ويرفض الفاتورة كلها إن نقصت مادة. تأجيله كان سيُنشئ فاتورة
      // تبدو مكتملة اليوم، ثم تفشل عملية مزامنتها بعد يومين لأن المادة
      // نفدت في الأثناء -- فيبقى في الجهاز سجل مخزن كاذب لا يعرف الطبيب
      // أنه لم يُطبَّق. الفاتورة نفسها تُؤجَّل كما كانت، والمواد تُضاف
      // بضغطة بعد عودة الاتصال (addInvoiceMaterials).
      if (materials != null && materials.isNotEmpty) {
        throw const ApiException(
            'لا يمكن خصم المواد من المخزن دون اتصال. أنشئ الفاتورة الآن بلا '
            'مواد، ثم أضِف موادها من بطاقتها بعد عودة الاتصال.');
      }
      final localId = _db.nextLocalId();
      await _db.enqueue(
        entityType: 'invoice',
        operation: 'create',
        targetId: localId,
        payload: {
          'patient_id': patientId,
          'title': title,
          'total_cost': totalCost,
          // مرجع الحالة من اللائحة يُؤجَّل بلا خطر: لا يُغيِّر شيئاً في
          // المخزن ولا في الأرقام، وقيمته الوحيدة تجميع تقرير الربحية.
          if (catalogItemId != null) 'catalog_item_id': catalogItemId,
          // المفتاح حاضراً (ولو null) = اختيار صريح يُرسَل كما هو عند المزامنة.
          if (sendClinicDoctor || clinicDoctorId != null) 'clinic_doctor_id': clinicDoctorId,
        },
      );
      await _refreshPendingCount();
      return TreatmentInvoice(
        id: localId,
        patientId: patientId,
        title: title,
        totalCost: totalCost,
        paidAmount: 0,
        remainingAmount: totalCost,
        status: 'open',
        createdAt: DateTime.now(),
        payments: const [],
        syncStatus: 'pending_create',
        catalogItemId: catalogItemId,
        clinicDoctorId: clinicDoctorId,
        // بلا مواد، فالربح = كامل التكلفة. رقم صادق في هذه اللحظة: لم
        // تُخصَم مادة بعد.
        netProfit: totalCost,
      );
    }
  }

  @override
  Future<TreatmentInvoice> addInvoicePayment(
    int patientId,
    int invoiceId, {
    required double amount,
    String? description,
    bool isOpeningBalance = false,
  }) async {
    if (patientId < 0) {
      throw const ApiException(
          'يجب أن تتم مزامنة بيانات هذا المريض أولاً (بعد عودة الاتصال بالإنترنت) قبل تسجيل دفعة له أوفلاين.');
    }
    try {
      return await super.addInvoicePayment(
        patientId,
        invoiceId,
        amount: amount,
        description: description,
        isOpeningBalance: isOpeningBalance,
      );
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      await _db.enqueue(
        entityType: 'invoice_payment',
        operation: 'create',
        targetId: _db.nextLocalId(),
        payload: {
          'patient_id': patientId,
          'invoice_id': invoiceId,
          'amount': amount,
          'description': description,
          'is_opening_balance': isOpeningBalance,
        },
      );
      await _refreshPendingCount();

      // نبني نسخة تقديرية من الفاتورة لعرضها فوراً: التكلفة الإجمالية/العنوان
      // من آخر نسخة معروفة (من التخزين المؤقت إن كانت الفاتورة نفسها متزامنة
      // أصلاً، أو من payload عملية إنشائها المعلَّقة إن كانت هي الأخرى ما
      // زالت أوفلاين)، والمدفوع = مجموع كل الدفعات المعلَّقة على نفس الفاتورة
      // (بما فيها هذه الدفعة) فوق أي مدفوع سابق مؤكَّد من السيرفر.
      double totalCost;
      String title;
      double basePaid;
      List<InvoicePayment> basePayments;
      // ما لا تمسّه دفعةٌ أبداً: المواد المستهلكة وتكلفتها المجمَّدة والطبيب
      // المنفّذ والحالة من اللائحة (أُضيفت 2026-09-18). إهمالها هنا كان
      // سيُفرِّغ مواد الفاتورة من العرض بمجرّد تسجيل دفعة أوفلاين عليها،
      // فيقرأ الطبيب فاتورة بلا مواد وبربح = كامل قيمتها -- رقم كاذب.
      List<InvoiceMaterial> baseMaterials = const [];
      double baseMaterialsCost = 0;
      int? baseClinicDoctorId;
      String? baseClinicDoctorName;
      int? baseCatalogItemId;
      if (invoiceId < 0) {
        final createOps = await _db.getPendingOpsByEntity('invoice');
        Map<String, dynamic>? invoicePayload;
        for (final op in createOps) {
          if (op['target_id'] == invoiceId) {
            invoicePayload = json.decode(op['payload'] as String) as Map<String, dynamic>;
            break;
          }
        }
        totalCost = (invoicePayload?['total_cost'] as num?)?.toDouble() ?? amount;
        title = (invoicePayload?['title'] as String?) ?? '';
        basePaid = 0;
        basePayments = const [];
      } else {
        final cached = await _cachedInvoice(patientId, invoiceId);
        totalCost = cached?.totalCost ?? amount;
        title = cached?.title ?? '';
        basePaid = cached?.paidAmount ?? 0;
        basePayments = cached?.payments ?? const [];
        baseMaterials = cached?.materials ?? const [];
        baseMaterialsCost = cached?.materialsCost ?? 0;
        baseClinicDoctorId = cached?.clinicDoctorId;
        baseClinicDoctorName = cached?.clinicDoctorName;
        baseCatalogItemId = cached?.catalogItemId;
      }
      final pending = await _pendingPaymentsFor(invoiceId);
      final newPaidAmount = basePaid + pending.total;
      final remaining = totalCost - newPaidAmount;
      return TreatmentInvoice(
        id: invoiceId,
        patientId: patientId,
        title: title,
        totalCost: totalCost,
        paidAmount: newPaidAmount,
        remainingAmount: remaining < 0 ? 0 : remaining,
        status: remaining <= 0 ? 'closed' : 'open',
        createdAt: DateTime.now(),
        payments: [...basePayments, ...pending.payments],
        syncStatus: invoiceId < 0 ? 'pending_create' : 'pending_update',
        clinicDoctorId: baseClinicDoctorId,
        clinicDoctorName: baseClinicDoctorName,
        catalogItemId: baseCatalogItemId,
        materials: baseMaterials,
        materialsCost: baseMaterialsCost,
        // ربح الفاتورة مفوتَر لا محصَّل، فلا تغيّره دفعة: يُعاد حسابه من
        // التكلفة الإجمالية وتكلفة المواد كما يفعل الخادم بالضبط.
        netProfit: totalCost - baseMaterialsCost,
      );
    }
  }

  @override
  Future<void> updateFinanceTransaction(
    int transactionId, {
    required double amount,
    required String description,
    bool? isOpeningBalance,
  }) async {
    if (transactionId < 0) {
      // دفعة/مصروف سُجِّل أوفلاين ولم يصل للسيرفر بعد أصلاً -- لا حاجة لعملية
      // "تعديل" منفصلة، يكفي تصحيح payload عملية الإنشاء المعلَّقة نفسها (نفس
      // فلسفة keepCreateStatus في updateAppointment أعلاه) بلا أي محاولة
      // اتصال فعلية.
      final patch = {
        'amount': amount,
        'description': description,
        if (isOpeningBalance != null) 'is_opening_balance': isOpeningBalance,
      };
      await _db.patchPendingOpPayload(
        entityType: 'invoice_payment',
        targetId: transactionId,
        operation: 'create',
        patch: patch,
      );
      await _db.patchPendingOpPayload(
        entityType: 'expense',
        targetId: transactionId,
        operation: 'create',
        patch: patch,
      );
      return;
    }
    try {
      await super.updateFinanceTransaction(
        transactionId,
        amount: amount,
        description: description,
        isOpeningBalance: isOpeningBalance,
      );
      await _invalidateFinanceCaches();
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      await _db.enqueue(
        entityType: 'finance_transaction',
        operation: 'update',
        targetId: transactionId,
        payload: {
          'amount': amount,
          'description': description,
          if (isOpeningBalance != null) 'is_opening_balance': isOpeningBalance,
        },
      );
      await _refreshPendingCount();
    }
  }

  @override
  Future<({bool inventorySynced, String? inventoryAction})> createExpense({
    required double amount,
    required String description,
    bool addToInventory = false,
    String? inventoryItemName,
    int? inventoryQuantity,
  }) async {
    try {
      final result = await super.createExpense(
        amount: amount,
        description: description,
        addToInventory: addToInventory,
        inventoryItemName: inventoryItemName,
        inventoryQuantity: inventoryQuantity,
      );
      await _invalidateFinanceCaches();
      return result;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      await _db.enqueue(
        entityType: 'expense',
        operation: 'create',
        targetId: _db.nextLocalId(),
        payload: {
          'amount': amount,
          'description': description,
          if (addToInventory) 'add_to_inventory': true,
          if (addToInventory) 'inventory_item_name': inventoryItemName,
          if (addToInventory) 'inventory_quantity': inventoryQuantity,
        },
      );
      await _refreshPendingCount();
      // لا سبيل لمعرفة نتيجة الربط بالمخزون قبل وصول المصروف فعلياً للسيرفر
      // -- رسالة النجاح "الأغنى" في finance_screen.dart تُستبدَل هنا تلقائياً
      // بالرسالة العادية (inventorySynced: false)، وتُطبَّق نتيجة الربط
      // الحقيقية على المخزون بصمت وقت المزامنة.
      return (inventorySynced: false, inventoryAction: null);
    }
  }

  @override
  Future<FinanceSummary> fetchFinanceSummary({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
  }) async {
    final cacheKey = _financePeriodCacheKey('finance_summary', year, month, day, allTime);
    try {
      final fresh =
          await super.fetchFinanceSummary(year: year, month: month, day: day, allTime: allTime);
      await _db.setCache(cacheKey, json.encode(fresh.toJson()));
      return fresh;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final cached = await _db.getCache(cacheKey);
      if (cached == null) rethrow;
      return FinanceSummary.fromJson(json.decode(cached) as Map<String, dynamic>);
    }
  }

  @override
  Future<List<FinanceTransaction>> fetchFinanceTransactions({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
    int limit = 8,
  }) async {
    final cacheKey =
        '${_financePeriodCacheKey('finance_transactions', year, month, day, allTime)}:$limit';
    try {
      final fresh = await super.fetchFinanceTransactions(
          year: year, month: month, day: day, allTime: allTime, limit: limit);
      await _db.setCache(cacheKey, json.encode(fresh.map((t) => t.toJson()).toList()));
      return fresh;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final cached = await _db.getCache(cacheKey);
      if (cached == null) return const [];
      final decoded = json.decode(cached) as List;
      return decoded
          .map((item) => FinanceTransaction.fromJson(item as Map<String, dynamic>))
          .toList();
    }
  }

  static String _financePeriodCacheKey(
      String prefix, int? year, int? month, int? day, bool allTime) {
    if (allTime) return '$prefix:all';
    return '$prefix:${year ?? ''}-${month ?? ''}-${day ?? ''}';
  }

  /// تُبطِل (تحذف) كل قراءات الفواتير/التقرير المالي/آخر الحركات المخزَّنة
  /// مؤقتاً -- تُستدعى فور نجاح مزامنة أي عملية مالية معلَّقة (invoice/
  /// invoice_payment/finance_transaction/expense) حتى لا يُعرض في انقطاع
  /// اتصال لاحق رقم قديم يسبق تلك المزامنة. إبطال شامل عمداً بدل محاولة
  /// تحديث كل قراءة بدقة -- أسلم بكثير لبيانات مالية، وثمنه مجرد طلب شبكة
  /// إضافي واحد في المرة التالية التي تُفتح فيها الشاشة المعنية.
  Future<void> _invalidateFinanceCaches() async {
    await _db.deleteCacheWithPrefix('patient_invoices:');
    await _db.deleteCacheWithPrefix('finance_transactions:');
    await _db.deleteCacheWithPrefix('finance_summary:');
  }

  // ===========================================================================
  // محرّك المزامنة -- عام لكل الكيانات، يُشغَّل عمليات outbox بترتيب حدوثها.
  // ===========================================================================

  Future<void> _trySync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final ops = await _db.getPendingOps();
      for (final op in ops) {
        final opId = op['op_id'] as int;
        try {
          await _applyOp(op);
          await _db.markOpDone(opId);
        } on ApiException catch (e) {
          if (_isConnectivityFailure(e)) {
            // ما زلنا أوفلاين فعلياً (أو انقطع الاتصال أثناء المزامنة) --
            // نوقف المحاولة كاملة الآن، ستُستأنَف بالمحاولة القادمة.
            break;
          }
          // رفض حقيقي (مثلاً موعد حُذف من الموقع بالوقت نفسه) -- لا نكرر
          // المحاولة تلقائياً لهذه العملية بعينها، ونكمل البقية.
          await _db.markOpFailed(opId, e.message);
        } catch (_) {
          break;
        }
      }
    } finally {
      _syncing = false;
      await _refreshPendingCount();
    }
  }

  Future<void> _applyOp(Map<String, Object?> op) async {
    final entityType = op['entity_type'] as String;
    final operation = op['operation'] as String;
    final targetId = op['target_id'] as int;
    final payload =
        json.decode(op['payload'] as String) as Map<String, dynamic>;

    switch (entityType) {
      case 'appointment':
        await _applyAppointmentOp(operation, targetId, payload);
        break;
      case 'patient':
        await _applyPatientOp(operation, targetId, payload);
        break;
      case 'patient_chart':
        await _applyPatientChartOp(targetId);
        break;
      case 'inventory':
        await _applyInventoryOp(operation, targetId, payload);
        break;
      case 'invoice':
        await _applyInvoiceCreateOp(targetId, payload);
        break;
      case 'invoice_payment':
        await _applyInvoicePaymentOp(payload);
        break;
      case 'finance_transaction':
        await _applyFinanceTransactionUpdateOp(targetId, payload);
        break;
      case 'expense':
        await _applyExpenseOp(payload);
        break;
    }
  }

  Future<void> _applyAppointmentOp(
      String operation, int targetId, Map<String, dynamic> payload) async {
    switch (operation) {
      case 'create':
        // نقرأ الصف المحلي *قبل* الإرسال -- إن كان الطبيب عدّل تاريخ/وقت/
        // وصف/حالة هذا الموعد أوفلاين بعد إنشائه وقبل وصول هذه اللحظة
        // (updateAppointment/updateAppointmentStatus أعلاه تحدّثان الصف
        // المحلي فقط في هذه الحالة، دون تسجيل عملية outbox منفصلة -- انظر
        // شرحهما)، فهذا الصف يحمل أحدث نسخة فعلية يجب أن تصل للسيرفر، وليس
        // القيم الأصلية وقت الإنشاء المحفوظة بـ payload.
        final localBeforeSync = await _db.getAppointment(targetId);
        // 2026-09-17: المدة والطبيب من الحمولة إن وُجدا. عملية قديمة عالقة في
        // outbox من نسخة سابقة للتطبيق لا تحملهما، فتأخذ الافتراضي (نصف ساعة
        // والطبيب المدير) -- نفس سلوك التطبيق قبل هذا التحديث بالضبط، فلا
        // تُرفَض أي عملية معلّقة لدى طبيب حدّث تطبيقه وهو أوفلاين.
        var created = await super.createAppointment(
          patientId: payload['patient_id'] as int,
          date: payload['date'] as String,
          time: payload['time'] as String,
          description: payload['description'] as String,
          durationMinutes:
              normalizeAppointmentDuration(payload['duration_minutes']),
          clinicDoctorId: payload['clinic_doctor_id'] as int?,
        );
        if (localBeforeSync != null) {
          final payloadDuration =
              normalizeAppointmentDuration(payload['duration_minutes']);
          final payloadDoctorId = payload['clinic_doctor_id'] as int?;
          final editedAfterCreate =
              localBeforeSync.appointmentTime != (payload['time'] as String) ||
                  localBeforeSync.procedureType !=
                      (payload['description'] as String) ||
                  localBeforeSync.durationMinutes != payloadDuration ||
                  localBeforeSync.clinicDoctorId != payloadDoctorId ||
                  localBeforeSync.appointmentDate?.toIso8601String().split('T').first !=
                      (payload['date'] as String);
          if (editedAfterCreate) {
            created = await super.updateAppointment(
              created.id,
              appointmentDateTime: localBeforeSync.appointmentDate ??
                  created.appointmentDate ??
                  DateTime.now(),
              time: localBeforeSync.appointmentTime,
              description: localBeforeSync.procedureType,
              durationMinutes: localBeforeSync.durationMinutes,
              clinicDoctorId: localBeforeSync.clinicDoctorId,
            );
          }
          final localStatus = localBeforeSync.status.toLowerCase();
          if (localStatus != created.status.toLowerCase() &&
              localStatus != 'pending') {
            await super.updateAppointmentStatus(created.id, localBeforeSync.status);
            created = created.copyWith(status: localBeforeSync.status);
          }
        }
        await _db.remapLocalIdToServerId(targetId, created.id);
        await _db.upsertAppointment(
            created.copyWith(id: created.id, syncStatus: 'synced'));
        break;

      case 'update':
        // send_clinic_doctor يميّز "أُرسِل الطبيب صراحةً (ولو null)" من "لم
        // يُرسَل". عملية معلّقة قديمة بلا المفتاح تُعامَل كأنها لم ترسله، فلا
        // تُعيد موعداً لطبيب مساعد إلى المدير بالخطأ عند المزامنة.
        final sendDoctor = payload['send_clinic_doctor'] == true;
        final updated = await super.updateAppointment(
          targetId,
          appointmentDateTime:
              DateTime.parse(payload['appointment_date'] as String),
          time: payload['appointment_time'] as String,
          description: payload['description'] as String,
          durationMinutes: payload.containsKey('duration_minutes')
              ? normalizeAppointmentDuration(payload['duration_minutes'])
              : null,
          clinicDoctorId: payload['clinic_doctor_id'] as int?,
          sendClinicDoctor: sendDoctor,
        );
        await _db.upsertAppointment(updated.copyWith(syncStatus: 'synced'));
        break;

      case 'delete':
        await super.deleteAppointment(targetId);
        await _db.deleteAppointmentRow(targetId);
        break;

      case 'status':
        final status = payload['status'] as String;
        await super.updateAppointmentStatus(targetId, status);
        await _db.updateAppointmentStatusLocal(targetId, status,
            syncStatus: 'synced');
        break;
    }
  }

  Future<void> _applyPatientOp(
      String operation, int targetId, Map<String, dynamic> payload) async {
    switch (operation) {
      case 'create':
        // نفس مبدأ appointment/create أعلاه بالضبط: الصف المحلي *قبل* الإرسال
        // يحمل أحدث بيانات فعلية إن عدَّل الطبيب هذا المريض (أو مخطط أسنانه)
        // أوفلاين بعد إنشائه وقبل وصول هذه اللحظة.
        final localBeforeSync = await _db.getPatientLocal(targetId);
        var created = await super.createPatient(
          fullName: payload['full_name'] as String,
          phone: payload['phone'] as String,
          birthDate: payload['birth_date'] != null
              ? DateTime.tryParse(payload['birth_date'] as String)
              : null,
          gender: payload['gender'] as String?,
          medicalHistory: payload['medical_history'] as String?,
          clinicDoctorId: payload['clinic_doctor_id'] as int?,
        );
        if (localBeforeSync != null) {
          final doctorChangedAfterCreate =
              localBeforeSync.clinicDoctorId != created.clinicDoctorId;
          final editedAfterCreate = localBeforeSync.fullName != created.fullName ||
              localBeforeSync.phone != created.phone ||
              (localBeforeSync.medicalHistory ?? '') != (created.medicalHistory ?? '') ||
              doctorChangedAfterCreate;
          if (editedAfterCreate) {
            created = await super.updatePatient(
              created.id,
              fullName: localBeforeSync.fullName,
              phone: localBeforeSync.phone,
              medicalHistory: localBeforeSync.medicalHistory ?? '',
              birthDate: localBeforeSync.birthDate,
              clinicDoctorId: localBeforeSync.clinicDoctorId,
              sendClinicDoctor: doctorChangedAfterCreate,
            );
          }
          if ((localBeforeSync.chartStateRaw ?? '').trim().isNotEmpty) {
            created = await super.updatePatientChart(created.id, localBeforeSync.chartState);
          }
        }
        await _db.remapPatientLocalIdToServerId(targetId, created.id);
        await _db.upsertPatient(created.copyWith(syncStatus: 'synced'));
        break;

      case 'update':
        final updated = await super.updatePatient(
          targetId,
          fullName: payload['full_name'] as String,
          phone: payload['phone'] as String,
          medicalHistory: (payload['medical_history'] as String?) ?? '',
          birthDate: payload['birth_date'] != null
              ? DateTime.tryParse(payload['birth_date'] as String)
              : null,
          // وجود المفتاح في الحمولة هو "اختار الطبيب فعلاً" -- عملية في
          // الطابور من قبل هذا الحقل لا تحمله فلا تلمس الطبيب.
          clinicDoctorId: payload['clinic_doctor_id'] as int?,
          sendClinicDoctor: payload.containsKey('clinic_doctor_id'),
        );
        await _db.upsertPatient(updated.copyWith(syncStatus: 'synced'));
        break;
    }
  }

  Future<void> _applyPatientChartOp(int targetId) async {
    final local = await _db.getPatientLocal(targetId);
    if (local == null) return;
    final updated = await super.updatePatientChart(targetId, local.chartState);
    await _db.upsertPatient(updated.copyWith(syncStatus: 'synced'));
  }

  Future<void> _applyInventoryOp(
      String operation, int targetId, Map<String, dynamic> payload) async {
    switch (operation) {
      case 'create':
        final localBeforeSync = await _db.getInventoryItemLocal(targetId);
        var created = await super.createInventoryItem(
          itemName: payload['item_name'] as String,
          quantity: payload['quantity'] as int,
          minAlertQuantity: (payload['min_alert_quantity'] as int?) ?? 5,
          // عملية معلّقة من نسخة تطبيق سابقة لا تحمل المفتاح -> null فلا
          // يُرسَل، والخادم يضع صفراً: نفس السلوك قبل هذا التحديث.
          unitCost: (payload['unit_cost'] as num?)?.toDouble(),
        );
        if (localBeforeSync != null) {
          final editedAfterCreate = localBeforeSync.itemName != created.itemName ||
              localBeforeSync.quantity != created.quantity ||
              localBeforeSync.minAlertQuantity != created.minAlertQuantity ||
              localBeforeSync.unitCost != created.unitCost;
          if (editedAfterCreate) {
            created = await super.updateInventoryItem(
              created.id,
              itemName: localBeforeSync.itemName,
              quantity: localBeforeSync.quantity,
              minAlertQuantity: localBeforeSync.minAlertQuantity,
              unitCost: localBeforeSync.unitCost,
            );
          }
        }
        await _db.remapInventoryLocalIdToServerId(targetId, created.id);
        await _db.upsertInventoryItem(created.copyWith(syncStatus: 'synced'));
        break;

      case 'update':
        final updated = await super.updateInventoryItem(
          targetId,
          itemName: payload['item_name'] as String?,
          quantity: payload['quantity'] as int?,
          minAlertQuantity: payload['min_alert_quantity'] as int?,
          unitCost: (payload['unit_cost'] as num?)?.toDouble(),
        );
        await _db.upsertInventoryItem(updated.copyWith(syncStatus: 'synced'));
        break;

      case 'delete':
        await super.deleteInventoryItem(targetId);
        await _db.deleteInventoryItemRow(targetId);
        break;
    }
  }

  Future<void> _applyInvoiceCreateOp(int targetId, Map<String, dynamic> payload) async {
    final created = await super.createInvoice(
      payload['patient_id'] as int,
      title: payload['title'] as String,
      totalCost: (payload['total_cost'] as num).toDouble(),
      // العمليات المؤجَّلة قبل 2026-09-18 لا تحمل هذين المفتاحين، فيبقيان
      // null ولا تنكسر مزامنة فاتورة كانت في الطابور قبل التحديث.
      catalogItemId: (payload['catalog_item_id'] as num?)?.toInt(),
      clinicDoctorId: (payload['clinic_doctor_id'] as num?)?.toInt(),
      sendClinicDoctor: payload.containsKey('clinic_doctor_id'),
    );
    // إعادة توجيه أي دفعات أُضيفت أوفلاين على هذه الفاتورة قبل مزامنتها --
    // تُعالَج بنفسها بعد قليل بنفس دورة المزامنة (مرتَّبة دائماً بعد عملية
    // الإنشاء زمنياً)، لكن payload كل واحدة منها ما زال يشير لمعرّفها السالب
    // المؤقت، فيجب تصحيحه أولاً لمعرّف السيرفر الحقيقي.
    await _db.remapPendingInvoicePayments(oldInvoiceId: targetId, newInvoiceId: created.id);
    await _invalidateFinanceCaches();
  }

  Future<void> _applyInvoicePaymentOp(Map<String, dynamic> payload) async {
    await super.addInvoicePayment(
      payload['patient_id'] as int,
      payload['invoice_id'] as int,
      amount: (payload['amount'] as num).toDouble(),
      description: payload['description'] as String?,
      isOpeningBalance: payload['is_opening_balance'] == true,
    );
    await _invalidateFinanceCaches();
  }

  Future<void> _applyFinanceTransactionUpdateOp(
      int targetId, Map<String, dynamic> payload) async {
    await super.updateFinanceTransaction(
      targetId,
      amount: (payload['amount'] as num).toDouble(),
      description: payload['description'] as String,
      isOpeningBalance: payload['is_opening_balance'] as bool?,
    );
    await _invalidateFinanceCaches();
  }

  Future<void> _applyExpenseOp(Map<String, dynamic> payload) async {
    await super.createExpense(
      amount: (payload['amount'] as num).toDouble(),
      description: payload['description'] as String,
      addToInventory: payload['add_to_inventory'] == true,
      inventoryItemName: payload['inventory_item_name'] as String?,
      inventoryQuantity: payload['inventory_quantity'] as int?,
    );
    await _invalidateFinanceCaches();
  }
}
