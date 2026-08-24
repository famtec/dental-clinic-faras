import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/appointment.dart';
import '../models/patient.dart';
import 'auth_storage.dart';

/// استثناء موحّد لكل أخطاء الـ API، يحمل statusCode حتى تقدر الشاشات تميّز
/// بين: 401 (جلسة منتهية -> يجب تسجيل الخروج)، 402 (الاشتراك متوقف/بانتظار
/// التفعيل -> رسالة جدار الحماية التجاري القادمة من الـ backend نفسه)، وأي
/// خطأ آخر (رسالة عامة تُعرض كما هي، الـ backend يرجعها بالعربي دائماً تقريباً).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  bool get isSessionExpired => statusCode == 401;
  bool get isSubscriptionBlocked => statusCode == 402;

  @override
  String toString() => message;
}

class ApiService {
  final AuthStorage authStorage;
  ApiService(this.authStorage);

  Future<Map<String, String>> _authHeaders() async {
    final token = await authStorage.getToken();
    final email = await authStorage.getEmail();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      // X-Doctor-Email لم يعد يُستخدَم لتحديد الهوية فعلياً في الـ backend
      // (التوكن الموقّع هو المصدر الوحيد الموثوق)، لكنه يبقى في التوقيع
      // للتوافق مع أي مسار قديم ما زال يقرأه -- انظر تعليق main.py.
      if (email != null && email.isNotEmpty) 'X-Doctor-Email': email,
    };
  }

  dynamic _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return {};
    try {
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return {};
    }
  }

  String _errorMessage(dynamic decoded, String fallback) {
    if (decoded is Map && decoded['detail'] != null) {
      final detail = decoded['detail'];
      if (detail is String) return detail;
      return detail.toString();
    }
    return fallback;
  }

  Never _throwForResponse(http.Response response, String fallback) {
    final decoded = _decodeBody(response);
    throw ApiException(
      _errorMessage(decoded, fallback),
      statusCode: response.statusCode,
    );
  }

  /// تسجيل الدخول -- يرجع خريطة تحتوي token / email / tier / doctor_name.
  Future<Map<String, dynamic>> login(String email, String password) async {
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }

    final decoded = _decodeBody(response);
    if (response.statusCode != 200) {
      throw ApiException(
        _errorMessage(decoded, 'فشل تسجيل الدخول. حاول مرة أخرى.'),
        statusCode: response.statusCode,
      );
    }
    return decoded as Map<String, dynamic>;
  }

  Future<List<Patient>> fetchPatients() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/patients'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل قائمة المرضى.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => Patient.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Appointment>> fetchAppointments() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/appointments'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل جدول المواعيد.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => Appointment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateAppointmentStatus(int appointmentId, String status) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/appointments/$appointmentId/status'),
            headers: headers,
            body: json.encode({'status': status}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث حالة الموعد.');
    }
  }

  /// تسجيل رمز جهاز FCM بعد تسجيل الدخول -- best-effort من ناحية الواجهة:
  /// فشل هذا النداء لا يجب أن يمنع الطبيب من استخدام التطبيق (انظر
  /// PushNotificationService حيث يُستدعى هذا داخل try/catch صامت).
  Future<void> registerDevice(String fcmToken) async {
    final headers = await _authHeaders();
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/auth/register-device'),
          headers: headers,
          body: json.encode({'fcm_token': fcmToken}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تسجيل الجهاز لاستقبال الإشعارات.');
    }
  }
}
