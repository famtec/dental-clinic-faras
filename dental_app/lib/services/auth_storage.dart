import 'package:shared_preferences/shared_preferences.dart';

/// تخزين محلي بسيط لجلسة الطبيب (نفس مفاتيح localStorage المستخدمة في
/// الموقع من حيث المعنى: token / doctor_email / doctor_name / tier)، حتى لا
/// يحتاج الطبيب لتسجيل الدخول من جديد في كل مرة يفتح فيها التطبيق.
class AuthStorage {
  static const _kToken = 'auth_token';
  static const _kEmail = 'doctor_email';
  static const _kDoctorName = 'doctor_name';
  static const _kTier = 'user_tier';
  // 2026-09-25: حساب طبيب مساعد (null/غائب = مالك العيادة).
  static const _kStaffDoctorId = 'staff_doctor_id';

  Future<void> saveSession({
    required String token,
    required String email,
    String? doctorName,
    String? tier,
    int? staffDoctorId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    if (staffDoctorId != null) {
      await prefs.setInt(_kStaffDoctorId, staffDoctorId);
    } else {
      await prefs.remove(_kStaffDoctorId);
    }
    await prefs.setString(_kEmail, email);
    if (doctorName != null && doctorName.isNotEmpty) {
      await prefs.setString(_kDoctorName, doctorName);
    }
    if (tier != null && tier.isNotEmpty) {
      await prefs.setString(_kTier, tier);
    }
  }

  /// تحديث الباقة وحدها بعد ترقية الحساب بكود تفعيل، بلا لمس التوكن.
  Future<void> saveTier(String tier) async {
    if (tier.isEmpty) return;
    await (await SharedPreferences.getInstance()).setString(_kTier, tier);
  }

  Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);

  Future<String?> getEmail() async =>
      (await SharedPreferences.getInstance()).getString(_kEmail);

  Future<String?> getDoctorName() async =>
      (await SharedPreferences.getInstance()).getString(_kDoctorName);

  Future<String?> getTier() async =>
      (await SharedPreferences.getInstance()).getString(_kTier);

  Future<int?> getStaffDoctorId() async =>
      (await SharedPreferences.getInstance()).getInt(_kStaffDoctorId);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kEmail);
    await prefs.remove(_kDoctorName);
    await prefs.remove(_kTier);
    await prefs.remove(_kStaffDoctorId);
  }
}
