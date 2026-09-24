import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../models/clinic_doctor.dart';
import '../models/doctor_statement.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/clinic_doctor_colors.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_widgets.dart';
import 'contact_developer_screen.dart';

part 'clinic_doctors_desktop.dart';

/// شاشة "الأطباء والنسب" -- نقل صفحة doctors.html إلى التطبيق، 2026-09-18.
///
/// الميزة محروسة بباقة العيادات (Premium Plus) في الخادم
/// (require_premium_doctor_user) فيرجع **403** لا 402. الشاشة لا تفحص الباقة
/// محلياً قبل النداء: تنادي وتُظهر بطاقة القفل عند 403 -- نفس نمط شاشة
/// المخزن، وهو النمط الصحيح لأن الباقة المخزّنة في الجهاز قد تكون قديمة
/// (طبيب رقّى باقته قبل دقيقة يجب أن يرى الميزة فوراً، لا بعد إعادة تسجيل
/// دخول).
///
/// الشاشة **متّصلة فقط ولا تعمل دون شبكة**: أرقام النسب والمستحقات محاسبة
/// تراكمية يحسبها الخادم من جدولي DoctorEarning و DoctorPayout، وعرض نسخة
/// مخزّنة منها كان سيُظهر رصيداً مستحقاً قديماً لطبيب سُدِّد له فعلاً --
/// وهو خطأ مالي لا مجرد بيانات قديمة. لهذا لا تمرّ عبر OfflineAwareApiService
/// ولا تكتب في local_db.

const List<String> _doctorsArabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// أرقام لاتينية بفواصل آلاف -- نفس toLocaleString('en-US') في الموقع.
/// الأرقام العربية-الهندية ممنوعة في هذا المشروع كله.
final NumberFormat _doctorsMoneyFormat = NumberFormat('#,##0', 'en_US');

String formatDoctorsMoney(double value) {
  if (!value.isFinite) return '0';
  return _doctorsMoneyFormat.format(value.round());
}

/// النسبة بلا كسور زائدة: 40 لا 40.00، و37.5 كما هي.
String formatDoctorsPercent(double value) {
  if (!value.isFinite) return '0';
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}

