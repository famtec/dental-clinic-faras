import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// حالات السن الثمانية -- نفس القيم والألوان المستخدمة تماماً في
/// patient_record.html (TOOTH_STATUS_OPTIONS)، حتى يتطابق مخطط الأسنان في
/// التطبيق مع الموقع لوناً وتسمية بالضبط. أُضيف 2026-08-30: hex (نفس صيغة
/// اللون كسلسلة نصية '#rrggbb' كما هي مخزَّنة حرفياً في TOOTH_STATUS_OPTIONS
/// بالموقع -- يُستخدم فقط لترميز/فك حالة مخصصة، انظر
/// encodeCustomToothStatus/decodeCustomToothStatus أدناه) وألوان بطاقة
/// الاختيار الثلاثة (cardBackground/cardBorder/cardText) المطابقة تماماً
/// لألوان Tailwind bg-*-50/border-*-200|300/text-*-700 لكل بطاقة في نافذة
/// toothStatusModal بالموقع.
class ToothStatusOption {
  final String key;
  final String label;
  final Color color;
  final String hex;
  final Color cardBackground;
  final Color cardBorder;
  final Color cardText;
  const ToothStatusOption(
    this.key,
    this.label,
    this.color,
    this.hex,
    this.cardBackground,
    this.cardBorder,
    this.cardText,
  );
}

const List<ToothStatusOption> toothStatusOptions = [
  ToothStatusOption('decay', 'تسوس', Color(0xFFEF4444), '#ef4444',
      AppColors.red50, AppColors.red200, AppColors.red700),
  ToothStatusOption('filling', 'حشوة', Color(0xFF3B82F6), '#3b82f6',
      AppColors.blue50, AppColors.blue200, AppColors.blue700),
  ToothStatusOption('veneer', 'فينير', Color(0xFF10B981), '#10b981',
      AppColors.emerald50, AppColors.emerald200, AppColors.emerald700),
  ToothStatusOption('crown', 'تاج / تلبيسة', Color(0xFFEAB308), '#eab308',
      AppColors.amber50, AppColors.amber300, AppColors.amber700),
  ToothStatusOption('endo', 'لبية (عصب)', Color(0xFFA855F7), '#a855f7',
      AppColors.purple50, AppColors.purple200, AppColors.purple700),
  ToothStatusOption('bridge', 'جسر', Color(0xFFF97316), '#f97316',
      AppColors.orange50, AppColors.orange300, AppColors.orange700),
  ToothStatusOption('implant', 'زراعة', Color(0xFFEC4899), '#ec4899',
      AppColors.pink50, AppColors.pink200, AppColors.pink700),
  ToothStatusOption('extracted', 'مقلوع', Color(0xFF64748B), '#64748b',
      AppColors.slate100, AppColors.slate300, AppColors.slate700),
];

ToothStatusOption? toothStatusByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final option in toothStatusOptions) {
    if (option.key == key) return option;
  }
  return null;
}

/// نفس الشيء لكن بحثاً باللون hex بدل المفتاح -- تُستخدم لإعادة تحديد نفس
/// دائرة اللون التي كانت مختارة عند إعادة فتح نافذة "حالة مخصصة" على سنٍّ
/// يحمل حالة مخصصة محفوظة مسبقاً.
ToothStatusOption? toothStatusByHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final normalized = hex.trim().toLowerCase();
  for (final option in toothStatusOptions) {
    if (option.hex.toLowerCase() == normalized) return option;
  }
  return null;
}

