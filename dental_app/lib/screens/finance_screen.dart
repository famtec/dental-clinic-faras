import 'package:flutter/material.dart';

import '../models/finance_summary.dart';
import '../models/finance_transaction.dart';
import '../models/patient_stats.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_widgets.dart';

part 'finance_desktop.dart';

const _arabicMonthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// "التقارير المالية" -- تطابق finance.html بالموقع: ملخص شهري (دخل/مصروفات/
/// صافي ربح) مع منتقي شهر، ورصيد افتتاحي منفصل عرضياً، وإمكانية تسجيل مصروف
/// عام جديد. تُستخدم require_active_doctor_user في main.py (بلا حارس Premium
/// إضافي)، فتبقى متاحة لكل الأطباء النشطين.
class FinanceScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const FinanceScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

/// شريط نسبة الواردات إلى المصاريف داخل بطاقة صافي الربح -- طبق الأصل عن
/// ‎#financeRatioBar في finance.html.
/// بطاقة رأس المالية (2026-09-25): صافي الربح رقماً كبيراً يعدّ إلى قيمته،
/// شريط الواردات/المصاريف يمتلئ، والإيرادات والمصاريف عدّادان أسفلها --
/// نفس بنية بطاقة صفحة المرضى (HeroPanel) بدل البطاقة الداكنة القديمة.
class _FinanceHero extends StatelessWidget {
  final FinanceSummary summary;
  final int? changePercent;

