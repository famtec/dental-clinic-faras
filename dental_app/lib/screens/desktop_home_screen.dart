import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/clinic_doctor.dart';
import '../models/finance_summary.dart';
import '../models/finance_transaction.dart';
import '../models/patient_stats.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/clinic_doctor_colors.dart';
import '../widgets/desktop_shell.dart';
import '../widgets/desktop_widgets.dart';

/// لوحة التحكم — صفحة «الرئيسية» في غلاف سطح المكتب (2026-09-22)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من لوحة الكانفاس، لا إحياءً لـ `dashboard_screen.dart` (تلك سابقة
/// لنظام «الليل النيلي» ولم تُهاجَر إليه). تظهر فوق
/// [AppDesktopMetrics.breakpoint] وحدها، فكل ألوانها من `context.desktop`.
///
/// **لا رقم على هذه الشاشة محسوب تقديرياً.** الكانفاس يعرض بطاقة «مرضى جدد
/// هذا الأسبوع»، و[Patient] لا يحمل تاريخ إنشاء إطلاقاً (لا في النموذج ولا
/// في استجابة الخادم)، فاستبدلتها بـ«إجمالي المرضى» من
/// `GET /api/patients/stats` — رقم حقيقي بدل رقم مُختلَق. وكل فرق «عن أمس»
/// محسوب من طلب فعلي ليوم أمس، ويختفي الشريط كلياً حين لا يكون للفرق مصدر.
class DesktopHomeScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  /// اسم الطبيب لسطر الترحيب. يأتي جاهزاً من `HomeScreen` (حمّله للشريط
  /// الجانبي أصلاً) فلا يُطلَب الملف مرّتين.
  final String? doctorName;

  /// «عرض الكل ←» وصفّ الجدول وزرّ «حجز موعد جديد». الأخير يمرّر
  /// `openSheet: true` فتفتح صفحة المواعيد نموذج الإضافة فوراً.
  final void Function({bool openSheet}) onOpenAppointments;

  /// «التفاصيل ←» فوق قائمة آخر الحركات.
  final VoidCallback onOpenFinance;

  const DesktopHomeScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
    required this.doctorName,
    required this.onOpenAppointments,
    required this.onOpenFinance,
  });

  @override
  State<DesktopHomeScreen> createState() => DesktopHomeScreenState();
}

