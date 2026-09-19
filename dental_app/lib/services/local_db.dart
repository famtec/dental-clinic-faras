import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/appointment.dart';
import '../models/inventory_item.dart';
import '../models/patient.dart';
import 'platform_support.dart';

/// طبقة تخزين محلية (SQLite عبر sqflite) لدعم العمل بدون إنترنت. بدأت
/// 2026-08-31 بشاشة المواعيد وحدها (جدولا appointments/outbox أدناه)، ثم
/// وُسِّعت 2026-09-02 لتغطي المرضى/مخطط الأسنان/المخزون/الفواتير أيضاً
/// (بطلب المستخدم "ابني نفس النمط على جميع الشاشات") -- انظر
/// OfflineAwareApiService لشرح مَن يستخدم كل جدول وكيف.
///
/// المبدأ العام لكل كيان "قابل للتعديل أوفلاين" (مواعيد/مرضى/مخزون): جدول
/// محلي يحمل نسخة مدمَجة من كل سجل يعرفه التطبيق مع عمود `sync_status`،
/// بالإضافة لجدول `outbox` مشترك (عمود entity_type يميّز نوع العملية) يشغَّل
/// بالترتيب عند عودة الاتصال. الكيانات الأصعب تعقيداً بسبب حقول محسوبة من
/// طرف السيرفر (فواتير العلاج/التقرير المالي/إحصائيات المرضى) لا تُخزَّن في
/// جدول مدمَج مماثل -- بدلاً من ذلك جدول `cache_kv` عام يخزّن آخر استجابة
/// ناجحة من السيرفر فقط (تُعرض كما هي عند انقطاع الاتصال، ولا تُعدَّل محلياً
/// أبداً)، والتعديلات عليها (فاتورة/دفعة/مصروف جديد) تمر حصراً عبر outbox
/// بلا نسخة محلية دائمة تُعرض قبل المزامنة -- تفصيل القرار في
/// OfflineAwareApiService.
///
/// المواعيد/المرضى/المواد المُنشأة أوفلاين تأخذ id سالباً مؤقتاً (انظر
/// [nextLocalId]) بدل الانتظار لمعرّف السيرفر الحقيقي، حتى تظهر فوراً في
/// القائمة؛ وحين تُزامَن فعلياً يُستبدَل هذا المعرّف السالب بمعرّف السيرفر
/// الحقيقي (انظر remap* أدناه لكل كيان).
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    // 2026-09-10 (نسخة ويندوز): كان هذا `getDatabasesPath()` مباشرة. على
    // الجوال لم يتغيّر شيء -- resolveLocalDbDirectory تستدعيها كما هي --
    // لكن على ويندوز يجب أن تسكن قاعدة البيانات في مجلد بيانات المستخدم
    // (%APPDATA%) لا بجوار ملف الـ .exe. التفصيل في platform_support.dart.
    final dir = await resolveLocalDbDirectory();
    final path = p.join(dir, 'dental_offline.db');
    final opened = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createV1Tables(db);
        await _createV2Tables(db);
      },
      // 2026-09-02: ترقية من النسخة 1 (مواعيد فقط) للنسخة 2 -- تضيف الجداول
      // الجديدة بلا لمس appointments/outbox القائمين أصلاً، حتى لا يفقد
      // الأطباء الذين ثبّتوا الميزة الأولى أي عملية معلّقة لديهم.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
        }
        // 2026-09-17: مدة الموعد والطبيب المنفّذ. عمودان مضافان على جدول
        // appointments القائم، فلا يمسّان أي صف ولا أي عملية معلّقة في
        // outbox -- والمواعيد المخزَّنة محلياً قبل الترقية تأخذ نصف ساعة
        // والطبيب المدير، وهي القيم نفسها التي يعطيها الخادم لها.
        if (oldVersion < 3) {
          await _upgradeAppointmentsToV3(db);
        }
        // 2026-09-18: تكلفة الوحدة على مواد المخزن (موجودة على الخادم منذ
        // جولة لائحة الأسعار). عمود واحد مضاف، لا يمسّ أي صف ولا أي عملية
        // معلّقة، والمواد المخزَّنة قبل الترقية تأخذ صفراً = "غير مسجَّلة".
        if (oldVersion < 4) {
          await _upgradeInventoryToV4(db);
        }
      },
    );
    _database = opened;
    return opened;
  }

  static Future<void> _createV1Tables(Database db) async {
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
        duration_minutes INTEGER NOT NULL DEFAULT 30,
        clinic_doctor_id INTEGER,
        clinic_doctor_name TEXT,
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
  }

  /// ترقية جدول appointments للنسخة 3 -- تُضيف الأعمدة الناقصة فقط.
  ///
  /// تُقرأ الأعمدة الموجودة فعلاً بـ PRAGMA بدل تنفيذ ALTER أعمى: تثبيت
  /// جديد يُنشئ الجدول بالأعمدة الثلاثة أصلاً (انظر _createV1Tables)، فتنفيذ
  /// ALTER عليه يرفع "duplicate column name" ويُفشل فتح قاعدة البيانات كلها
  /// -- أي يفقد الطبيب كل عملياته المعلّقة. نفس مبدأ inspector.get_columns
  /// المعتمد في database.py على الخادم.
  static Future<void> _upgradeAppointmentsToV3(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(appointments)');
    final existing =
        info.map((row) => (row['name'] as String?) ?? '').toSet();
    if (!existing.contains('duration_minutes')) {
      await db.execute(
          'ALTER TABLE appointments ADD COLUMN duration_minutes INTEGER NOT NULL DEFAULT 30');
    }
    if (!existing.contains('clinic_doctor_id')) {
      await db.execute(
          'ALTER TABLE appointments ADD COLUMN clinic_doctor_id INTEGER');
    }
    if (!existing.contains('clinic_doctor_name')) {
      await db.execute(
          'ALTER TABLE appointments ADD COLUMN clinic_doctor_name TEXT');
    }
  }

  /// ترقية جدول inventory_items للنسخة 4 -- نفس مبدأ الترقية أعلاه: تُقرأ
  /// الأعمدة الموجودة فعلاً بـ PRAGMA، فتثبيت جديد أنشأ العمود أصلاً لا يفشل
  /// بـ "duplicate column name" (وهو فشل يمنع فتح قاعدة البيانات كلها).
  static Future<void> _upgradeInventoryToV4(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(inventory_items)');
    final existing =
        info.map((row) => (row['name'] as String?) ?? '').toSet();
    if (!existing.contains('unit_cost')) {
      await db.execute(
          'ALTER TABLE inventory_items ADD COLUMN unit_cost REAL NOT NULL DEFAULT 0');
    }
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id INTEGER PRIMARY KEY,
        full_name TEXT,
        phone TEXT,
        gender TEXT,
        birth_date TEXT,
        medical_history TEXT,
        total_treatment_cost REAL,
        paid_amount REAL,
        chart_state TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_items (
        id INTEGER PRIMARY KEY,
        doctor_email TEXT,
        item_name TEXT,
        quantity INTEGER,
        min_alert_quantity INTEGER,
        unit_cost REAL NOT NULL DEFAULT 0,
        updated_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
    // تخزين مؤقت عام لآخر استجابة ناجحة من السيرفر لأي قراءة "معقدة"
    // (فواتير مريض/تقرير مالي/آخر الحركات/إحصائيات) -- مفتاحها نصّي حرّ
    // (مثال: 'patient_invoices:42'، 'finance_summary:2026-9') يبنيه المستدعي.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_kv (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// معرّف سالب فريد لسجل أُنشئ أوفلاين ولم يصل للسيرفر بعد (موعد/مريض/مادة
  /// مخزون) -- بالميكروثانية حتى لا يتكرر عند إنشاءين متتاليين سريعين. مشترك
  /// بين كل الكيانات لأن كل واحد منها بجدوله الخاص (مساحة مفاتيح مستقلة)،
  /// فلا تعارض بين معرّف سالب لموعد وآخر لمريض حتى لو تطابقا رقمياً.
  int nextLocalId() => -DateTime.now().microsecondsSinceEpoch;

  // =========================================================================
  // مواعيد -- كما كانت (بلا أي تعديل) منذ 2026-08-31.
  // =========================================================================

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
        'duration_minutes': a.durationMinutes,
        'clinic_doctor_id': a.clinicDoctorId,
        'clinic_doctor_name': a.clinicDoctorName,
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
        durationMinutes:
            normalizeAppointmentDuration(row['duration_minutes']),
        clinicDoctorId: row['clinic_doctor_id'] as int?,
        clinicDoctorName: row['clinic_doctor_name'] as String?,
        syncStatus: (row['sync_status'] as String?) ?? 'synced',
      );

  Future<void> upsertAppointment(Appointment a) async {
    final db = await _db;
    await db.insert('appointments', _toRow(a),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

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

  Future<void> remapLocalIdToServerId(int oldId, int newId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('appointments', {'id': newId},
          where: 'id = ?', whereArgs: [oldId]);
      await txn.update('outbox', {'target_id': newId},
          where: "target_id = ? AND entity_type = 'appointment'", whereArgs: [oldId]);
    });
  }

  // =========================================================================
  // مرضى -- أُضيف 2026-09-02، نفس نمط المواعيد أعلاه بالضبط. chart_state هنا
  // هو نفس النص الخام (JSON مُرمَّز مسبقاً) الذي يخزّنه Patient.chartStateRaw،
  // فلا حاجة لأي تحويل عند القراءة/الكتابة -- مجرد نسخ مباشر.
  // =========================================================================

  Map<String, Object?> _patientToRow(Patient p) => {
        'id': p.id,
        'full_name': p.fullName,
        'phone': p.phone,
        'gender': p.gender,
        'birth_date': p.birthDate?.toIso8601String(),
        'medical_history': p.medicalHistory,
        'total_treatment_cost': p.totalTreatmentCost,
        'paid_amount': p.paidAmount,
        'chart_state': p.chartStateRaw,
        'sync_status': p.syncStatus,
      };

  Patient _patientFromRow(Map<String, Object?> row) => Patient(
        id: row['id'] as int,
        fullName: (row['full_name'] as String?) ?? 'بدون اسم',
        phone: (row['phone'] as String?) ?? '',
        gender: row['gender'] as String?,
        birthDate: row['birth_date'] != null
            ? DateTime.tryParse(row['birth_date'] as String)
            : null,
        medicalHistory: row['medical_history'] as String?,
        totalTreatmentCost: (row['total_treatment_cost'] as num?)?.toDouble() ?? 0.0,
        paidAmount: (row['paid_amount'] as num?)?.toDouble() ?? 0.0,
        chartStateRaw: row['chart_state'] as String?,
        syncStatus: (row['sync_status'] as String?) ?? 'synced',
      );

  Future<void> upsertPatient(Patient patient) async {
    final db = await _db;
    await db.insert('patients', _patientToRow(patient),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// يستبدل كل الصفوف المتزامنة فعلياً بأحدث نسخة من السيرفر، مع ترك أي صف
  /// ما زال بانتظار المزامنة (إنشاء/تعديل/تعديل مخطط) كما هو -- نفس منطق
  /// [replaceServerAppointments] بالضبط.
  Future<void> replaceServerPatients(List<Patient> serverList) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('patients', where: "sync_status = 'synced'");
      for (final patient in serverList) {
        await txn.insert(
          'patients',
          _patientToRow(patient.copyWith(syncStatus: 'synced')),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<Patient>> getAllPatientsMerged() async {
    final db = await _db;
    final rows = await db.query('patients');
    return rows.map(_patientFromRow).toList();
  }

  Future<Patient?> getPatientLocal(int id) async {
    final db = await _db;
    final rows = await db.query('patients', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _patientFromRow(rows.first);
  }

  /// بعد نجاح مزامنة مريض أُنشئ أوفلاين، يستبدل معرّفه السالب المؤقت بمعرّف
  /// السيرفر الحقيقي -- في جدول المرضى وأي عملية أخرى بالـ outbox تخصّه (بيانات
  /// أساسية أو مخطط أسنان) وما زالت تشير لنفس المعرّف السالب.
  Future<void> remapPatientLocalIdToServerId(int oldId, int newId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('patients', {'id': newId}, where: 'id = ?', whereArgs: [oldId]);
      await txn.update(
        'outbox',
        {'target_id': newId},
        where: "target_id = ? AND entity_type IN ('patient', 'patient_chart')",
        whereArgs: [oldId],
      );
    });
  }

  // =========================================================================
  // مخزون -- أُضيف 2026-09-02، نفس النمط. لا تبعية على مريض أو أي كيان آخر،
  // فلا حاجة لأي منطق إعادة توجيه معقّد كما في الفواتير أدناه.
  // =========================================================================

  Map<String, Object?> _inventoryToRow(InventoryItem item) => {
        'id': item.id,
        'doctor_email': item.doctorEmail,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'min_alert_quantity': item.minAlertQuantity,
        'unit_cost': item.unitCost,
        'updated_at': item.updatedAt.toIso8601String(),
        'sync_status': item.syncStatus,
      };

  InventoryItem _inventoryFromRow(Map<String, Object?> row) => InventoryItem(
        id: row['id'] as int,
        doctorEmail: (row['doctor_email'] as String?) ?? '',
        itemName: (row['item_name'] as String?) ?? '',
        quantity: (row['quantity'] as int?) ?? 0,
        minAlertQuantity: (row['min_alert_quantity'] as int?) ?? 5,
        unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0,
        updatedAt: row['updated_at'] != null
            ? (DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now())
            : DateTime.now(),
        syncStatus: (row['sync_status'] as String?) ?? 'synced',
      );

  Future<void> upsertInventoryItem(InventoryItem item) async {
    final db = await _db;
    await db.insert('inventory_items', _inventoryToRow(item),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceServerInventoryItems(List<InventoryItem> serverList) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('inventory_items', where: "sync_status = 'synced'");
      for (final item in serverList) {
        await txn.insert(
          'inventory_items',
          _inventoryToRow(item.copyWith(syncStatus: 'synced')),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<InventoryItem>> getAllInventoryItemsMerged() async {
    final db = await _db;
    final rows = await db.query('inventory_items');
    return rows.map(_inventoryFromRow).toList();
  }

  Future<InventoryItem?> getInventoryItemLocal(int id) async {
    final db = await _db;
    final rows =
        await db.query('inventory_items', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _inventoryFromRow(rows.first);
  }

  Future<void> deleteInventoryItemRow(int id) async {
    final db = await _db;
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> remapInventoryLocalIdToServerId(int oldId, int newId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('inventory_items', {'id': newId},
          where: 'id = ?', whereArgs: [oldId]);
      await txn.update(
        'outbox',
        {'target_id': newId},
        where: "target_id = ? AND entity_type = 'inventory'",
        whereArgs: [oldId],
      );
    });
  }

  // =========================================================================
  // تخزين مؤقت عام (cache_kv) -- أُضيف 2026-09-02 لقراءات الفواتير/التقرير
  // المالي/آخر الحركات/إحصائيات المرضى: يُكتَب فقط عند نجاح جلب حقيقي من
  // السيرفر (نسخة "آخر ما هو معروف")، ويُقرأ فقط عند فشل الجلب بسبب انقطاع
  // اتصال -- لا يُعدَّل أبداً من عمليات الكتابة (إنشاء فاتورة/دفعة/مصروف)،
  // فهذه تمر عبر outbox وحده وتُبطِل (تحذف) المفتاح المرتبط عند نجاح
  // مزامنتها لاحقاً حتى لا تُعرض قراءة قديمة فوق بيانات تغيّرت فعلياً على
  // السيرفر (انظر _applyOp في OfflineAwareApiService).
  // =========================================================================

  Future<void> setCache(String key, String jsonPayload) async {
    final db = await _db;
    await db.insert(
      'cache_kv',
      {
        'cache_key': key,
        'payload': jsonPayload,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getCache(String key) async {
    final db = await _db;
    final rows =
        await db.query('cache_kv', where: 'cache_key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }

  Future<void> deleteCache(String key) async {
    final db = await _db;
    await db.delete('cache_kv', where: 'cache_key = ?', whereArgs: [key]);
  }

  Future<void> deleteCacheWithPrefix(String prefix) async {
    final db = await _db;
    await db.delete('cache_kv', where: 'cache_key LIKE ?', whereArgs: ['$prefix%']);
  }

  // =========================================================================
  // قائمة الانتظار (outbox) -- الجزء المشترك بين كل الكيانات.
  // =========================================================================

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
  /// يسبق تعديلٌ إنشاءَ سجله (موعد/مريض/فاتورة/مادة مخزون).
  Future<List<Map<String, Object?>>> getPendingOps() async {
    final db = await _db;
    return db.query('outbox', where: 'failed = 0', orderBy: 'created_at ASC');
  }

  /// نفس [getPendingOps] لكن مقصورة على نوع كيان واحد -- تُستخدَم لاستخراج
  /// حالة معلَّقة لم تُزامَن بعد (مثال: كل الدفعات المعلَّقة على فاتورة معيّنة
  /// في addInvoicePayment) بلا نسخة محلية منفصلة تُعاد بناؤها من outbox نفسه
  /// في كل مرة.
  Future<List<Map<String, Object?>>> getPendingOpsByEntity(String entityType) async {
    final db = await _db;
    return db.query(
      'outbox',
      where: 'entity_type = ? AND failed = 0',
      whereArgs: [entityType],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markOpDone(int opId) async {
    final db = await _db;
    await db.delete('outbox', where: 'op_id = ?', whereArgs: [opId]);
  }

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

  /// يُحدِّث حقول محدَّدة داخل payload عملية معلَّقة قائمة بدل تسجيل عملية
  /// outbox جديدة -- يُستخدم حين يعدّل الطبيب أوفلاين سجلاً لم يصل للسيرفر
  /// بعد أصلاً (مثال: دفعة أُضيفت أوفلاين ثم عُدِّل مبلغها قبل عودة الاتصال):
  /// عملية الإنشاء المعلّقة نفسها سترسل القيم المحدَّثة هذه وقت مزامنتها
  /// فعلياً، فلا داعي لعملية "تعديل" منفصلة لسجل لم يوجد على السيرفر أصلاً --
  /// نفس فلسفة keepCreateStatus في OfflineAwareApiService.updateAppointment.
  /// لا تفعل شيئاً بصمت إن لم توجد عملية معلَّقة مطابقة (يحدث فقط لو زامَنت
  /// خلفية أخرى العملية بين لحظة العرض ولحظة الحفظ -- نادر جداً).
  Future<void> patchPendingOpPayload({
    required String entityType,
    required int targetId,
    required String operation,
    required Map<String, dynamic> patch,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'outbox',
      where: 'entity_type = ? AND target_id = ? AND operation = ? AND failed = 0',
      whereArgs: [entityType, targetId, operation],
    );
    for (final row in rows) {
      final opId = row['op_id'] as int;
      final current = json.decode(row['payload'] as String) as Map<String, dynamic>;
      current.addAll(patch);
      await db.update('outbox', {'payload': json.encode(current)},
          where: 'op_id = ?', whereArgs: [opId]);
    }
  }

  /// يستبدل invoice_id (المعرّف السالب المؤقت لفاتورة أُنشئت أوفلاين) بمعرّف
  /// السيرفر الحقيقي داخل payload أي عملية 'invoice_payment' معلَّقة تخصّها --
  /// يُستدعى فور نجاح مزامنة عملية إنشاء الفاتورة نفسها (انظر _applyOp حالة
  /// 'invoice'/'create')، قبل أن يصل دور عمليات الدفعات المعلَّقة عليها (تُرتَّب
  /// دائماً بعد عملية الإنشاء زمنياً، فتُعالَج لاحقاً بنفس دورة المزامنة).
  Future<void> remapPendingInvoicePayments({
    required int oldInvoiceId,
    required int newInvoiceId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'outbox',
      where: "entity_type = 'invoice_payment' AND failed = 0",
    );
    for (final row in rows) {
      final opId = row['op_id'] as int;
      final payload = json.decode(row['payload'] as String) as Map<String, dynamic>;
      if (payload['invoice_id'] == oldInvoiceId) {
        payload['invoice_id'] = newInvoiceId;
        await db.update('outbox', {'payload': json.encode(payload)},
            where: 'op_id = ?', whereArgs: [opId]);
      }
    }
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