  const _FinanceHero({required this.summary, required this.changePercent});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulseDot(),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'صافي أرباح العيادة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: surf.heroCaption),
                ),
              ),
              _GrowthBadge(changePercent: changePercent),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedNumber(
            value: summary.netProfit,
            builder: (context, value) => HeroBigNumber(value: formatGroupedMoney(value), unit: 'ل.س'),
          ),
          const SizedBox(height: 14),
          HeroSplitBar(
            first: summary.totalIncome,
            second: summary.totalExpenses,
            firstColor: AppColors.emerald500,
            secondColor: AppColors.rose500,
            firstLabel: 'واردات',
            secondLabel: 'مصاريف',
          ),
          HeroStatsRow(
            children: [
              AnimatedNumber(
                value: summary.totalIncome,
                builder: (context, value) => HeroMiniStat(
                  icon: Icons.arrow_upward_rounded,
                  value: formatGroupedMoney(value),
                  label: 'إجمالي الإيرادات',
                ),
              ),
              AnimatedNumber(
                value: summary.totalExpenses,
                builder: (context, value) => HeroMiniStat(
                  icon: Icons.arrow_downward_rounded,
                  value: formatGroupedMoney(value),
                  // كانت «تكلفة المواد والمستلزمات» -- والرقم يشمل كل مصروف
                  // بما فيه تسويات مستحقات الأطباء، فالتسمية كانت تضلّل.
                  label: 'إجمالي المصاريف',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شارة نسبة التغيّر عن الشهر السابق داخل بطاقة الربح.
class _GrowthBadge extends StatelessWidget {
  final int? changePercent;

  const _GrowthBadge({required this.changePercent});

  @override
  Widget build(BuildContext context) {
    final change = changePercent;
    if (change == null || change == 0) return const SizedBox.shrink();
    final isUp = change > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = isUp
        ? (dark ? const Color(0xFF6EE7B7) : AppColors.emerald700text)
        : (dark ? AppColors.rose200 : AppColors.rose700text);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: (isUp ? AppColors.emerald500 : AppColors.rose500)
            .withValues(alpha: .15),
        border: Border.all(
          color: (isUp ? AppColors.emerald500 : AppColors.rose500)
              .withValues(alpha: .45),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            '${change.abs()}%',
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// قسم "آخر الحركات" -- قائمة الدفعات والمصاريف التي كوّنت الأرقام أعلاه.
/// لم يكن للشاشة (ولا لصفحة الموقع قبل 2026-09-02) أي طريقة لرؤيتها.
/// 2026-09-07: كل حركة أصبحت قابلة للضغط لتعديلها (onTapMove) -- طبق الأصل
/// عن نافذة #financeEditForm في patient_record.html.
class _MovesSection extends StatelessWidget {
  final List<FinanceTransaction> moves;
  final ValueChanged<FinanceTransaction> onTapMove;

  const _MovesSection({required this.moves, required this.onTapMove});

  static String _formatAmount(double value) {
    final digits = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)} · ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'آخر الحركات',
              style: AppType.kufi(
                  color: surf.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: -0.4),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: surf.iconBoxBg,
                border: Border.all(color: surf.iconBoxBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'هذه الفترة',
                style: TextStyle(
                    color: surf.iconBoxFg,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        if (moves.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: surf.chipBg,
              border: Border.all(color: surf.chipBorder),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'لا توجد حركات مالية في هذه الفترة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: surf.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          )
        else
          Column(
            children: [
              for (final move in moves) ...[
                _MoveRow(move: move, onTap: () => onTapMove(move)),
                if (move != moves.last) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  final FinanceTransaction move;
  final VoidCallback onTap;

  const _MoveRow({required this.move, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final isIncome = move.isIncome;
    final accent = isIncome ? AppColors.emerald600 : AppColors.rose700text;

    // Padding انتقل من SectionCard إلى داخل InkWell كي تمتد موجة اللمس على
    // كامل مساحة البطاقة (بما فيها ما كان هامشاً خارجياً)، بدل أن تُقتطع عند
    // حدود منطقة أضيق داخلياً.
    return SectionCard(
      radius: 20,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isIncome ? AppColors.emerald50 : AppColors.rose50,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isIncome ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  move.description.trim().isEmpty
                      ? (isIncome ? 'دفعة' : 'مصروف')
                      : move.description,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.kufi(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: surf.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  _MovesSection._formatDate(move.createdAt),
                  textAlign: TextAlign.right,
                  style: AppType.kufi(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: surf.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // الإشارة تبقى يسار الرقم كما في كشوف الحسابات، فلا تنقلب مع RTL.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${isIncome ? '+' : '-'} ${_MovesSection._formatAmount(move.amount)}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: accent),
            ),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinanceScreenState extends State<FinanceScreen> {
  /// نسبة تغيّر صافي الربح عن الشهر السابق. null = لا تُعرض الشارة (فترة
  /// "كل الوقت"/يوم واحد، أو شهر سابق بلا ربح فلا قاعدة مقارنة له).
  int? _profitChangePercent;

  /// آخر الحركات المالية للفترة المعروضة. قائمة فارغة = لا حركات أو تعذّر
  /// جلبها (المسار غير منشور بعد على الخادم)؛ في الحالتين تُعرض حالة
  /// "لا توجد حركات" ولا شيء يُقاطع الأرقام أعلاه.
  List<FinanceTransaction> _moves = const [];
  FinanceSummary? _summary;
  List<({int year, int month})> _months = [];
  // null/null + _allTime=false + _isToday=false يعني "الشهر الحالي" (سلوك
  // السيرفر الافتراضي). _isToday=true يطابق خيار "اليوم" الجديد في
  // finance.html -- 2026-08-29.
  int? _selectedYear;
  int? _selectedMonth;
  bool _allTime = false;
  bool _isToday = false;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLocked = false;

  // ── سطح المكتب (انظر finance_desktop.dart) ──
  /// ملخّصات الأشهر الستة الأخيرة بمفتاح "سنة-شهر" لمخطط سطح المكتب.
  Map<String, FinanceSummary> _trend = const {};
  double? _pendingBalances;
  bool _desktopExtrasRequested = false;
  /// 0 = الكل، 1 = إيرادات، 2 = مصاريف.
  int _desktopMoveFilter = 0;

  /// setState لامتداد سطح المكتب في ملف الـ part (setState محميّة).
  void _update(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _loadMonths();
    _loadSummary();
  }

  Future<void> _loadMonths() async {
    try {
      final months = await widget.apiService.fetchAvailableMonths();
      if (!mounted) return;
      setState(() => _months = months);
    } on ApiException catch (e) {
      if (e.isSessionExpired) widget.onSessionExpired();
    } catch (_) {
      // قائمة الأشهر ثانوية -- فشلها لا يمنع عرض ملخص الشهر الحالي.
    }
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isLocked = false;
    });
    try {
      // خيار "اليوم" يرسل تاريخ اليوم الحالي (سنة/شهر/يوم) في لحظة الطلب --
      // مطابق تماماً لـ buildMetricsUrl() في finance.html التي تبني `new
      // Date()` عند كل طلب بدل تخزين قيمة قديمة.
      final today = DateTime.now();
      final summary = await widget.apiService.fetchFinanceSummary(
        year: _isToday ? today.year : _selectedYear,
        month: _isToday ? today.month : _selectedMonth,
        day: _isToday ? today.day : null,
        allTime: _allTime,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
      _loadProfitComparison(summary);
      _loadMoves();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isLocked = e.isSubscriptionBlocked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل التقرير المالي. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  void _selectAllTime() {
    setState(() {
      _allTime = true;
      _isToday = false;
      _selectedYear = null;
      _selectedMonth = null;
    });
    _loadSummary();
  }

  void _selectToday() {
    setState(() {
      _allTime = false;
      _isToday = true;
      _selectedYear = null;
      _selectedMonth = null;
    });
    _loadSummary();
  }

  void _selectMonth(int year, int month) {
    setState(() {
      _allTime = false;
      _isToday = false;
      _selectedYear = year;
      _selectedMonth = month;
    });
    _loadSummary();
  }

  Future<void> _openAddExpenseSheet() async {
    final result =
        await showAppSheet<({bool inventorySynced, String? inventoryAction})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(apiService: widget.apiService),
    );
    if (result != null) {
      _loadMonths();
      _loadSummary();
      _refreshDesktopExtras();
      if (!mounted) return;
      // نفس رسالة النجاح "الأغنى" التي يعرضها submitExpense() بالموقع عند
      // نجاح الربط بمخزن المواد (finance.html).
      final message = result.inventorySynced
          ? 'تم حفظ المصروف بنجاح، و${result.inventoryAction == 'created' ? 'تمت إضافتها كمادة جديدة' : 'تم تحديث كميتها'} في مخزن المواد.'
          : 'تم حفظ المصروف بنجاح.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// فتح ورقة تعديل حركة مالية واحدة (دفعة أو مصروف) من قسم "آخر الحركات" --
  /// طبق الأصل عن نافذة #financeEditForm في patient_record.html، لكنها تعمل
  /// هنا على أي حركة بلا تمييز نوعها لأن PUT /api/finance/transaction/{id}
  /// عام لكل صفوف FinancialTransaction (انظر شرح updateFinanceTransaction في
  /// api_service.dart). 2026-09-07.
  Future<void> _openEditMoveSheet(FinanceTransaction move) async {
    final saved = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTransactionSheet(
        apiService: widget.apiService,
        move: move,
        onSessionExpired: widget.onSessionExpired,
      ),
    );
    if (saved == true) {
      _loadMonths();
      _loadSummary();
      _refreshDesktopExtras();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ التعديل بنجاح.')));
    }
  }

  String _money(double value) => value.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopShell) return _buildDesktop(context);
    final summary = _summary;
    return Scaffold(
      body: AtmosphereBackground(
        child: RefreshIndicator(
          onRefresh: _loadSummary,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const ClinicTopBar(),
              const OfflineSyncBanner(),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, floatingNavInset(context) + 84),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMonthSelector(),
                    const SizedBox(height: 16),
                    LoadingErrorEmpty(
                      isLoading: _isLoading,
                      errorMessage: _errorMessage,
                      isLocked: _isLocked,
                      onRetry: _loadSummary,
                      child: summary == null
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 2026-09-25: بطاقة الرأس الموحّدة (HeroPanel) كصفحة
                                // المرضى بدل البطاقة الداكنة القديمة وبطاقتين
                                // بيضاوين تحتها، بأرقام تعدّ وشريط يمتلئ.
                                FadeSlideIn(
                                  child: _FinanceHero(
                                    summary: summary,
                                    changePercent: _profitChangePercent,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FadeSlideIn(
                                  delay: const Duration(milliseconds: 140),
                                  child: _MovesSection(
                                      moves: _moves,
                                      onTapMove: _openEditMoveSheet),
                                ),
                                if (summary.openingBalanceIncome != 0) ...[
                                  const SizedBox(height: 12),
                                  SectionCard(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.account_balance_wallet_outlined,
                                            color: AppColors.indigo700),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text('الرصيد الافتتاحي (مُرحّل)',
                                              style: TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                        Text(
                                          _money(summary.openingBalanceIncome),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.indigo700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                GradientButton(
                                  label: 'تسجيل مصروف جديد',
                                  icon: Icons.add,
                                  onPressed: _openAddExpenseSheet,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// آخر الحركات للفترة المعروضة حالياً -- بنفس معاملات الملخّص تماماً.
  Future<void> _loadMoves() async {
    final today = DateTime.now();
    // سطح المكتب يعرض جدولاً بارتفاع الصفحة لا قسماً من ثمانية أسطر.
    final limit = context.isDesktopShell ? 60 : 8;
    try {
      final moves = await widget.apiService.fetchFinanceTransactions(
        limit: limit,
        year: _isToday ? today.year : _selectedYear,
        month: _isToday ? today.month : _selectedMonth,
        day: _isToday ? today.day : null,
        allTime: _allTime,
      );
      if (mounted) setState(() => _moves = moves);
    } catch (_) {
      // قسم توضيحي -- فشله لا يجب أن يمسّ المجاميع ولا يُظهر رسالة خطأ.
      if (mounted) setState(() => _moves = const []);
    }
  }

  /// مقارنة صافي الربح بالشهر السابق -- طلب إضافي واحد لنفس مسار الملخّص.
  /// لا تُعرض الشارة إطلاقاً في وضع "كل الوقت" أو "اليوم" (لا معنى لمقارنة
  /// يوم بشهر)، ولا حين يكون ربح الشهر السابق صفراً أو أقل (لا قاعدة نسبة).
  /// أي فشل هنا يُخفي الشارة فقط ولا يمسّ الأرقام المعروضة.
  Future<void> _loadProfitComparison(FinanceSummary summary) async {
    if (_allTime || _isToday || summary.year == null || summary.month == null) {
      if (mounted) setState(() => _profitChangePercent = null);
      return;
    }

    final year = summary.year!;
    final month = summary.month!;
    final previousMonth = month == 1 ? 12 : month - 1;
    final previousYear = month == 1 ? year - 1 : year;

    try {
      final previous = await widget.apiService.fetchFinanceSummary(
        year: previousYear,
        month: previousMonth,
      );
      if (!mounted) return;
      final previousProfit = previous.netProfit;
      if (previousProfit <= 0) {
        setState(() => _profitChangePercent = null);
        return;
      }
      final change =
          ((summary.netProfit - previousProfit) / previousProfit * 100).round();
      setState(() => _profitChangePercent = change);
    } catch (_) {
      if (mounted) setState(() => _profitChangePercent = null);
    }
  }

  /// زر قائمة منسدلة لاختيار فترة التقرير -- مطابق حرفياً للقائمة المنسدلة
  /// الحالية في finance.html (#monthSelect/#monthSelectTrigger): "اليوم"
  /// أولاً، ثم الأشهر التي فيها حركات فعلية (الأحدث أولاً، والشهر الحالي
  /// مضمون الوجود دائماً حتى بلا حركات -- انظر get_finance_available_months
  /// بالـ main.py)، ثم "كل الوقت (الإجمالي التراكمي)" أخيراً. الاختيار
  /// الافتراضي يبقى أول شهر (الشهر الحالي) وليس "اليوم" -- نفس سلوك
  /// populateMonthSelect() بالموقع، الذي يضيف خيار اليوم بلا تغيير الافتراضي.
  Widget _buildMonthSelector() {
    final surf = context.surface;
    final now = DateTime.now();
    final monthEntries =
        _months.isEmpty ? [(year: now.year, month: now.month)] : _months;

    String selectedValue;
    if (_allTime) {
      selectedValue = 'all';
    } else if (_isToday) {
      selectedValue = 'today';
    } else if (_selectedYear != null && _selectedMonth != null) {
      selectedValue = '${_selectedYear}-${_selectedMonth}';
    } else {
      selectedValue = '${monthEntries.first.year}-${monthEntries.first.month}';
    }

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'today',
        child: Text('اليوم', textAlign: TextAlign.right),
      ),
      for (final entry in monthEntries)
        DropdownMenuItem(
          value: '${entry.year}-${entry.month}',
          child: Text(
            '${_arabicMonthNames[entry.month - 1]} ${entry.year}',
            textAlign: TextAlign.right,
          ),
        ),
      const DropdownMenuItem(
        value: 'all',
        child: Text('كل الوقت (الإجمالي التراكمي)', textAlign: TextAlign.right),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'عرض التقرير المالي لشهر',
          textAlign: TextAlign.right,
          style: AppType.kufi(
              fontWeight: FontWeight.w600, fontSize: 13, color: surf.heroCaption),
        ),
        const SizedBox(height: 8),
        Container(
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
              items: items,
              onChanged: (value) {
                if (value == null) return;
                if (value == 'today') {
                  _selectToday();
                } else if (value == 'all') {
                  _selectAllTime();
                } else {
                  final parts = value.split('-');
                  _selectMonth(int.parse(parts[0]), int.parse(parts[1]));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _periodHintText(),
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11.5, color: surf.textSecondary),
        ),
      ],
    );
  }

  /// مطابق لـ updatePeriodHint() في finance.html -- نص توضيحي يتغيّر حسب
  /// الفترة المختارة فعلياً في آخر تقرير مُحمَّل (وليس حسب الاختيار في
  /// القائمة فقط، لتفادي عرض نص لا يطابق البيانات المعروضة أثناء التحميل).
  String _periodHintText() {
    final summary = _summary;
    if (summary == null) {
      return 'التقرير يتجدد تلقائياً كل شهر، مع الاحتفاظ الكامل بتقارير كل الأشهر السابقة.';
    }
    if (summary.allTime) {
      return 'يعرض هذا الملخص إجمالي كل الحركات المالية منذ بداية استخدام النظام.';
    }
    // 2026-08-29: عند اختيار "اليوم" يعيد الخادم day مع year/month معاً --
    // يجب فحص هذا الفرع قبل فرع "شهر فقط" أدناه، تماماً كترتيب الفحص في
    // updatePeriodHint() بالموقع.
    if (summary.day != null && summary.year != null && summary.month != null) {
      return 'يعرض هذا الملخص حركات يوم ${summary.day} ${_arabicMonthNames[summary.month! - 1]} ${summary.year} فقط.';
    }
    if (summary.year != null && summary.month != null) {
      return 'يعرض هذا الملخص حركات شهر ${_arabicMonthNames[summary.month! - 1]} ${summary.year} فقط، ويتجدد تلقائياً كل شهر مع الاحتفاظ بتقارير الأشهر السابقة كاملة.';
    }
    return 'التقرير يتجدد تلقائياً كل شهر، مع الاحتفاظ الكامل بتقارير كل الأشهر السابقة.';
  }
}

class _AddExpenseSheet extends StatefulWidget {
  final ApiService apiService;

  const _AddExpenseSheet({required this.apiService});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  // 2026-08-29: ربط اختياري بمخزن المواد -- مطابق لقسم #addToInventoryToggle
  // بـ finance.html (انظر شرح createExpense() في api_service.dart).
  final _inventoryItemNameController = TextEditingController();
  final _inventoryQuantityController = TextEditingController();
  bool _addToInventory = false;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _inventoryItemNameController.dispose();
    _inventoryQuantityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final result = await widget.apiService.createExpense(
        amount: double.parse(_amountController.text.trim()),
        description: _descriptionController.text.trim(),
        addToInventory: _addToInventory,
        inventoryItemName:
            _addToInventory ? _inventoryItemNameController.text.trim() : null,
        inventoryQuantity: _addToInventory
            ? int.tryParse(_inventoryQuantityController.text.trim())
            : null,
      );
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر تسجيل المصروف. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BottomSheetOnly(
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: surf.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const Text(
                'تسجيل مصروف جديد',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'قيمة المصروف'),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) return 'أدخل قيمة صحيحة أكبر من صفر';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'وصف المصروف'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'وصف المصروف مطلوب' : null,
              ),
              const SizedBox(height: 14),
              _buildInventoryLinkSection(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.rose700text)),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'حفظ المصروف',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// قسم "أضفها تلقائياً إلى مخزن المواد" -- مطابق حرفياً لكتلة
  /// #addToInventoryToggle/#inventoryLinkFields في finance.html: نفس النص
  /// العربي بالضبط، ونفس التحقق الشرطي في submitExpense() هناك (اسم مادة
  /// غير فارغ وكمية أكبر من صفر إلزاميان فقط عند تفعيل المفتاح).
  Widget _buildInventoryLinkSection() {
    final surf = context.surface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surf.iconBoxBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: surf.iconBoxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _addToInventory = !_addToInventory),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '📦 هذا المصروف لشراء مادة جديدة — أضفها تلقائياً إلى مخزن المواد',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.indigo700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: _addToInventory,
                  activeColor: AppColors.indigo600,
                  onChanged: (value) =>
                      setState(() => _addToInventory = value ?? false),
                ),
              ],
            ),
          ),
          if (_addToInventory) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _inventoryItemNameController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'اسم المادة'),
              validator: (value) {
                if (!_addToInventory) return null;
                return (value == null || value.trim().isEmpty)
                    ? 'اسم المادة مطلوب'
                    : null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _inventoryQuantityController,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الكمية المضافة'),
              validator: (value) {
                if (!_addToInventory) return null;
                final parsed = int.tryParse((value ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return 'أدخل كمية صحيحة أكبر من صفر';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'إن وجدت مادة بنفس الاسم في المخزن سيتم زيادة كميتها تلقائياً، وإلا سيتم إنشاء مادة جديدة.',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: surf.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// ورقة "تعديل الحركة المالية" -- طبق الأصل عن نافذة #financeEditForm في
/// patient_record.html (نفس الحقول الثلاثة بالضبط: المبلغ / الوصف / تسوية
/// رصيد قديم أو سابق)، لكنها تُفتح هنا من قسم "آخر الحركات" في الشاشة
/// المالية العامة بدل شاشة فاتورة مريض محدَّدة، وتعمل على أي حركة (دفعة أو
/// مصروف) بلا تمييز نوعها -- PUT /api/finance/transaction/{id} عام لكل صفوف
/// FinancialTransaction (انظر توثيق updateFinanceTransaction في
/// api_service.dart). الحفظ يمر عبر OfflineAwareApiService كأي عملية أخرى:
/// أوفلاين لحركة سُجِّلت أوفلاين ولم تُزامَن بعد (id سالب) يُصحَّح payload
/// عملية الإنشاء المعلَّقة نفسها فوراً بلا محاولة اتصال؛ أوفلاين لحركة
/// مُزامَنة فعلاً (id موجب) يُسجَّل تعديل outbox منفصل يُطبَّق عند عودة
/// الاتصال -- كلا المسارين مبنيان مسبقاً في الخدمة، هذه الورقة مجرد واجهة.
/// 2026-09-07.
class _EditTransactionSheet extends StatefulWidget {
  final ApiService apiService;
  final FinanceTransaction move;
  final VoidCallback onSessionExpired;

  const _EditTransactionSheet({
    required this.apiService,
    required this.move,
    required this.onSessionExpired,
  });

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late bool _isOpeningBalance;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.move.amount.toStringAsFixed(0));
    _descriptionController =
        TextEditingController(text: widget.move.description);
    _isOpeningBalance = widget.move.isOpeningBalance;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.updateFinanceTransaction(
        widget.move.id,
        amount: double.parse(_amountController.text.trim()),
        description: _descriptionController.text.trim(),
        isOpeningBalance: _isOpeningBalance,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر حفظ التعديل. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final isIncome = widget.move.isIncome;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BottomSheetOnly(
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: surf.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Text(
                isIncome ? 'تعديل الدفعة المالية' : 'تعديل المصروف',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ'),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) return 'أدخل قيمة صحيحة أكبر من صفر';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                textAlign: TextAlign.right,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'الوصف'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'الوصف مطلوب' : null,
              ),
              const SizedBox(height: 12),
              // نفس نص #financeEditOpeningBalance في patient_record.html
              // حرفياً، ونفس أسلوب مفتاح "أضفها إلى مخزن المواد" أعلاه
              // (Container ملوّن + InkWell على كامل الصف يبدّل قيمة
              // Checkbox، بدل الاعتماد على النقر داخل مربع الفحص وحده).
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surf.iconBoxBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: surf.iconBoxBorder),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setState(() => _isOpeningBalance = !_isOpeningBalance),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'هذه تسوية رصيد قديم/سابق (تُستبعد من تقرير أي شهر محدَّد، وتبقى ضمن الإجمالي الكلي)',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.indigo700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Checkbox(
                        value: _isOpeningBalance,
                        activeColor: AppColors.indigo600,
                        onChanged: (value) =>
                            setState(() => _isOpeningBalance = value ?? false),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.rose700text)),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'حفظ التعديل',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
