import 'package:flutter/material.dart';

import '../config.dart';
import '../models/doctor_profile.dart';
import '../theme/app_theme.dart';
import '../utils/tier_access.dart';

/// غلاف سطح المكتب: شريط جانبي ثابت + ترويسة علوية + مساحة محتوى (2026-09-22)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// يُستعمل **فوق [AppDesktopMetrics.breakpoint] فقط**. تحت العتبة يبقى
/// التطبيق على شريطه السفلي الزجاجي كما هو بلا أي تغيير -- انظر
/// `home_screen.dart`، حيث يتفرّع التخطيط.
///
/// كل الألوان من `context.desktop` ([AppDesktop])، لا من `context.surface`،
/// حتى لا يتسرّب أي قرار خاص بسطح المكتب إلى شاشات الجوال.
///
/// **الحدود اتجاهية لا فيزيائية**: [BorderDirectional] مع `end`/`start` بدل
/// `left`/`right`. التطبيق كله RTL، فالشريط الجانبي يظهر يميناً وحدّه الفاصل
/// عن المحتوى هو حدّه الفيزيائي الأيسر -- كتابته `end` تجعلها صحيحة بلا
/// اعتماد على أن الاتجاه لن يتغيّر أبداً.

/// أسماء الأشهر وأيام الأسبوع بالعربية. مكرَّرة هنا بنسخة خاصة بهذا الملف
/// على نفس النمط المتَّبع في `today_schedule_screen.dart` و`finance_screen.dart`
/// و`clinic_doctors_screen.dart` -- كل ملف بنسخته، بلا ملف أدوات مشترك.
const _desktopArabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// مرتّبة على ترتيب `DateTime.weekday` (1 = الإثنين ... 7 = الأحد).
const _desktopArabicWeekdays = <String>[
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// سطر التاريخ في الترويسة -- «الثلاثاء، 22 سبتمبر 2026».
String desktopArabicDateLine(DateTime date) {
  final weekday = _desktopArabicWeekdays[date.weekday - 1];
  final month = _desktopArabicMonths[date.month - 1];
  return '$weekday، ${date.day} $month ${date.year}';
}

/// عنصر واحد في الشريط الجانبي.
@immutable
class DesktopDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// عنوان الصفحة في الترويسة العلوية -- قد يكون أطول من عنوان العنصر
  /// («لائحة الأسعار» في الشريط، «لائحة أسعار العلاجات» في الترويسة).
  final String pageTitle;

  /// شارة العدّ الحمراء (طلبات الحجز المعلّقة على «المواعيد»). صفر = بلا شارة.
  final int badgeCount;

  const DesktopDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    String? pageTitle,
    this.badgeCount = 0,
  }) : pageTitle = pageTitle ?? label;
}

class DesktopShell extends StatelessWidget {
  final List<DesktopDestination> destinations;

  /// الفهرس داخل [destinations]، أو ‎-1 عندما تكون «الإعدادات» هي المفتوحة.
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// «الإعدادات» أسفل الشريط -- عنصر مستقل لا صفٌّ في [destinations]، لأن
  /// موضعه أسفل الشريط بعد فاصل، ولأن إدخاله في القائمة كان سيخلط فهرسته
  /// بفهرسة الصفحات الرئيسية.
  final bool settingsSelected;
  final VoidCallback onSettingsTap;

  /// ملف الطبيب لبطاقة أسفل الشريط وللترويسة. null = لم يُحمَّل بعد،
  /// فتُعرَض الحالة الهيكلية بلا انهيار.
  final DoctorProfile? profile;

  /// شارة الإشعارات في الترويسة (نفس عدّاد طلبات الحجز المعلّقة).
  final int notificationCount;
  final VoidCallback? onNotificationsTap;

  /// جملة حالة العيادة قبل التاريخ في الترويسة («العيادة مفتوحة الآن»).
  /// **null = لا تُكتب جملة إطلاقاً**، ويبقى التاريخ وحده: الكانفاس يكتبها
  /// ثابتةً، لكن الادّعاء بأن العيادة مفتوحة قبل قراءة أيام العمل وساعاته من
  /// إعدادات الحجز كذبٌ صغير يراه الطبيب كل صباح.
  final String? statusPrefix;

  /// يلوّن النقطة الحيّة: مفتوحة = سماوي نابض، مغلقة = رمادي خافت،
  /// null (غير معروف بعد) = السماوي كما في التصميم.
  final bool? clinicOpen;

  /// حقل البحث في الترويسة. null = لا يُعرَض إطلاقاً (لم يُوصَل بعد).
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;

