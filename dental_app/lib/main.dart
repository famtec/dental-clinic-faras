import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/today_schedule_screen.dart';
import 'services/api_service.dart';
import 'services/auth_storage.dart';
import 'services/push_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  late final ApiService _apiService = ApiService(_authStorage);
  late final PushNotificationService _pushService =
      PushNotificationService(_apiService);

  final GlobalKey<HomeScreenState> _homeScreenKey = GlobalKey<HomeScreenState>();
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
      // أي إشعار حالياً هو طلب حجز جديد -- نوجّه الطبيب لتبويب جدول اليوم
      // ونحدّث القائمة فوراً حتى يظهر الحجز الجديد بلا حاجة لسحب يدوي.
      _homeScreenKey.currentState?.showTodayTab();
      _todayScheduleKey.currentState?.refresh();
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
    return MaterialApp(
      title: 'عيادتي الرقمية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // كل واجهات التطبيق بالعربي، والتخطيط من اليمين لليسار بالكامل -- بلا
      // حاجة لحزمة flutter_localizations الإضافية لأن كل النصوص هنا مكتوبة
      // يدوياً بالعربي أصلاً وليست نصوص إطار عمل مترجَمة تلقائياً.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isLoggedIn
              ? HomeScreen(
                  key: _homeScreenKey,
                  apiService: _apiService,
                  onLogout: _handleLogout,
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
