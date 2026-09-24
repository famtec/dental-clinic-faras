import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// إطار شاشتَي الدخول والتفعيل على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// على الجوال تبقى البطاقة المفردة كما هي. على نافذة ويندوز كانت البطاقة
/// نفسها (420px) تسبح في وسط شاشة 1920px فتبدو صفحة ويب مصغّرة؛ هنا تنقسم
/// النافذة: لوحة تعريف متدرّجة بمزايا المنصة على جهة البداية، والنموذج
/// نفسه (نفس الحقول ونفس المنطق) على سطح الصفحة بجانبها.
class DesktopAuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget form;

  /// زرّ رجوع أعلى النموذج (شاشة التفعيل تُفتح فوق شاشة الدخول).
  final VoidCallback? onBack;

  const DesktopAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.onBack,
  });

  static const List<({IconData icon, String title, String text})> _features = [
    (
      icon: Icons.people_alt_outlined,
      title: 'ملفات المرضى',
      text: 'المخطط السنّي والفواتير والوصفات في ملف واحد لكل مريض.',
    ),
    (
      icon: Icons.calendar_month_outlined,
      title: 'المواعيد والحجز العام',
      text: 'جدول ساعات لكل طبيب، وطلبات حجز تصلك من رابط عيادتك.',
    ),
    (
      icon: Icons.insights_outlined,
      title: 'المالية والنسب',
      text: 'الإيرادات والمصاريف ونسب الأطباء محسوبة من الدفعات الفعلية.',
    ),
    (
      icon: Icons.cloud_sync_outlined,
      title: 'يعمل بلا إنترنت',
      text: 'ما تسجّله أثناء الانقطاع يُزامَن تلقائياً عند عودة الاتصال.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 9, child: _brandPanel(context)),
        Expanded(
          flex: 11,
          child: Container(
            color: d.shellBg,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onBack != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: onBack,
                            icon: Icon(Icons.arrow_forward, size: 18, color: d.linkFg),
                            label: Text(
                              'رجوع',
                              style: AppType.sans(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: d.linkFg),
                            ),
                          ),
                        ),
                      Text(
                        title,
                        style: AppType.kufi(
                            fontSize: 24, fontWeight: FontWeight.w800, color: d.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: AppType.sans(fontSize: 13.5, height: 1.7, color: d.textSecondary),
                      ),
                      const SizedBox(height: 26),
                      form,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.authCardHeaderGradient),
      child: Stack(
        children: [
          // كرتا ضوء خافتتان -- نفس لغة بطاقات الرأس داخل التطبيق.
          PositionedDirectional(
            top: -120,
            end: -100,
            child: _glow(const Color(0xFF22D3EE), 340, .18),
          ),
          PositionedDirectional(
            bottom: -140,
            start: -80,
            child: _glow(const Color(0xFFA78BFA), 380, .28),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: .22)),
                      ),
                      child: const Icon(Icons.medical_services_rounded, size: 26, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('عيادتي الرقمية',
                            style: AppType.kufi(
                                fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text('لوحة إدارة العيادة السنّية',
                            style: AppType.sans(
                                fontSize: 12.5, color: Colors.white.withValues(alpha: .75))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 56),
                Text(
                  'عيادتك كاملة\nعلى شاشة واحدة.',
                  style: AppType.kufi(
                      fontSize: 34, height: 1.45, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 14),
                Text(
                  'نفس حسابك على الموقع وتطبيق الجوال — كل ما تسجّله هنا يظهر هناك.',
                  style: AppType.sans(
                      fontSize: 14, height: 1.8, color: Colors.white.withValues(alpha: .82)),
                ),
                const SizedBox(height: 40),
                for (final f in _features) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: .16)),
                        ),
                        child: Icon(f.icon, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title,
                                style: AppType.sans(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(f.text,
                                style: AppType.sans(
                                    fontSize: 12.5,
                                    height: 1.6,
                                    color: Colors.white.withValues(alpha: .72))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                const SizedBox(height: 24),
                Text(
                  'تطوير وإدارة: المهندس فارس حلاوي © 2026',
                  style: AppType.sans(fontSize: 11.5, color: Colors.white.withValues(alpha: .6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
