import 'package:shared_preferences/shared_preferences.dart';

/// تخزين محلي بسيط لجلسة الطبيب (نفس مفاتيح localStorage المستخدمة في
/// الموقع من حيث المعنى: token / doctor_email / doctor_name / tier)، حتى لا
/// يحتاج الطبيب لتسجيل الدخول من جديد في كل مرة يفتح فيها التطبيق.
class AuthStorage {
  static const _kToken = 'auth_token';
  static const _kEmail = 'doctor_email';
  static const _kDoctorName = 'doctor_name';
  static const _kTier = 'user_tier';

  Future<void> saveSession({
    required String token,
    required String email,
    String? doctorName,
    String? tier,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kEmail, email);
    if (doctorName != null && doctorName.isNotEmpty) {
      await prefs.setString(_kDoctorName, doctorName);
    }
    if (tier != null && tier.isNotEmpty) {
      await prefs.setString(_kTier, tier);
    }
  }

  Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);

  Future<String?> getEmail() async =>
      (await SharedPreferences.getInstance()).getString(_kEmail);

  Future<String?> getDoctorName() async =>
      (await SharedPreferences.getInstance()).getString(_kDoctorName);

  Future<String?> getTier() async =>
      (await SharedPreferences.getInstance()).getString(_kTier);

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kEmail);
    await prefs.remove(_kDoctorName);
    await prefs.remove(_kTier);
  }
}
