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

  const InventoryItem({
    required this.id,
    required this.doctorEmail,
    required this.itemName,
    required this.quantity,
    required this.minAlertQuantity,
    required this.updatedAt,
  });

  bool get isLowStock => quantity <= minAlertQuantity;

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