class DesktopHomeScreenState extends State<DesktopHomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<Appointment> _todayAppointments = const [];
  List<ClinicDoctor> _clinicDoctors = const [];
  List<FinanceTransaction> _moves = const [];
  PatientStats? _stats;
  FinanceSummary? _today;
  FinanceSummary? _yesterday;

  /// عدد مواعيد أمس — لفرق بطاقة «مواعيد اليوم». null = تعذّر حسابه.
  int? _yesterdayAppointmentCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// يُستدعى من الخارج بعد أي تغيير قد ينعكس على الأرقام (إشعار حجز جديد
  /// مثلاً)، تماماً كـ `refresh()` في بقية الشاشات.
  Future<void> refresh() => _load();

  /// لحظة اكتمال آخر تحميل ناجح. null = لم يكتمل أي تحميل بعد.
  DateTime? _loadedAt;

  /// عتبة «قديم». العودة إلى لوحة التحكم بعد قبول موعد أو تسجيل دفعة يجب أن
  /// تُظهر الأثر، لكن التنقّل ذهاباً وإياباً بين الصفحات لا يجوز أن يُشعل ستة
  /// طلبات في كل نقرة -- خادم Render المجاني يستيقظ من نوم بارد.
  static const Duration _staleAfter = Duration(seconds: 90);

  /// يُعيد التحميل إن تجاوزت البيانات [_staleAfter]، وإلا لا يفعل شيئاً.
  /// يستدعيها الغلاف عند كل عودة إلى صفحة «الرئيسية».
  void refreshIfStale() {
    if (_isLoading) return;
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) < _staleAfter) return;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // الطلبات متوازية: سبعة طلبات متتابعة كانت ستُبقي اللوحة فارغة ثوانيَ
    // على اتصال بطيء. كل طلب ثانوي ملفوف بـ catch خاص به فيسقط وحده:
    // عيادة Premium عادية ترجع 403 على /api/clinic-doctors، ومسار
    // /api/finance/transactions يرجع 404 على خادم لم يُنشر بعد — كلاهما
    // حالة طبيعية لا خطأ يُعطَّل له نصف اللوحة.
    try {
      final results = await Future.wait([
        widget.apiService.fetchAppointments(),
        widget.apiService.fetchPatientStats(),
        widget.apiService
            .fetchFinanceSummary(year: now.year, month: now.month, day: now.day),
        _quiet(() => widget.apiService.fetchFinanceSummary(
            year: yesterday.year, month: yesterday.month, day: yesterday.day)),
        _quiet(() => widget.apiService.fetchFinanceTransactions(
            year: now.year, month: now.month, limit: 5)),
        _quiet(() => widget.apiService.fetchClinicDoctors()),
      ]);

      if (!mounted) return;

      final appointments = results[0] as List<Appointment>;
      final normal = appointments
          .where((a) => a.status.toLowerCase() != 'pending_confirmation')
          .toList();

      setState(() {
        _todayAppointments = _onDay(normal, now)
          ..sort((a, b) => (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0));
        _yesterdayAppointmentCount = _onDay(normal, yesterday).length;
        _stats = results[1] as PatientStats;
        _today = results[2] as FinanceSummary;
        _yesterday = results[3] as FinanceSummary?;
        _moves = (results[4] as List<FinanceTransaction>?) ?? const [];
        _clinicDoctors = (results[5] as List<ClinicDoctor>?) ?? const [];
        _loadedAt = DateTime.now();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل لوحة التحكم. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  /// يحوّل فشل طلب ثانوي إلى null بدل أن يُسقط `Future.wait` كلها.
  Future<T?> _quiet<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (_) {
      return null;
    }
  }

  List<Appointment> _onDay(List<Appointment> source, DateTime day) {
    return source.where((a) {
      final date = a.appointmentDate;
      if (date == null) return false;
      return date.year == day.year && date.month == day.month && date.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (_errorMessage != null) {
      return DesktopErrorState(message: _errorMessage!, onRetry: _load);
    }

    return SingleChildScrollView(
      padding: AppDesktopMetrics.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _welcomeRow(context),
          const SizedBox(height: AppDesktopMetrics.gapSection),
          _statCards(context),
          const SizedBox(height: AppDesktopMetrics.gapSection),
          // ارتفاع ثابت للصفّ السفلي: الجدول واللوحتان بجانبه يجب أن تنتهي
          // حوافها عند سطر واحد، وإلا بدت البطاقتان اليمنى واليسرى معلّقتين
          // بلا محاذاة. 430 يسع سبعة صفوف مواعيد بلا تمرير داخلي.
          SizedBox(
            height: 430,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 18, child: _todayTable(context)),
                const SizedBox(width: AppDesktopMetrics.gapPanel),
                Expanded(
                  flex: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _doctorsToday(context),
                      const SizedBox(height: AppDesktopMetrics.gapStat),
                      Expanded(child: _latestMoves(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── سطر الترحيب ─────────────────────────────────────────────────────────

  Widget _welcomeRow(BuildContext context) {
    final d = context.desktop;
    final name = (widget.doctorName ?? '').trim();
    final firstName = name.isEmpty
        ? ''
        : (name
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty && w != 'د.' && w != 'د')
                .toList()
              ..add(''))
            .first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName.isEmpty ? 'أهلاً بعودتك' : 'أهلاً بعودتك، د. $firstName',
                style: AppType.kufi(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: d.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'هذا ملخّص سريع عن يومك في العيادة',
                style: AppType.sans(fontSize: 13, color: d.textSecondary),
              ),
            ],
          ),
        ),
        DesktopCtaButton(
          icon: Icons.add,
          label: 'حجز موعد جديد',
          onTap: () => widget.onOpenAppointments(openSheet: true),
        ),
      ],
    );
  }

  // ── بطاقات الإحصاء ──────────────────────────────────────────────────────

  Widget _statCards(BuildContext context) {
    final stats = _stats;
    final todayCount = _todayAppointments.length;
    final yesterdayCount = _yesterdayAppointmentCount;

    String? apptDelta;
    if (yesterdayCount != null) {
      final diff = todayCount - yesterdayCount;
      apptDelta = diff == 0
          ? 'كأمس'
          : '${diff > 0 ? '+' : '−'}${diff.abs()} عن أمس';
    }

    final todayIncome = _today?.totalIncome;
    String? incomeDelta;
    final yesterdayIncome = _yesterday?.totalIncome;
    if (todayIncome != null && yesterdayIncome != null) {
      final diff = todayIncome - yesterdayIncome;
      incomeDelta = diff == 0
          ? 'كأمس'
          : '${diff > 0 ? '▲' : '▼'} ${desktopMoney.format(diff.abs())}';
    }

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.calendar_today_outlined,
            value: '$todayCount',
            label: 'موعد اليوم',
            delta: apptDelta,
            deltaPositive: yesterdayCount == null || todayCount >= yesterdayCount,
          ),
        ),
        const SizedBox(width: AppDesktopMetrics.gapStat),
        Expanded(
          child: _StatCard(
            icon: Icons.people_outline,
            value: stats == null ? '—' : desktopMoney.format(stats.totalPatients),
            // الكانفاس يقول «مرضى جدد هذا الأسبوع»، والخادم لا يُرجع تاريخ
            // تسجيل المريض فلا سبيل لحسابه بصدق. الرقم هنا هو ما تعنيه
            // بطاقة «إجمالي المرضى» في index.html بالموقع حرفياً.
            label: 'إجمالي المرضى',
          ),
        ),
        const SizedBox(width: AppDesktopMetrics.gapStat),
        Expanded(
          child: _StatCard(
            icon: Icons.payments_outlined,
            value: todayIncome == null ? '—' : desktopMoney.format(todayIncome),
            label: 'إيرادات اليوم (ل.س)',
            delta: incomeDelta,
            deltaPositive:
                yesterdayIncome == null || (todayIncome ?? 0) >= yesterdayIncome,
          ),
        ),
        const SizedBox(width: AppDesktopMetrics.gapStat),
        Expanded(
          child: _StatCard(
            icon: Icons.account_balance_wallet_outlined,
            value: stats == null ? '—' : desktopMoney.format(stats.pendingBalances),
            label: 'مستحقات معلّقة (ل.س)',
            warn: true,
          ),
        ),
      ],
    );
  }

  // ── جدول مواعيد اليوم ───────────────────────────────────────────────────

  Widget _todayTable(BuildContext context) {
    final rows = _todayAppointments;
    final multiDoctor = _clinicDoctors.isNotEmpty;

    return DesktopPanel(
      title: 'مواعيد اليوم',
      actionLabel: 'عرض الكل ←',
      onAction: () => widget.onOpenAppointments(),
      child: rows.isEmpty
          ? DesktopEmptyHint(
              icon: Icons.event_available_outlined,
              text: 'لا توجد مواعيد اليوم',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tableHeader(context, multiDoctor),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _AppointmentRow(
                      appointment: rows[i],
                      isLast: i == rows.length - 1,
                      showDoctor: multiDoctor,
                      doctorColor: multiDoctor
                          ? clinicDoctorColor(rows[i].clinicDoctorId, _clinicDoctors)
                          : null,
                      onTap: () => widget.onOpenAppointments(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tableHeader(BuildContext context, bool multiDoctor) {
    final d = context.desktop;
    Widget cell(String text, int flex) => Expanded(
          flex: flex,
          child: Text(
            text,
            style: AppType.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: d.tableHeaderFg,
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: d.rowDivider)),
      ),
      child: Row(
        children: [
          cell('الوقت', 16),
          cell('المريض', 26),
          if (multiDoctor) cell('الطبيب', 24),
          cell('نوع الموعد', 22),
          cell('الحالة', 18),
        ],
      ),
    );
  }

  // ── الأطباء اليوم ───────────────────────────────────────────────────────

  Widget _doctorsToday(BuildContext context) {
    final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;

    // صاحب الحساب أولاً دائماً (مواعيده هي التي clinic_doctor_id فيها NULL)،
    // ثم الأطباء المساعدون المفعّلون. عيادة الطبيب الواحد تعرض صفّاً واحداً
    // بدل أن تختفي اللوحة: «كم بقي لي اليوم» سؤال وجيه لطبيب وحده أيضاً.
    final entries = <({int? id, String name})>[
      (id: null, name: widget.doctorName?.trim().isNotEmpty == true
          ? widget.doctorName!.trim()
          : 'أنا'),
      for (final doctor in _clinicDoctors.where((x) => x.isActive))
        (id: doctor.id, name: doctor.fullName),
    ];

    return DesktopPanel(
      title: 'الأطباء اليوم',
      shrink: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            _DoctorRow(
              name: entry.name,
              color: clinicDoctorColor(entry.id, _clinicDoctors),
              status: _doctorStatus(entry.id, nowMinutes),
              inSession: _inSession(entry.id, nowMinutes),
            ),
        ],
      ),
    );
  }

  bool _inSession(int? doctorId, int nowMinutes) {
    return _todayAppointments.any((a) {
      if (a.clinicDoctorId != doctorId) return false;
      final start = a.startMinutes;
      final end = a.endMinutes;
      if (start == null || end == null) return false;
      return nowMinutes >= start && nowMinutes < end;
    });
  }

  String _doctorStatus(int? doctorId, int nowMinutes) {
    if (_inSession(doctorId, nowMinutes)) return 'في جلسة الآن';
    final remaining = _todayAppointments
        .where((a) => a.clinicDoctorId == doctorId && (a.startMinutes ?? 0) > nowMinutes)
        .length;
    if (remaining == 0) return 'لا مواعيد متبقية';
    if (remaining == 1) return 'موعد واحد متبقٍّ';
    if (remaining == 2) return 'موعدان متبقيان';
    return '$remaining مواعيد متبقية';
  }

  // ── آخر الحركات المالية ─────────────────────────────────────────────────

  Widget _latestMoves(BuildContext context) {
    return DesktopPanel(
      title: 'آخر الحركات المالية',
      actionLabel: 'التفاصيل ←',
      onAction: widget.onOpenFinance,
      child: _moves.isEmpty
          ? DesktopEmptyHint(
              icon: Icons.receipt_long_outlined,
              text: 'لا توجد حركات في هذا الشهر',
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _moves.length,
              itemBuilder: (context, i) => _MoveRow(
                move: _moves[i],
                isLast: i == _moves.length - 1,
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// المكوّنات
// ═══════════════════════════════════════════════════════════════════════════

/// بطاقة إحصاء واحدة. [delta] شريط الفرق أعلى اليسار — **يختفي كلياً حين لا
/// يوجد له مصدر** بدل أن يعرض صفراً أو «—»: شريط فارغ يوحي بأن الرقم ثابت.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? delta;
  final bool deltaPositive;
  final bool warn;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.delta,
    this.deltaPositive = true,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final boxBg = warn ? d.warnBoxBg : d.iconBoxBg;
    final boxBorder = warn ? d.warnBoxBorder : d.iconBoxBorder;
    final boxFg = warn ? d.warnBoxFg : d.iconBoxFg;
    final glow = d.bigNumberGlow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: d.cardBg,
        gradient: d.cardGradient,
        borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusCard),
        border: Border.all(color: d.cardBorder),
        boxShadow: d.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: boxBg,
                  borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusIconBox),
                  border: Border.all(color: boxBorder),
                ),
                child: Icon(icon, size: 17, color: boxFg),
              ),
              const Spacer(),
              if (delta != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: deltaPositive ? d.pillDoneBg : d.pillWaitingBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delta!,
                    style: AppType.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: deltaPositive ? d.pillDoneFg : d.pillWaitingFg,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.kufi(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: d.bigNumber,
            ).copyWith(
              shadows: glow == null
                  ? null
                  : [Shadow(color: glow, blurRadius: 32)],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// صفّ موعد في جدول اليوم.
class _AppointmentRow extends StatefulWidget {
  final Appointment appointment;
  final bool isLast;
  final bool showDoctor;
  final Color? doctorColor;
  final VoidCallback onTap;

  const _AppointmentRow({
    required this.appointment,
    required this.isLast,
    required this.showDoctor,
    required this.doctorColor,
    required this.onTap,
  });

  @override
  State<_AppointmentRow> createState() => _AppointmentRowState();
}

class _AppointmentRowState extends State<_AppointmentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final a = widget.appointment;
    final statusPill = desktopStatusPill(context, a.status);

    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);
    Widget text(String value, {bool strong = false, Color? color}) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(
            fontSize: 13,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            color: color ?? d.textPrimary,
          ),
        );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          decoration: BoxDecoration(
            color: _hovered ? d.rowHover : Colors.transparent,
            border: widget.isLast
                ? null
                : Border(bottom: BorderSide(color: d.rowDivider)),
          ),
          child: Row(
            children: [
              cell(16, text(desktopClockLabel(a.startMinutes), strong: true)),
              cell(26, text(a.patientName)),
              if (widget.showDoctor)
                cell(
                  24,
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsetsDirectional.only(end: 7),
                        decoration: BoxDecoration(
                          color: widget.doctorColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: text(
                          a.clinicDoctorName ?? 'أنا',
                          color: d.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              cell(22, text(a.procedureType, color: d.textSecondary)),
              cell(
                18,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: statusPill,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفّ طبيب في لوحة «الأطباء اليوم».
class _DoctorRow extends StatelessWidget {
  final String name;
  final Color color;
  final String status;
  final bool inSession;

  const _DoctorRow({
    required this.name,
    required this.color,
    required this.status,
    required this.inSession,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusIconBox),
                ),
                child: Text(
                  desktopInitials(name),
                  style: AppType.kufi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: -2,
                start: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: inSession ? d.statusBusy : d.statusOnline,
                    shape: BoxShape.circle,
                    border: Border.all(color: d.cardBg, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: d.textPrimary,
                  ),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(fontSize: 11.5, color: d.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صفّ حركة مالية.
class _MoveRow extends StatelessWidget {
  final FinanceTransaction move;
  final bool isLast;

  const _MoveRow({required this.move, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final income = move.isIncome;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: d.rowDivider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  move.description.trim().isEmpty ? '—' : move.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: d.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _moveDateLabel(move.createdAt),
                  style: AppType.sans(fontSize: 11, color: d.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${income ? '+' : '−'}${desktopMoney.format(move.amount.abs())}',
            style: AppType.kufi(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: income ? d.amountIn : d.amountOut,
            ),
          ),
        ],
      ),
    );
  }
}

/// «اليوم، 09:20 ص» / «أمس، 06:10 م» / «22 سبتمبر، 06:10 م».
String _moveDateLabel(DateTime? date) {
  if (date == null) return '—';
  final now = DateTime.now();
  final local = date.toLocal();
  final time = desktopClockLabel(local.hour * 60 + local.minute);
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(local, now)) return 'اليوم، $time';
  if (sameDay(local, now.subtract(const Duration(days: 1)))) return 'أمس، $time';
  return '${desktopArabicDateLine(local).split('، ').last}، $time';
}

