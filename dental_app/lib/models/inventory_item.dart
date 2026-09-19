/// مادة في مخزن العيادة -- يطابق InventoryItemResponse حرفياً (main.py،
/// ميزة Premium حصراً -- انظر require_premium_user_by_email). "isLowStock"
/// تحسب هنا محلياً بنفس منطق أيقونة التنبيه في inventory.html بالموقع.
class InventoryItem {
  final int id;
  final String doctorEmail;
  final String itemName;
  final int quantity;
  final int minAlertQuantity;

  /// تكلفة **الوحدة** لا العبوة (أُضيف للتطبيق 2026-09-18؛ موجود على الخادم
  /// منذ جولة لائحة الأسعار). عليها يقوم حساب تكلفة المواد المستهلكة في
  /// الفاتورة، وتصحيحها يسري على الاستهلاك القادم وحده -- كل سطر استهلاك
  /// سابق يحمل نسخته المجمّدة منها (models.InvoiceMaterialUsage).
  ///
  /// «الوحدة» هي أصغر ما يُستهلك في علاج واحد لا أصغر ما يُشترى: عبوة كومبوزت
  /// تُشترى مرة وتُستهلك على عشرات الحشوات، والكمية في المخزن عدد صحيح فلا
  /// تُخصم بالكسور -- فالوحدة المسجَّلة هي الجرعة. حاسبة الجرعة في شاشة
  /// المخزن تحوّل سعر العبوة إلى تكلفة جرعة بلا حساب يدوي.
  final double unitCost;

  final DateTime updatedAt;

  /// حالة المزامنة مع السيرفر -- 'synced' دائماً لأي مادة قادمة فعلياً من
  /// الـ backend (fromJson). القيم الأخرى ('pending_create' / 'pending_update'
  /// / 'pending_delete') لا تظهر إلا لمادة أُنشئت/عُدِّلت/حُذفت أوفلاين وما
  /// زالت بانتظار الاتصال بالإنترنت -- انظر OfflineAwareApiService وLocalDb.
  /// أُضيف 2026-09-02.
  final String syncStatus;

  const InventoryItem({
    required this.id,
    required this.doctorEmail,
    required this.itemName,
    required this.quantity,
    required this.minAlertQuantity,
    required this.updatedAt,
    this.unitCost = 0,
    this.syncStatus = 'synced',
  });

  bool get isLowStock => quantity <= minAlertQuantity;

  bool get hasUnitCost => unitCost > 0;

  bool get isPendingSync => syncStatus != 'synced';

  InventoryItem copyWith({
    String? doctorEmail,
    String? itemName,
    int? quantity,
    int? minAlertQuantity,
    double? unitCost,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return InventoryItem(
      id: id,
      doctorEmail: doctorEmail ?? this.doctorEmail,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      minAlertQuantity: minAlertQuantity ?? this.minAlertQuantity,
      unitCost: unitCost ?? this.unitCost,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as int,
      doctorEmail: (json['doctor_email'] as String?)?.trim() ?? '',
      itemName: (json['item_name'] as String?)?.trim() ?? '',
      quantity: json['quantity'] as int? ?? 0,
      minAlertQuantity: json['min_alert_quantity'] as int? ?? 5,
      // خادم قديم لا يرسل الحقل -> صفر، أي "غير مسجَّلة" (نفس ما يعرضه الموقع).
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
