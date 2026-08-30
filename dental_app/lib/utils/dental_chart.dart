import 'package:flutter/material.dart';

/// حالات السن الثمانية -- نفس القيم والألوان المستخدمة تماماً في
/// patient_record.html (TOOTH_STATUS_OPTIONS)، حتى يتطابق مخطط الأسنان في
/// التطبيق مع الموقع لوناً وتسمية بالضبط.
class ToothStatusOption {
  final String key;
  final String label;
  final Color color;
  const ToothStatusOption(this.key, this.label, this.color);
}

const List<ToothStatusOption> toothStatusOptions = [
  ToothStatusOption('decay', 'تسوس', Color(0xFFEF4444)),
  ToothStatusOption('filling', 'حشوة', Color(0xFF3B82F6)),
  ToothStatusOption('veneer', 'فينير', Color(0xFF10B981)),
  ToothStatusOption('crown', 'تاج / تلبيسة', Color(0xFFEAB308)),
  ToothStatusOption('endo', 'لبية (عصب)', Color(0xFFA855F7)),
  ToothStatusOption('bridge', 'جسر', Color(0xFFF97316)),
  ToothStatusOption('implant', 'زراعة', Color(0xFFEC4899)),
  ToothStatusOption('extracted', 'مقلوع', Color(0xFF64748B)),
];

ToothStatusOption? toothStatusByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final option in toothStatusOptions) {
    if (option.key == key) return option;
  }
  return null;
}

/// لون السن الافتراضي (بلا أي حالة مسجّلة) -- نفس اللون الكريمي/العاجي
/// المستخدم في مخطط أسنان الموقع.
const Color toothDefaultFill = Color(0xFFFFFBEB);
const Color toothDefaultStroke = Color(0xFFD6B98C);

/// خريطة أرقام الأسنان بترميز FDI (المعروض على الشاشة، بالأرقام الشائعة
/// 11-48) إلى ترميز Palmer المستخدم فعلياً في قاعدة بيانات الـ backend
/// (chart_state) بالمفاتيح UR1-UR8 / UL1-UL8 / LR1-LR8 / LL1-LL8 (انظر
/// PatientChartUpdate.normalize_palmer_chart_state في main.py). التطبيق
/// يعرض FDI مثل الموقع تماماً، لكنه يحفظ ويقرأ Palmer داخلياً عند التخاطب
/// مع الـ API.
const Map<int, String> fdiToPalmer = {
  // الفك العلوي، الربع الأيمن (Upper Right).
  18: 'UR8', 17: 'UR7', 16: 'UR6', 15: 'UR5', 14: 'UR4', 13: 'UR3', 12: 'UR2', 11: 'UR1',
  // الفك العلوي، الربع الأيسر (Upper Left).
  21: 'UL1', 22: 'UL2', 23: 'UL3', 24: 'UL4', 25: 'UL5', 26: 'UL6', 27: 'UL7', 28: 'UL8',
  // الفك السفلي، الربع الأيمن (Lower Right).
  48: 'LR8', 47: 'LR7', 46: 'LR6', 45: 'LR5', 44: 'LR4', 43: 'LR3', 42: 'LR2', 41: 'LR1',
  // الفك السفلي، الربع الأيسر (Lower Left).
  31: 'LL1', 32: 'LL2', 33: 'LL3', 34: 'LL4', 35: 'LL5', 36: 'LL6', 37: 'LL7', 38: 'LL8',
};

/// ترتيب أرقام الأسنان بترميز FDI كما تُعرض في صفّي المخطط (نفس ترتيب
/// الموقع بالضبط، من اليسار لليمين بصرياً بغض النظر عن اتجاه RTL للنص).
const List<int> upperArchFdi = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const List<int> lowerArchFdi = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
