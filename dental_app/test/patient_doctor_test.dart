import 'package:dental_app/models/patient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 7,
        'full_name': 'مريض',
        'phone': '0999',
        'total_treatment_cost': 0,
        'paid_amount': 0,
      };

  test('خادم قديم بلا الحقلين ⇒ الطبيب المدير (null/null)', () {
    final patient = Patient.fromJson(base());
    expect(patient.clinicDoctorId, isNull);
    expect(patient.clinicDoctorName, isNull);
  });

  test('المعرّف والاسم يُقرآن من الرد', () {
    final patient = Patient.fromJson({
      ...base(),
      'clinic_doctor_id': 3,
      'clinic_doctor_name': '  د. لينا مرعي ',
    });
    expect(patient.clinicDoctorId, 3);
    expect(patient.clinicDoctorName, 'د. لينا مرعي');
  });

  test('copyWith بلا الحقلين لا يمسّ الطبيب', () {
    final patient = Patient.fromJson({...base(), 'clinic_doctor_id': 3, 'clinic_doctor_name': 'د. لينا'});
    final copy = patient.copyWith(fullName: 'اسم جديد');
    expect(copy.clinicDoctorId, 3);
    expect(copy.clinicDoctorName, 'د. لينا');
  });

  test('copyWith بـ null صريح يعيد المريض للمدير', () {
    final patient = Patient.fromJson({...base(), 'clinic_doctor_id': 3, 'clinic_doctor_name': 'د. لينا'});
    final copy = patient.copyWith(clinicDoctorId: null, clinicDoctorName: null);
    expect(copy.clinicDoctorId, isNull);
    expect(copy.clinicDoctorName, isNull);
  });
}
