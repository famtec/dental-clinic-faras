import 'package:flutter/material.dart';

import 'screens/patients_list_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/today_schedule_screen.dart';
import 'services/api_service.dart';
import 'services/auth_storage.dart';
import 'services/offline_aware_api_service.dart';
import 'services/platform_support.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/desktop_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-09-10: تهيئة المنصّة قبل أول إطار -- على ويندوز تضبط محرّك SQLite
  // (sqflite_common_ffi) وحجم النافذة وعنوانها، وعلى الجوال لا تفعل شيئاً
  // سوى ضبط سياسة الخطوط المرفقة. **يجب أن تسبق runApp**: أول شاشة قد تفتح
  // قاعدة البيانات المحلية فوراً، وفتحها قبل ضبط المصنع يفشل على ويندوز.
  await initPlatformServices();
  runApp(const DentalDoctorApp());
}

/// جذر التطبيق -- يدير الجلسة (مسجّل دخول أم لا)، ويهيّئ إشعارات Push بعد
/// نجاح تسجيل الدخول فقط (لا حاجة لطلب إذن الإشعارات قبل أن يصبح للطبيب
/// جلسة فعلية يُسجَّل عليها الجهاز).
class DentalDoctorApp extends StatefulWidget {
  const DentalDoctorApp({super.key});

  @override
  State<DentalDoctorApp> createState() => _DentalDoctorAppState();
}

class _DentalDoctorAppState extends State<DentalDoctorApp> {
  final AuthStorage _authStorage = AuthStorage();
  // OfflineAwareApiService بدل ApiService العادية -- تُبقي شاشة "المواعيد"
  // عاملة بلا إنترنت (عرض/إضافة/تعديل/حذف/تحديث حالة) مع مزامنة تلقائية
  // بمجرد عودة الاتصال (تجربة أولى 2026-08-31، بقية الشاشات ما زالت تحتاج
  // اتصالاً كالمعتاد). النوع المُعلَن يبقى ApiService حتى تستمر كل الشاشات
  // الأخرى بالعمل بلا أي تعديل عليها.
  late final ApiService _apiService = OfflineAwareApiService(_authStorage);
  late final PushNotificationService _pushService =
      PushNotificationService(_apiService);

  final GlobalKey<HomeScreenState> _homeScreenKey = GlobalKey<HomeScreenState>();
  // 2026-09-02: حلّ محلّ _dashboardKey بعد دمج لوحة القيادة في قائمة
  // المرضى -- إشعار الحجز الجديد يُحدّث الآن القائمة وبطاقات إحصائياتها.
  final GlobalKey<PatientsListScreenState> _patientsKey =
      GlobalKey<PatientsListScreenState>();
  final GlobalKey<TodayScheduleScreenState> _todayScheduleKey =
      GlobalKey<TodayScheduleScreenState>();

