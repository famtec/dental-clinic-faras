part of 'finance_screen.dart';

/// صفحة «المالية» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من `Finance.dc.html` على الكانفاس، وتخطيطٌ آخر لنفس
/// [_FinanceScreenState]: نفس الملخّص ونفس الحركات ونفس ورقتَي المصروف
/// والتعديل. ما أُضيف للعرض العريض وحده:
///
/// * **مخطط آخر ستة أشهر** (إيرادات/مصاريف) من ستة طلبات ملخّص شهري فعلية،
///   والنقر على شهر يبدّل التقرير إليه.
/// * **مستحقات المرضى** من `GET /api/patients/stats` -- نفس رقم صفحة المرضى.
///
/// ما في الكانفاس ولم يُبنَ لأن الخادم لا يملك مصدره: «منها نسب الأطباء»
/// و«توزيع المصاريف» حسب الفئة (المصروف لا يحمل فئة، وصفه نصّ حرّ)، وزرّ
/// «تسجيل إيراد» المستقل (الإيراد يُسجَّل دفعةً على فاتورة المريض). حلّ مكان
/// التوزيع شريطُ «الإيرادات مقابل المصاريف» المحسوب من الملخّص نفسه.
extension _FinanceDesktop on _FinanceScreenState {
  static const double _sideWidth = 320;

  String _periodKey() {
    if (_allTime) return 'all';
    if (_isToday) return 'today';
    final now = DateTime.now();
    return '${_selectedYear ?? now.year}-${_selectedMonth ?? now.month}';
  }

  String _periodLabelDesktop() {
    if (_allTime) return 'كل الوقت';
    if (_isToday) return 'اليوم';
    final now = DateTime.now();
    final month = _selectedMonth ?? now.month;
    final year = _selectedYear ?? now.year;
    return '${desktopArabicMonths[month - 1]} $year';
  }

  /// الأشهر الستة الأخيرة حتى الشهر الحالي -- محور المخطط.
  List<({int year, int month})> get _trendMonths {
    final now = DateTime.now();
    return [
      for (var i = 5; i >= 0; i--)
        (
          year: DateTime(now.year, now.month - i, 1).year,
          month: DateTime(now.year, now.month - i, 1).month,
        ),
    ];
  }

  /// طلبات المخطط ومستحقات المرضى -- مرة واحدة لعمر الشاشة، وتُعاد بعد
  /// تسجيل مصروف أو تعديل حركة (انظر [_refreshDesktopExtras]).
  Future<void> _loadDesktopExtras() async {
    _update(() => _desktopExtrasRequested = true);
    final months = _trendMonths;
    final results = await Future.wait([
      for (final m in months)
        widget.apiService
            .fetchFinanceSummary(year: m.year, month: m.month)
            .then<FinanceSummary?>((s) => s)
            .catchError((Object _) => null),
    ]);
    PatientStats? stats;
    try {
      stats = await widget.apiService.fetchPatientStats();
    } catch (_) {}
    if (!mounted) return;
    _update(() {
      _trend = {
        for (var i = 0; i < months.length; i++)
          if (results[i] != null) '${months[i].year}-${months[i].month}': results[i]!,
      };
      _pendingBalances = stats?.pendingBalances;
    });
  }

