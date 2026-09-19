import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'clinic_doctors_screen.dart';
import 'contact_developer_screen.dart';
import 'treatment_catalog_screen.dart';
import 'profile_screen.dart';

/// تبويب "المزيد" -- بوابة التنقل لبقية صفحات الموقع التي لا مكان لها في
/// شريط التنقل السفلي ذي الثلاث تبويبات (التقارير المالية / مخزن المواد /
/// حسابي / تواصل مع المطور)، تماماً كما تظهر في هيدر/قائمة الموقع. يحوي
/// أيضاً زر تسجيل الخروج (نفس الزر الموجود في هيدر كل صفحة بالموقع).
class MoreMenuScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onLogout;
  final VoidCallback onSessionExpired;

  const MoreMenuScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onLogout,
    required this.onSessionExpired,
  });

  @override
  State<MoreMenuScreen> createState() => _MoreMenuScreenState();
}

class _MoreMenuScreenState extends State<MoreMenuScreen> {
  // شارة الباقة صارت داخل ClinicTopBar التي تقرأها من AuthStorage بنفسها،
  // فلم تعد هذه الشاشة تحتاج تحميلها.

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AtmosphereBackground(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const ClinicTopBar(),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, floatingNavInset(context) + 84),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "التقارير المالية" و"مخزن المواد" لم يعودا هنا: صارا
                  // تبويبين مستقلين في الشريط السفلي (2026-09-02)، ولوحة
                  // "المزيد" في الموقع لا تحتويهما أصلاً.
                  _MenuTile(
                    icon: Icons.person_outline,
                    // cyan400 (#22D3EE) على خلفية فاتحة يقرأ باهتاً جداً --
                    // بُدِّل بالنيلي، وهو لون الهوية أصلاً.
                    color: AppColors.indigo600,
                    title: 'حسابي',
                    subtitle: 'بيانات الطبيب والعيادة وكلمة السر',
                    onTap: () => _push(ProfileScreen(
                      apiService: widget.apiService,
                      authStorage: widget.authStorage,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  // لائحة أسعار العلاجات -- 2026-09-18. محروسة باشتراك نشط
                  // فقط لا بباقة مدفوعة، فهي متاحة لكل مشترك.
                  _MenuTile(
                    icon: Icons.price_change_outlined,
                    color: AppColors.cyan500,
                    title: 'لائحة أسعار العلاجات',
                    subtitle: 'تسعيرة كل حالة وموادها المعتادة وربحيتها',
                    onTap: () => _push(TreatmentCatalogScreen(
                      apiService: widget.apiService,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  // الأطباء والنسب -- 2026-09-18. يظهر للجميع ولا يُخفى بفحص
                  // الباقة محلياً: الباقة المخزّنة في الجهاز قد تكون قديمة،
                  // وإخفاء المدخل كان سيمنع طبيباً رقّى باقته للتوّ من رؤية
                  // ما دفع لأجله. الشاشة نفسها تُظهر بطاقة القفل عند 403.
                  _MenuTile(
                    icon: Icons.groups_2_outlined,
                    color: AppColors.violet600,
                    title: 'الأطباء والنسب',
                    subtitle: 'نِسَب الأطباء ومستحقاتهم وكشوف حسابهم',
                    onTap: () => _push(ClinicDoctorsScreen(
                      apiService: widget.apiService,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  _MenuTile(
                    icon: Icons.support_agent_outlined,
                    color: AppColors.emerald500,
                    title: 'تواصل مع المطور',
                    subtitle: 'الدعم الفني والترقية والتواصل المباشر',
                    onTap: () => _push(const ContactDeveloperScreen()),
                  ),
                  const SizedBox(height: 18),
                  const _ThemeModeCard(),
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final surf = context.surface;
                      // الأحمر يبقى أحمر في الوضعين (دلالته ثابتة)، لكن
                      // rose50 المصمت يصير بقعة بيضاء على سطح ‎#07061A --
                      // فالخلفية والحدّ شفافيتان من نفس اللون بدل درجتين
                      // فاتحتين ثابتتين.
                      final tint =
                          surf.isDark ? AppColors.rose400 : AppColors.rose700text;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: widget.onLogout,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.rose500
                                  .withValues(alpha: surf.isDark ? .12 : .07),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.rose500
                                    .withValues(alpha: surf.isDark ? .28 : .30),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'تسجيل الخروج',
                                  style: AppType.kufi(
                                    color: tint,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.logout, color: tint, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surf.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: surf.cardBorder),
            boxShadow: surf.cardShadow,
          ),
          child: Row(
            children: [
              Icon(Icons.chevron_left, color: surf.textMuted),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: AppType.kufi(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: surf.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11.5, color: surf.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  border: Border.all(color: color.withValues(alpha: .24)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مبدّل وضع الإضاءة -- ثلاث كبسولات داخل بطاقة واحدة. الاختيار يُحفَظ
/// فوراً عبر [ThemeController] ويُطبَّق على كامل التطبيق في نفس اللحظة
/// (main.dart يستمع للـ ValueNotifier مباشرة).
///
/// "تلقائي" يتبع إعداد النظام في الجهاز، وهو الخيار الذي يجعل التطبيق
/// ينقلب ليلاً وحده مساءً على أجهزة تفعّل الجدولة التلقائية.
class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard();

  static const _options = <_ThemeOptionSpec>[
    _ThemeOptionSpec(ThemeMode.light, 'نهاري', Icons.light_mode_outlined),
    _ThemeOptionSpec(ThemeMode.dark, 'ليلي', Icons.dark_mode_outlined),
    _ThemeOptionSpec(
        ThemeMode.system, 'تلقائي', Icons.brightness_auto_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, current, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          decoration: BoxDecoration(
            color: surf.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: surf.cardBorder),
            boxShadow: surf.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'مظهر التطبيق',
                      textAlign: TextAlign.right,
                      style: AppType.kufi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: surf.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: surf.iconBoxBg,
                      border: Border.all(color: surf.iconBoxBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.palette_outlined,
                        size: 17, color: surf.iconBoxFg),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _ThemeModeOption(
                        mode: _options[i].mode,
                        label: _options[i].label,
                        icon: _options[i].icon,
                        selected: current == _options[i].mode,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// وصف خيار واحد في المبدّل. صنف صغير بدل Record ثلاثي -- أوضح عند القراءة
/// (`.mode` بدل `.$1`) وأأمن لو تغيّر ترتيب الحقول لاحقاً.
class _ThemeOptionSpec {
  final ThemeMode mode;
  final String label;
  final IconData icon;

  const _ThemeOptionSpec(this.mode, this.label, this.icon);
}

class _ThemeModeOption extends StatelessWidget {
  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;

  const _ThemeModeOption({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ThemeController.instance.set(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? null : surf.chipBg,
            gradient: selected ? surf.accentGradient : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : surf.chipBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: surf.accentGlow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: selected ? surf.onAccent : surf.chipFg),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? surf.onAccent : surf.chipFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
