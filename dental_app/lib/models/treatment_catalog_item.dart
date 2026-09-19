/// لائحة أسعار العلاجات -- نقل صفحة treatment_catalog.html إلى التطبيق،
/// 2026-09-18.
///
/// المبدأ المحاسبي الذي تقوم عليه هذه الكتلة كلها (وهو قرار الخادم، لا
/// اختيار واجهة): **الوصفة اقتراح، والفاتورة سجل.** موادُ الحالة في اللائحة
/// وتكلفتُها تُقرأ من أسعار المخزن لحظة العرض فتتحرك معها؛ وما يُجمَّد على
/// الفاتورة وقت التنفيذ هو الرقم الملزِم الذي لا يتغيّر بعد ذلك أبداً. لهذا
/// [TreatmentCatalogItem.materialsCost] و [estimatedProfit] تقديران يُعرَضان
/// بوصفهما تقديراً، ولا يجوز عرضهما بوصفهما ربحاً محقَّقاً.
library;

/// مادة واحدة في وصفة حالة من اللائحة.
class CatalogMaterial {
  final int? id;
  final int? inventoryItemId;
  final String itemName;
  final int quantity;

  /// سعر الوحدة من المخزن **لحظة العرض** لا مجمَّداً -- انظر شرح الكتلة.
  final double unitCost;
  final double totalCost;

  /// الكمية المتوفّرة في المخزن الآن. null = المادة غير مرتبطة بصنف مخزن
  /// (أُدخلت بالاسم فقط) فلا معنى لسؤال التوفّر عنها.
  final int? availableQuantity;

  const CatalogMaterial({
    this.id,
    this.inventoryItemId,
    this.itemName = '',
    this.quantity = 1,
    this.unitCost = 0,
    this.totalCost = 0,
    this.availableQuantity,
  });

  /// المخزن لا يكفي هذه الوصفة. لا يمنع الحفظ: الوصفة خطّة لعلاج قادم،
  /// وقد تُشترى المادة قبل تنفيذه.
  bool get isShort =>
      availableQuantity != null && availableQuantity! < quantity;

  Map<String, dynamic> toInputJson() => {
        if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
        if (inventoryItemId == null) 'item_name': itemName,
        'quantity': quantity,
      };

  factory CatalogMaterial.fromJson(Map<String, dynamic> json) {
    return CatalogMaterial(
      id: _int(json['id']),
      inventoryItemId: _int(json['inventory_item_id']),
      itemName: _text(json['item_name']) ?? '',
      quantity: _int(json['quantity']) ?? 0,
      unitCost: _money(json['unit_cost']),
      totalCost: _money(json['total_cost']),
      availableQuantity: _int(json['available_quantity']),
    );
  }
}

class TreatmentCatalogItem {
  final int id;
  final String name;
  final double price;
  final String? notes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<CatalogMaterial> materials;

  /// تكلفة الوصفة بأسعار المخزن الحالية، والربح المتوقَّع منها. تقديريان.
  final double materialsCost;
  final double estimatedProfit;

  const TreatmentCatalogItem({
    required this.id,
    required this.name,
    this.price = 0,
    this.notes,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.materials = const [],
    this.materialsCost = 0,
    this.estimatedProfit = 0,
  });

  bool get hasMaterials => materials.isNotEmpty;

  /// هامش الربح المتوقَّع كنسبة من السعر. السعر صفراً يعني "حالة بلا سعر
  /// محدَّد" لا خسارة كاملة، فتُعاد null ولا تُرسَم نسبة.
  double? get estimatedMarginPercent {
    if (price <= 0) return null;
    return (estimatedProfit / price) * 100;
  }

  /// وصفة لا يكفيها المخزن الآن -- شارة تحذير لا مانع حفظ.
  bool get hasShortMaterial => materials.any((m) => m.isShort);

  factory TreatmentCatalogItem.fromJson(Map<String, dynamic> json) {
    final rawActive = json['is_active'];
    final rawMaterials = json['materials'];
    return TreatmentCatalogItem(
      id: _int(json['id']) ?? 0,
      name: _text(json['name']) ?? '',
      price: _money(json['price']),
      notes: _text(json['notes']),
      isActive: rawActive is bool ? rawActive : rawActive != 0,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      materials: rawMaterials is List
          ? rawMaterials
              .whereType<Map<String, dynamic>>()
              .map(CatalogMaterial.fromJson)
              .toList()
          : const [],
      materialsCost: _money(json['materials_cost']),
      estimatedProfit: _money(json['estimated_profit']),
    );
  }
}

/// سطر واحد في تقرير ربحية العلاجات.
///
/// catalogItemId = null سطر حقيقي لا حالة شاذة: كل فاتورة كُتبت يدوياً بلا
/// حالة من اللائحة (وهي حال كل فاتورة سابقة لهذه الميزة) تُجمَّع تحته،
/// والخادم يسمّيه "علاجات بلا حالة من اللائحة" -- فلا يُحذَف من العرض.
class CatalogProfitRow {
  final int? catalogItemId;
  final String name;
  final int invoicesCount;
  final double billed;
  final double materialsCost;
  final double netProfit;

  const CatalogProfitRow({
    this.catalogItemId,
    this.name = '',
    this.invoicesCount = 0,
    this.billed = 0,
    this.materialsCost = 0,
    this.netProfit = 0,
  });

  factory CatalogProfitRow.fromJson(Map<String, dynamic> json) {
    return CatalogProfitRow(
      catalogItemId: _int(json['catalog_item_id']),
      name: _text(json['name']) ?? '',
      invoicesCount: _int(json['invoices_count']) ?? 0,
      billed: _money(json['billed']),
      materialsCost: _money(json['materials_cost']),
      netProfit: _money(json['net_profit']),
    );
  }
}

/// تقرير ربحية العلاجات لفترة.
///
/// **الفترة تُقاس بتاريخ إنشاء الفاتورة لا بتاريخ تحصيلها** (قرار الخادم):
/// هذا تقرير ربحية عمل لا تدفّق نقدي، والتدفّق النقدي مكانه شاشة المالية.
/// عرضه كأنه محصَّل نقداً خطأ في المعنى.
class CatalogProfitReport {
  final int? year;
  final int? month;
  final int? day;
  final bool allTime;
  final int invoicesCount;
  final double billed;
  final double materialsCost;
  final double netProfit;
  final List<CatalogProfitRow> items;

  const CatalogProfitReport({
    this.year,
    this.month,
    this.day,
    this.allTime = false,
    this.invoicesCount = 0,
    this.billed = 0,
    this.materialsCost = 0,
    this.netProfit = 0,
    this.items = const [],
  });

  factory CatalogProfitReport.fromJson(Map<String, dynamic> json) {
    final period = json['period'] is Map<String, dynamic>
        ? json['period'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final totals = json['totals'] is Map<String, dynamic>
        ? json['totals'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawAll = period['all_time'];
    final rawItems = json['items'];
    return CatalogProfitReport(
      year: _int(period['year']),
      month: _int(period['month']),
      day: _int(period['day']),
      allTime: rawAll is bool ? rawAll : rawAll == 1 || rawAll == 'true',
      invoicesCount: _int(totals['invoices_count']) ?? 0,
      billed: _money(totals['billed']),
      materialsCost: _money(totals['materials_cost']),
      netProfit: _money(totals['net_profit']),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(CatalogProfitRow.fromJson)
              .toList()
          : const [],
    );
  }
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// JSON قد يعيد 0 كـ int، وقراءته `as double` تُسقِط الشاشة كلها -- نفس
/// احتراز ClinicDoctor._money، وقد وقع فعلاً قبل إضافته.
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

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}
