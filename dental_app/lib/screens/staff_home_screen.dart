import 'package:flutter/material.dart';

import '../models/clinic_doctor.dart';
import '../models/doctor_profile.dart';
import '../models/pending_payment.dart';
import '../services/api_service.dart';
import '../services/app_session.dart';
import '../services/appointment_reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_shell.dart';
import '../widgets/finance_review_panel.dart';
import 'clinic_doctors_screen.dart';
import 'contact_developer_screen.dart';
import 'more_menu_screen.dart';
import 'patients_list_screen.dart';
import 'today_schedule_screen.dart';

/// الشاشة الرئيسية للطبيب المساعد (2026-09-25)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// شاشة مستقلة لا فرعاً داخل HomeScreen: شاشة المالك تربط ثماني صفحات
/// بفهارس متقابلة بين الجوال وسطح المكتب، وحشو شروط الدور فيها كان سيجعل
/// أي خطأ يفتح للمساعد صفحة مالية لا يملك صلاحيتها. هنا ثلاث صفحات فقط:
/// مرضاه، مواعيده، كشف حسابه -- وإعدادات شخصية (الوضع الليلي، التذكير،
/// الخروج). الخادم يفرض الصلاحيات نفسها على أي حال (StaffAccessMiddleware).
class StaffHomeScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLogout;
  final GlobalKey<PatientsListScreenState> patientsKey;
  final GlobalKey<TodayScheduleScreenState> todayScheduleKey;

  const StaffHomeScreen({
    super.key,
    required this.apiService,
    required this.onLogout,
    required this.patientsKey,
    required this.todayScheduleKey,
  });

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  int _index = 0;
  bool _settingsSelected = false;
  DoctorProfile? _profile;
  final TextEditingController _searchController = TextEditingController();
  late final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    widget.apiService.fetchProfile().then((profile) {
      if (mounted) setState(() => _profile = profile);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index == _index && !_settingsSelected) return;
    setState(() {
      _index = index;
      _settingsSelected = false;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(index,
          duration: const Duration(milliseconds: 320), curve: Curves.easeInOutCubic);
    }
  }

  Widget get _patients => PatientsListScreen(
        key: widget.patientsKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  Widget get _appointments => TodayScheduleScreen(
        key: widget.todayScheduleKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  Widget get _statement => StaffStatementPage(
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppDesktopMetrics.breakpoint
        ? _buildDesktop(context)
        : _buildMobile();
  }

  Widget _buildDesktop(BuildContext context) {
    final pages = [_patients, _appointments, _statement, StaffMorePage(onLogout: widget.onLogout, embedded: true)];
    return Scaffold(
      body: DesktopShell(
        destinations: const [
          DesktopDestination(icon: Icons.people_outline, activeIcon: Icons.people, label: 'مرضاي'),
          DesktopDestination(
              icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'مواعيدي'),
          DesktopDestination(
              icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'كشف حسابي'),
        ],
        currentIndex: _settingsSelected ? -1 : _index,
        onSelect: _goTo,
        settingsSelected: _settingsSelected,
        onSettingsTap: () => setState(() => _settingsSelected = true),
        profile: _profile,
        onLogout: widget.onLogout,
        onContactDeveloper: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ContactDeveloperScreen()),
        ),
        searchController: _searchController,
        onSearchChanged: (query) {
          if (_index != 0 || _settingsSelected) _goTo(0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.patientsKey.currentState?.applyExternalSearch(query);
          });
        },
        child: IndexedStack(index: _settingsSelected ? 3 : _index, children: pages),
      ),
    );
  }

  Widget _buildMobile() {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _KeepAlive(child: _patients),
          _KeepAlive(child: _appointments),
          _KeepAlive(child: _statement),
          StaffMorePage(onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: GlassBottomNav(
        currentIndex: _index,
        onTap: _goTo,
        items: const [
          GlassNavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'مرضاي'),
          GlassNavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'مواعيدي'),
          GlassNavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'كشفي'),
          GlassNavItem(icon: Icons.more_horiz, activeIcon: Icons.more_horiz, label: 'المزيد'),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// «كشف حسابي» -- نفس شاشة كشف الحساب التي يفتحها المالك لكل طبيب، للقراءة
/// فقط (بلا حذف تسويات) ومحصورة بحساب الطبيب نفسه (الخادم يرفض غيره).
class StaffStatementPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const StaffStatementPage({super.key, required this.apiService, required this.onSessionExpired});

  @override
  State<StaffStatementPage> createState() => _StaffStatementPageState();
}

