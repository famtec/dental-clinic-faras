/// مادة في مخزن العيادة -- يطابق InventoryItemResponse حرفياً (main.py،
/// ميزة Premium حصراً -- انظر require_premium_user_by_email). "isLowStock"
/// تحسب هنا محلياً بنفس منطق أيقونة التنبيه في inventory.html بالموقع.
class InventoryItem {
  final int id;
  final String doctorEmail;
  final String itemName;
  final int quantity;
  final int minAlertQuantity;
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
    this.syncStatus = 'synced',
  });

  bool get isLowStock => quantity <= minAlertQuantity;

  bool get isPendingSync => syncStatus != 'synced';

  InventoryItem copyWith({
    String? doctorEmail,
    String? itemName,
    int? quantity,
    int? minAlertQuantity,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return InventoryItem(
      id: id,
      doctorEmail: doctorEmail ?? this.doctorEmail,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      minAlertQuantity: minAlertQuantity ?? this.minAlertQuantity,
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
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
