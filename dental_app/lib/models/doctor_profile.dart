/// ملف بيانات الطبيب المعروض في شاشة "حسابي" -- يطابق serialize_doctor_profile
/// في main.py حرفياً (انظر أيضاً profile.html بالموقع). كلمة السر الحقيقية لا
/// تُرجَع أبداً من الـ backend، فقط has_password كمؤشر بسيط (ثغرة أُصلحت
/// 2026-08-23 في main.py).
class DoctorProfile {
  final String? doctorName;
  final String email;
  final bool hasPassword;
  final String tier;
  final String? clinicName;
  final String? clinicAddress;
  final String? clinicPhone;
  final String? avatarUrl;
  final bool isActive;
  final bool subscriptionActive;
  final DateTime? subscriptionExpiresAt;

  const DoctorProfile({
    this.doctorName,
    required this.email,
    required this.hasPassword,
    required this.tier,
    this.clinicName,
    this.clinicAddress,
    this.clinicPhone,
    this.avatarUrl,
    required this.isActive,
    required this.subscriptionActive,
    this.subscriptionExpiresAt,
  });

  bool get isPremium => tier.toLowerCase() == 'premium';

  factory DoctorProfile.fromJson(Map<String, dynamic> json) {
    DateTime? expiresAt;
    final raw = json['subscription_expires_at'];
    if (raw is String && raw.isNotEmpty) {
      expiresAt = DateTime.tryParse(raw);
    }
    return DoctorProfile(
      doctorName: json['doctor_name'] as String?,
      email: (json['email'] as String?)?.trim() ?? '',
      hasPassword: json['has_password'] as bool? ?? false,
      tier: (json['tier'] as String?)?.trim() ?? 'standard',
      clinicName: json['clinic_name'] as String?,
      clinicAddress: json['clinic_address'] as String?,
      clinicPhone: json['clinic_phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      subscriptionActive: json['subscription_active'] as bool? ?? false,
      subscriptionExpiresAt: expiresAt,
    );
  }
}