  /// تسجيل الخروج -- زر صغير في بطاقة الطبيب أسفل الشريط. **إلزامي على سطح
  /// المكتب**: زرّ الخروج الوحيد في التطبيق يعيش في شاشة «المزيد»، وهي لا
  /// وجود لها في هذا التخطيط، فبلا هذا الزر يصير الطبيب عاجزاً عن الخروج من
  /// حسابه. موضعه في البطاقة يطابق أيضاً زر الخروج في هيدر كل صفحة بالموقع.
  final VoidCallback onLogout;

  /// «تواصل مع المطور» -- أيقونة ثانية في بطاقة الطبيب بجانب الخروج
  /// (2026-09-24). نفس سبب زر الخروج: الشاشة تعيش في «المزيد» على الجوال،
  /// ولا «مزيد» في هذا التخطيط، فبلا الأيقونة لا طريق إلى الدعم الفني ولا
  /// إلى الترقية -- وشاشات الباقات المقفلة كلها تقول «تواصل مع المطور».
  final VoidCallback onContactDeveloper;

  final Widget child;

  const DesktopShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.settingsSelected,
    required this.onSettingsTap,
    required this.profile,
    required this.onLogout,
    required this.onContactDeveloper,
    required this.child,
    this.notificationCount = 0,
    this.onNotificationsTap,
    this.onSearchChanged,
    this.searchController,
    this.statusPrefix,
    this.clinicOpen,
  });

  /// عنوان الصفحة المفتوحة حالياً.
  String get _pageTitle {
    if (settingsSelected) return 'حسابي';
    if (currentIndex < 0 || currentIndex >= destinations.length) return '';
    return destinations[currentIndex].pageTitle;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Container(
      color: d.shellBg,
      child: Row(
        children: [
          _Sidebar(
            destinations: destinations,
            currentIndex: currentIndex,
            onSelect: onSelect,
            settingsSelected: settingsSelected,
            onSettingsTap: onSettingsTap,
            profile: profile,
            onLogout: onLogout,
            onContactDeveloper: onContactDeveloper,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _pageTitle,
                  statusPrefix: statusPrefix,
                  clinicOpen: clinicOpen,
                  profile: profile,
                  notificationCount: notificationCount,
                  onNotificationsTap: onNotificationsTap,
                  onSearchChanged: onSearchChanged,
                  searchController: searchController,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ── الشريط الجانبي ────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<DesktopDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool settingsSelected;
  final VoidCallback onSettingsTap;
  final DoctorProfile? profile;
  final VoidCallback onLogout;
  final VoidCallback onContactDeveloper;

  const _Sidebar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.settingsSelected,
    required this.onSettingsTap,
    required this.profile,
    required this.onLogout,
    required this.onContactDeveloper,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Container(
      width: AppDesktopMetrics.sidebarWidth,
      padding: AppDesktopMetrics.sidebarPadding,
      decoration: BoxDecoration(
        color: d.sidebarBg,
        border: BorderDirectional(
          end: BorderSide(color: d.sidebarBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(context),
          _hairline(context, const EdgeInsets.fromLTRB(4, 2, 4, 16)),
          // القائمة قابلة للتمرير حتى لا تفيض على نافذة قصيرة -- تصميم
          // الكانفاس على ارتفاع 960px، وويندوز يسمح بنافذة أقصر بكثير.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == destinations.length - 1 ? 0 : 4),
                      child: _SideLink(
                        destination: destinations[i],
                        isActive: !settingsSelected && currentIndex == i,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SideLink(
            destination: const DesktopDestination(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'الإعدادات',
            ),
            isActive: settingsSelected,
            onTap: onSettingsTap,
          ),
          _hairline(context, const EdgeInsets.fromLTRB(4, 16, 4, 14)),
          _doctorCard(context),
        ],
      ),
    );
  }

  Widget _hairline(BuildContext context, EdgeInsets margin) {
    return Padding(
      padding: margin,
      child: Container(height: 1, color: context.desktop.sidebarBorder),
    );
  }

  Widget _brand(BuildContext context) {
    final d = context.desktop;
    final clinic = (profile?.clinicName ?? '').trim();
    final title = clinic.isNotEmpty
        ? clinic
        : 'عيادة ${_shortDoctorName(profile?.doctorName)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 22),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: d.logoGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: d.navActiveShadow,
            ),
            // نفس علامة التطبيق في شاشة الإقلاع (splash_screen.dart) بالضبط،
            // لا أيقونة جديدة -- الكانفاس يرسم ضِرساً في SVG، والتطبيق ليس
            // فيه أصل صورة للشعار، فالعلامة الموحّدة أقلّ الشرّين.
            child: Icon(Icons.medical_services_rounded, size: 22, color: d.onLogo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.kufi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: d.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'لوحة تحكم العيادة الرقمية',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(fontSize: 11, color: d.brandSubtitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _doctorCard(BuildContext context) {
    final d = context.desktop;
    final name = (profile?.doctorName ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: d.sidebarHover,
        borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusDoctorCard),
        border: Border.all(color: d.sidebarBorder),
      ),
      child: Row(
        children: [
          DesktopAvatar(profile: profile, size: 38, radius: 12, fontSize: 13),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '—' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: d.textPrimary,
                  ),
                ),
                if (profile != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: d.tierBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      ClinicTier.badgeLabel(profile!.tier),
                      style: AppType.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: d.tierFg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _CardIconButton(
            icon: Icons.support_agent_outlined,
            label: 'تواصل مع المطور',
            hoverColor: context.desktop.linkFg,
            onTap: onContactDeveloper,
          ),
          const SizedBox(width: 2),
          _CardIconButton(
            icon: Icons.logout,
            label: 'تسجيل الخروج',
            hoverColor: context.desktop.badgeDot,
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

/// زر أيقونة صغير في بطاقة الطبيب (الخروج، تواصل مع المطور). أيقونة وحدها
/// مع [Semantics] وتلميح يقرأ الوظيفة، ولونها يظهر عند المرور فقط -- وجود
/// أحمر دائم أسفل الشريط الجانبي يسحب العين بلا داعٍ.
class _CardIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color hoverColor;
  final VoidCallback onTap;

  const _CardIconButton({
    required this.icon,
    required this.label,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  State<_CardIconButton> createState() => _CardIconButtonState();
}

class _CardIconButtonState extends State<_CardIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.label,
        child: Semantics(
          label: widget.label,
          button: true,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovered
                    ? widget.hoverColor.withValues(alpha: .12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 17,
                color: _hovered ? widget.hoverColor : d.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رابط واحد في الشريط الجانبي. النشط كبسولة ممتلئة بسلّم التمييز ونصّ
/// أبيض في الوضعين؛ الساكن شفّاف يضيء عند مرور المؤشّر.
class _SideLink extends StatefulWidget {
  final DesktopDestination destination;
  final bool isActive;
  final VoidCallback onTap;

  const _SideLink({
    required this.destination,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SideLink> createState() => _SideLinkState();
}

class _SideLinkState extends State<_SideLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final active = widget.isActive;
    final dest = widget.destination;
    return Semantics(
      selected: active,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          // طبقتان لا طبقة واحدة متحرّكة: كانت AnimatedContainer تمزج
          // BoxDecoration بين «لون مرور» و«تدرّج + ظلّ» عند كل مرور ونقرة،
          // ومزج التدرّج بلا تدرّج يرسم إطاراً وسيطاً شاذّاً (وميض/قفزة).
          // الآن التدرّج والظلّ ثابتان على الطبقة الخارجية، ولا يتحرّك إلا
          // لون المرور الشفّاف على الداخلية.
          child: Container(
            decoration: active
                ? BoxDecoration(
                    gradient: d.navActiveGradient,
                    borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusNavItem),
                    boxShadow: d.navActiveShadow,
                  )
                : null,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: !active && _hovered ? d.sidebarHover : d.sidebarHover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusNavItem),
            ),
            child: Row(
              children: [
                Icon(
                  active ? dest.activeIcon : dest.icon,
                  size: 20,
                  color: active ? d.onNavActive : d.navInactiveFg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dest.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: active ? d.onNavActive : d.navInactiveFg,
                    ),
                  ),
                ),
                if (dest.badgeCount > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: d.badgeDot,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${dest.badgeCount}',
                      textAlign: TextAlign.center,
                      style: AppType.kufi(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// ── الترويسة العلوية ──────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String? statusPrefix;
  final bool? clinicOpen;
  final DoctorProfile? profile;
  final int notificationCount;
  final VoidCallback? onNotificationsTap;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;

  const _TopBar({
    required this.title,
    required this.statusPrefix,
    required this.clinicOpen,
    required this.profile,
    required this.notificationCount,
    required this.onNotificationsTap,
    required this.onSearchChanged,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final name = (profile?.doctorName ?? '').trim();
    return Container(
      height: AppDesktopMetrics.topBarHeight,
      padding: AppDesktopMetrics.topBarPadding,
      decoration: BoxDecoration(
        border: BorderDirectional(bottom: BorderSide(color: d.topBarBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.kufi(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: d.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Builder(builder: (context) {
                      // مغلقة = نقطة رمادية بلا هالة: الهالة النابضة تعني
                      // «حيّ الآن»، فإبقاؤها على عيادة مغلقة يناقض النص
                      // بجانبها.
                      final closed = clinicOpen == false;
                      return Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: closed ? d.textMuted : d.liveDot,
                          shape: BoxShape.circle,
                          boxShadow: closed
                              ? null
                              : [
                                  BoxShadow(
                                    color: d.liveDotHalo,
                                    blurRadius: d.isDark ? 10 : 0,
                                    spreadRadius: d.isDark ? 0 : 3,
                                  ),
                                ],
                        ),
                      );
                    }),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusPrefix == null
                            ? desktopArabicDateLine(DateTime.now())
                            : '$statusPrefix — ${desktopArabicDateLine(DateTime.now())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: 12, color: d.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // حقل البحث يُعرَض فقط عندما يكون موصولاً فعلاً بشيء. حقل بحث
          // معطّل أو لا يفلتر شيئاً أسوأ من غيابه: الطبيب يكتب فيه ويظنّ أن
          // النظام لا يجد المريض. يُوصَل مع شاشة المرضى في دفعة (ج).
          if (onSearchChanged != null) ...[
            _searchField(context),
            const SizedBox(width: 14),
          ],
          _NotificationButton(
            count: notificationCount,
            onTap: onNotificationsTap,
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsetsDirectional.only(start: 12),
            decoration: BoxDecoration(
              border: BorderDirectional(start: BorderSide(color: d.topBarBorder)),
            ),
            child: Row(
              children: [
                DesktopAvatar(profile: profile, size: 36, radius: 11, fontSize: 12.5),
                const SizedBox(width: 10),
                Text(
                  name.isEmpty ? '—' : name,
                  style: AppType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: d.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final d = context.desktop;
    return SizedBox(
      width: AppDesktopMetrics.searchWidth,
      height: AppDesktopMetrics.controlHeight,
      child: TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        style: AppType.sans(fontSize: 13, color: d.fieldFg),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          hintText: 'بحث عن مريض أو موعد...',
          hintStyle: AppType.sans(fontSize: 13, color: d.fieldHint),
          filled: true,
          fillColor: d.fieldBg,
          prefixIcon: Icon(Icons.search, size: 17, color: d.fieldHint),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusField),
            borderSide: BorderSide(color: d.fieldBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusField),
            borderSide: BorderSide(color: d.fieldBorder),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusField),
            borderSide: BorderSide(color: d.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusField),
            borderSide: BorderSide(color: d.linkFg, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// زر الإشعارات المربّع مع نقطته الحمراء. الحلقة حول النقطة بلون السطح
/// تحتها ([AppDesktop.badgeDotRing]) لا بأبيض ثابت، وإلا صارت حلقة بيضاء
/// على سطح ‎#07061A ليلاً.
class _NotificationButton extends StatefulWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationButton({required this.count, required this.onTap});

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final side = AppDesktopMetrics.controlHeight;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: _hovered ? d.iconBtnHover : d.iconBtnBg,
                borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusField),
                border: Border.all(color: d.iconBtnBorder),
              ),
              child: Semantics(
                label: 'الإشعارات',
                button: true,
                child: Icon(Icons.notifications_outlined, size: 18, color: d.iconBtnFg),
              ),
            ),
            if (widget.count > 0)
              Positioned(
                top: 8,
                left: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: d.badgeDot,
                    shape: BoxShape.circle,
                    border: Border.all(color: d.badgeDotRing, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ── الصورة الرمزية ────────────────────────────────────────────────────────

/// مربّع مستدير الأركان بصورة الطبيب الحقيقية إن وُجدت، وإلا الأحرف الأولى
/// على سلّم البنفسجي. مقاس مستدير الأركان لا دائرة -- هذا ما في الكانفاس،
/// ويختلف عن [InitialsAvatar] الدائرية المستعملة في شاشات الجوال.
class DesktopAvatar extends StatelessWidget {
  final DoctorProfile? profile;
  final double size;
  final double radius;
  final double fontSize;

  const DesktopAvatar({
    super.key,
    required this.profile,
    required this.size,
    required this.radius,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final url = profile?.avatarUrl;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: d.avatarGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        _initials(profile?.doctorName),
        style: AppType.kufi(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        '${AppConfig.apiBaseUrl}$url',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

/// «د. فارس حلاوي» ← «ف.ح». يتجاهل لقب «د.» حتى لا تصير الأحرف «د.ف».
String _initials(String? fullName) {
  final words = _nameWords(fullName);
  if (words.isEmpty) return 'ط';
  if (words.length == 1) return words.first.substring(0, 1);
  return '${words[0].substring(0, 1)}.${words[1].substring(0, 1)}';
}

/// «د. فارس حلاوي» ← «حلاوي» (آخر كلمة)، لسطر «عيادة د. حلاوي».
String _shortDoctorName(String? fullName) {
  final words = _nameWords(fullName);
  if (words.isEmpty) return 'الطبيب';
  return words.last;
}

/// كلمات الاسم بلا الألقاب الشائعة ولا الفراغات الزائدة.
List<String> _nameWords(String? fullName) {
  const honorifics = {'د', 'د.', 'دكتور', 'الدكتور', 'دكتورة', 'الدكتورة'};
  return (fullName ?? '')
      .split(RegExp(r'\s+'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty && !honorifics.contains(w))
      .toList();
}