class _StaffStatementPageState extends State<StaffStatementPage> {
  bool _allTime = false;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final doctorId = session.staffDoctorId.value;
    final surf = context.surface;
    final desktop = context.isDesktopShell;
    if (doctorId == null) return const SizedBox.shrink();
    final doctor = ClinicDoctor(id: doctorId, fullName: session.staffName ?? 'حسابي');
    final chips = Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 32 : 20, desktop ? 20 : 8, desktop ? 32 : 20, 0),
      child: Row(
        children: [
          Text('كشف حسابي',
              style: AppType.kufi(fontSize: 17, fontWeight: FontWeight.w700, color: surf.textPrimary)),
          const Spacer(),
          FilterChipsBar(
            labels: const ['هذا الشهر', 'كل الوقت'],
            selectedIndex: _allTime ? 1 : 0,
            onSelect: (i) => setState(() => _allTime = i == 1),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: desktop ? Colors.transparent : null,
      body: AtmosphereBackground(
        child: Column(
          children: [
            if (!desktop) const ClinicTopBar(),
            chips,
            _StaffSubmissionsStrip(
              key: ValueKey('subs-$_allTime'),
              apiService: widget.apiService,
              onSessionExpired: widget.onSessionExpired,
            ),
            Expanded(
              child: DoctorStatementScreen(
                key: ValueKey(_allTime),
                apiService: widget.apiService,
                doctor: doctor,
                allTime: _allTime,
                periodLabel: _allTime ? 'كل الوقت' : 'هذا الشهر',
                onSessionExpired: widget.onSessionExpired,
                onPayoutsChanged: () {},
                readOnly: true,
                embedded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «المزيد» للطبيب المساعد: هويته وعيادته، الوضع الليلي، تذكير المواعيد،
/// التواصل مع المطور، والخروج. لا حساب ولا اشتراك ولا إعدادات عيادة -- تلك
/// للمالك.
class StaffMorePage extends StatelessWidget {
  final VoidCallback onLogout;

  /// داخل غلاف سطح المكتب: بلا ترويسة الجوال ولا حشوة الشريط العائم.
  final bool embedded;

  const StaffMorePage({super.key, required this.onLogout, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final name = AppSession.instance.staffName ?? '';
    final content = Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, embedded ? 24 : floatingNavInset(context) + 84),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: surf.accentGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.badge_outlined, color: surf.onAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'طبيب مساعد' : name,
                            style: AppType.kufi(
                                fontSize: 15, fontWeight: FontWeight.w700, color: surf.textPrimary)),
                        const SizedBox(height: 2),
                        Text('حساب طبيب مساعد — صلاحياتك يحدّدها الطبيب المدير',
                            style: TextStyle(fontSize: 11.5, color: surf.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const ThemeModeCard(),
            if (AppointmentReminderService.instance.isSupported) ...[
              const SizedBox(height: 12),
              const ReminderSettingsCard(),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactDeveloperScreen()),
              ),
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('تواصل مع المطور'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.rose500),
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
    if (embedded) {
      return SingleChildScrollView(child: Align(alignment: AlignmentDirectional.topStart, child: content));
    }
    return Scaffold(
      body: AtmosphereBackground(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [const ClinicTopBar(), content],
        ),
      ),
    );
  }
}

/// «دفعاتي المرسلة» (2026-09-25): ما أرسله الطبيب المساعد من مبالغ استلمها،
/// وحالة كل منها عند المدير. الكشف أدناه لا يحوي إلا المؤكَّد منها.
class _StaffSubmissionsStrip extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const _StaffSubmissionsStrip({super.key, required this.apiService, required this.onSessionExpired});

  @override
  State<_StaffSubmissionsStrip> createState() => _StaffSubmissionsStripState();
}

class _StaffSubmissionsStripState extends State<_StaffSubmissionsStrip> {
  List<PendingPayment> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.apiService.fetchPendingPayments(status: 'all');
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (e.isSessionExpired) widget.onSessionExpired();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final surf = context.surface;
    final desktop = context.isDesktopShell;
    final pending = _items.where((p) => p.isPending).toList();
    final pendingTotal = pending.fold<double>(0, (sum, p) => sum + p.amount);
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 32 : 20, 12, desktop ? 32 : 20, 0),
      child: Material(
        color: pending.isEmpty ? surf.iconBoxBg : surf.pillDueBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await showAppSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _StaffSubmissionsSheet(items: _items),
            );
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(pending.isEmpty ? Icons.receipt_long_outlined : Icons.hourglass_top_rounded,
                    size: 20, color: pending.isEmpty ? surf.iconBoxFg : surf.pillDueFg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pending.isEmpty
                        ? 'دفعاتي المرسلة — راجعها الطبيب المدير كلها'
                        : '${pending.length} دفعة (${formatGroupedMoney(pendingTotal)} ل.س) بانتظار تأكيد الطبيب المدير',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: surf.textPrimary),
                  ),
                ),
                Text('عرض', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: surf.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffSubmissionsSheet extends StatelessWidget {
  final List<PendingPayment> items;

  const _StaffSubmissionsSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      decoration: BoxDecoration(
        color: surf.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BottomSheetOnly(
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: surf.divider, borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('دفعاتي المرسلة',
                style: AppType.kufi(fontSize: 16, fontWeight: FontWeight.w700, color: surf.textPrimary)),
            const SizedBox(height: 4),
            Text('المؤكَّدة تدخل كشف حسابك بتاريخ استلامك لها. المرفوضة لا تُحسب.',
                style: TextStyle(fontSize: 12, color: surf.textSecondary)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(height: 16, color: surf.divider),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final (label, fg) = item.isPending
                      ? ('بانتظار التأكيد', surf.pillDueFg)
                      : item.isConfirmed
                          ? ('مؤكَّدة', surf.pillPaidFg)
                          : ('مرفوضة', AppColors.rose700text);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('${formatGroupedMoney(item.amount)} ل.س',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: surf.textPrimary)),
                          const Spacer(),
                          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.patientName ?? ''}${item.invoiceTitle != null ? ' — ${item.invoiceTitle}' : ''} · '
                        '${formatPendingDate(item.recordedAt)}',
                        style: TextStyle(fontSize: 11.5, color: surf.textSecondary),
                      ),
                      if (item.isRejected && item.reviewNote != null)
                        Text('السبب: ${item.reviewNote}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.rose700text)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

