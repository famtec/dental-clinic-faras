import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'appointment_reminder_service.dart';
import 'platform_support.dart';

/// معرّف قناة الإشعارات الافتراضية -- يجب أن يطابق بالضبط القيمة الموضوعة في
/// android/app/src/main/AndroidManifest.xml (com.google.firebase.messaging.default_notification_channel_id).
const String kBookingNotificationChannelId = 'new_booking_channel';

/// قناة "تذكيرات العيادة" (أُضيفت 2026-09-05) -- منفصلة عمداً عن قناة الحجوزات
/// حتى يقدر الطبيب كتم التذكيرات اليومية وحدها من إعدادات أندرويد دون أن يفقد
/// إشعار وصول حجز جديد (وهو الأهم عنده). **يجب أن تطابق القيمة نفسها
/// IDLE_REMINDER_CHANNEL_ID في main.py على الخادم**: الخادم يمرّرها داخل
/// android.notification.channel_id فتصل إشعارات الخلفية إلى القناة الصحيحة
/// بدل القناة الافتراضية.
const String kClinicReminderChannelId = 'clinic_reminder_channel';

/// نوع الإشعار كما يرسله الخادم في data["type"] -- نستخدمه لاختيار القناة عند
/// عرض الإشعار والتطبيق مفتوح، ولتوجيه الطبيب للتبويب الصحيح عند الضغط عليه.
const String kIdleReminderNotificationType = 'idle_reminder';

const AndroidNotificationChannel _bookingChannel = AndroidNotificationChannel(
  kBookingNotificationChannelId,
  'حجوزات جديدة',
  description: 'إشعارات فورية عند وصول طلب حجز جديد من مريض عبر رابط الحجز العام',
  importance: Importance.high,
);

const AndroidNotificationChannel _reminderChannel = AndroidNotificationChannel(
  kClinicReminderChannelId,
  'تذكيرات العيادة',
  description: 'تذكير يومي بمتابعة عيادتك إن لم تفتح التطبيق أو الموقع في ذلك اليوم',
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

  /// هل يدعم هذا الجهاز إشعارات Push أصلاً؟ **firebase_messaging لا يملك
  /// تطبيقاً على ويندوز إطلاقاً** (لا سطح مكتب عموماً) -- لمس
  /// `FirebaseMessaging.instance` هناك يرمي MissingPluginException. لذلك
  /// نخرج مبكراً بدل الاعتماد على try/catch في الطرف المستدعي: الخروج المبكر
  /// يوثّق السبب، والـ catch يخفيه.
  ///
  /// أثر ذلك على نسخة ويندوز: لا يصل "طلب حجز جديد" ولا "تذكير العيادة
  /// اليومي" كإشعار نظام. البديل المخطَّط له (المرحلة 3) هو استطلاع دوري
  /// لنقطة `/api/appointments/pending-count` -- وهي موجودة وتعمل بالفعل على
  /// الموقع لشارة العدّاد -- ثم عرض إشعار ويندوز أصلي منها.
  bool get isSupportedOnThisPlatform => isMobilePlatform;

  Future<void> initialize() async {
    if (!isSupportedOnThisPlatform) return;
    if (_initialized) return;
    _initialized = true;

    // الإشعارات المحلية قبل Firebase (2026-09-25): تذكير المواعيد لا يعتمد
    // على Firebase، ففشل تهيئته (google-services غير مضبوط مثلاً) لا يعطّله.
    // أيقونة شريط الحالة سنّ أبيض أحادي -- أيقونة التطبيق المتكيّفة لا تصلح
    // هنا (أندرويد يرسمها مربعاً، وأندرويد 8.0 ينهار بها).
    const androidInitSettings =
        AndroidInitializationSettings('@drawable/ic_stat_notify');
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

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(_bookingChannel);
    await androidNotifications?.createNotificationChannel(_reminderChannel);
    await AppointmentReminderService.instance.attach(_localNotifications);

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

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

    // القناة تُختار من نوع الإشعار نفسه: إشعارات الخلفية يوجّهها الخادم عبر
    // android.notification.channel_id، وهذه هي النسخة المقابلة لحالة "التطبيق
    // مفتوح" حيث نعرض الإشعار بأنفسنا (أندرويد لا يعرض إشعارات foreground).
    final isReminder =
        message.data['type'] == kIdleReminderNotificationType;
    final channel = isReminder ? _reminderChannel : _bookingChannel;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF5A4BD4),
        ),
      ),
      payload: json.encode(message.data),
    );
  }

  PushNotificationService(this._apiService);
}