  void _refreshDesktopExtras() {
    if (_desktopExtrasRequested) _loadDesktopExtras();
  }

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    if (!_desktopExtrasRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_desktopExtrasRequested) _loadDesktopExtras();
      });
    }
    final summary = _summary;
    if (summary == null && _isLoading) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (summary == null) {
      return DesktopErrorState(
        message: _errorMessage ?? 'تعذر تحميل التقرير المالي.',
        onRetry: _loadSummary,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHeader(context),
          const SizedBox(height: 16),
          SizedBox(
            height: 262,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 380, child: _netCard(context, summary)),
                const SizedBox(width: 20),
                Expanded(child: _trendChart(context)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _movesTable(context)),
                const SizedBox(width: 20),
                SizedBox(
                  width: _FinanceDesktop._sideWidth,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _reviewPanel(summary, bottomSpacing: 14),
                        _ratioCard(context, summary),
                        const SizedBox(height: 14),
                        _receivablesCard(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── الترويسة ────────────────────────────────────────────────────────────

  Widget _desktopHeader(BuildContext context) {
    final d = context.desktop;
    final now = DateTime.now();
    final months = _months.isEmpty ? [(year: now.year, month: now.month)] : _months;
    return Row(
      children: [
        DesktopMenuButton<String>(
          label: _periodLabelDesktop(),
          tooltip: 'فترة التقرير',
          options: [
            (value: 'today', label: 'اليوم'),
            for (final m in months)
              (value: '${m.year}-${m.month}', label: '${desktopArabicMonths[m.month - 1]} ${m.year}'),
            (value: 'all', label: 'كل الوقت (الإجمالي التراكمي)'),
          ],
          onSelected: (value) {
            if (value == _periodKey()) return;
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
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'اضغط أي شهر في المخطط للتبديل إليه',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
          ),
        ),
        if (_isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: d.linkFg),
          ),
          const SizedBox(width: 12),
        ],
        DesktopCtaButton(
          icon: Icons.remove_circle_outline,
          label: 'تسجيل مصروف',
          onTap: _openAddExpenseSheet,
        ),
      ],
    );
  }

  // ── بطاقة الصافي ────────────────────────────────────────────────────────

  Widget _netCard(BuildContext context, FinanceSummary summary) {
    final d = context.desktop;
    final change = _profitChangePercent;
    final income = summary.totalIncome;
    final margin = income > 0 ? (summary.netProfit / income * 100).round() : null;
    final now = DateTime.now();
    final isCurrentMonth = !_allTime &&
        !_isToday &&
        (_selectedYear ?? now.year) == now.year &&
        (_selectedMonth ?? now.month) == now.month;

    return DesktopCard(
      glow: true,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: DesktopEyebrow('صافي الأرباح — ${_periodLabelDesktop()}')),
              if (change != null)
                DesktopBadge(
                  // كلمة لا رمز: «▲/▼» ليسا في خطّي Noto العربيين (مربّع فارغ)،
                  // و«+8٪» تنقلب إلى «8٪+» داخل سطر عربي.
                  label: change == 0
                      ? 'كالشهر السابق'
                      : '${change > 0 ? 'ارتفاع' : 'انخفاض'} ${change.abs()}٪ عن الشهر السابق',
                  colors: change >= 0
                      ? DesktopBadgeColors.done(d)
                      : DesktopBadgeColors(
                          const Color(0xFFBE123C),
                          const Color(0xFFBE123C).withValues(alpha: .10),
                          const Color(0xFFBE123C).withValues(alpha: .25),
                        ),
                  fontSize: 11,
                ),
            ],
          ),
          const SizedBox(height: 10),
          DesktopBigAmount(value: desktopMoney.format(summary.netProfit), fontSize: 32),
          if (isCurrentMonth)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'الشهر جارٍ — حتى ${now.day} ${desktopArabicMonths[now.month - 1]}',
                style: AppType.sans(fontSize: 11.5, color: d.textMuted),
              ),
            ),
          const Spacer(),
          DesktopFiguresRow(
            figures: [
              DesktopFigure(
                label: 'الإيرادات',
                value: desktopMoney.format(summary.totalIncome),
                color: d.amountIn,
              ),
              DesktopFigure(
                label: 'المصاريف',
                value: desktopMoney.format(summary.totalExpenses),
                color: d.amountOut,
              ),
              DesktopFigure(
                label: 'هامش الربح',
                value: margin == null ? '—' : '$margin٪',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── مخطط الأشهر الستة ───────────────────────────────────────────────────

  Widget _trendChart(BuildContext context) {
    final d = context.desktop;
    final months = _trendMonths;
    final values = [for (final m in months) _trend['${m.year}-${m.month}']];
    final maxValue = values.fold<double>(0, (max, s) {
      if (s == null) return max;
      final top = s.totalIncome > s.totalExpenses ? s.totalIncome : s.totalExpenses;
      return top > max ? top : max;
    });
    final selectedKey = _periodKey();

    Widget legend(String text, Gradient fill) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(gradient: fill, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(text, style: AppType.sans(fontSize: 11.5, color: d.textSecondary)),
          ],
        );

    const incomeFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF06B6D4), Color(0xFF4F46E5)],
    );
    const expenseFill = LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF59E0B)]);

    return DesktopPanel(
      title: 'آخر ستة أشهر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              legend('إيرادات', incomeFill),
              const SizedBox(width: 16),
              legend('مصاريف', expenseFill),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _trend.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: d.linkFg),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final barArea = constraints.maxHeight - 26;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < months.length; i++)
                            Expanded(
                              child: _TrendColumn(
                                label: desktopArabicMonths[months[i].month - 1],
                                income: values[i]?.totalIncome ?? 0,
                                expense: values[i]?.totalExpenses ?? 0,
                                maxValue: maxValue <= 0 ? 1 : maxValue,
                                barArea: barArea,
                                selected: selectedKey == '${months[i].year}-${months[i].month}',
                                incomeFill: incomeFill,
                                expenseFill: expenseFill,
                                onTap: () => _selectMonth(months[i].year, months[i].month),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── جدول الحركات ────────────────────────────────────────────────────────

  Widget _movesTable(BuildContext context) {
    final d = context.desktop;
    final moves = _moves.where((m) {
      if (_desktopMoveFilter == 1) return m.isIncome;
      if (_desktopMoveFilter == 2) return !m.isIncome;
      return true;
    }).toList();
    const labels = ['الكل', 'إيرادات', 'مصاريف'];
    final counts = [
      _moves.length,
      _moves.where((m) => m.isIncome).length,
      _moves.where((m) => !m.isIncome).length,
    ];

    return DesktopTablePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'آخر الحركات',
                    style: AppType.kufi(fontSize: 14.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                  ),
                ),
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  DesktopChip(
                    label: labels[i],
                    count: counts[i],
                    selected: _desktopMoveFilter == i,
                    onTap: () => _update(() => _desktopMoveFilter = i),
                  ),
                ],
              ],
            ),
          ),
          const DesktopTableHeader(columns: [
            (label: 'البيان', flex: 40, align: TextAlign.start),
            (label: 'النوع', flex: 12, align: TextAlign.start),
            (label: 'التاريخ', flex: 16, align: TextAlign.start),
            (label: 'المبلغ (ل.س)', flex: 16, align: TextAlign.end),
          ], trailingWidth: _MoveTableRow.actionsWidth),
          Expanded(
            child: moves.isEmpty
                ? const DesktopEmptyHint(
                    icon: Icons.receipt_long_outlined,
                    text: 'لا توجد حركات في هذه الفترة',
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: moves.length,
                    itemBuilder: (context, i) => _MoveTableRow(
                      move: moves[i],
                      onEdit: () => _openEditMoveSheet(moves[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── العمود الجانبي ──────────────────────────────────────────────────────

  Widget _ratioCard(BuildContext context, FinanceSummary summary) {
    final d = context.desktop;
    final income = summary.totalIncome;
    final expense = summary.totalExpenses;
    final total = income + expense;
    final incomeShare = total <= 0 ? 0.5 : income / total;
    final expenseOfIncome = income > 0 ? (expense / income * 100).round() : null;

    return DesktopCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الإيرادات مقابل المصاريف',
            style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(_periodLabelDesktop(), style: AppType.sans(fontSize: 11, color: d.textMuted)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: total <= 0
                  ? Container(color: d.rowDivider)
                  : Row(
                      children: [
                        Expanded(
                          flex: (incomeShare * 1000).round().clamp(1, 1000),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF4F46E5)]),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: ((1 - incomeShare) * 1000).round().clamp(1, 1000),
                          child: Container(color: const Color(0xFFF59E0B)),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DesktopFigure(
                    label: 'الإيرادات', value: desktopMoney.format(income), color: d.amountIn),
              ),
              Expanded(
                child: DesktopFigure(
                    label: 'المصاريف', value: desktopMoney.format(expense), color: d.amountOut),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            expenseOfIncome == null
                ? 'لا إيرادات في هذه الفترة بعد.'
                : 'المصاريف تستهلك $expenseOfIncome٪ من الإيرادات.',
            style: AppType.sans(fontSize: 12, color: d.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _receivablesCard(BuildContext context) {
    final d = context.desktop;
    final pending = _pendingBalances;
    return DesktopCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مستحقات المرضى',
            style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
          ),
          const SizedBox(height: 8),
          DesktopBigAmount(
            value: pending == null ? '—' : desktopMoney.format(pending),
            fontSize: 24,
          ),
          const SizedBox(height: 6),
          Text(
            'أرصدة متبقية على فواتير المرضى — لا تدخل في صافي الأرباح حتى تُحصَّل',
            style: AppType.sans(fontSize: 11.5, height: 1.6, color: d.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// عمود شهر واحد في المخطط: عمودا إيراد ومصروف متجاوران وتسمية الشهر.
class _TrendColumn extends StatefulWidget {
  final String label;
  final double income;
  final double expense;
  final double maxValue;
  final double barArea;
  final bool selected;
  final Gradient incomeFill;
  final Gradient expenseFill;
  final VoidCallback onTap;

  const _TrendColumn({
    required this.label,
    required this.income,
    required this.expense,
    required this.maxValue,
    required this.barArea,
    required this.selected,
    required this.incomeFill,
    required this.expenseFill,
    required this.onTap,
  });

  @override
  State<_TrendColumn> createState() => _TrendColumnState();
}

class _TrendColumnState extends State<_TrendColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final on = widget.selected;
    double h(double v) => (v / widget.maxValue * (widget.barArea - 8)).clamp(2, widget.barArea);
    final opacity = on || _hovered ? 1.0 : .45;

    Widget bar(double value, Gradient fill) => Container(
          width: 16,
          height: h(value),
          decoration: BoxDecoration(
            gradient: fill,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        );

    return Tooltip(
      message:
          '${widget.label}\nإيرادات ${desktopMoney.format(widget.income)}\nمصاريف ${desktopMoney.format(widget.expense)}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: on ? d.linkFg.withValues(alpha: d.isDark ? .12 : .045) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: opacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        bar(widget.income, widget.incomeFill),
                        const SizedBox(width: 4),
                        bar(widget.expense, widget.expenseFill),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 20,
                  child: Text(
                    widget.label,
                    style: AppType.sans(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      color: on ? d.linkFg : d.textMuted,
                    ),
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

/// صفّ حركة في جدول «آخر الحركات».
class _MoveTableRow extends StatelessWidget {
  final FinanceTransaction move;
  final VoidCallback onEdit;

  const _MoveTableRow({required this.move, required this.onEdit});

  /// زرّ التعديل بعرض 32 وهامش -- انظر [DesktopTableHeader.trailingWidth].
  static const double actionsWidth = 46;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final income = move.isIncome;
    final colors = income ? DesktopBadgeColors.done(d) : DesktopBadgeColors.waiting(d);
    final date = move.createdAt;
    final title = move.description.trim().isEmpty ? (income ? 'دفعة' : 'مصروف') : move.description;
    final sub = move.isOpeningBalance
        ? 'رصيد افتتاحي'
        : (date == null ? '' : 'الساعة ${desktopClockLabel(date.hour * 60 + date.minute)}');

    return DesktopTableRow(
      onDoubleTap: onEdit,
      child: Row(
        children: [
          Expanded(
            flex: 40,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    income ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16,
                    color: colors.fg,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: 13, fontWeight: FontWeight.w700, color: d.textPrimary),
                      ),
                      if (sub.isNotEmpty)
                        Text(sub, style: AppType.sans(fontSize: 11, color: d.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 12,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DesktopBadge(label: income ? 'إيراد' : 'مصروف', colors: colors, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              date == null ? '—' : desktopShortDate(date),
              style: AppType.sans(fontSize: 12.5, color: d.navInactiveFg),
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              '${income ? '+' : '−'}${desktopMoney.format(move.amount.abs())}',
              // النصّ LTR حتى تبقى الإشارة يسار الرقم، فالمحاذاة «يسار»
              // صريحة: end في LTR تعني اليمين.
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: AppType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: income ? d.amountIn : d.amountOut,
              ),
            ),
          ),
          SizedBox(
            width: actionsWidth,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DesktopSquareButton(
                icon: Icons.edit_outlined,
                tooltip: 'تعديل الحركة',
                size: 32,
                onTap: onEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
