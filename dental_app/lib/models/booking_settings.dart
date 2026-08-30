/// إعدادات "صفحة الحجز العامة" -- تطابق serialize_booking_settings حرفياً
/// (main.py، قسم "صفحة الحجز العامة" في profile.html بالموقع). هذا الرابط
/// العام (/d/<slug>) يسمح لأي مريض بحجز موعده مباشرة بلا تسجيل دخول.
class BookingSettings {
  final String? bookingSlug;
  final bool publicBookingEnabled;
  final List<int> workDays;
  final String? workStartTime;
  final String? workEndTime;
  final int? slotDurationMinutes;
  final String? clinicPhone;
  final String? bookingUrlPath;

  const BookingSettings({
    this.bookingSlug,
    required this.publicBookingEnabled,
    required this.workDays,
    this.workStartTime,
    this.workEndTime,
    this.slotDurationMinutes,
    this.clinicPhone,
    this.bookingUrlPath,
  });

  factory BookingSettings.fromJson(Map<String, dynamic> json) {
    final rawDays = json['work_days'] as List? ?? const [];
    return BookingSettings(
      bookingSlug: json['booking_slug'] as String?,
      publicBookingEnabled: json['public_booking_enabled'] as bool? ?? false,
      workDays: rawDays.map((d) => d as int).toList(),
      workStartTime: json['work_start_time'] as String?,
      workEndTime: json['work_end_time'] as String?,
      slotDurationMinutes: json['slot_duration_minutes'] as int?,
      clinicPhone: json['clinic_phone'] as String?,
      bookingUrlPath: json['booking_url_path'] as String?,
    );
  }
}
