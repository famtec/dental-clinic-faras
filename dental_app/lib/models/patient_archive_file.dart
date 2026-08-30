import '../config.dart';

/// ملف طبي مرفوع لمريض (صورة/أشعة أو مستند PDF) -- يطابق PatientXRayResponse
/// في main.py (normalize_archive_record) و"أرشيف ملفات المريض" في
/// patient_record.html بالموقع (endpoint واحد: /api/patients/{id}/archive،
/// اسم الجدول القديم PatientXRay محفوظ في main.py بلا تغيير رغم أن الميزة
/// تدعم أي صورة/أشعة/PDF وليس الأشعة فقط -- التسمية الظاهرة للمستخدم
/// "أرشيف ملفات المريض" في كل مكان).
class PatientArchiveFile {
  final int id;
  final int patientId;
  final String fileName;
  final String fileUrl;
  final String? description;
  final String fileType; // "image" أو "pdf" -- انظر ARCHIVE_FILE_MAP في main.py
  final DateTime uploadedAt;
  final String imageUrl;

  const PatientArchiveFile({
    required this.id,
    required this.patientId,
    required this.fileName,
    required this.fileUrl,
    required this.description,
    required this.fileType,
    required this.uploadedAt,
    required this.imageUrl,
  });

  bool get isPdf => fileType.trim().toLowerCase() == 'pdf';

  /// رابط الملف كاملاً -- file_url القادم من السيرفر نسبي دائماً
  /// (مثال: "/uploads/patient_xrays/...")، يجب تسبيقه بـ AppConfig.apiBaseUrl
  /// تماماً مثل resolveXRayImageUrl() في patient_record.html.
  String get resolvedFileUrl => _resolveUrl(fileUrl);

  String get resolvedImageUrl => _resolveUrl(imageUrl.isNotEmpty ? imageUrl : fileUrl);

  static String _resolveUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return '${AppConfig.apiBaseUrl}${trimmed.startsWith('/') ? trimmed : '/$trimmed'}';
  }

  factory PatientArchiveFile.fromJson(Map<String, dynamic> json) {
    final rawFileUrl = (json['file_url'] as String? ?? '').trim();
    final rawImageUrl = (json['image_url'] as String? ?? '').trim();
    final rawFileName = (json['file_name'] as String? ?? '').trim();
    final rawDescription = (json['description'] as String? ?? '').trim();
    return PatientArchiveFile(
      id: json['id'] as int,
      patientId: json['patient_id'] as int,
      fileName: rawFileName.isNotEmpty ? rawFileName : 'ملف طبي',
      fileUrl: rawFileUrl,
      description: rawDescription.isEmpty ? null : rawDescription,
      fileType: (json['file_type'] as String? ?? 'image').trim().toLowerCase(),
      uploadedAt: DateTime.tryParse(json['uploaded_at'] as String? ?? '') ?? DateTime.now(),
      imageUrl: rawImageUrl.isNotEmpty ? rawImageUrl : rawFileUrl,
    );
  }
}
