import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment.dart';
import 'platform_support.dart';

/// نوع إشعار التذكير في payload -- الضغط عليه يفتح تبويب المواعيد مثل بقية
/// الإشعارات (انظر _initPush في main.dart).
const String kAppointmentReminderNotificationType = 'appointment_reminder';

const AndroidNotificationChannel _appointmentReminderChannel = AndroidNotificationChannel(
  'appointment_reminder_channel',
  'تذكير المواعيد',
  description: 'تنبيه قبل كل موعد قادم بالمدة المختارة في «المزيد»',
  importance: Importance.high,
);

/// تذكير محلي قبل كل موعد قادم (2026-09-25)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مجدول على الجهاز نفسه لا من الخادم: يصل ولو انقطع الإنترنت ساعة الموعد.
/// كل جلب للمواعيد (OfflineAwareApiService.fetchAppointments، أونلاين أو من
/// النسخة المحلية) يعيد بناء الجدول كاملاً: يُلغى كل تذكير سابق ضمن نطاق
/// المعرّفات المحجوز ويُجدوَل من جديد -- فالموعد المحذوف أو المنقول لا يترك
/// تذكيراً يتيماً.
///
/// الجدولة غير دقيقة عمداً (inexactAllowWhileIdle): الدقيقة لا تحتاج إذن
/// «المنبّهات الدقيقة» الذي يطلبه أندرويد 14 يدوياً من المستخدم، وتأخّر
/// دقائق قليلة لا يضرّ تذكيراً قبل الموعد بنصف ساعة.
///
/// الجوال فقط: flutter_local_notifications 17 لا تدعم ويندوز.
class AppointmentReminderService {
  AppointmentReminderService._();

  static final AppointmentReminderService instance = AppointmentReminderService._();

  static const _prefEnabled = 'appointment_reminders_enabled';
  static const _prefLead = 'appointment_reminder_lead_minutes';

  /// نطاق معرّفات محجوز لهذه الإشعارات وحدها -- الإلغاء الجماعي لا يمسّ غيرها.
  static const _idBase = 710000;
  static const _idSpan = 1000;

  /// سقف ما يُجدوَل دفعة واحدة، وأفق أسبوعين: أندرويد يحدّ عدد المنبّهات
  /// المعلّقة لكل تطبيق، وكل فتح للتطبيق يعيد الجدولة على أي حال.
  static const _maxScheduled = 60;
  static const _horizon = Duration(days: 14);

  static const List<int> leadOptions = [15, 30, 60];

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final ValueNotifier<int> leadMinutes = ValueNotifier<int>(30);

  FlutterLocalNotificationsPlugin? _plugin;
  List<Appointment> _last = const [];
  bool _prefsLoaded = false;

  /// لاختبارات الواجهة على جهاز التطوير (ويندوز) حيث isMobilePlatform خاطئة.
  @visibleForTesting
  static bool? debugForceSupported;

  bool get isSupported => debugForceSupported ?? isMobilePlatform;

