import '../utils/tier_access.dart';

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

  /// اشتراك من كود دائم (2026-09-25) -- يُعرض «دائم» بدل تاريخ بعد مئة عام.
  final bool subscriptionLifetime;

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
    this.subscriptionLifetime = false,
  });

  /// أي باقة مدفوعة (بما فيها باقة العيادات) -- القياس بالمستوى لا
  /// بالتطابق النصّي، وإلا حُرم مشترك الباقة الأعلى من ميزة أدنى منها.
  bool get isPremium => ClinicTier.hasPremium(tier);

  /// إدارة العيادة متعددة الأطباء وحساب النسب -- باقة العيادات وحدها.
  bool get hasDoctorsAccess => ClinicTier.hasDoctors(tier);

  /// اسم الباقة كما يُعرض للطبيب (عربي).
  String get tierArabicName => ClinicTier.arabicName(tier);

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
      // لا افتراض لأي باقة عند غياب الحقل: بعد التوحيد صارت "standard"
      // مرادفاً لـ premium، فافتراضها هنا كان سيمنح واجهة مشترك مدفوع
      // لحساب لم يُفعَّل أصلاً.
      tier: (json['tier'] as String?)?.trim() ?? '',
      clinicName: json['clinic_name'] as String?,
      clinicAddress: json['clinic_address'] as String?,
      clinicPhone: json['clinic_phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      subscriptionActive: json['subscription_active'] as bool? ?? false,
      subscriptionExpiresAt: expiresAt,
      subscriptionLifetime: json['subscription_lifetime'] as bool? ?? false,
    );
  }
}
