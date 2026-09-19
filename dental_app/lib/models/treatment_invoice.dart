class InvoicePayment {
  final int id;
  final double amount;
  final String description;
  final DateTime createdAt;
  final bool isOpeningBalance;

  /// 'synced' لأي دفعة قادمة فعلياً من السيرفر. 'pending' لدفعة سُجِّلت
  /// أوفلاين ولا تزال بانتظار الاتصال لترسَل فعلياً -- انظر
  /// OfflineAwareApiService.addInvoicePayment. أُضيف 2026-09-02.
  final String syncStatus;

  const InvoicePayment({
    required this.id,
    required this.amount,
    required this.description,
    required this.createdAt,
    required this.isOpeningBalance,
    this.syncStatus = 'synced',
  });

  bool get isPendingSync => syncStatus != 'synced';

  factory InvoicePayment.fromJson(Map<String, dynamic> json) {
    return InvoicePayment(
      id: json['id'] as int,
      amount: (json['amount'] as num).toDouble(),
      description: (json['description'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isOpeningBalance: json['is_opening_balance'] as bool? ?? false,
    );
  }

  /// عكس [fromJson] -- تُستخدم فقط لتخزين آخر نسخة معروفة من فواتير مريض
  /// محلياً (cache_kv) لعرضها عند انقطاع الاتصال، وليس لإرسالها للسيرفر.
  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'is_opening_balance': isOpeningBalance,
      };
}

/// سطر مادة استُهلكت فعلاً على فاتورة، وخُصمت من المخزن. أُضيف 2026-09-18.
///
/// **أرقامه مجمَّدة لحظة التسجيل** ولا تتحرك مع سعر المخزن بعدها -- هذا قرار
/// الخادم وأساس صحّة كل تقرير ربحية: فاتورة نُفِّذت بمادة كلفت 500 تبقى
/// كذلك وإن صار سعرها 900 غداً. لا تُعِد حساب totalCost من المخزن في أي
/// واجهة.
///
/// حذف السطر يُرجِع كميته إلى المخزن (عكس الخصم تماماً) -- فحذفه ليس
/// تصحيحاً مرئياً فقط بل حركة مخزن حقيقية.
class InvoiceMaterial {
  final int id;
  final int invoiceId;
  final int? inventoryItemId;
  final String itemName;
  final int quantity;
  final double unitCost;
  final double totalCost;
  final DateTime? createdAt;

  const InvoiceMaterial({
    required this.id,
    this.invoiceId = 0,
    this.inventoryItemId,
    this.itemName = '',
    this.quantity = 0,
    this.unitCost = 0,
    this.totalCost = 0,
    this.createdAt,
  });

  factory InvoiceMaterial.fromJson(Map<String, dynamic> json) {
    return InvoiceMaterial(
      id: _int(json['id']) ?? 0,
      invoiceId: _int(json['invoice_id']) ?? 0,
      inventoryItemId: _int(json['inventory_item_id']),
      itemName: (json['item_name'] as String?)?.trim() ?? '',
      quantity: _int(json['quantity']) ?? 0,
      unitCost: _money(json['unit_cost']),
      totalCost: _money(json['total_cost']),
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
    );
  }

  /// تخزين مؤقت فقط (cache_kv) -- انظر تعليق InvoicePayment.toJson.
  Map<String, dynamic> toJson() => {
        'id': id,
        'invoice_id': invoiceId,
        'inventory_item_id': inventoryItemId,
        'item_name': itemName,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
        'created_at': createdAt?.toIso8601String(),
      };
}

/// مادة يطلب الطبيب خصمها على فاتورة -- مُدخَل لا سجل. تُرسَل بمعرّف صنف
/// المخزن أو بالاسم (مطابقة غير حساسة لحالة الأحرف من طرف الخادم).
class InvoiceMaterialInput {
  final int? inventoryItemId;
  final String? itemName;
  final int quantity;

  /// تجاوز سعر المخزن لهذه الفاتورة وحدها. null = استخدم سعر المادة
  /// المسجَّل في المخزن (وهو الوضع الصحيح في الغالب).
  final double? unitCost;

  const InvoiceMaterialInput({
    this.inventoryItemId,
    this.itemName,
    this.quantity = 1,
    this.unitCost,
  });

  Map<String, dynamic> toJson() => {
        if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
        if (inventoryItemId == null && itemName != null) 'item_name': itemName,
        'quantity': quantity,
        if (unitCost != null) 'unit_cost': unitCost,
      };
}

/// فاتورة علاج مستقلة لمريض واحد -- تكلفتها ودفعاتها الخاصة بها فقط (انظر
/// شرح models.TreatmentInvoice في main.py). "status" يُشتق دائماً من طرف
/// السيرفر: "open" ما زال عليها متبقي، "closed" سُدِّدت بالكامل.
class TreatmentInvoice {
  final int id;
  final int patientId;
  final String title;
  final double totalCost;
  final double paidAmount;
  final double remainingAmount;
  final String status;
  final DateTime createdAt;
  final List<InvoicePayment> payments;

  /// الطبيب المساعد المنفّذ للفاتورة. null = الطبيب المدير صاحب الحساب
  /// نفسه، لا "غير محدَّد" -- نفس معنى NULL في appointments.clinic_doctor_id.
  final int? clinicDoctorId;
  final String? clinicDoctorName;

  /// الحالة المختارة من لائحة الأسعار -- **مرجع للقراءة فقط**: العنوان
  /// والتكلفة مجمَّدان على الفاتورة، فتعديل سعر الحالة في اللائحة لاحقاً لا
  /// يمسّ هذه الفاتورة إطلاقاً.
  final int? catalogItemId;

  /// المواد المستهلكة وتكلفتها المجمَّدة، وربح الفاتورة كاملة.
  ///
  /// netProfit = totalCost - materialsCost، أي ربح **مفوتَر** لا محصَّل:
  /// مستقل تماماً عن كم دُفع منها فعلاً (ذاك paidAmount). عرضه كنقد في
  /// الصندوق خطأ في المعنى.
  final List<InvoiceMaterial> materials;
  final double materialsCost;
  final double netProfit;

  /// 'synced' لفاتورة قادمة فعلياً من السيرفر. 'pending_create' لفاتورة
  /// أُنشئت أوفلاين ولم تصل للسيرفر بعد، 'pending_update' لفاتورة مزامَنة
  /// أصلاً لكن عليها دفعة/تعديل جديد ما زال بانتظار الاتصال -- انظر
  /// OfflineAwareApiService. أُضيف 2026-09-02.
  final String syncStatus;

  const TreatmentInvoice({
    required this.id,
    required this.patientId,
    required this.title,
    required this.totalCost,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.createdAt,
    required this.payments,
    this.syncStatus = 'synced',
    this.clinicDoctorId,
    this.clinicDoctorName,
    this.catalogItemId,
    this.materials = const [],
    this.materialsCost = 0,
    this.netProfit = 0,
  });

  bool get isOpen => status == 'open';

  bool get isPendingSync => syncStatus != 'synced';

  double get progress {
    if (totalCost <= 0) return 0;
    final ratio = paidAmount / totalCost;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  TreatmentInvoice copyWith({
    double? paidAmount,
    double? remainingAmount,
    String? status,
    List<InvoicePayment>? payments,
    String? syncStatus,
    List<InvoiceMaterial>? materials,
    double? materialsCost,
    double? netProfit,
  }) {
    return TreatmentInvoice(
      id: id,
      patientId: patientId,
      title: title,
      totalCost: totalCost,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      createdAt: createdAt,
      payments: payments ?? this.payments,
      syncStatus: syncStatus ?? this.syncStatus,
      clinicDoctorId: clinicDoctorId,
      clinicDoctorName: clinicDoctorName,
      catalogItemId: catalogItemId,
      materials: materials ?? this.materials,
      materialsCost: materialsCost ?? this.materialsCost,
      netProfit: netProfit ?? this.netProfit,
    );
  }

  factory TreatmentInvoice.fromJson(Map<String, dynamic> json) {
    final rawPayments = json['payments'] as List? ?? const [];
    final rawMaterials = json['materials'] as List? ?? const [];
    return TreatmentInvoice(
      id: json['id'] as int,
      patientId: json['patient_id'] as int,
      title: (json['title'] as String?)?.trim() ?? '',
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      remainingAmount: (json['remaining_amount'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] as String?)?.trim() ?? 'open',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      payments: rawPayments
          .map((item) => InvoicePayment.fromJson(item as Map<String, dynamic>))
          .toList(),
      clinicDoctorId: _int(json['clinic_doctor_id']),
      clinicDoctorName: (json['clinic_doctor_name'] as String?)?.trim(),
      catalogItemId: _int(json['catalog_item_id']),
      materials: rawMaterials
          .whereType<Map<String, dynamic>>()
          .map(InvoiceMaterial.fromJson)
          .toList(),
      materialsCost: _money(json['materials_cost']),
      netProfit: _money(json['net_profit']),
    );
  }

  /// عكس [fromJson] -- تخزين مؤقت (cache_kv) فقط، انظر تعليق InvoicePayment.toJson.
  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'title': title,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'remaining_amount': remainingAmount,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'clinic_doctor_id': clinicDoctorId,
        'clinic_doctor_name': clinicDoctorName,
        'catalog_item_id': catalogItemId,
        'materials': materials.map((m) => m.toJson()).toList(),
        'materials_cost': materialsCost,
        'net_profit': netProfit,
      };
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// الخادم يرسل المبالغ float، لكن JSON يعيد 0 كـ int -- و`as double` عليها
/// تُسقِط الشاشة. هذا احتراز لازم لا تجميل.
double _money(Object? value) {
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