// ---------------------------------------------------------------------
// حالة سن "مخصصة" بالاسم واللون -- مرآة تامة لآلية الموقع (انظر
// CUSTOM_STATUS_PREFIX / encodeCustomStatusValue / decodeCustomStatusValue
// في patient_record.html): الـ backend (PatientChartUpdate في main.py) لا
// يقبل سوى dict[str, str]، لذا تُرمَّز الحالة المخصصة كسلسلة نصية واحدة
// "custom:<اسم مرمّز>|<لون hex>" تمر عبر نفس أنبوب chart_state الحالي بلا
// أي تعديل على الـ backend، ويمكن لحالة أُنشئت من الموقع أن تُقرأ وتُعدَّل
// من التطبيق والعكس صحيح.
// ---------------------------------------------------------------------
const String _customToothStatusPrefix = 'custom:';

class CustomToothStatus {
  final String label;
  final String hex;
  const CustomToothStatus(this.label, this.hex);
}

String encodeCustomToothStatus(String label, String hex) {
  return '$_customToothStatusPrefix${Uri.encodeComponent(label)}|$hex';
}

CustomToothStatus? decodeCustomToothStatus(String? value) {
  if (value == null || !value.startsWith(_customToothStatusPrefix)) return null;
  final rest = value.substring(_customToothStatusPrefix.length);
  final separatorIndex = rest.lastIndexOf('|');
  if (separatorIndex == -1) return null;

  final hex = rest.substring(separatorIndex + 1).trim();
  String label;
  try {
    label = Uri.decodeComponent(rest.substring(0, separatorIndex));
  } catch (_) {
    label = rest.substring(0, separatorIndex);
  }
  label = label.trim();

  if (label.isEmpty || hex.isEmpty) return null;
  return CustomToothStatus(label, hex);
}

/// يحوّل سلسلة hex نصية ('#rrggbb' أو 'rrggbb') إلى Color فعلي -- يُستخدم
/// فقط لرسم لون حالة مخصصة على مخطط الأسنان (ToothCell)، لا لِترميزها (لا
/// علاقة له بـ Color.value المحتمل تغيّر سلوكه بين إصدارات Flutter).
Color? parseToothStatusHex(String hex) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length != 6) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return Color(0xFF000000 | parsed);
}

/// لون وتسمية حالة سن جاهزين للعرض، بعد محاولة حلّها بكل الأشكال الممكنة
/// المخزَّنة تاريخياً في chart_state: مفتاح حالة ثابت (decay/filling/...)،
/// ثم أحد ألوان CSS القديمة التي كانت تُخزَّن مباشرة من نسخة سابقة من
/// الموقع (مطابق تماماً لِـ resolveStatusKey في patient_record.html)، ثم
/// حالة مخصصة مرمّزة. تُستخدم في ToothCell حتى تُعرض بيانات المخطط القديمة
/// بشكل صحيح في التطبيق أيضاً لا فقط في الموقع.
class ResolvedToothStatus {
  final String label;
  final Color color;
  const ResolvedToothStatus(this.label, this.color);
}

const Map<String, String> _legacyToothColorSynonyms = {
  '#ef4444': 'decay',
  'red': 'decay',
  '#3b82f6': 'filling',
  'blue': 'filling',
  '#475569': 'extracted',
  'gray': 'extracted',
  'grey': 'extracted',
  '#8b0000': 'endo',
  'darkred': 'endo',
  '#c0c0c0': 'implant',
  'silver': 'implant',
  '#ffd700': 'crown',
  'gold': 'crown',
  '#ff8c00': 'bridge',
  'darkorange': 'bridge',
};

ResolvedToothStatus? resolveToothStatus(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) return null;
  final normalized = rawValue.trim().toLowerCase();

  final direct = toothStatusByKey(normalized);
  if (direct != null) return ResolvedToothStatus(direct.label, direct.color);

  final synonymKey = _legacyToothColorSynonyms[normalized];
  if (synonymKey != null) {
    final option = toothStatusByKey(synonymKey)!;
    return ResolvedToothStatus(option.label, option.color);
  }

  final custom = decodeCustomToothStatus(rawValue);
  if (custom != null) {
    final color = parseToothStatusHex(custom.hex) ?? toothDefaultStroke;
    return ResolvedToothStatus(custom.label, color);
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
