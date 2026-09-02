import 'dart:async';
import 'dart:convert';

import '../models/appointment.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import 'local_db.dart';
import 'offline_sync_status.dart';

/// نسخة من ApiService تعمل بدون إنترنت لشاشة المواعيد تحديداً (تجربة أولى
/// -- سيُوسَّع لاحقاً لبقية الشاشات إن نجحت). الفكرة العامة:
///
/// - القراءة (fetchAppointments): تحاول السيرفر أولاً كالمعتاد؛ عند نجاحها
///   تُحدَّث النسخة المحلية وتُرجَع؛ عند فشلها بسبب انقطاع اتصال (لا رفض
///   حقيقي من السيرفر) تُقرَأ آخر نسخة محفوظة محلياً بدل رمي خطأ يوقف
///   الشاشة.
/// - الكتابة (create/update/delete/status): تحاول السيرفر أولاً؛ عند فشلها
///   بانقطاع اتصال، تُطبَّق التغييرات محلياً فوراً (فيراها الطبيب مباشرة في
///   القائمة) وتُسجَّل بقائمة انتظار (outbox) لتُرسَل تلقائياً بمجرد عودة
///   الشبكة، دون أي إجراء إضافي من الطبيب.
///
/// كل الدوال الموروثة الأخرى (مرضى، فواتير، مخزون، ...) تعمل كما هي دون أي
/// تغيير -- تحتاج اتصالاً بالإنترنت تماماً كما كانت.
///
/// **مهم**: التمييز بين "انقطاع اتصال" و"رفض حقيقي من السيرفر" يعتمد على
/// ApiException.statusCode: كل دالة بـ ApiService الأصلية ترمي استثناءً
/// بلا statusCode (null) حصراً حين يفشل http نفسه (SocketException/Timeout/
/// إلخ في catch (_))، وبـ statusCode فعلي (400/401/402/...) حين يردّ
/// السيرفر فعلاً برفض. الحالة الأولى فقط تُعامَل كأوفلاين وتُوضَع
/// بقائمة الانتظار؛ الثانية تُمرَّر للشاشة كما هي فوراً (لا داعي لتأجيل
/// خطأ تحقّق حقيقي، مثل موعد بحقل ناقص).
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

  // ---------------------------------------------------------------------
  // القراءة
  // ---------------------------------------------------------------------

  @override
  Future<List<Appointment>> fetchAppointments() async {
    try {
      final fresh = await super.fetchAppointments();
      await _db.replaceServerAppointments(fresh);
      OfflineSyncStatus.instance.isOnline.value = true;
      unawaited(_trySync());
      return await _db.getAllAppointmentsMerged();
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      OfflineSyncStatus.instance.isOnline.value = false;
      return await _db.getAllAppointmentsMerged();
    }
  }

  // ---------------------------------------------------------------------
  // الكتابة
  // ---------------------------------------------------------------------

  @override
  Future<Appointment> createAppointment({
    required int patientId,
    required String date,
    required String time,
    required String description,
    String? patientNameHint,
    String? patientPhoneHint,
  }) async {
    try {
      final created = await super.createAppointment(
        patientId: patientId,
        date: date,
        time: time,
        description: description,
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
  }) async {
    try {
      final updated = await super.updateAppointment(
        appointmentId,
        appointmentDateTime: appointmentDateTime,
        time: time,
        description: description,
      );
      await _db.upsertAppointment(updated.copyWith(syncStatus: 'synced'));
      return updated;
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      final existing = await _db.getAppointment(appointmentId);
      // إن كان الموعد أصلاً معلّق الإنشاء (id سالب لم يُزامَن بعد) يبقى
      // pending_create كما هو، ونكتفي بتحديث الصف المحلي دون تسجيل عملية
      // outbox جديدة -- عملية الإنشاء المعلّقة نفسها ستقرأ أحدث نسخة من
      // الصف المحلي وقت مزامنتها فعلياً (انظر _applyOp حالة 'create')، فلا
      // داعي لعملية تعديل منفصلة لموعد لم يصل للسيرفر أصلاً بعد.
      final keepCreateStatus =
          existing != null && existing.syncStatus == 'pending_create';
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
        // لم يُزامَن أصلاً بعد -- يكفي حذفه محلياً وإلغاء عملياته المعلّقة
        // (إنشاء/تعديل) بدل إرسال حذف لموعد لن يوجد على السيرفر أصلاً.
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
      // نفس منطق updateAppointment أعلاه: موعد لم يُزامَن بعد (pending_create)
      // يكفي تحديث حالته بالصف المحلي فقط، وستقرأ عملية الإنشاء المعلّقة
      // هذه الحالة الجديدة وترسلها فور نجاح المزامنة (انظر _applyOp).
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
      // الرد على طلب حجز يغيّر حالته على السيرفر (قُبل/رُفض) -- أبسط طريقة
      // صحيحة لعكس ذلك محلياً هي حذف النسخة القديمة وترك refresh() التالي
      // (تستدعيه الشاشة دائماً بعد هذا النداء) يجلب حالته الجديدة من
      // السيرفر بدل تخمينها هنا.
      await _db.deleteAppointmentRow(appointmentId);
    } on ApiException catch (e) {
      if (!_isConnectivityFailure(e)) rethrow;
      // قبول/رفض طلب حجز عام يحتاج رؤية الطلب لحظياً وقراراً نهائياً، وهي
      // حالة نادرة الحدوث أوفلاين -- بخلاف باقي عمليات المواعيد، لا نُقدِّم
      // دعماً أوفلاين لها في هذه المرحلة (تجربة أولى) ونطلب من الطبيب
      // المحاولة عند عودة الشبكة بدل تعقيد سيناريو نادر.
      throw const ApiException(
          'قبول/رفض طلبات الحجز يحتاج اتصالاً بالإنترنت حالياً. حاول عند عودة الشبكة.');
    }
  }

  // ---------------------------------------------------------------------
  // محرّك المزامنة
  // ---------------------------------------------------------------------

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
    final operation = op['operation'] as String;
    final targetId = op['target_id'] as int;
    final payload =
        json.decode(op['payload'] as String) as Map<String, dynamic>;

    switch (operation) {
      case 'create':
        // نقرأ الصف المحلي *قبل* الإرسال -- إن كان الطبيب عدّل تاريخ/وقت/
        // وصف/حالة هذا الموعد أوفلاين بعد إنشائه وقبل وصول هذه اللحظة
        // (updateAppointment/updateAppointmentStatus أعلاه تحدّثان الصف
        // المحلي فقط في هذه الحالة، دون تسجيل عملية outbox منفصلة -- انظر
        // شرحهما)، فهذا الصف يحمل أحدث نسخة فعلية يجب أن تصل للسيرفر، وليس
        // القيم الأصلية وقت الإنشاء المحفوظة بـ payload.
        final localBeforeSync = await _db.getAppointment(targetId);
        var created = await super.createAppointment(
          patientId: payload['patient_id'] as int,
          date: payload['date'] as String,
          time: payload['time'] as String,
          description: payload['description'] as String,
        );
        if (localBeforeSync != null) {
          final editedAfterCreate =
              localBeforeSync.appointmentTime != (payload['time'] as String) ||
                  localBeforeSync.procedureType !=
                      (payload['description'] as String) ||
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
        final updated = await super.updateAppointment(
          targetId,
          appointmentDateTime:
              DateTime.parse(payload['appointment_date'] as String),
          time: payload['appointment_time'] as String,
          description: payload['description'] as String,
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
}