/// تاريخ قصير للحركات: 2026-09-18 بأرقام لاتينية.
String formatDoctorsDate(DateTime? value) {
  if (value == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

class ClinicDoctorsScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const ClinicDoctorsScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<ClinicDoctorsScreen> createState() => _ClinicDoctorsScreenState();
}

class _ClinicDoctorsScreenState extends State<ClinicDoctorsScreen> {
  List<ClinicDoctor>? _doctors;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPremiumLocked = false;

  // نفس تمثيل الفترة في شاشة المالية حرفياً: null/null + !allTime + !isToday
  // تعني "الشهر الحالي" (وهو سلوك الخادم الافتراضي)، فلا يُرسَل شيء.
  int? _selectedYear;
  int? _selectedMonth;
  bool _allTime = false;
  bool _isToday = false;

  // ── سطح المكتب (انظر clinic_doctors_desktop.dart) ──
  int? _selectedDoctorId;
  DoctorStatement? _statement;
  /// "معرّف الطبيب|الفترة" للكشف المحمّل أو قيد التحميل. null = يجب إعادة
  /// الطلب (تُصفَّر مع كل _load لأن أي تغيير في الأرقام يمسّ الكشف أيضاً).
  String? _statementKey;
  bool _statementLoading = false;
  String? _statementError;
  /// 0 = الكل، 1 = الاستحقاقات، 2 = التسويات.
  int _statementTab = 0;

  /// setState لامتداد سطح المكتب في ملف الـ part (setState محميّة).
  void _update(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isPremiumLocked = false;
      _statementKey = null;
    });
    final today = DateTime.now();
    try {
      final doctors = await widget.apiService.fetchClinicDoctorsDetailed(
        year: _isToday ? today.year : _selectedYear,
        month: _isToday ? today.month : _selectedMonth,
        day: _isToday ? today.day : null,
        allTime: _allTime,
      );
      if (!mounted) return;
      setState(() {
        _doctors = doctors;
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
        _isPremiumLocked = e.isPremiumRequired || e.isSubscriptionBlocked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل أطباء العيادة. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  void _selectPeriod({int? year, int? month, bool allTime = false, bool isToday = false}) {
    setState(() {
      _selectedYear = year;
      _selectedMonth = month;
      _allTime = allTime;
      _isToday = isToday;
    });
    _load();
  }

  String get _periodLabel {
    if (_allTime) return 'كل الفترات';
    if (_isToday) return 'اليوم';
    final now = DateTime.now();
    final year = _selectedYear ?? now.year;
    final month = _selectedMonth ?? now.month;
    return '${_doctorsArabicMonths[month - 1]} $year';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDoctorSheet({ClinicDoctor? doctor}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      constraints: context.isDesktopShell ? const BoxConstraints(maxWidth: 560) : null,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DoctorFormSheet(apiService: widget.apiService, doctor: doctor),
    );
    if (saved == true) {
      _toast(doctor == null ? 'تمت إضافة الطبيب' : 'تم تحديث بيانات الطبيب');
      _load();
    }
  }

  Future<void> _openPayoutSheet(ClinicDoctor doctor) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      constraints: context.isDesktopShell ? const BoxConstraints(maxWidth: 560) : null,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayoutSheet(apiService: widget.apiService, doctor: doctor),
    );
    if (saved == true) {
      _toast('تم تسجيل التسوية');
      _load();
    }
  }

  Future<void> _openStatement(ClinicDoctor doctor) async {
    final today = DateTime.now();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DoctorStatementScreen(
          apiService: widget.apiService,
          doctor: doctor,
          year: _isToday ? today.year : _selectedYear,
          month: _isToday ? today.month : _selectedMonth,
          day: _isToday ? today.day : null,
          allTime: _allTime,
          periodLabel: _periodLabel,
          onSessionExpired: widget.onSessionExpired,
          // التسويات تُحذف من داخل الكشف، والرصيد المستحق في البطاقة هنا
          // يتغيّر بذلك. نداء مباشر لا نتيجة راجعة من pop: النتيجة الراجعة
          // تحتاج اعتراض الزر الخلفي للنظام أيضاً، ونداء واحد يكفي.
          onPayoutsChanged: _load,
        ),
      ),
    );
  }

  Future<void> _toggleActive(ClinicDoctor doctor) async {
    try {
      await widget.apiService
          .updateClinicDoctor(doctor.id, isActive: !doctor.isActive);
      if (!mounted) return;
      _toast(doctor.isActive ? 'تم تعطيل الطبيب' : 'تم تفعيل الطبيب');
      _load();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } catch (_) {
      _toast('تعذر تغيير حالة الطبيب.');
    }
  }

  Future<void> _confirmDelete(ClinicDoctor doctor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surface.sheetBg,
        title: Text('حذف ${doctor.fullName}؟',
            style: AppType.kufi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.surface.textPrimary)),
        content: Text(
          'الطبيب الذي له سجل مالي لا يُحذف. الأفضل تعطيله: يختفي من قوائم '
          'اختيار الطبيب ويبقى كشف حسابه كاملاً.',
          style: TextStyle(color: context.surface.textSecondary, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('حذف', style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteClinicDoctor(doctor.id);
      if (!mounted) return;
      _toast('تم حذف الطبيب');
      _load();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      // رفض 400 ("له سجل مالي") ليس فشلاً عارضاً بل قرار الخادم، فتُعرَض
      // رسالته كما هي ومعها طريق الخروج الصحيح.
      _toast(e.message);
    } catch (_) {
      _toast('تعذر حذف الطبيب.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopShell) return _buildDesktop(context);
    final doctors = _doctors ?? const <ClinicDoctor>[];
    return Scaffold(
      body: Stack(
        children: [
          AtmosphereBackground(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const ClinicTopBar(),
                  const OfflineSyncBanner(),
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(20, 16, 20, floatingNavInset(context) + 84),
                    child: LoadingErrorEmpty(
                      isLoading: _isLoading,
                      errorMessage: _isPremiumLocked ? null : _errorMessage,
                      isLocked: false,
                      onRetry: _load,
                      child: _isPremiumLocked
                          ? _buildPremiumLockCard()
                          : _buildContent(doctors),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isPremiumLocked && !_isLoading && _errorMessage == null)
            PositionedDirectional(
              bottom: floatingNavInset(context) + 16,
              end: 20,
              child: GradientFab(onPressed: () => _openDoctorSheet()),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(List<ClinicDoctor> doctors) {
    final surf = context.surface;
    final collected =
        doctors.fold<double>(0, (sum, d) => sum + d.periodCollected);
    final doctorShare =
        doctors.fold<double>(0, (sum, d) => sum + d.periodDoctorShare);
    final clinicShare =
        doctors.fold<double>(0, (sum, d) => sum + d.periodClinicShare);
    final balanceDue = doctors.fold<double>(0, (sum, d) => sum + d.balanceDue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('أطباء العيادة والنسب',
                style: AppType.kufi(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: surf.textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: surf.chipBg,
                border: Border.all(color: surf.chipBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                doctors.length == 1 ? 'طبيب واحد' : '${doctors.length} أطباء',
                style: TextStyle(
                    color: surf.chipFg, fontWeight: FontWeight.w700, fontSize: 11.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'حدّد نسبة كل طبيب، وتابع ما حصّله وما استحقّه وما تبقّى له.',
          style: TextStyle(color: surf.textSecondary, fontSize: 12.5, height: 1.7),
        ),
        const SizedBox(height: 14),
        _buildPeriodSelector(),
        const SizedBox(height: 14),
        // ثلاثة أعمدة لا أربعة: SmartStatCard صفٌّ واحد بأعمدة متساوية، ورابعُها
        // على عرض الجوال يصير 80px فيتكسّر عنوانه ثلاثة أسطر. والمستحقات
        // أصلاً **تراكمية لا تتبع الفترة**، فوضعها بين أرقام الشهر يدعو
        // لقراءتها كرقم شهري -- شريطها المستقل أدناه أصدق وأوسع.
        SmartStatCard(stats: [
          SmartStat(
            value: formatDoctorsMoney(collected),
            label: 'المحصّل عبر الأطباء',
            icon: Icons.payments_outlined,
            iconColor: AppColors.indigo700,
            iconBackground: AppColors.indigo50,
          ),
          SmartStat(
            value: formatDoctorsMoney(doctorShare),
            label: 'حصص الأطباء',
            icon: Icons.groups_outlined,
            iconColor: AppColors.purple700,
            iconBackground: AppColors.purple50,
          ),
          SmartStat(
            value: formatDoctorsMoney(clinicShare),
            label: 'حصة العيادة',
            icon: Icons.local_hospital_outlined,
            iconColor: AppColors.emerald700text,
            iconBackground: AppColors.emerald50,
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: surf.pillDueBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: surf.pillDueBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: surf.pillDueFg),
              const SizedBox(width: 9),
              Expanded(
                child: Text('مستحقات غير مسدَّدة (تراكمي، لكل الأطباء)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: surf.pillDueFg)),
              ),
              Text('${formatDoctorsMoney(balanceDue)} ل.س',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: surf.pillDueFg)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'النسبة تُحسب على المبلغ المحصّل فعلياً من المريض، لا على قيمة '
          'الفاتورة. المستحقات تراكمية على كل الفترات ولا تتبع الشهر المعروض.',
          style: TextStyle(color: surf.textMuted, fontSize: 11.5, height: 1.8),
        ),
        const SizedBox(height: 14),
        if (doctorShare > 0) ...[
          _buildDistributionBar(doctors, doctorShare),
          const SizedBox(height: 14),
        ],
        if (doctors.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.groups_2_outlined, size: 44, color: surf.textMuted),
                  const SizedBox(height: 10),
                  Text('لا يوجد أطباء مسجّلون بعد',
                      style: TextStyle(color: surf.textSecondary)),
                  const SizedBox(height: 4),
                  Text('أضِف طبيباً لتبدأ بتوزيع النسب ومتابعة المستحقات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: surf.textMuted, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          ...doctors.map(_buildDoctorCard),
      ],
    );
  }

  /// لوحة المفاتيح الافتراضية في الجوال تغطّي القائمة المنسدلة الطويلة،
  /// ولذلك اخترنا DropdownButton (نفس شاشة المالية) لا حقل بحث.
  Widget _buildPeriodSelector() {
    final surf = context.surface;
    final now = DateTime.now();

    // 18 شهراً إلى الخلف كما في buildPeriodOptions() بالموقع: مسار الأطباء
    // لا يملك نقطة "الأشهر التي فيها حركات" التي تستخدمها شاشة المالية.
    final months = <({int year, int month})>[
      for (var i = 0; i < 18; i += 1)
        (
          year: DateTime(now.year, now.month - i, 1).year,
          month: DateTime(now.year, now.month - i, 1).month,
        ),
    ];

    String selectedValue;
    if (_allTime) {
      selectedValue = 'all';
    } else if (_isToday) {
      selectedValue = 'today';
    } else if (_selectedYear != null && _selectedMonth != null) {
      selectedValue = '$_selectedYear-$_selectedMonth';
    } else {
      selectedValue = '${months.first.year}-${months.first.month}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: surf.fieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surf.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: surf.textSecondary),
          dropdownColor: surf.sheetBg,
          borderRadius: BorderRadius.circular(16),
          items: [
            for (var i = 0; i < months.length; i += 1)
              DropdownMenuItem(
                value: '${months[i].year}-${months[i].month}',
                child: Text(
                  i == 0
                      ? '${_doctorsArabicMonths[months[i].month - 1]} ${months[i].year} (الشهر الحالي)'
                      : '${_doctorsArabicMonths[months[i].month - 1]} ${months[i].year}',
                  textAlign: TextAlign.right,
                ),
              ),
            const DropdownMenuItem(
              value: 'today',
              child: Text('اليوم', textAlign: TextAlign.right),
            ),
            const DropdownMenuItem(
              value: 'all',
              child: Text('كل الفترات', textAlign: TextAlign.right),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == 'today') {
              _selectPeriod(isToday: true);
            } else if (value == 'all') {
              _selectPeriod(allTime: true);
            } else {
              final parts = value.split('-');
              _selectPeriod(
                  year: int.parse(parts[0]), month: int.parse(parts[1]));
            }
          },
        ),
      ),
    );
  }

  /// شريط أفقي واحد لتوزيع حصص الأطباء في الفترة -- بديل الحلقة الدائرية في
  /// الموقع: الحلقة على عرض الجوال تصير أصغر من أن تُقرأ منها نسبة، والشريط
  /// المكدّس يعطي المعلومة نفسها بعرض كامل.
  Widget _buildDistributionBar(List<ClinicDoctor> doctors, double total) {
    final surf = context.surface;
    final share = doctors.where((d) => d.periodDoctorShare > 0).toList()
      ..sort((a, b) => b.periodDoctorShare.compareTo(a.periodDoctorShare));
    if (share.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('توزيع حصص الأطباء',
                  style: AppType.kufi(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary)),
              const Spacer(),
              Text(_periodLabel,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: surf.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final doctor in share)
                    Expanded(
                      flex: (doctor.periodDoctorShare / total * 1000).round().clamp(1, 1000),
                      child: Container(
                          color: clinicDoctorColor(doctor.id, doctors)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final doctor in share)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: clinicDoctorColor(doctor.id, doctors),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${doctor.shortName} · ${(doctor.periodDoctorShare / total * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: surf.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorCard(ClinicDoctor doctor) {
    final surf = context.surface;
    final color = clinicDoctorColor(doctor.id, _doctors ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InitialsAvatar(
                  name: doctor.fullName,
                  size: 44,
                  background: color,
                  foreground: Colors.white,
                  borderRadius: 14,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doctor.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.kufi(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: surf.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        doctor.specialty ?? 'طبيب في العيادة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: surf.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                doctor.isActive
                    ? SoftStatusPill(
                        label: 'نشط',
                        foreground: surf.pillPaidFg,
                        background: surf.pillPaidBg,
                        border: surf.pillPaidBorder,
                      )
                    : SoftStatusPill(
                        label: 'معطَّل',
                        foreground: surf.pillNoneFg,
                        background: surf.pillNoneBg,
                        border: surf.pillNoneBorder,
                      ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: surf.iconBoxBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: surf.iconBoxBorder),
              ),
              child: Row(
                children: [
                  _buildFigure('النسبة', '${doctor.commissionLabel}%', color),
                  _figureDivider(surf.divider),
                  _buildFigure('محصّل الفترة',
                      formatDoctorsMoney(doctor.periodCollected), surf.textPrimary),
                  _figureDivider(surf.divider),
                  _buildFigure('حصته من الفترة',
                      formatDoctorsMoney(doctor.periodDoctorShare), surf.textPrimary),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 15, color: surf.pillDueFg),
                const SizedBox(width: 6),
                Text('الرصيد المستحق (تراكمي)',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: surf.textSecondary)),
                const Spacer(),
                Text(
                  '${formatDoctorsMoney(doctor.balanceDue)} ل.س',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: doctor.balanceDue > 0
                          ? surf.pillDueFg
                          : surf.textSecondary),
                ),
              ],
            ),
            if (doctor.phone != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: surf.textMuted),
                  const SizedBox(width: 6),
                  Text(doctor.phone!,
                      style: TextStyle(fontSize: 12, color: surf.textMuted)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'كشف الحساب',
                    icon: Icons.receipt_long_outlined,
                    onPressed: () => _openStatement(doctor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GradientButton(
                    label: 'تسوية',
                    icon: Icons.price_check,
                    gradient: AppColors.successButtonGradient,
                    onPressed: () => _openPayoutSheet(doctor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SoftIconButton(
                  icon: Icons.edit_outlined,
                  foreground: AppColors.indigo700,
                  tooltip: 'تعديل بيانات الطبيب والنسبة',
                  onPressed: () => _openDoctorSheet(doctor: doctor),
                ),
                const SizedBox(width: 8),
                SoftIconButton(
                  icon: doctor.isActive
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                  foreground: doctor.isActive
                      ? AppColors.amber800text
                      : AppColors.emerald700text,
                  tooltip: doctor.isActive ? 'تعطيل الطبيب' : 'تفعيل الطبيب',
                  onPressed: () => _toggleActive(doctor),
                ),
                const Spacer(),
                SoftIconButton(
                  icon: Icons.delete_outline,
                  foreground: AppColors.rose700text,
                  tooltip: 'حذف الطبيب',
                  onPressed: () => _confirmDelete(doctor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFigure(String label, String value, Color valueColor) {
    final surf = context.surface;
    return Expanded(
      child: Column(
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: surf.textMuted)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: valueColor)),
        ],
      ),
    );
  }

  Widget _figureDivider(Color color) =>
      Container(width: 1, height: 26, color: color);

  Widget _buildPremiumLockCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy900, AppColors.indigo800, AppColors.violet700],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: const Text('PREMIUM PLUS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ),
          const SizedBox(height: 14),
          const Icon(Icons.lock_outline, color: Colors.white, size: 34),
          const SizedBox(height: 12),
          Text(
            _errorMessage ??
                'إدارة العيادة متعددة الأطباء وحساب النسب متاحة حصرياً لـ '
                    'باقة العيادات (Premium Plus).',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, height: 1.6),
          ),
          const SizedBox(height: 6),
          Text(
            'تواصل مع المطور لترقية باقتك والحصول على كود التفعيل.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .75), fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// ============================ ورقة بيانات الطبيب ============================

class _DoctorFormSheet extends StatefulWidget {
  final ApiService apiService;
  final ClinicDoctor? doctor;

  const _DoctorFormSheet({required this.apiService, this.doctor});

  @override
  State<_DoctorFormSheet> createState() => _DoctorFormSheetState();
}

class _DoctorFormSheetState extends State<_DoctorFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _specialtyController;
  late final TextEditingController _percentController;
  late final TextEditingController _notesController;
  bool _isSaving = false;
  String? _error;

  bool get _isEdit => widget.doctor != null;

  @override
  void initState() {
    super.initState();
    final doctor = widget.doctor;
    _nameController = TextEditingController(text: doctor?.fullName ?? '');
    _phoneController = TextEditingController(text: doctor?.phone ?? '');
    _specialtyController = TextEditingController(text: doctor?.specialty ?? '');
    _percentController =
        TextEditingController(text: doctor == null ? '' : doctor.commissionLabel);
    _notesController = TextEditingController(text: doctor?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _specialtyController.dispose();
    _percentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final percent = double.tryParse(_percentController.text.trim()) ?? 0;
    try {
      if (_isEdit) {
        // النص الفارغ يُرسَل كما هو ليمحو الهاتف أو الاختصاص فعلياً: الخادم
        // يقرأ null على أنه "لا تغيير"، فلو أرسلنا null للحقل المُفرَّغ لظلّت
        // القيمة القديمة وبدا الحفظ كأنه لم يعمل.
        await widget.apiService.updateClinicDoctor(
          widget.doctor!.id,
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          specialty: _specialtyController.text.trim(),
          commissionPercent: percent,
          notes: _notesController.text.trim(),
        );
      } else {
        await widget.apiService.createClinicDoctor(
          fullName: _nameController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          specialty: _specialtyController.text.trim().isEmpty
              ? null
              : _specialtyController.text.trim(),
          commissionPercent: percent,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر الحفظ. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return _SheetShell(
      title: _isEdit ? 'تعديل بيانات الطبيب' : 'إضافة طبيب جديد',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetField(
              label: 'اسم الطبيب',
              controller: _nameController,
              hint: 'د. لينا مرعي',
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'اسم الطبيب مطلوب'
                  : null,
            ),
            _SheetField(
              label: 'نسبة الطبيب %',
              controller: _percentController,
              hint: '40',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'النسبة مطلوبة (اكتب 0 إن لم تكن هناك نسبة)';
                final parsed = double.tryParse(text);
                if (parsed == null || !parsed.isFinite) return 'اكتب رقماً صحيحاً';
                if (parsed < 0 || parsed > 100) return 'النسبة بين 0 و 100';
                return null;
              },
            ),
            _SheetField(
              label: 'الاختصاص (اختياري)',
              controller: _specialtyController,
              hint: 'تقويم الأسنان',
            ),
            _SheetField(
              label: 'رقم الهاتف (اختياري)',
              controller: _phoneController,
              hint: '09XXXXXXXX',
              keyboardType: TextInputType.phone,
            ),
            _SheetField(
              label: 'ملاحظة (اختياري)',
              controller: _notesController,
              hint: 'أي تفاصيل تخص اتفاق النسبة',
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(
                      color: AppColors.rose700text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            GradientButton(
              label: _isEdit ? 'حفظ التعديلات' : 'إضافة الطبيب',
              icon: Icons.check,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _submit,
            ),
            const SizedBox(height: 8),
            Text(
              'النسبة تُطبَّق على الدفعات الجديدة. الحركات المسجَّلة سابقاً '
              'تبقى بالنسبة التي كانت عند تسجيلها.',
              textAlign: TextAlign.center,
              style: TextStyle(color: surf.textMuted, fontSize: 11.5, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================== ورقة التسوية ==============================

class _PayoutSheet extends StatefulWidget {
  final ApiService apiService;
  final ClinicDoctor doctor;

  const _PayoutSheet({required this.apiService, required this.doctor});

  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _paidAt = DateTime.now();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _paidAt = DateTime(
          picked.year, picked.month, picked.day, _paidAt.hour, _paidAt.minute));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.createDoctorPayout(
        widget.doctor.id,
        amount: double.parse(_amountController.text.trim()),
        note: _noteController.text,
        paidAt: _paidAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تسجيل التسوية. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return _SheetShell(
      title: 'تسجيل تسوية لـ ${widget.doctor.shortName}',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: surf.pillDueBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: surf.pillDueBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 16, color: surf.pillDueFg),
                  const SizedBox(width: 8),
                  Text('الرصيد المستحق حالياً',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: surf.pillDueFg)),
                  const Spacer(),
                  Text('${formatDoctorsMoney(widget.doctor.balanceDue)} ل.س',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: surf.pillDueFg)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SheetField(
              label: 'المبلغ المُسلَّم للطبيب',
              controller: _amountController,
              hint: '0',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'المبلغ مطلوب';
                final parsed = double.tryParse(text);
                if (parsed == null || !parsed.isFinite) return 'اكتب رقماً صحيحاً';
                if (parsed <= 0) return 'المبلغ يجب أن يكون أكبر من صفر';
                return null;
              },
            ),
            Text('تاريخ التسليم',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: surf.heroCaption)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: surf.fieldBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: surf.fieldBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 17, color: surf.textSecondary),
                    const SizedBox(width: 8),
                    Text(formatDoctorsDate(_paidAt),
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: surf.textPrimary)),
                    const Spacer(),
                    Icon(Icons.keyboard_arrow_down, color: surf.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SheetField(
              label: 'ملاحظة (اختياري)',
              controller: _noteController,
              hint: 'تسوية نصف شهرية، نقداً',
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(
                      color: AppColors.rose700text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            GradientButton(
              label: 'تسجيل التسوية',
              icon: Icons.price_check,
              gradient: AppColors.successButtonGradient,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// =============================== كشف الحساب ===============================

class DoctorStatementScreen extends StatefulWidget {
  final ApiService apiService;
  final ClinicDoctor doctor;
  final int? year;
  final int? month;
  final int? day;
  final bool allTime;
  final String periodLabel;
  final VoidCallback onSessionExpired;

  /// يُنادى بعد كل حذف تسوية -- يُحدِّث بطاقة الطبيب في الشاشة السابقة
  /// فوراً بدل أن تبقى على رصيد مستحق قديم.
  final VoidCallback onPayoutsChanged;

  const DoctorStatementScreen({
    super.key,
    required this.apiService,
    required this.doctor,
    required this.periodLabel,
    required this.onSessionExpired,
    required this.onPayoutsChanged,
    this.year,
    this.month,
    this.day,
    this.allTime = false,
  });

  @override
  State<DoctorStatementScreen> createState() => _DoctorStatementScreenState();
}

class _DoctorStatementScreenState extends State<DoctorStatementScreen> {
  DoctorStatement? _statement;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final statement = await widget.apiService.fetchDoctorStatement(
        widget.doctor.id,
        year: widget.year,
        month: widget.month,
        day: widget.day,
        allTime: widget.allTime,
      );
      if (!mounted) return;
      setState(() {
        _statement = statement;
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
        _errorMessage = 'تعذر تحميل كشف الحساب. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDeletePayout(DoctorPayoutRow payout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surface.sheetBg,
        title: Text('حذف التسوية؟',
            style: AppType.kufi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.surface.textPrimary)),
        content: Text(
          'حذف تسوية بمبلغ ${formatDoctorsMoney(payout.amount)} ل.س يُعيد '
          'المبلغ إلى الرصيد المستحق للطبيب.',
          style: TextStyle(color: context.surface.textSecondary, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('حذف', style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteDoctorPayout(widget.doctor.id, payout.id);
      if (!mounted) return;
      widget.onPayoutsChanged();
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر حذف التسوية.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    // زر الرجوع افتراضي: Directionality في main.dart يقلبه لليمين تلقائياً
    // في الواجهة العربية، فلا حاجة لأيقونة يدوية تكسر السلوك على ويندوز.
    return Scaffold(
      backgroundColor: surf.pageBg,
      appBar: AppBar(
        backgroundColor: surf.cardBg,
        surfaceTintColor: Colors.transparent,
        title: Text('كشف حساب ${widget.doctor.shortName}',
            style: AppType.kufi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: surf.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            LoadingErrorEmpty(
              isLoading: _isLoading,
              errorMessage: _errorMessage,
              isLocked: false,
              onRetry: _load,
              child: _statement == null
                  ? const SizedBox.shrink()
                  : _buildStatement(_statement!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatement(DoctorStatement statement) {
    final surf = context.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('ملخص الفترة',
                      style: AppType.kufi(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: surf.textPrimary)),
                  const Spacer(),
                  Text(widget.periodLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: surf.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              _summaryRow('المحصّل في الفترة', statement.period.collected,
                  surf.textPrimary),
              _summaryRow('حصة الطبيب', statement.period.doctorShare,
                  AppColors.purple700),
              _summaryRow('حصة العيادة', statement.period.clinicShare,
                  AppColors.emerald700text),
              _summaryRow('المُسلَّم في الفترة', statement.period.paidOut,
                  surf.textSecondary),
              if (statement.period.materialsCost > 0)
                _summaryRow('تكلفة المواد المستهلكة',
                    statement.period.materialsCost, AppColors.amber800text),
              Divider(color: surf.divider, height: 20),
              _summaryRow('استحقاقه التراكمي', statement.doctor.totalDoctorShare,
                  surf.textPrimary),
              _summaryRow('المُسلَّم له (تراكمي)', statement.doctor.totalPaidOut,
                  surf.textSecondary),
              _summaryRow('الرصيد المستحق', statement.doctor.balanceDue,
                  surf.pillDueFg,
                  bold: true),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildEarningsSection(statement),
        const SizedBox(height: 14),
        _buildPayoutsSection(statement),
        if (statement.materials.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildMaterialsSection(statement),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, double value, Color color, {bool bold = false}) {
    final surf = context.surface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? color : surf.textSecondary)),
          ),
          Text('${formatDoctorsMoney(value)} ل.س',
              style: TextStyle(
                  fontSize: bold ? 14 : 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildEarningsSection(DoctorStatement statement) {
    final surf = context.surface;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('حركات الطبيب',
                  style: AppType.kufi(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary)),
              const Spacer(),
              Text('${statement.earnings.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: surf.textMuted)),
            ],
          ),
          if (statement.earnings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('لا حركات في هذه الفترة',
                    style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
              ),
            )
          else
            for (final earning in statement.earnings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: surf.iconBoxBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: surf.iconBoxBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              earning.patientName ?? 'مريض غير محدَّد',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: surf.textPrimary),
                            ),
                          ),
                          if (earning.isAdjusted) ...[
                            const SizedBox(width: 6),
                            SoftStatusPill(
                              label: 'معدَّلة',
                              foreground: surf.warnFg,
                              background: surf.warnBg,
                              border: surf.warnBorder,
                            ),
                          ],
                          const SizedBox(width: 6),
                          Text(formatDoctorsDate(earning.earnedAt),
                              style: TextStyle(
                                  fontSize: 10.5, color: surf.textMuted)),
                        ],
                      ),
                      if (earning.description != null) ...[
                        const SizedBox(height: 3),
                        Text(earning.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: surf.textSecondary)),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _miniFigure('المبلغ',
                              formatDoctorsMoney(earning.grossAmount), surf.textPrimary),
                          _miniFigure(
                              'النسبة',
                              '${earning.appliedPercent.round()}%',
                              surf.textSecondary),
                          _miniFigure('حصته',
                              formatDoctorsMoney(earning.doctorShare), AppColors.purple700),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPayoutsSection(DoctorStatement statement) {
    final surf = context.surface;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('التسويات المسدَّدة',
                  style: AppType.kufi(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary)),
              const Spacer(),
              Text('${statement.payouts.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: surf.textMuted)),
            ],
          ),
          if (statement.payouts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('لا تسويات في هذه الفترة',
                    style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
              ),
            )
          else
            for (final payout in statement.payouts)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(11, 9, 5, 9),
                  decoration: BoxDecoration(
                    color: surf.pillPaidBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: surf.pillPaidBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${formatDoctorsMoney(payout.amount)} ل.س',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: surf.pillPaidFg)),
                            const SizedBox(height: 2),
                            Text(
                              payout.note == null
                                  ? formatDoctorsDate(payout.paidAt)
                                  : '${formatDoctorsDate(payout.paidAt)} · ${payout.note}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: surf.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 19, color: AppColors.rose700text),
                        tooltip: 'حذف التسوية',
                        onPressed: () => _confirmDeletePayout(payout),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildMaterialsSection(DoctorStatement statement) {
    final surf = context.surface;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('المواد المستهلكة في فواتيره',
              style: AppType.kufi(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: surf.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'تكلفة على العيادة لا تُخصم من حصة الطبيب -- تُعرَض هنا لقياس '
            'الربح الصافي من عمله.',
            style: TextStyle(fontSize: 11, color: surf.textMuted, height: 1.7),
          ),
          for (final material in statement.materials)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(material.itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: surf.textPrimary)),
                  ),
                  Text('${material.quantity} ×',
                      style: TextStyle(fontSize: 11.5, color: surf.textMuted)),
                  const SizedBox(width: 8),
                  Text('${formatDoctorsMoney(material.totalCost)} ل.س',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.amber800text)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniFigure(String label, String value, Color color) {
    final surf = context.surface;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: surf.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// ========================= عناصر مشتركة للأوراق =========================

/// غلاف الورقة السفلية: يترك مساحة للوحة المفاتيح ويُمرِّر المحتوى.
class _SheetShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _SheetShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: surf.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: AppType.kufi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;

  const _SheetField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: surf.heroCaption)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            validator: validator,
            style: TextStyle(color: surf.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: surf.fieldHint, fontWeight: FontWeight.w500),
              filled: true,
              fillColor: surf.fieldBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: surf.fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: surf.fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.indigo600, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
