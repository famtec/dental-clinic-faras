import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'platform_support.dart';

/// نتيجة اختيار ملف موحّدة بين الجوال وسطح المكتب -- بايتات + اسم ملف، وهو
/// بالضبط ما تحتاجه `uploadAvatar` و `uploadPatientArchiveFile` (كلتاهما
/// تستقبل `List<int> bytes` + `String filename`، لا مسار ملف). لهذا لا حاجة
/// لـ `dart:io File` في أي مسار رفع.
class PickedMedia {
  const PickedMedia({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// نفس الامتدادات التي يقبلها الموقع ويتحقق منها `validate_avatar_file`
/// في main.py. تُمرَّر لحوار ملفات ويندوز حتى لا يختار الطبيب ملفاً سيرفضه
/// السيرفر بعد رفعه.
const List<String> kPickableImageExtensions = <String>['png', 'jpg', 'jpeg', 'webp'];

/// هل تدعم هذه المنصّة التصوير بالكاميرا مباشرة؟ على ويندوز لا يوجد
/// `ImageSource.camera`، ولا "معرض صور" بالمعنى الموجود على الهاتف -- المكافئ
/// الوحيد هو حوار ملفات النظام. الشاشات تستخدم هذا لإخفاء خيار "تصوير
/// بالكاميرا" بدل عرضه ثم الفشل عند الضغط عليه.
bool get supportsCameraCapture => isMobilePlatform;

/// اختيار صورة: كاميرا/معرض على الجوال، وحوار ملفات ويندوز على سطح المكتب.
///
/// [source] يُتجاهَل تماماً على سطح المكتب.
///
/// ملاحظة لمن يعدّل لاحقاً: image_picker يملك تطبيقاً على ويندوز نظرياً، لكنه
/// يتجاهل `imageQuality` ولا يدعم الكاميرا. توحيد مسار سطح المكتب على
/// file_picker (وهو موجود في المشروع أصلاً لاختيار PDF) يجعل السلوك
/// محدَّداً بدل الاعتماد على تفاصيل تطبيق قد تتغيّر.
Future<PickedMedia?> pickImageFromDevice({
  ImageSource source = ImageSource.gallery,
}) async {
  if (isDesktopPlatform) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kPickableImageExtensions,
      // withData إلزامي: بدونه يرجع مساراً فقط، ونحن نريد البايتات مباشرة.
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedMedia(bytes: bytes, name: file.name);
  }

  final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
  if (picked == null) return null;
  return PickedMedia(bytes: await picked.readAsBytes(), name: picked.name);
}

/// اختيار مستند PDF -- نفس السلوك على كل المنصّات (file_picker يدعم ويندوز
/// وأندرويد معاً)، مجموع هنا فقط ليبقى كل اختيار ملف في مكان واحد.
Future<PickedMedia?> pickPdfFromDevice() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) return null;
  return PickedMedia(bytes: bytes, name: file.name);
}
