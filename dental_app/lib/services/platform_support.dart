import 'dart:io' show Platform;

// widgets.dart وليس foundation.dart: نحتاج منه kDebugMode/kIsWeb **و** Size
// (المستخدَم في WindowOptions أدناه)، وهو يعيد تصدير foundation بالكامل.
import 'package:flutter/widgets.dart' show Size, kDebugMode, kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
// `show` مقصود: sqflite و sqflite_common_ffi يصدّران كلاهما اسم
// `databaseFactory`، وحصر الاستيراد بـ getDatabasesPath وحدها يمنع أي تعارض
// أسماء بينهما في هذا الملف.
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

/// نقطة التمييز الوحيدة بين "جوال" و"سطح مكتب" في التطبيق كله (2026-09-10،
/// نسخة ويندوز). قبل هذا الملف لم يكن في lib/ أي استخدام لـ `Platform.is*`
/// إطلاقاً -- وهذا مقصود: كل فرع منصّة جديد يجب أن يمرّ من هنا حتى لا تتناثر
/// شروط `if (Platform.isWindows)` في الشاشات.
///
/// **مهم:** لا تستورد `dart:io` مباشرة في ملفات الواجهة -- استورد هذا الملف.
/// فحص [kIsWeb] أولاً إلزامي لأن `Platform` نفسه غير متاح على الويب ويرمي
/// استثناءً بمجرد لمسه هناك (التطبيق يُشغَّل أحياناً بـ `flutter run -d chrome`
/// للتجربة).
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// أندرويد/iOS فقط. تُستخدم لحصر كل ما يعتمد على Firebase (الإشعارات) والكاميرا
/// في المنصّات التي تدعمهما فعلاً.
bool get isMobilePlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// مسار مجلد قاعدة البيانات المحلية (dental_offline.db).
///
/// على أندرويد/iOS يبقى السلوك كما كان تماماً: `getDatabasesPath()` من حزمة
/// sqflite. أمّا على ويندوز فلا يصلح ذلك: مصنع sqflite_common_ffi يرجع المجلد
/// الحالي للعملية، وهو غالباً مجلد ملف الـ .exe نفسه -- أي `Program Files`
/// بعد التثبيت، وهو **غير قابل للكتابة** لمستخدم عادي، فتفشل قاعدة البيانات
/// المحلية بالكامل ومعها كل ميزة العمل بلا إنترنت. لذلك نستخدم مجلد بيانات
/// التطبيق الخاص بالمستخدم (`%APPDATA%\...`) عبر path_provider.
///
/// ⚠️ فخّ يجب تذكّره عند أي تعديل لاحق: على ويندوز يبني path_provider هذا
/// المسار من `CompanyName` و `ProductName` المكتوبَين في
/// `windows/runner/Runner.rc` -- أي `%APPDATA%\<CompanyName>\<ProductName>`.
/// تغيير أيٍّ من هذين النصّين في إصدار لاحق ينقل مجلد البيانات، فتبدو كل
/// العمليات المعلّقة غير المزامَنة لدى الطبيب وكأنها اختفت. إن لزم تغييرهما
/// يوماً، يجب نقل الملف من المسار القديم للجديد عند أول إقلاع.
Future<String> resolveLocalDbDirectory() async {
  if (isDesktopPlatform) {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }
  return getDatabasesPath();
}

/// تهيئة كل ما تحتاجه المنصّة قبل أول إطار. تُستدعى مرة واحدة من `main()`
/// بعد `WidgetsFlutterBinding.ensureInitialized()` مباشرة.
///
/// على الجوال لا تفعل شيئاً سوى ضبط سياسة الخطوط -- فلا خطر من استدعائها
/// دائماً.
Future<void> initPlatformServices() async {
  _configureFonts();
  if (!isDesktopPlatform) return;

  // sqflite لا يملك تطبيقاً أصلياً على ويندوز؛ sqflite_common_ffi يوفّر نفس
  // الواجهة فوق مكتبة sqlite3 مرفقة مع التطبيق. النتيجة: **لا يتغيّر أي
  // استعلام SQL ولا أي سطر في LocalDb** -- يتغيّر المصنع فقط.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    // 1280×820 يُظهر تخطيط العيادة كاملاً على شاشة 1366×768 الشائعة في
    // عيادات كثيرة دون أن يخرج عن حدودها.
    size: Size(1280, 820),
    // الحد الأدنى يمنع تصغير النافذة لعرض تنهار عنده بطاقات المرضى/المالية.
    minimumSize: Size(1024, 700),
    center: true,
    title: 'عيادتي الرقمية',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// الخطوط مُرفقة كملفات داخل التطبيق (مجلد `google_fonts/` في جذر المشروع،
/// انظر قسم assets في pubspec.yaml) بدل تنزيلها من الإنترنت عند أول تشغيل.
///
/// هذا شرط أساسي لتطبيق "يعمل بلا إنترنت": بدونه، أول تشغيل على جهاز بلا
/// اتصال يعرض التطبيق بخط النظام الاحتياطي (Segoe UI على ويندوز) بدل هوية
/// الموقع -- والطبيب يرى تطبيقاً "غير التصميم المتفق عليه" من أول انطباع.
///
/// `allowRuntimeFetching` يُمنع في وضع التطوير فقط: أي وزن خط يُطلب ولا يوجد
/// له ملف مرفق سيرمي استثناءً واضحاً أمام المطوّر فوراً بدل أن يمرّ صامتاً.
/// أمّا في الإصدار النهائي فيُسمح به كشبكة أمان: التدهور لخط احتياطي أهون
/// بكثير من انهيار شاشة أمام طبيب داخل عيادته.
void _configureFonts() {
  GoogleFonts.config.allowRuntimeFetching = !kDebugMode;
}
