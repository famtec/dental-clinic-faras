import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/appointment.dart';

/// طبقة تخزين محلية (SQLite عبر sqflite) لدعم العمل بدون إنترنت -- تُستخدم
/// حالياً للمواعيد فقط كتجربة أولى (انظر OfflineAwareApiService). فكرتها:
///
/// 1) جدول `appointments`: نسخة محلية من كل موعد يعرفه التطبيق، مع عمود
///    `sync_status` يميّز الصفوف المتزامنة فعلياً مع السيرفر ('synced') عن
///    أي تعديل/إضافة/حذف تم أوفلاين ولم يصل للسيرفر بعد
///    ('pending_create' / 'pending_update' / 'pending_delete').
/// 2) جدول `outbox`: قائمة انتظار بكل عملية (POST/PUT/DELETE) لم تُرسَل بعد
///    بسبب انقطاع الإنترنت، بترتيب حدوثها (created_at) -- تُشغَّل بالترتيب
///    نفسه عند عودة الاتصال حتى لا يسبق تعديلٌ إنشاءَ الموعد نفسه.
///
/// المواعيد المُنشأة أوفلاين تأخذ id سالباً مؤقتاً (انظر [nextLocalId])
/// بدل الانتظار لمعرّف السيرفر الحقيقي، حتى تظهر فوراً في القائمة؛ وحين
/// تُزامَن فعلياً يُستبدَل هذا المعرّف السالب بمعرّف السيرفر الحقيقي في كلا
/// الجدولين دفعة واحدة (انظر [remapLocalIdToServerId]).
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'dental_offline.db');
    final opened = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE appointments (
            id INTEGER PRIMARY KEY,
            patient_name TEXT,
            appointment_date TEXT,
            appointment_time TEXT,
            procedure_type TEXT,
            notes TEXT,
            status TEXT,
            patient_phone TEXT,
            patient_id INTEGER,
            sync_status TEXT NOT NULL DEFAULT 'synced'
          )
        ''');
        await db.execute('''
          CREATE TABLE outbox (
            op_id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            operation TEXT NOT NULL,
            target_id INTEGER NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            failed INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
      },
    );
    _database = opened;
    return opened;
  }

  // ---------------------------------------------------------------------
  // مواعيد -- تحويل من/إلى صف قاعدة البيانات
  // ---------------------------------------------------------------------

  Map<String, Object?> _toRow(Appointment a) => {
        'id': a.id,
        'patient_name': a.patientName,
        'appointment_date': a.appointmentDate?.toIso8601String(),
        'appointment_time': a.appointmentTime,
        'procedure_type': a.procedureType,
        'notes': a.notes,
        'status': a.status,
        'patient_phone': a.patientPhone,
        'patient_id': a.patientId,
        'sync_status': a.syncStatus,
      };

  Appointment _fromRow(Map<String, Object?> row) => Appointment(
        id: row['id'] as int,
        patientName: (row['patient_name'] as String?) ?? '',
        appointmentDate: row['appointment_date'] != null
            ? DateTime.tryParse(row['appointment_date'] as String)
            : null,
        appointmentTime: (row['appointment_time'] as String?) ?? '',
        procedureType: (row['procedure_type'] as String?) ?? '',
        notes: row['notes'] as String?,
        status: (row['status'] as String?) ?? 'pending',
        patientPhone: row['patient_phone'] as String?,
        patientId: row['patient_id'] as int?,
        syncStatus: (row['sync_status'] as String?) ?? 'synced',
      );

  /// معرّف سالب فريد لموعد أُنشئ أوفلاين ولم يصل للسيرفر بعد -- بالميكروثانية
  /// حتى لا يتكرر عند إنشاءين متتاليين سريعين.
  int nextLocalId() => -DateTime.now().microsecondsSinceEpoch;

  Future<void> upsertAppointment(Appointment a) async {
    final db = await _db;
    await db.insert('appointments', _toRow(a),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// يستبدل كل الصفوف المتزامنة فعلياً (`sync_status = 'synced'`) بأحدث
  /// نسخة من السيرفر، مع ترك أي صف لا يزال بانتظار المزامنة (إنشاء/تعديل/حذف
  /// أوفلاين) كما هو دون لمسه -- INSERT OR IGNORE يمنع الكتابة فوق صف معلَّق
  /// يشارك نفس المعرّف (حالة موعد عُدِّل أوفلاين لحظة وصول نسخة السيرفر
  /// القديمة له).
  Future<void> replaceServerAppointments(List<Appointment> serverList) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('appointments', where: "sync_status = 'synced'");
      for (final appointment in serverList) {
        await txn.insert(
          'appointments',
          _toRow(appointment.copyWith(syncStatus: 'synced')),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<Appointment>> getAllAppointmentsMerged() async {
    final db = await _db;
    final rows = await db.query('appointments');
    return rows.map(_fromRow).toList();
  }

  Future<Appointment?> getAppointment(int id) async {
    final db = await _db;
    final rows =
        await db.query('appointments', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> deleteAppointmentRow(int id) async {
    final db = await _db;
    await db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAppointmentStatusLocal(
    int id,
    String status, {
    required String syncStatus,
  }) async {
    final db = await _db;
    await db.update(
      'appointments',
      {'status': status, 'sync_status': syncStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAppointmentPendingDelete(int id) async {
    final db = await _db;
    await db.update(
      'appointments',
      {'sync_status': 'pending_delete'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// بعد نجاح مزامنة موعد أُنشئ أوفلاين، يستبدل معرّفه السالب المؤقت
  /// بمعرّف السيرفر الحقيقي -- في جدول المواعيد وأي عملية أخرى ما زالت
  /// بالـ outbox تشير لنفس المعرّف السالب (مثال: الطبيب عدّل نفس الموعد
  /// أوفلاين مرتين قبل عودة الاتصال).
  Future<void> remapLocalIdToServerId(int oldId, int newId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('appointments', {'id': newId},
          where: 'id = ?', whereArgs: [oldId]);
      await txn.update('outbox', {'target_id': newId},
          where: 'target_id = ?', whereArgs: [oldId]);
    });
  }

  // ---------------------------------------------------------------------
  // قائمة الانتظار (outbox)
  // ---------------------------------------------------------------------

  Future<int> enqueue({
    required String entityType,
    required String operation,
    required int targetId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    return db.insert('outbox', {
      'entity_type': entityType,
      'operation': operation,
      'target_id': targetId,
      'payload': json.encode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'failed': 0,
    });
  }

  /// العمليات التي ما زالت تستحق إعادة المحاولة (تستثني ما فشل نهائياً برفض
  /// حقيقي من السيرفر -- انظر [markOpFailed]) مرتّبة حسب وقت حدوثها حتى لا
  /// يسبق تعديلٌ إنشاءَ موعده.
  Future<List<Map<String, Object?>>> getPendingOps() async {
    final db = await _db;
    return db.query('outbox', where: 'failed = 0', orderBy: 'created_at ASC');
  }

  Future<void> markOpDone(int opId) async {
    final db = await _db;
    await db.delete('outbox', where: 'op_id = ?', whereArgs: [opId]);
  }

  /// رفض حقيقي من السيرفر (وليس مجرد انقطاع اتصال) -- يوقف إعادة المحاولة
  /// التلقائية لهذه العملية تحديداً (تبقى مسجَّلة بالقاعدة لمراجعة لاحقة) دون
  /// إيقاف بقية قائمة الانتظار.
  Future<void> markOpFailed(int opId, String error) async {
    final db = await _db;
    await db.update(
      'outbox',
      {'failed': 1, 'last_error': error},
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<void> cancelPendingOpsFor(int targetId) async {
    final db = await _db;
    await db.delete('outbox', where: 'target_id = ?', whereArgs: [targetId]);
  }

  Future<int> countPendingOps() async {
    final db = await _db;
    final result =
        await db.rawQuery("SELECT COUNT(*) AS c FROM outbox WHERE failed = 0");
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countFailedOps() async {
    final db = await _db;
    final result =
        await db.rawQuery("SELECT COUNT(*) AS c FROM outbox WHERE failed = 1");
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