  /// يُستدعى من PushNotificationService بعد تهيئة الإضافة (مرة واحدة) --
  /// الإضافة مشتركة، وتهيئتها مرتين كانت ستستبدل معالج الضغط على الإشعار.
  Future<void> attach(FlutterLocalNotificationsPlugin plugin) async {
    if (!isSupported) return;
    tzdata.initializeTimeZones();
    _plugin = plugin;
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_appointmentReminderChannel);
    await _loadPrefs();
    await _reschedule();
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefEnabled) ?? true;
      final lead = prefs.getInt(_prefLead);
      if (lead != null && leadOptions.contains(lead)) leadMinutes.value = lead;
    } catch (_) {
      // تعذّر القراءة: تبقى القيم الافتراضية (مفعّل، نصف ساعة).
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _save((prefs) => prefs.setBool(_prefEnabled, value));
    await _reschedule();
  }

  Future<void> setLeadMinutes(int value) async {
    leadMinutes.value = value;
    await _save((prefs) => prefs.setInt(_prefLead, value));
    await _reschedule();
  }

  Future<void> _save(Future<bool> Function(SharedPreferences prefs) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // الاختيار فعّال في هذه الجلسة حتى لو فشل الحفظ.
    }
  }

  /// آخر قائمة مواعيد معروفة -- تُحفظ ولو لم تُهيَّأ الإضافة بعد، فتُجدوَل
  /// فور التهيئة.
  Future<void> sync(List<Appointment> appointments) async {
    if (!isSupported) return;
    _last = List.of(appointments);
    await _reschedule();
  }

  /// عند تسجيل الخروج: لا تذكير بمواعيد حساب لم يعد مفتوحاً على الجهاز.
  Future<void> cancelAll() async {
    _last = const [];
    await _cancelScheduled();
  }

  Future<void> _cancelScheduled() async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      final pending = await plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.id >= _idBase && request.id < _idBase + _idSpan) {
          await plugin.cancel(request.id);
        }
      }
    } catch (_) {
      // best-effort: فشل الإلغاء لا يوقف التطبيق.
    }
  }

  /// الجدولات متسلسلة لا متوازية: عدّة شاشات تجلب المواعيد معاً عند الإقلاع،
  /// وتداخل «إلغاء ثم جدولة» بينها كان سيُسقط تذكيرات جُدولت للتوّ.
  Future<void> _queue = Future<void>.value();

  Future<void> _reschedule() {
    return _queue = _queue.then((_) => _rescheduleNow()).catchError((Object _) {});
  }

  Future<void> _rescheduleNow() async {
    final plugin = _plugin;
    if (plugin == null) return;
    await _cancelScheduled();
    if (!enabled.value) return;

    final lead = Duration(minutes: leadMinutes.value);
    final now = DateTime.now();
    final upcoming = <({Appointment appointment, DateTime start})>[];
    for (final a in _last) {
      final status = a.status.toLowerCase();
      if (status != 'pending' && status != 'confirmed') continue;
      final start = _startOf(a);
      if (start == null) continue;
      if (start.subtract(lead).isBefore(now.add(const Duration(minutes: 1)))) continue;
      if (start.isAfter(now.add(_horizon))) continue;
      upcoming.add((appointment: a, start: start));
    }
    upcoming.sort((x, y) => x.start.compareTo(y.start));

    for (var i = 0; i < upcoming.length && i < _maxScheduled; i++) {
      final a = upcoming[i].appointment;
      final start = upcoming[i].start;
      final procedure = a.procedureType.trim();
      try {
        await plugin.zonedSchedule(
          _idBase + i,
          'موعد بعد ${_leadLabel(leadMinutes.value)}',
          '${a.patientName} — الساعة ${_clock(start)}${procedure.isEmpty ? '' : ' · $procedure'}',
          tz.TZDateTime.from(start.subtract(lead), tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              _appointmentReminderChannel.id,
              _appointmentReminderChannel.name,
              channelDescription: _appointmentReminderChannel.description,
              importance: Importance.high,
              priority: Priority.high,
              color: const Color(0xFF5A4BD4),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: json.encode({
            'type': kAppointmentReminderNotificationType,
            'appointment_id': a.id,
          }),
        );
      } catch (_) {
        // موعد واحد تعذّرت جدولته لا يوقف البقية.
      }
    }
  }

  static DateTime? _startOf(Appointment a) {
    final date = a.appointmentDate;
    if (date == null) return null;
    final parts = a.appointmentTime.split(':');
    if (parts.length < 2) return null;
    // "09:30" أو "09:30:00" من الخادم.
    final minuteText = parts[1].trim();
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(minuteText.length > 2 ? minuteText.substring(0, 2) : minuteText);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _leadLabel(int minutes) {
    if (minutes == 60) return 'ساعة';
    if (minutes == 30) return 'نصف ساعة';
    return 'ربع ساعة';
  }

  static String _clock(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${t.hour < 12 ? 'ص' : 'م'}';
  }
}
