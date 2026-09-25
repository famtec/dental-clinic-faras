import 'package:flutter/material.dart';

import '../models/clinic_doctor.dart';
import '../services/api_service.dart';
import '../services/app_session.dart';

/// خيارات اختيار «الطبيب المعالج» للمريض (2026-09-24): أطباء العيادة
/// النشطون + تسمية صاحب الحساب لخيار null.
class ClinicDoctorChoices {
  final List<ClinicDoctor> doctors;
  final String ownerLabel;

  const ClinicDoctorChoices({required this.doctors, required this.ownerLabel});

  /// عيادة بطبيب واحد (أو باقة بلا ميزة الأطباء، أو انقطاع شبكة) -- الحقل
  /// لا يظهر إطلاقاً، ولا يُرسَل الطبيب مع الحفظ فلا يُمسّ ما على الخادم.
  bool get isEmpty => doctors.isEmpty;

  /// اسم الطبيب لمعرّف مختار، لتلميح العرض المحلي عند الحفظ أوفلاين.
  String? nameFor(int? id) {
    if (id == null) return null;
    for (final doctor in doctors) {
      if (doctor.id == id) return doctor.fullName;
    }
    return null;
  }

  /// نفس مصدر حقل الطبيب في نموذج الموعد (today_schedule_screen): قائمة
  /// fetchClinicDoctors التي لا ترفع استثناءً أبداً، واسم الطبيب المخزَّن
  /// محلياً عند تسجيل الدخول.
  static Future<ClinicDoctorChoices> load(ApiService apiService) async {
    // الطبيب المساعد (2026-09-25): كل ما يسجّله يُنسب إليه على الخادم مهما
    // أُرسل، فقائمة فارغة تُخفي حقول الاختيار وزر «تغيير» في كل الشاشات.
    if (AppSession.instance.isStaff) {
      return ClinicDoctorChoices(
          doctors: const [], ownerLabel: AppSession.instance.staffName ?? '');
    }
    final doctors = await apiService.fetchClinicDoctors();
    String ownerName = '';
    try {
      ownerName = (await apiService.authStorage.getDoctorName())?.trim() ?? '';
    } catch (_) {
      ownerName = '';
    }
    return ClinicDoctorChoices(
      doctors: doctors.where((doctor) => doctor.isActive).toList(),
      ownerLabel: ownerName.isEmpty ? 'الطبيب المدير' : ownerName,
    );
  }
}

/// قائمة منسدلة لاختيار الطبيب المعالج. null = صاحب الحساب.
///
/// إن كان طبيب المريض الحالي غير موجود في القائمة (عُطِّل بعد تعيينه)
/// يُضاف خياراً باسمه القادم من الخادم: [DropdownButtonFormField] يرفض قيمة
/// لا تطابق أي عنصر، وإسقاطها صامتاً كان سيعيد المريض للمدير عند أول حفظ.
class ClinicDoctorDropdown extends StatelessWidget {
  final ClinicDoctorChoices choices;
  final int? value;
  final String? currentDoctorName;
  final ValueChanged<int?> onChanged;

  /// «الطبيب المعالج» للمريض، «الطبيب المنفّذ» للفاتورة.
  final String label;

  const ClinicDoctorDropdown({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.currentDoctorName,
    this.label = 'الطبيب المعالج',
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(value: null, child: Text(choices.ownerLabel)),
      for (final doctor in choices.doctors)
        DropdownMenuItem<int?>(value: doctor.id, child: Text(doctor.fullName)),
    ];
    final current = value;
    if (current != null && choices.nameFor(current) == null) {
      items.add(DropdownMenuItem<int?>(
        value: current,
        child: Text(currentDoctorName ?? 'طبيب غير نشط'),
      ));
    }
    return DropdownButtonFormField<int?>(
      initialValue: current,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}
