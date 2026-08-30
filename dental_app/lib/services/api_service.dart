import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/appointment.dart';
import '../models/booking_settings.dart';
import '../models/doctor_profile.dart';
import '../models/finance_summary.dart';
import '../models/inventory_item.dart';
import '../models/patient.dart';
import '../models/patient_archive_file.dart';
import '../models/prescription.dart';
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
  Future<TreatmentInvoice> createInvoice(
    int patientId, {
    required String title,
    required double totalCost,
  }) async {
    final headers = await _authHeaders();
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/patients/$patientId/invoices'),
            headers: headers,
            body: json.encode({'title': title, 'total_cost': totalCost}),
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
  }) async {
    final headers = await _authHeaders();
    final payload = <String, dynamic>{
      'full_name': fullName,
      'phone': phone,
      'medical_history': medicalHistory,
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

  /// الأشهر التي فيها حركات مالية فعلية لهذا الطبيب (لبناء قائمة اختيار
  /// الشهر) -- الشهر الحالي مضمون الوجود دائماً من طرف السيرفر.
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
