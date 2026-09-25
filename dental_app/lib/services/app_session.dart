import 'package:flutter/foundation.dart';

import 'auth_storage.dart';

/// دور الحساب المفتوح على هذا الجهاز (2026-09-25): مالك العيادة، أو طبيب
/// مساعد بحساب دخول خاص.
///
/// الصلاحيات الفعلية يفرضها الخادم (StaffAccessMiddleware في main.py) --
/// هذا للعرض فقط: أيّ الشاشات تظهر، وأيّ الأزرار تُخفى حتى لا يضغط المساعد
/// زراً يعرف الخادم أنه سيرفضه.
class AppSession {
  AppSession._();

  static final AppSession instance = AppSession._();

  /// معرّف الطبيب المساعد (ClinicDoctor.id)، أو null للمالك.
  final ValueNotifier<int?> staffDoctorId = ValueNotifier<int?>(null);

  /// اسم الطبيب المساعد كما يظهر في ترويسته وكشف حسابه.
  String? staffName;

  bool get isStaff => staffDoctorId.value != null;

  Future<void> load(AuthStorage storage) async {
    staffDoctorId.value = await storage.getStaffDoctorId();
    staffName = isStaff ? await storage.getDoctorName() : null;
  }

  void clear() {
    staffDoctorId.value = null;
    staffName = null;
  }
}
