// اختبار ودجات أساسي للتطبيق.
//
// كان هذا الملف منذ إنشاء المشروع هو ملف القالب الافتراضي الذي يولّده
// `flutter create`: كان يستدعي DentalApp() -- وهي دالة/صنف غير موجود أصلاً
// (جذر التطبيق الحقيقي اسمه DentalDoctorApp في lib/main.dart) -- ويتحقق من
// عدّاد "0"/"1" لتطبيق العدّاد النموذجي الذي لم يوجد في هذا المشروع قط.
// لذلك كان `flutter analyze` يُظهر خطأ undefined_function دائماً، وهو الخطأ
// الوحيد في المشروع كله، فيُخفي أي خطأ حقيقي جديد وسط الضجيج.
//
// استُبدل باختبار حقيقي صغير لا يحتاج شبكة ولا Firebase: يتحقق من سلوك
// InitialsAvatar، ومنه الخيار الجديد spacedInitials المستخدَم في بطاقة
// المريض. تعمّدنا عدم تشغيل DentalDoctorApp نفسه هنا لأنه يبدأ فحص الجلسة
// وتهيئة الإشعارات، وهذا يحتاج محاكاة كاملة لا قيمة لها في اختبار دخان.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dental_app/widgets/app_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  testWidgets('InitialsAvatar يعرض أول حرف من أول كلمتين', (tester) async {
    await pump(tester, const InitialsAvatar(name: 'محمد العلي'));
    expect(find.text('ما'), findsOneWidget);
  });

  testWidgets('spacedInitials يفصل الحرفين بمسافة', (tester) async {
    await pump(
      tester,
      const InitialsAvatar(name: 'محمد العلي', spacedInitials: true),
    );
    expect(find.text('م ا'), findsOneWidget);
  });

  testWidgets('اسم من كلمة واحدة يعطي حرفاً واحداً بلا مسافة', (tester) async {
    await pump(
      tester,
      const InitialsAvatar(name: 'سامر', spacedInitials: true),
    );
    expect(find.text('س'), findsOneWidget);
  });

  testWidgets('الاسم الفارغ لا يُسقط الودجة', (tester) async {
    await pump(tester, const InitialsAvatar(name: '   '));
    expect(find.text('؟'), findsOneWidget);
  });
}
