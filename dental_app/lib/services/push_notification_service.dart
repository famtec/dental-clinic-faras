import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// معرّف قناة الإشعارات -- يجب أن يطابق بالضبط القيمة الموضوعة في
/// android/app/src/main/AndroidManifest.xml (com.google.firebase.messaging.default_notification_channel_id).
const String kBookingNotificationChannelId = 'new_booking_channel';

const AndroidNotificationChannel _bookingChannel = AndroidNotificationChannel(
  kBookingNotificationChannelId,
  'حجوزات جديدة',
  description: 'إشعارات فورية عند وصول طلب حجز جديد من مريض عبر رابط الحجز العام',
  importance: Importance.high,
);

/// معالج الإشعارات الواردة والتطبيق في الخلفية بالكامل (مغلق أو مُصغَّر) --
/// **يجب** أن تبقى دالة top-level (وليست method داخل كلاس) بهذا الشكل بالضبط،
/// هذا شرط من Firebase نفسه. لا حاجة لعرض إشعار يدوياً هنا: أندرويد يعرض حقل
/// notification في الرسالة تلقائياً عندما يكون التطبيق بالخلفية/مغلقاً.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  final ApiService _apiService;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// يُستدعى عند ضغط الطبيب على الإشعار (سواء والتطبيق مفتوح، أو كان
  /// بالخلفية وفُتح بالضغط عليه) -- الشاشة الرئيسية تربطه بالانتقال لتبويب
  /// "جدول اليوم".
  void Function(Map<String, dynamic> data)? onNotificationTap;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInitSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = json.decode(payload) as Map<String, dynamic>;
            onNotificationTap?.call(data);
          } catch (_) {
            // payload غير صالح -- نتجاهله بصمت بدلاً من تعطيل التطبيق
          }
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_bookingChannel);

    // إشعار وصل والتطبيق مفتوح فعلاً -- نعرضه يدوياً عبر flutter_local_notifications
    // لأن أندرويد لا يعرض إشعارات foreground تلقائياً بنفسه.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // الطبيب ضغط على الإشعار والتطبيق كان بالخلفية (وليس مغلقاً تماماً)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(message.data);
    });

    // التطبيق كان مغلقاً تماماً وفُتح بالضغط على إشعار -- نتحقق مرة واحدة عند الإقلاع
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      onNotificationTap?.call(initialMessage.data);
    }

    await _registerCurrentToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerCurrentToken());
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _apiService.registerDevice(token);
      }
    } catch (_) {
      // best-effort بالكامل: فشل تسجيل الجهاز لا يجب أن يمنع الطبيب من
      // استخدام باقي التطبيق (جدول اليوم / المرضى) بشكل طبيعي.
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kBookingNotificationChannelId,
          'حجوزات جديدة',
          channelDescription:
              'إشعارات فورية عند وصول طلب حجز جديد من مريض عبر رابط الحجز العام',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: json.encode(message.data),
    );
  }

  PushNotificationService(this._apiService);
}
