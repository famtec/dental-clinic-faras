/// وصفة طبية لمريض واحدة -- تطابق PrescriptionResponse في main.py. يصدرها
/// الطبيب من صفحة "حالة المريض" ويمكن طباعتها فوراً (انظر
/// _printPrescription في patient_detail_screen.dart)، تماماً مثل قسم
/// "الوصفات الطبية" في patient_record.html بالموقع.
class Prescription {
  final int id;
  final int patientId;
  final String medications;
  final String instructions;
  final DateTime createdAt;

  const Prescription({
    required this.id,
    required this.patientId,
    required this.medications,
    required this.instructions,
    required this.createdAt,
  });

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: json['id'] as int,
      patientId: json['patient_id'] as int,
      medications: (json['medications'] as String?)?.trim() ?? '',
      instructions: (json['instructions'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
