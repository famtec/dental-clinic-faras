import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/appointment.dart';
import '../models/booking_settings.dart';
import '../models/clinic_doctor.dart';
import '../models/doctor_profile.dart';
import '../models/doctor_statement.dart';
import '../models/finance_summary.dart';
import '../models/finance_transaction.dart';
import '../models/inventory_item.dart';
import '../models/patient.dart';
import '../models/patient_archive_file.dart';
import '../models/patient_stats.dart';
import '../models/pending_payment.dart';
import '../models/prescription.dart';
import '../models/treatment_catalog_item.dart';
import '../models/treatment_invoice.dart';
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
  // ميزة مخزن المواد (inventory) محمية بحارس مختلف في main.py
  // (require_premium_user_by_email) يرجع 403 وليس 402 -- انظر شرح كامل عند
  // استخدامها في InventoryScreen. باقي ميزات جدار الحماية التجاري في التطبيق
  // تستخدم 402 حصراً، لذا أُبقي التمييز كخاصية منفصلة بدل توسيع
  // isSubscriptionBlocked نفسها.
  bool get isPremiumRequired => statusCode == 403;

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

  /// قبل تسجيل الخروج (2026-09-25): يحاول مزامنة ما أُجّل دون اتصال، ويرجع
  /// عدد العمليات التي بقيت غير مُزامنة. ApiService العادية لا تؤجّل شيئاً.
  Future<int> prepareLogout() async => 0;

  /// يمسح النسخة المحلية من بيانات الحساب (انظر OfflineAwareApiService).
  Future<void> wipeLocalData() async {}

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

  /// تفعيل حساب جديد -- نفس نداء POST /api/auth/register الذي يستخدمه
  /// register.html بالموقع بالحرف (نفس أسماء الحقول الأربعة ونفس منطق قراءة
  /// رسالة الخطأ: detail أو message أو error). يرجع خريطة تحتوي token/tier
  /// عند النجاح (status 200) تماماً كما يقرأها سكربت الموقع.
  Future<Map<String, dynamic>> register({
    required String doctorName,
    required String email,
    required String password,
    required String activationCode,
  }) async {
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/register'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'doctor_name': doctorName,
              'email': email,
              'password': password,
              'activation_code': activationCode,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالخادم الآن. يرجى المحاولة لاحقًا.');
    }

    final decoded = _decodeBody(response);
    if (response.statusCode != 200) {
      String fallback = 'تعذر إتمام التسجيل الآن. تحقق من البيانات ثم حاول مرة أخرى.';
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['detail'] ?? decoded['error'];
        if (message is String && message.isNotEmpty) fallback = message;
      }
      throw ApiException(fallback, statusCode: response.statusCode);
    }
    return decoded as Map<String, dynamic>;
  }

  /// ترقية الحساب الحالي بكود تفعيل -- POST /api/auth/upgrade-tier، نفس
  /// المسار الذي يستعمله الموقع للترقية والتجديد. يرسل بريد الحساب المسجّل
  /// دخوله (الخادم يحدّد الحساب به)، ويحفظ الباقة الجديدة محلياً عند النجاح.
  /// يرجع رسالة الخادم («تمت ترقية الحساب إلى ... بنجاح.») لعرضها كما هي.
  Future<({String message, String tier})> upgradeTier(String activationCode) async {
    final email = await authStorage.getEmail();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/upgrade-tier'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'activation_code': activationCode.trim(),
              'email': ?email,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالخادم الآن. يرجى المحاولة لاحقًا.');
    }
    final decoded = _decodeBody(response);
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تفعيل الكود. تحقق منه وحاول مرة أخرى.');
    }
    final map = decoded is Map ? decoded : const {};
    final tier = '${map['tier'] ?? ''}';
    await authStorage.saveTier(tier);
    return (
      message: '${map['message'] ?? 'تمت ترقية الحساب بنجاح.'}',
      tier: tier,
    );
  }

  /// ماذا سيحدث لو فُعّل هذا الرمز الآن؟ (2026-09-25) -- POST
  /// /api/auth/activation-preview، بلا أي تعديل على الخادم. الرمز الجديد يحلّ
  /// محلّ القديم (الأيام المتبقية تسقط)، فإن كان للحساب اشتراك سارٍ يرجع
  /// warning برسالة التأكيد الجاهزة من الخادم؛ وإلا null. أي فشل (شبكة، رمز
  /// خاطئ) يرجع null أيضاً: التفعيل الفعلي بعده يعرض خطأه كالمعتاد.
  Future<String?> activationReplacementWarning(String activationCode) async {
    try {
      final email = await authStorage.getEmail();
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/activation-preview'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'activation_code': activationCode.trim(),
              'email': ?email,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final decoded = _decodeBody(response);
      if (decoded is! Map || decoded['will_cancel_previous'] != true) return null;
      final message = decoded['message'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }

  /// [upgradeTier] بنتيجة لا باستثناء -- لبطاقات «الميزة مقفلة» التي تعرض
  /// رسالة النجاح أو الرفض تحت حقل الكود مباشرةً.
  Future<({bool ok, String message})> tryUpgradeTier(String activationCode) async {
    try {
      final result = await upgradeTier(activationCode);
      return (ok: true, message: result.message);
    } on ApiException catch (e) {
      return (ok: false, message: e.message);
    } catch (_) {
      return (ok: false, message: 'تعذر تفعيل الكود. حاول مرة أخرى.');
    }
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

  /// إحصائيات بطاقات "الرئيسية" الثلاث -- GET /api/patients/stats، نفس نقطة
  /// النهاية التي يستخدمها index.html بالموقع لتعبئة statsTotalPatients/
  /// statsActiveAppointments/pendingBalancesCounter (انظر PatientStats
  /// لتفاصيل الحقول). أُضيف 2026-08-31 مع تحديث هوية الشاشة الرئيسية.
  Future<PatientStats> fetchPatientStats() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/patients/stats'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل الإحصائيات.');
    }
    return PatientStats.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// إنشاء مريض جديد -- نفس مسار POST /api/patients الذي يستخدمه زر "إضافة
  /// مريض" في index.html بالموقع (PatientCreate في main.py: full_name/phone
  /// مطلوبان، والباقي اختياري). الـ backend يرفض بـ 400 عند تكرار اسم مريض
  /// لنفس الطبيب (حارس التكرار من 2026-08-29) -- تصل رسالته العربية جاهزة
  /// عبر ApiException.message فتُعرض كما هي دون أي منطق تكرار إضافي هنا.
  Future<Patient> createPatient({
    required String fullName,
    required String phone,
    DateTime? birthDate,
    String? gender,
    String? medicalHistory,
    int? clinicDoctorId,
    // للعرض المحلي وحده عند الحفظ أوفلاين (OfflineAwareApiService)، غير مستخدَم هنا.
    String? clinicDoctorNameHint,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients'),
            headers: headers,
            body: json.encode({
              'full_name': fullName,
              'phone': phone,
              if (birthDate != null)
                'birth_date':
                    '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
              if (gender != null && gender.isNotEmpty) 'gender': gender,
              if (medicalHistory != null && medicalHistory.isNotEmpty)
                'medical_history': medicalHistory,
              // null = الطبيب المدير، وهو نفس معنى غياب الحقل على الخادم.
              'clinic_doctor_id': ?clinicDoctorId,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر إضافة المريض.');
    }
    return Patient.fromJson(_decodeBody(response) as Map<String, dynamic>);
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

  /// حجز موعد جديد يدوياً من الطبيب نفسه -- نفس مسار POST /api/appointments
  /// الذي يستخدمه زر "إضافة موعد جديد" في appointments.html بالموقع
  /// (AppointmentCreate في main.py: patient_id/date/time/description كلها
  /// مطلوبة، وحالته الافتراضية "Pending"). date بصيغة YYYY-MM-DD وtime بصيغة
  /// HH:MM كما يتحقق منهما الـ backend حرفياً.
  Future<Appointment> createAppointment({
    required int patientId,
    required String date,
    required String time,
    required String description,
    // اسم/هاتف المريض -- غير مستخدَمين هنا (المسار الحقيقي عبر السيرفر يعرف
    // المريض من patientId مباشرة)، موجودان فقط ليطابق التوقيع نسخة
    // OfflineAwareApiService.createAppointment التي تحتاجهما لبناء موعد
    // مؤقت معروض للطبيب أثناء انتظار المزامنة حين لا يوجد إنترنت. أُضيفا
    // 2026-08-31.
    String? patientNameHint,
    String? patientPhoneHint,
    // 2026-09-17: المدة والطبيب المنفّذ. كان التطبيق لا يرسل المدة إطلاقاً
    // فتصير كل مواعيده نصف ساعة ضمناً. null للمدة = اترك الافتراضي للخادم،
    // وnull للطبيب = الطبيب المدير صاحب الحساب (وهي قيمة صحيحة لا ناقصة،
    // ولا فرق هنا بين إرسالها وحذف الحقل خلافاً للتعديل).
    int? durationMinutes,
    int? clinicDoctorId,
    // اسم الطبيب المنفّذ -- غير مستخدَم هنا (الخادم يعرف الاسم من المعرّف)،
    // موجود فقط ليطابق التوقيع نسخة OfflineAwareApiService التي تحتاجه لعرض
    // اسم الطبيب على الموعد المؤقّت أثناء انتظار المزامنة. نفس سبب وجود
    // patientNameHint/patientPhoneHint أعلاه: الشاشة تنادي عبر مرجع من نوع
    // ApiService، فلا يُترجم النداء لو غاب المعامل عن الأساس.
    String? clinicDoctorNameHint,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/appointments'),
            headers: headers,
            body: json.encode({
              'patient_id': patientId,
              'date': date,
              'time': time,
              'description': description,
              if (durationMinutes != null) 'duration_minutes': durationMinutes,
              'clinic_doctor_id': clinicDoctorId,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 201) {
      _throwForResponse(response, 'تعذر حجز الموعد.');
    }
    return Appointment.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// تعديل تاريخ/وقت/وصف موعد قائم لأحد المرضى -- مطابق لِـ
  /// submitAppointmentEdit() في patient_record.html (زر "تعديل" في قسم
  /// "إدارة مواعيد هذا المريض"). PUT /api/appointments/{id} (AppointmentUpdate
  /// في main.py: appointment_date/appointment_time/description كلها اختيارية
  /// لكن نرسلها الثلاثة معاً دائماً كما يفعل الموقع). appointmentDateTime
  /// تُرسَل بصيغة محلية بلا تحويل UTC (بخلاف الموقع الذي يستخدم
  /// toISOString() فيحوّلها ضمنياً حسب توقيت المتصفح) -- تماشياً مع
  /// createAppointment() في هذا الملف نفسه، التي ترسل date/time كسلسلتين
  /// خامّتين بلا أي تحويل توقيت أيضاً.
  Future<Appointment> updateAppointment(
    int appointmentId, {
    required DateTime appointmentDateTime,
    required String time,
    required String description,
    int? durationMinutes,
    // ‼️ يُرسَل دائماً وصراحةً (بـ null عند اختيار الطبيب المدير): الخادم
    // يقرأ هذا الحقل بـ model_fields_set لا بـ is not None، فحذفه من الجسم
    // يعني "لا تغيير" بينما إرساله null يعني "أعِد الموعد للمدير". لذلك
    // نرسل المفتاح دائماً ولا نضعه داخل شرط -- وإلا صار إرجاع موعد من طبيب
    // مساعد إلى المدير مستحيلاً من التطبيق بصمت.
    int? clinicDoctorId,
    bool sendClinicDoctor = true,
    // كما في createAppointment أعلاه: للعرض المحلي وحده، غير مستخدَم هنا.
    String? clinicDoctorNameHint,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/appointments/$appointmentId'),
            headers: headers,
            body: json.encode({
              'appointment_date': appointmentDateTime.toIso8601String(),
              'appointment_time': time,
              'description': description,
              if (durationMinutes != null) 'duration_minutes': durationMinutes,
              if (sendClinicDoctor) 'clinic_doctor_id': clinicDoctorId,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث الموعد.');
    }
    return Appointment.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// أطباء العيادة (للاختيار عند حجز موعد وللأعمدة في جدول الساعات).
  ///
  /// **لا ترفع استثناءً عند الفشل عن قصد**: المسار محروس بباقة العيادات
  /// (Premium Plus) فيعيد 403 لحساب Premium عادي، وذلك هو الحال الطبيعي
  /// لأغلب العيادات لا خطأ يُعرَض للطبيب. القائمة الفارغة تعني "عيادة بطبيب
  /// واحد" فتختفي كل واجهة اختيار الطبيب من الشاشة. وانقطاع الشبكة يُعامَل
  /// بالمثل: الجدول يعمل بعمود واحد بدل ألا يعمل.
  Future<List<ClinicDoctor>> fetchClinicDoctors() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return const <ClinicDoctor>[];
    }
    if (response.statusCode != 200) {
      return const <ClinicDoctor>[];
    }
    try {
      final decoded = _decodeBody(response);
      final rows = decoded is List
          ? decoded
          : (decoded is Map && decoded['doctors'] is List
              ? decoded['doctors'] as List
              : const []);
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ClinicDoctor.fromJson)
          .where((doctor) => doctor.fullName.isNotEmpty)
          .toList();
    } catch (_) {
      return const <ClinicDoctor>[];
    }
  }

  /// نفس المسار السابق لكن **يرفع الاستثناء** ويحمل معاملات الفترة --
  /// لشاشة "الأطباء والنسب" وحدها. أُضيف 2026-09-18.
  ///
  /// الفرق عن fetchClinicDoctors ليس تفصيلاً: هناك 403 يعني "عيادة بطبيب
  /// واحد، أخفِ الاختيار"، وهنا 403 هو **جواب السؤال** الذي فتح الطبيب
  /// الشاشة لأجله، فيجب أن يصل إليها لتعرض بطاقة "الميزة تحتاج باقة
  /// العيادات" بدل قائمة فارغة توحي بأن لا أطباء له. ولهذا دالتان لا دالة
  /// واحدة بمُبدِّل: مُبدِّل صامت/صائح على نفس النداء كان سيُنسى في أحد
  /// الموضعين.
  ///
  /// معاملات الفترة تطابق fetchFinanceSummary حرفياً (وعبر نفس الدالة في
  /// الخادم) حتى يطابق "محصّل الشهر" هنا ما تعرضه شاشة المالية للشهر نفسه.
  Future<List<ClinicDoctor>> fetchClinicDoctorsDetailed({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
    bool includeInactive = true,
  }) async {
    final headers = await _authHeaders();
    final query = <String, String>{
      if (allTime) 'all_time': 'true',
      if (!allTime && year != null) 'year': '$year',
      if (!allTime && month != null) 'month': '$month',
      if (!allTime && day != null) 'day': '$day',
      if (!includeInactive) 'include_inactive': 'false',
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors')
        .replace(queryParameters: query.isEmpty ? null : query);
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل أطباء العيادة.');
    }
    final decoded = _decodeBody(response);
    final rows = decoded is List ? decoded : const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ClinicDoctor.fromJson)
        .toList();
  }

  Future<ClinicDoctor> createClinicDoctor({
    required String fullName,
    String? phone,
    String? specialty,
    double commissionPercent = 0,
    String? notes,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors'),
            headers: headers,
            body: json.encode({
              'full_name': fullName,
              'phone': phone,
              'specialty': specialty,
              'commission_percent': commissionPercent,
              'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwForResponse(response, 'تعذر إضافة الطبيب.');
    }
    return ClinicDoctor.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// PATCH جزئي: **كل حقل لا يُمرَّر لا يُرسَل**، والخادم يقرأ null على أنه
  /// "لا تغيير" (ClinicDoctorUpdate في main.py). هذا ما يسمح بتعديل النسبة
  /// وحدها من بطاقة الطبيب، أو بتعطيله، بلا إرسال بقية بياناته وطمسها.
  ///
  /// تنبيه: لهذا السبب **لا يمكن تفريغ الهاتف أو الاختصاص عبر هذا المسار**
  /// بإرسال null -- الطريقة هي إرسال نص فارغ ''، والخادم يخزّنه كما هو.
  Future<ClinicDoctor> updateClinicDoctor(
    int doctorId, {
    String? fullName,
    String? phone,
    String? specialty,
    double? commissionPercent,
    bool? isActive,
    String? notes,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .patch(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId'),
            headers: headers,
            body: json.encode({
              if (fullName != null) 'full_name': fullName,
              if (phone != null) 'phone': phone,
              if (specialty != null) 'specialty': specialty,
              if (commissionPercent != null) 'commission_percent': commissionPercent,
              if (isActive != null) 'is_active': isActive,
              if (notes != null) 'notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث بيانات الطبيب.');
    }
    return ClinicDoctor.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// حذف طبيب. الخادم **يرفض بـ400 كل طبيب له سجل مالي** ويطلب تعطيله بدلاً
  /// من ذلك -- وهو قرار مقصود لا خطأ يُعاد المحاولة عليه: الرسالة القادمة
  /// منه تُعرَض للطبيب كما هي.
  Future<void> deleteClinicDoctor(int doctorId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف الطبيب.');
    }
  }

  /// إنشاء/تعديل حساب دخول طبيب مساعد (2026-09-25) -- المالك وحده.
  /// [password] فارغة = تبقى كلمة السرّ الحالية (مطلوبة للحساب الجديد).
  Future<ClinicDoctor> updateDoctorLogin(
    int doctorId, {
    required String loginEmail,
    String? password,
    required bool loginEnabled,
    required bool canViewAllPatients,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId/login'),
            headers: headers,
            body: json.encode({
              'login_email': loginEmail.trim(),
              if (password != null && password.isNotEmpty) 'password': password,
              'login_enabled': loginEnabled,
              'can_view_all_patients': canViewAllPatients,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حفظ حساب الدخول.');
    }
    return ClinicDoctor.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// حذف حساب دخول طبيب مساعد: يُطرد من جلساته فوراً، ويبقى الطبيب وسجله.
  Future<ClinicDoctor> deleteDoctorLogin(int doctorId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId/login'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف حساب الدخول.');
    }
    return ClinicDoctor.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// كشف حساب طبيب واحد: حركاته في الفترة + تسوياته + المواد المستهلكة.
  Future<DoctorStatement> fetchDoctorStatement(
    int doctorId, {
    int? year,
    int? month,
    int? day,
    bool allTime = false,
  }) async {
    final headers = await _authHeaders();
    final query = <String, String>{
      if (allTime) 'all_time': 'true',
      if (!allTime && year != null) 'year': '$year',
      if (!allTime && month != null) 'month': '$month',
      if (!allTime && day != null) 'day': '$day',
    };
    final uri =
        Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId/statement')
            .replace(queryParameters: query.isEmpty ? null : query);
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل كشف حساب الطبيب.');
    }
    return DoctorStatement.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// تسجيل تسوية مسدَّدة للطبيب. paidAt اختياري، والخادم يستخدم وقت دمشق
  /// الحالي عند غيابه -- يُرسَل بلا لاحقة منطقة زمنية لأن الخادم يخزّن
  /// naive datetime بتوقيت دمشق (انظر _damascus_now في main.py)؛ إرسال UTC
  /// كان سيُزيح تسوية الساعة 1 ظهراً إلى يوم آخر في الكشف.
  Future<void> createDoctorPayout(
    int doctorId, {
    required double amount,
    String? note,
    DateTime? paidAt,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId/payouts'),
            headers: headers,
            body: json.encode({
              'amount': amount,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
              if (paidAt != null) 'paid_at': _naiveIso(paidAt),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwForResponse(response, 'تعذر تسجيل التسوية.');
    }
  }

  Future<void> deleteDoctorPayout(int doctorId, int payoutId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse(
                '${AppConfig.apiBaseUrl}/api/clinic-doctors/$doctorId/payouts/$payoutId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف التسوية.');
    }
  }

  /// ISO بلا لاحقة منطقة زمنية ولا أجزاء ثانية -- الصيغة التي يقبلها
  /// Pydantic ويخزّنها الخادم كما هي.
  static String _naiveIso(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  /// حذف موعد نهائياً -- مطابق لزر "حذف" في قسم "إدارة مواعيد هذا المريض"
  /// (deleteAppointmentById() في patient_record.html). DELETE
  /// /api/appointments/{id}، يرجع فقط {"message": ...} فلا حاجة لقراءة الجسم.
  Future<void> deleteAppointment(int appointmentId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/appointments/$appointmentId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف الموعد.');
    }
  }

  /// تحديث حالة موعد عادي (وليس طلب حجز عام) -- القيم المقبولة من الـ backend
  /// حصراً هي: pending / checked_in / no_show (انظر AppointmentStatusUpdate
  /// في main.py). لا تُستخدم هذه الدالة لطلبات pending_confirmation، فلها
  /// respondToBooking أدناه.
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

  /// قبول أو رفض طلب حجز وارد من صفحة الحجز العامة (status الحالية
  /// pending_confirmation فقط) -- decision: 'accept' أو 'reject'.
  Future<void> respondToBooking(int appointmentId, String decision) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/appointments/$appointmentId/respond'),
            headers: headers,
            body: json.encode({'decision': decision}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر الرد على طلب الحجز.');
    }
  }

  /// ================== لائحة أسعار العلاجات -- 2026-09-18 ==================
  ///
  /// المسارات محروسة بـ require_active_doctor_user فقط (اشتراك نشط) لا
  /// بباقة مدفوعة إضافية، فلا حاجة لبطاقة قفل باقة في شاشتها -- بخلاف
  /// المخزن والأطباء.

  Future<List<TreatmentCatalogItem>> fetchTreatmentCatalog({
    bool includeInactive = true,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/treatment-catalog')
        .replace(queryParameters:
            includeInactive ? null : {'include_inactive': 'false'});
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل لائحة أسعار العلاجات.');
    }
    final decoded = _decodeBody(response);
    final rows = decoded is List ? decoded : const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(TreatmentCatalogItem.fromJson)
        .toList();
  }

  Future<TreatmentCatalogItem> createTreatmentCatalogItem({
    required String name,
    required double price,
    String? notes,
    bool isActive = true,
    List<CatalogMaterial> materials = const [],
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/treatment-catalog'),
            headers: headers,
            body: json.encode({
              'name': name,
              'price': price,
              'notes': notes,
              'is_active': isActive,
              'materials': materials.map((m) => m.toInputJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwForResponse(response, 'تعذر إضافة الحالة إلى اللائحة.');
    }
    return TreatmentCatalogItem.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// PATCH جزئي. **materials حالة ثلاثية لا ثنائية** (انظر
  /// TreatmentCatalogItemUpdate في main.py): عدم تمريرها = لا تمسّ الوصفة،
  /// وتمرير قائمة فارغة = احذف كل موادها. لهذا لا يمكن التمييز بينهما
  /// باستخدام `List<...>? = null` وحده من طرف الواجهة، فوُضِع علم صريح
  /// [replaceMaterials]: بلا هذا التمييز يستحيل إفراغ وصفة من موادها.
  Future<TreatmentCatalogItem> updateTreatmentCatalogItem(
    int itemId, {
    String? name,
    double? price,
    String? notes,
    bool? isActive,
    bool replaceMaterials = false,
    List<CatalogMaterial> materials = const [],
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .patch(
            Uri.parse('${AppConfig.apiBaseUrl}/api/treatment-catalog/$itemId'),
            headers: headers,
            body: json.encode({
              if (name != null) 'name': name,
              if (price != null) 'price': price,
              if (notes != null) 'notes': notes,
              if (isActive != null) 'is_active': isActive,
              if (replaceMaterials)
                'materials': materials.map((m) => m.toInputJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث الحالة.');
    }
    return TreatmentCatalogItem.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  Future<void> deleteTreatmentCatalogItem(int itemId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/treatment-catalog/$itemId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف الحالة.');
    }
  }

  /// تقرير ربحية العلاجات لفترة. **الفترة بتاريخ إنشاء الفاتورة لا تحصيلها**
  /// (قرار الخادم): ربحية عمل لا تدفّق نقدي.
  Future<CatalogProfitReport> fetchTreatmentCatalogProfitReport({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
  }) async {
    final headers = await _authHeaders();
    final query = <String, String>{
      if (allTime) 'all_time': 'true',
      if (!allTime && year != null) 'year': '$year',
      if (!allTime && month != null) 'month': '$month',
      if (!allTime && day != null) 'day': '$day',
    };
    final uri =
        Uri.parse('${AppConfig.apiBaseUrl}/api/treatment-catalog/profit-report')
            .replace(queryParameters: query.isEmpty ? null : query);
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل تقرير ربحية العلاجات.');
    }
    return CatalogProfitReport.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// فواتير علاج مريض معيّن (مرتّبة الأحدث أولاً من طرف السيرفر).
  Future<List<TreatmentInvoice>> fetchPatientInvoices(int patientId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل فواتير العلاج.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => TreatmentInvoice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// إنشاء فاتورة علاج جديدة لمريض.
  ///
  /// [catalogItemId] مرجع للقراءة فقط إلى الحالة المختارة من لائحة الأسعار:
  /// العنوان والتكلفة يُرسَلان في title/total_cost كأي فاتورة ويُجمَّدان
  /// عليها، فتعديل سعر الحالة في اللائحة لاحقاً لا يمسّ هذه الفاتورة.
  ///
  /// [materials] تُخصَم من المخزن في **نفس عملية إنشاء الفاتورة** (كل شيء أو
  /// لا شيء من طرف الخادم): نقص مادة واحدة يُفشِل إنشاء الفاتورة كلها بـ400
  /// بدل أن يُنشئها ناقصة الخصم. قائمة فارغة أو null = بلا مواد، وهو سلوك أي
  /// إصدار قديم من التطبيق فلا ينكسر شيء.
  Future<TreatmentInvoice> createInvoice(
    int patientId, {
    required String title,
    required double totalCost,
    int? catalogItemId,
    int? clinicDoctorId,
    bool sendClinicDoctor = false,
    List<InvoiceMaterialInput>? materials,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices'),
            headers: headers,
            body: json.encode({
              'title': title,
              'total_cost': totalCost,
              if (catalogItemId != null) 'catalog_item_id': catalogItemId,
              // (2026-09-25) الحقل يُرسَل صراحةً متى ظهر اختيار الطبيب -- null
              // عندها تعني «الطبيب المدير» فعلاً. غيابه يجعل الخادم ينسب
              // الفاتورة لطبيب المريض المعالج (سلوك النسخ القديمة).
              if (sendClinicDoctor || clinicDoctorId != null)
                'clinic_doctor_id': clinicDoctorId,
              if (materials != null && materials.isNotEmpty)
                'materials': materials.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 201) {
      _throwForResponse(response, 'تعذر إنشاء فاتورة العلاج.');
    }
    return TreatmentInvoice.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// تصحيح الطبيب المنفّذ لفاتورة (2026-09-25) -- PATCH الفاتورة نفسها مع
  /// تكلفتها الحالية (حقل إلزامي في المسار). [applyToExistingPayments] ينقل
  /// الدفعات المسجّلة سابقاً ونسبها ومواد الفاتورة إلى الطبيب الجديد (تصحيح
  /// خطأ)؛ بدونه يسري التغيير على الأقساط القادمة فقط.
  Future<TreatmentInvoice> updateInvoiceDoctor(
    int patientId,
    int invoiceId, {
    required double totalCost,
    required int? clinicDoctorId,
    required bool applyToExistingPayments,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .patch(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices/$invoiceId'),
            headers: headers,
            body: json.encode({
              'total_cost': totalCost,
              'clinic_doctor_id': clinicDoctorId,
              'apply_to_existing_payments': applyToExistingPayments,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تغيير طبيب الفاتورة.');
    }
    return TreatmentInvoice.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// إضافة مواد إلى فاتورة موجودة (علاج احتاج مادة لم تُحسب عند فتحه).
  ///
  /// يخصم من المخزن فوراً ويرجع الفاتورة كاملة محدَّثة (بموادها وتكلفتها
  /// وربحها) -- فلا حاجة لإعادة تحميل قائمة الفواتير بعده.
  Future<TreatmentInvoice> addInvoiceMaterials(
    int patientId,
    int invoiceId,
    List<InvoiceMaterialInput> materials,
  ) async {
    if (materials.isEmpty) {
      throw const ApiException('لم تُحدَّد أي مادة للإضافة.');
    }
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(
                '${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices/$invoiceId/materials'),
            headers: headers,
            body: json.encode(materials.map((m) => m.toJson()).toList()),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwForResponse(response, 'تعذر تسجيل المواد المستهلكة.');
    }
    return TreatmentInvoice.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// حذف سطر مادة من فاتورة. **يُرجِع كميته إلى المخزن** (عكس الخصم تماماً)
  /// -- فهو حركة مخزن حقيقية لا تصحيح مرئي، ولذلك يُستأذَن قبله في الواجهة.
  Future<TreatmentInvoice> deleteInvoiceMaterial(
    int patientId,
    int invoiceId,
    int usageId,
  ) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse(
                '${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices/$invoiceId/materials/$usageId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف سطر المادة.');
    }
    return TreatmentInvoice.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// تسجيل دفعة على فاتورة علاج قائمة.
  ///
  /// isOpeningBalance: يطابق checkbox "تسوية رصيد قديم/سابق" في نموذج تسجيل
  /// الدفعة في patient_record.html (submitInvoicePayment) -- يُستبعد من تقرير
  /// أي شهر محدد في finance.html لكنه يبقى ضمن "كل الوقت" (انظر شرح كامل عند
  /// get_finance_summary()/register_invoice_payment() في main.py).
  Future<TreatmentInvoice> addInvoicePayment(
    int patientId,
    int invoiceId, {
    required double amount,
    String? description,
    bool isOpeningBalance = false,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(
                '${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices/$invoiceId/payments'),
            headers: headers,
            body: json.encode({
              'amount': amount,
              if (description != null && description.isNotEmpty)
                'description': description,
              'is_opening_balance': isOpeningBalance,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تسجيل الدفعة.');
    }
    return TreatmentInvoice.fromJson(
        _decodeBody(response) as Map<String, dynamic>);
  }

  /// تعديل دفعة مسجّلة على فاتورة علاج (في حال أُدخلت بالخطأ) -- يطابق
  /// PUT /api/finance/transaction/{id} حرفياً (FinancialTransactionUpdate في
  /// main.py؛ نفس المسار الذي يستخدمه زر "تعديل" على كل دفعة في
  /// patient_record.html، لأن دفعات الفواتير هي صفوف FinancialTransaction
  /// عادية مرتبطة بـ invoice_id). الاستجابة رسالة نجاح فقط بلا كائن محدَّث،
  /// لذا لا تُرجع شيئاً هنا -- على المتصل إعادة تحميل فواتير المريض بعدها
  /// (fetchPatientInvoices) ليعكس أي تغيّر في المتبقي على الفاتورة، تماماً
  /// كما يفعل الموقع (يستدعي loadPatientInvoices() بعد كل تعديل دفعة).
  Future<void> updateFinanceTransaction(
    int transactionId, {
    required double amount,
    required String description,
    bool? isOpeningBalance,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/finance/transaction/$transactionId'),
            headers: headers,
            body: json.encode({
              'amount': amount,
              'description': description,
              if (isOpeningBalance != null) 'is_opening_balance': isOpeningBalance,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث الدفعة المالية.');
    }
  }

  /// تحديث مخطط الأسنان (chart_state) بالكامل -- الـ backend يستبدل كامل
  /// القيمة المخزّنة بما يُرسَل هنا، لذا يجب دائماً إرسال الخريطة كاملة
  /// (الحالة الحالية + التعديل الجديد) لا الفرق فقط، وإلا فُقدت حالة بقية
  /// الأسنان المسجَّلة سابقاً.
  Future<Patient> updatePatientChart(
    int patientId,
    Map<String, String> chartState,
  ) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/chart'),
            headers: headers,
            body: json.encode({'chart_state': chartState}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حفظ مخطط الأسنان.');
    }
    return Patient.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// تعديل بيانات المريض الأساسية (الاسم/الهاتف/العمر/ملاحظات التاريخ
  /// الطبي) -- يطابق PatientUpdate و PUT /api/patients/{id} في main.py، وزر
  /// "تعديل" في patient_record.html بالضبط: fullName/phone/medicalHistory
  /// تُرسَل دائماً (حتى فارغة، لأن الموقع لا يرسل null لها أبداً)، بينما
  /// birthDate يُرسَل فقط عند تعديل العمر (الشاشة تحسبه هنا بنفس طريقة
  /// الموقع: 1 يناير من سنة الميلاد الموافقة للعمر المُدخَل -- لا يوجد عمود
  /// "age" فعلي في قاعدة البيانات، العمر يُحسب دائماً من birth_date).
  Future<Patient> updatePatient(
    int patientId, {
    required String fullName,
    required String phone,
    required String medicalHistory,
    DateTime? birthDate,
    int? clinicDoctorId,
    bool sendClinicDoctor = false,
    // كما في createPatient أعلاه: للعرض المحلي وحده، غير مستخدَم هنا.
    String? clinicDoctorNameHint,
  }) async {
    final headers = await _authHeaders();
    final payload = <String, dynamic>{
      'full_name': fullName,
      'phone': phone,
      'medical_history': medicalHistory,
      // الخادم يفرّق بين غياب المفتاح (لا تلمس الطبيب) وnull (أعِده للمدير)،
      // فالمفتاح لا يُرسَل إلا حين تعرض الشاشة اختيار الطبيب فعلاً -- وإلا
      // أعاد كل حفظ من عيادة بطبيب واحد المريضَ للمدير صامتاً.
      if (sendClinicDoctor) 'clinic_doctor_id': clinicDoctorId,
    };
    if (birthDate != null) {
      payload['birth_date'] =
          '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';
    }
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId'),
            headers: headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'حدث خطأ أثناء حفظ التعديلات.');
    }
    return Patient.fromJson(_decodeBody(response) as Map<String, dynamic>);
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

  /// بيانات ملف الطبيب (صفحة "حسابي" -- profile.html بالموقع).
  Future<DoctorProfile> fetchProfile() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/auth/profile'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل بيانات الحساب.');
    }
    return DoctorProfile.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// تحديث بيانات ملف الطبيب -- كل الحقول اختيارية، يُرسَل فقط ما تغيّر
  /// (DoctorProfileUpdate في main.py، وget_current_doctor_user وليس
  /// require_active_doctor_user، فيبقى الحساب المعلَّق/منتهي الاشتراك قادراً
  /// على تعديل بياناته الأساسية).
  Future<DoctorProfile> updateProfile({
    String? doctorName,
    String? clinicName,
    String? clinicAddress,
    String? clinicPhone,
    String? password,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/profile'),
            headers: headers,
            body: json.encode({
              if (doctorName != null) 'doctor_name': doctorName,
              if (clinicName != null) 'clinic_name': clinicName,
              if (clinicAddress != null) 'clinic_address': clinicAddress,
              if (clinicPhone != null) 'clinic_phone': clinicPhone,
              if (password != null && password.isNotEmpty) 'password': password,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حفظ التعديلات.');
    }
    return DoctorProfile.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// ملخص التقرير المالي لشهر محدد، أو ليوم واحد إن مُرِّر day (يطابق خيار
  /// "اليوم" في finance.html -- day يُرسَل دائماً مع year/month معاً)، أو
  /// للإجمالي الكلي إن allTime=true (نفس منطق get_finance_summary في main.py:
  /// بلا year/month يُستخدم الشهر الحالي تلقائياً من طرف السيرفر).
  Future<FinanceSummary> fetchFinanceSummary({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
  }) async {
    final headers = await _authHeaders();
    final query = <String, String>{
      if (allTime) 'all_time': 'true',
      if (!allTime && year != null) 'year': '$year',
      if (!allTime && month != null) 'month': '$month',
      if (!allTime && day != null) 'day': '$day',
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/finance/summary')
        .replace(queryParameters: query.isEmpty ? null : query);
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل التقرير المالي.');
    }
    return FinanceSummary.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// آخر الحركات المالية للفترة نفسها التي يعرضها fetchFinanceSummary --
  /// نفس المعاملات بالضبط حتى لا تنحرف القائمة عن المجاميع فوقها.
  ///
  /// المسار /api/finance/transactions أُضيف للـ backend في 2026-09-02.
  /// قبل نشره على Render يعيد 404، ولذلك تتعامل الشاشة مع الفشل بإظهار
  /// "لا توجد حركات" بدل رسالة خطأ فوق الأرقام الصحيحة.
  Future<List<FinanceTransaction>> fetchFinanceTransactions({
    int? year,
    int? month,
    int? day,
    bool allTime = false,
    int limit = 8,
  }) async {
    final headers = await _authHeaders();
    final query = <String, String>{
      if (allTime) 'all_time': 'true',
      if (!allTime && year != null) 'year': '$year',
      if (!allTime && month != null) 'month': '$month',
      if (!allTime && day != null) 'day': '$day',
      'limit': '$limit',
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/finance/transactions')
        .replace(queryParameters: query);
    late http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل آخر الحركات المالية.');
    }
    final decoded = _decodeBody(response);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FinanceTransaction.fromJson)
        .toList();
  }

  /// الأشهر التي فيها حركات مالية فعلية لهذا الطبيب (لبناء قائمة اختيار
  /// الشهر) -- الشهر الحالي مضمون الوجود دائماً من طرف السيرفر.
  // ═══ دفعات المساعدين بانتظار التأكيد + إقفال الشهر (2026-09-25) ═══

  /// طلب JSON موحّد للمسارات الجديدة -- كلها متصلة فقط (لا تأجيل دون اتصال):
  /// الدفعة المعلّقة وتأكيدها وإقفال الشهر قرارات مالية لا تُؤجَّل بصمت.
  Future<dynamic> _jsonRequest(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    required String fallback,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);
    late http.Response response;
    try {
      final encoded = body == null ? null : json.encode(body);
      final Future<http.Response> future;
      switch (method) {
        case 'GET':
          future = http.get(uri, headers: headers);
        case 'POST':
          future = http.post(uri, headers: headers, body: encoded ?? '{}');
        case 'DELETE':
          future = http.delete(uri, headers: headers);
        default:
          throw ArgumentError(method);
      }
      response = await future.timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response, fallback);
    }
    return _decodeBody(response);
  }

  /// الطبيب المساعد يسجّل مبلغاً استلمه -- ينتظر تأكيد المدير.
  Future<PendingPayment> createPendingPayment(
    int patientId,
    int invoiceId, {
    required double amount,
    String? description,
  }) async {
    final decoded = await _jsonRequest(
      'POST',
      '/api/patients/$patientId/invoices/$invoiceId/pending-payments',
      body: {
        'amount': amount,
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      },
      fallback: 'تعذر إرسال الدفعة.',
    );
    return PendingPayment.fromJson(decoded as Map<String, dynamic>);
  }

  /// المدير: دفعات كل الأطباء. المساعد: دفعاته وحده. [status]: pending أو all.
  Future<List<PendingPayment>> fetchPendingPayments({String status = 'pending'}) async {
    final decoded = await _jsonRequest(
      'GET',
      '/api/pending-payments',
      query: {'status': status},
      fallback: 'تعذر جلب الدفعات.',
    );
    return (decoded as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PendingPayment.fromJson)
        .toList();
  }

  Future<PendingSummary> fetchPendingPaymentsCount() async {
    final decoded = await _jsonRequest('GET', '/api/pending-payments/count', fallback: 'تعذر جلب الدفعات.');
    final map = decoded is Map ? decoded : const {};
    return PendingSummary(
      count: (map['count'] as num?)?.toInt() ?? 0,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<PendingPayment> confirmPendingPayment(int id) async {
    final decoded = await _jsonRequest('POST', '/api/pending-payments/$id/confirm', fallback: 'تعذر تأكيد الدفعة.');
    return PendingPayment.fromJson(decoded as Map<String, dynamic>);
  }

  Future<PendingPayment> rejectPendingPayment(int id, {String? note}) async {
    final decoded = await _jsonRequest(
      'POST',
      '/api/pending-payments/$id/reject',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
      fallback: 'تعذر رفض الدفعة.',
    );
    return PendingPayment.fromJson(decoded as Map<String, dynamic>);
  }

  /// المساعد يلغي دفعة سجّلها بالخطأ قبل المراجعة.
  Future<void> cancelPendingPayment(int id) async {
    await _jsonRequest('DELETE', '/api/pending-payments/$id', fallback: 'تعذر إلغاء الدفعة.');
  }

  Future<List<ClosedPeriod>> fetchClosedPeriods() async {
    final decoded = await _jsonRequest('GET', '/api/finance/closed-periods', fallback: 'تعذر جلب الأشهر المقفلة.');
    return (decoded as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClosedPeriod.fromJson)
        .toList();
  }

  Future<ClosedPeriod> closeFinanceMonth(int year, int month) async {
    final decoded = await _jsonRequest(
      'POST',
      '/api/finance/closed-periods',
      body: {'year': year, 'month': month},
      fallback: 'تعذر إقفال الشهر.',
    );
    return ClosedPeriod.fromJson(decoded as Map<String, dynamic>);
  }

  Future<void> reopenFinanceMonth(int year, int month) async {
    await _jsonRequest('DELETE', '/api/finance/closed-periods/$year/$month', fallback: 'تعذر فتح قفل الشهر.');
  }

  Future<List<({int year, int month})>> fetchAvailableMonths() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/finance/available-months'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل قائمة الأشهر.');
    }
    final decoded = _decodeBody(response) as Map<String, dynamic>;
    final months = (decoded['months'] as List?) ?? const [];
    return months
        .map((item) => (
              year: (item as Map<String, dynamic>)['year'] as int,
              month: item['month'] as int,
            ))
        .toList();
  }

  /// تسجيل مصروف عام جديد -- نطاق التطبيق الحالي يغطي المصروفات العامة
  /// (type=expense) فقط، وليس دفعات المرضى المرتبطة بفاتورة علاج، فتلك لها
  /// شاشة ملف المريض وaddInvoicePayment أعلاه أصلاً (ExpenseCreate في
  /// main.py: amount/description مطلوبان، type يُرسَل ثابتاً "expense" هنا).
  ///
  /// 2026-08-29: ربط اختياري بمخزن المواد -- مطابق تماماً لـ finance.html
  /// (`#addToInventoryToggle`): تُرسَل حقول add_to_inventory/inventory_item_name/
  /// inventory_quantity فقط عندما addToInventory=true. الـ backend (create_expense
  /// في main.py) يتجاهل الربط بصمت (لا يفشل حفظ المصروف) إن لم يكن حساب الطبيب
  /// premium أو النوع income -- لا حاجة لأي تحقق إضافي هنا. القيمة المُرجَعة
  /// تعكس ExpenseResponse.inventory_synced/inventory_action ليعرضها الطالب
  /// كرسالة نجاح أغنى، تماماً كما يفعل submitExpense() بالموقع.
  Future<({bool inventorySynced, String? inventoryAction})> createExpense({
    required double amount,
    required String description,
    bool addToInventory = false,
    String? inventoryItemName,
    int? inventoryQuantity,
  }) async {
    final headers = await _authHeaders();
    final payload = <String, dynamic>{
      'amount': amount,
      'description': description,
      'type': 'expense',
    };
    if (addToInventory) {
      payload['add_to_inventory'] = true;
      payload['inventory_item_name'] = inventoryItemName;
      payload['inventory_quantity'] = inventoryQuantity;
    }
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/finance/expenses'),
            headers: headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تسجيل المصروف.');
    }
    final decoded = _decodeBody(response) as Map<String, dynamic>;
    return (
      inventorySynced: decoded['inventory_synced'] as bool? ?? false,
      inventoryAction: decoded['inventory_action'] as String?,
    );
  }

  /// قائمة مواد مخزن العيادة -- ميزة Premium حصراً، الـ backend يرجع 403
  /// لغير المشتركين (require_premium_user_by_email، وليس 402 كباقي جدار
  /// الحماية التجاري -- انظر isPremiumRequired أعلاه).
  Future<List<InventoryItem>> fetchInventory() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/inventory'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل مخزن المواد.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => InventoryItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<InventoryItem> createInventoryItem({
    required String itemName,
    required int quantity,
    int minAlertQuantity = 5,
    // تكلفة الوحدة (2026-09-18). null = لا تُرسَل فيأخذ الخادم صفراً، وهو
    // سلوك التطبيق قبل هذا التحديث بالضبط.
    double? unitCost,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/inventory'),
            headers: headers,
            body: json.encode({
              'item_name': itemName,
              'quantity': quantity,
              'min_alert_quantity': minAlertQuantity,
              if (unitCost != null) 'unit_cost': unitCost,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 201) {
      _throwForResponse(response, 'تعذر إضافة المادة.');
    }
    return InventoryItem.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  Future<InventoryItem> updateInventoryItem(
    int itemId, {
    String? itemName,
    int? quantity,
    int? minAlertQuantity,
    double? unitCost,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/inventory/$itemId'),
            headers: headers,
            body: json.encode({
              if (itemName != null) 'item_name': itemName,
              if (quantity != null) 'quantity': quantity,
              if (minAlertQuantity != null) 'min_alert_quantity': minAlertQuantity,
              if (unitCost != null) 'unit_cost': unitCost,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحديث المادة.');
    }
    return InventoryItem.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  Future<void> deleteInventoryItem(int itemId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(Uri.parse('${AppConfig.apiBaseUrl}/api/inventory/$itemId'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف المادة.');
    }
  }

  /// إعدادات "صفحة الحجز العامة" (قسم في profile.html بالموقع، وليست شاشة
  /// منفصلة -- الرابط العام /d/<slug> يُقدَّم من نفس أصل الـ backend نفسه،
  /// انظر main.py: `@app.get("/d/{slug}")`).
  Future<BookingSettings> fetchBookingSettings() async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/auth/booking-settings'), headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل إعدادات الحجز.');
    }
    return BookingSettings.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// تحديث إعدادات الحجز -- كل الحقول اختيارية، يُرسَل فقط ما تغيّر (نفس
  /// BookingSettingsUpdate في main.py). لا يقبل الـ backend تفعيل
  /// public_booking_enabled قبل ضبط الرابط/أيام العمل/وقت الدوام، فتصل رسالة
  /// الخطأ العربية الجاهزة عبر ApiException.message عند محاولة ذلك.
  Future<BookingSettings> updateBookingSettings({
    String? bookingSlug,
    bool? publicBookingEnabled,
    List<int>? workDays,
    String? workStartTime,
    String? workEndTime,
    int? slotDurationMinutes,
    String? clinicPhone,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/booking-settings'),
            headers: headers,
            body: json.encode({
              if (bookingSlug != null) 'booking_slug': bookingSlug,
              if (publicBookingEnabled != null) 'public_booking_enabled': publicBookingEnabled,
              if (workDays != null) 'work_days': workDays,
              if (workStartTime != null) 'work_start_time': workStartTime,
              if (workEndTime != null) 'work_end_time': workEndTime,
              if (slotDurationMinutes != null) 'slot_duration_minutes': slotDurationMinutes,
              if (clinicPhone != null) 'clinic_phone': clinicPhone,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حفظ إعدادات الحجز.');
    }
    return BookingSettings.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// رفع صورة الحساب (الأفاتار) -- multipart/form-data بحقل واحد اسمه "file"،
  /// نفس ما يرسله avatarFileInput في profile.html بالموقع. bytes/filename
  /// يأتيان من ImagePicker في الشاشة (XFile.readAsBytes) بدل dart:io File
  /// مباشرة، حتى يبقى الكود يعمل على الويب أيضاً (flutter run -d chrome) لا
  /// فقط على أندرويد/iOS. يرجع avatar_url نسبياً (مثل "/uploads/avatars/..")
  /// يجب دمجه مع AppConfig.apiBaseUrl عند العرض، تماماً كما يفعل الموقع.
  Future<String?> uploadAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final headers = await _authHeaders();
    // multipart request يضبط Content-Type بنفسه (مع boundary صحيح)، فيجب
    // إزالة القيمة الثابتة 'application/json' التي يضيفها _authHeaders()
    // دائماً وإلا فسد جسم الطلب على السيرفر.
    headers.remove('Content-Type');
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/auth/avatar');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    late http.Response response;
    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
      response = await http.Response.fromStream(streamedResponse);
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر رفع صورة الحساب.');
    }
    final decoded = _decodeBody(response) as Map<String, dynamic>;
    return decoded['avatar_url'] as String?;
  }

  /// أرشيف ملفات المريض (صور/أشعة أو مستندات PDF) -- يطابق GET
  /// /api/patients/{id}/archive في main.py (مرتّبة الأحدث أولاً من طرف
  /// السيرفر، انظر get_patient_archive()).
  Future<List<PatientArchiveFile>> fetchPatientArchive(int patientId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/archive'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل أرشيف الملفات الطبية.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => PatientArchiveFile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// رفع ملف طبي جديد لأرشيف مريض -- يطابق POST /api/patients/{id}/archive
  /// (upload_patient_archive في main.py: multipart، حقل "file" + حقل
  /// "description" نصي اختياري، PNG/JPG/JPEG/PDF فقط -- انظر
  /// validate_archive_file). مطابق لسلوك uploadArchiveFile() في
  /// patient_record.html بالموقع حرفياً. لا يُحدَّد Content-Type للملف نفسه
  /// عمداً (يُترك الافتراضي application/octet-stream من حزمة http) --
  /// الـ backend يقبله صراحةً كبديل مقبول عن نوع MIME الحقيقي.
  Future<PatientArchiveFile> uploadPatientArchiveFile(
    int patientId, {
    required List<int> bytes,
    required String filename,
    String? description,
  }) async {
    final headers = await _authHeaders();
    headers.remove('Content-Type');
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/archive');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['description'] = description ?? ''
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    late http.Response response;
    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
      response = await http.Response.fromStream(streamedResponse);
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 201) {
      _throwForResponse(response, 'تعذر رفع الملف الطبي.');
    }
    return PatientArchiveFile.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }

  /// حذف ملف من أرشيف مريض -- يطابق DELETE
  /// /api/patients/{patient_id}/archive/{archive_id} الموجود مسبقاً في
  /// main.py (delete_patient_archive: يحذف السجل من قاعدة البيانات ثم
  /// الملف الفعلي من القرص إن وُجد). يُستدعى من الضغط المطوّل على بطاقة
  /// الملف في أرشيف المريض بالتطبيق.
  Future<void> deletePatientArchiveFile(int patientId, int archiveId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .delete(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/archive/$archiveId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر حذف الملف الطبي.');
    }
  }

  /// الوصفات الطبية لمريض معيّن (مرتّبة الأحدث أولاً من طرف السيرفر) -- تطابق
  /// GET /api/prescriptions/patient/{id} في main.py.
  Future<List<Prescription>> fetchPatientPrescriptions(int patientId) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/prescriptions/patient/$patientId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 200) {
      _throwForResponse(response, 'تعذر تحميل الوصفات الطبية.');
    }
    final decoded = _decodeBody(response) as List;
    return decoded
        .map((item) => Prescription.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// إصدار وحفظ وصفة طبية جديدة لمريض -- تطابق POST /api/prescriptions
  /// (PrescriptionCreate في main.py: medications/instructions مطلوبان
  /// وغير فارغين).
  Future<Prescription> createPrescription(
    int patientId, {
    required String medications,
    required String instructions,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/prescriptions'),
            headers: headers,
            body: json.encode({
              'patient_id': patientId,
              'medications': medications,
              'instructions': instructions,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('تعذر الاتصال بالسيرفر. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.');
    }
    if (response.statusCode != 201) {
      _throwForResponse(response, 'تعذر حفظ الوصفة الطبية.');
    }
    return Prescription.fromJson(_decodeBody(response) as Map<String, dynamic>);
  }
}
