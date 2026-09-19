import 'package:flutter/material.dart';

import '../models/clinic_doctor.dart';

/// ألوان أطباء العيادة -- نقطة الحقيقة الوحيدة في التطبيق.
///
/// نُقلت إلى utils في 2026-09-18 بعد أن صارت شاشتان تحتاجانها (جدول ساعات
/// المواعيد وشاشة الأطباء والنسب): لونُ الطبيب معنى مشترك بين الشاشتين، فلو
/// بقيت نسختان لأظهرت الشاشتان الطبيب نفسه بلونين مختلفين، وهو أسوأ من عدم
/// التلوين أصلاً.
///
/// القيم مأخوذة حرفياً من --viz-1..7 في الموقع، فيقرأ الطبيب اللون نفسه
/// على الجوال وعلى المتصفّح.
const List<Color> kClinicDoctorColorSlots = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
];

/// صاحب الحساب وحده يأخذ لون العلامة (indigo 600) فيُقرأ فوراً كـ«أنا»، ولا
/// يزاحم ألوان الأطباء المساعدين.
const Color kOwnerDoctorColor = Color(0xFF4F46E5);

/// اللون يُشتَق من **ترتيب المعرّف** لا من موضع الطبيب في القائمة المعروضة:
/// القائمة تُرتَّب في شاشة الأطباء بالنشاط ثم الاسم، وفي جدول الساعات
/// بالمعرّف، فلو اعتمد اللون على الموضع لتبدّل لون الطبيب بين الشاشتين ومع
/// كل تعطيل أو إعادة تسمية.
///
/// null = صاحب الحساب (الطبيب المدير) -- وهو نفس معنى NULL في
/// appointments.clinic_doctor_id على الخادم، لا "غير محدَّد".
Color clinicDoctorColor(int? doctorId, List<ClinicDoctor> doctors) {
  if (doctorId == null) return kOwnerDoctorColor;
  final sorted = [...doctors]..sort((a, b) => a.id.compareTo(b.id));
  final index = sorted.indexWhere((doctor) => doctor.id == doctorId);
  if (index < 0) return const Color(0xFF94A3B8);
  return kClinicDoctorColorSlots[index % kClinicDoctorColorSlots.length];
}