  bool _checkingSession = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // وضع الإضاءة يُقرأ قبل أول إطار حتى لا يومض التطبيق نهارياً ثم ينقلب
    // ليلياً أمام عين الطبيب. فشل القراءة يُبقيه على النهاري (انظر
    // ThemeController.load).
    await ThemeController.instance.load();
    final token = await _authStorage.getToken();
    final loggedIn = token != null && token.isNotEmpty;
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _checkingSession = false;
    });
    if (loggedIn) {
      await _initPush();
    }
  }

  Future<void> _initPush() async {
    _pushService.onNotificationTap = (data) {
      // نوعا الإشعارات الحاليان -- طلب حجز جديد (new_booking)، وتذكير العيادة
      // اليومي عند الخمول (idle_reminder، أُضيف 2026-09-05) -- يقصدان معاً
      // تبويب "المواعيد": الأول لطلب ينتظر رداً، والثاني لأن نص التذكير نفسه
      // مبني على مواعيد اليوم وطلبات الحجز المعلّقة.
      //
      // ملاحظة لمن يعدّل لاحقاً: التبويب 0 هو "المرضى" وليس لوحة قيادة --
      // لوحة القيادة دُمجت في قائمة "المزيد" (2026-09-02)، فلا تفترض وجود
      // تبويب رئيسية مستقل عند إضافة توجيه جديد هنا.
      _homeScreenKey.currentState?.showTodayTab();

      // نحدّث الشاشات الحيّة فوراً حتى يظهر الجديد بلا حاجة لسحب يدوي، أياً
      // كان التبويب المفتوح وقت وصول الإشعار (كل تبويب يبقى حيّاً عبر
      // _KeepAlivePage داخل home_screen.dart).
      _todayScheduleKey.currentState?.refresh();
      _patientsKey.currentState?.refresh();
    };
    try {
      await _pushService.initialize();
    } catch (_) {
      // فشل تهيئة الإشعارات (مثلاً: google-services.json غير مضبوط بعد) لا
      // يجب أن يمنع الطبيب من استخدام باقي التطبيق إطلاقاً.
    }
  }

  Future<void> _handleLoginSuccess() async {
    setState(() => _isLoggedIn = true);
    await _initPush();
  }

  Future<void> _handleLogout() async {
    await _authStorage.clear();
    if (!mounted) return;
    setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder بدل setState: مبدّل الوضع يعيش في شاشة "المزيد"
    // (عمق أربع طبقات تحت هذه)، وربطه برفع الحالة إلى هنا كان سيمرّر
    // callback عبر كل شاشة بينهما. ThemeController مصدر حقيقة واحد يستمع له
    // الجذر مباشرة.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, themeMode, _) => _buildApp(themeMode),
    );
  }

  Widget _buildApp(ThemeMode themeMode) {
    return MaterialApp(
      title: 'عيادتي الرقمية',
      debugShowCheckedModeBanner: false,
      // نظام «الليل النيلي»: بنية واحدة ووضعان لونيان (انظر
      // theme/app_theme.dart). النهاري هو الافتراضي لأنه وضع ضوء العيادة.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // كل واجهات التطبيق بالعربي، والتخطيط من اليمين لليسار بالكامل -- بلا
      // حاجة لحزمة flutter_localizations الإضافية لأن كل النصوص هنا مكتوبة
      // يدوياً بالعربي أصلاً وليست نصوص إطار عمل مترجَمة تلقائياً.
      builder: (context, child) {
        Widget rtl = Directionality(textDirection: TextDirection.rtl, child: child!);
        // ويندوز: شريط العنوان من رسم التطبيق فوق كل الشاشات (الدخول
        // والغلاف والصفحات المدفوعة فوقه) -- انظر DesktopTitleBar.
        if (isDesktopPlatform) {
          rtl = Column(
            children: [
              const DesktopTitleBar(title: 'عيادتي الرقمية'),
              Expanded(child: rtl),
            ],
          );
        }
        // سطح المكتب (2026-09-24): كل ورقة سفلية في التطبيق -- إضافة فاتورة،
        // دفعة، وصفة، موعد، مادة -- كانت تمتدّ بعرض نافذة ويندوز كاملاً
        // فيصير حقل الوصف بطول 1500px. قيد واحد هنا بدل تمريره لكل نداء
        // showModalBottomSheet على حدة، والجوال بلا أي تغيير.
        if (!context.isDesktopShell) return rtl;
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            bottomSheetTheme: theme.bottomSheetTheme.copyWith(
              constraints: const BoxConstraints(maxWidth: 640),
            ),
          ),
          child: rtl,
        );
      },
      // 2026-08-31: شاشة تحميل افتتاحية بهوية العيادة (شعار + رسالة ترحيب +
      // حلقة تحميل بنفس أسلوب الموقع) بدل مؤشر تحميل رمادي افتراضي بلا هوية.
      home: _checkingSession
          ? const SplashScreen()
          : _isLoggedIn
              ? HomeScreen(
                  key: _homeScreenKey,
                  apiService: _apiService,
                  authStorage: _authStorage,
                  onLogout: _handleLogout,
                  patientsKey: _patientsKey,
                  todayScheduleKey: _todayScheduleKey,
                )
              : LoginScreen(
                  apiService: _apiService,
                  authStorage: _authStorage,
                  onLoginSuccess: _handleLoginSuccess,
                ),
    );
  }
}
