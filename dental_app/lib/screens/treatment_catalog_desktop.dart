part of 'treatment_catalog_screen.dart';

/// صفحة «لائحة الأسعار» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من `Pricing.dc.html` على الكانفاس، وتخطيطٌ آخر لنفس
/// [_TreatmentCatalogScreenState]: نفس اللائحة ونفس تقرير الربحية ونفس ورقة
/// الحالة. الجدول يعرض التسعيرة والتكلفة والربح والهامش لكل حالة بسطر، ولوحة
/// الوصفة الجانبية تشرح الحالة المختارة مادةً مادة مع توفّرها في المخزن.
///
/// «الأعلى ربحاً» و«فاتورة هذا الشهر» يأتيان من تقرير الربحية نفسه (بتاريخ
/// إنشاء الفاتورة)، فيتبعان فترة التقرير المختارة لا الشهر الحالي دائماً.
extension _CatalogDesktop on _TreatmentCatalogScreenState {
  static const double _recipeWidth = 340;

  List<TreatmentCatalogItem> _visibleItems() {
    final items = _items ?? const <TreatmentCatalogItem>[];
    return _showInactive ? items : items.where((i) => i.isActive).toList();
  }

  TreatmentCatalogItem? _desktopSelectedItem(List<TreatmentCatalogItem> visible) {
    if (visible.isEmpty) return null;
    for (final i in visible) {
      if (i.id == _selectedItemId) return i;
    }
    return visible.first;
  }

  Map<int, CatalogProfitRow> get _reportByItem => {
        for (final r in _report?.items ?? const <CatalogProfitRow>[])
          if (r.catalogItemId != null) r.catalogItemId!: r,
      };

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    if (_isLoading && _items == null) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (_errorMessage != null && _items == null) {
      return DesktopErrorState(message: _errorMessage!, onRetry: _load);
    }
    final visible = _visibleItems();
    final selected = _desktopSelectedItem(visible);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHeader(context),
          const SizedBox(height: 16),
          _kpiStrip(context),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _itemsTable(context, visible, selected)),
                      const SizedBox(height: 16),
                      SizedBox(height: 236, child: _reportPanel(context)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: _CatalogDesktop._recipeWidth,
                  child: _recipePanel(context, selected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── الترويسة والمؤشرات ──────────────────────────────────────────────────

  Widget _desktopHeader(BuildContext context) {
    final d = context.desktop;
    return Row(
      children: [
        Expanded(
          child: Text(
            'تسعيرة كل حالة ووصفة موادها — تُختار عند فتح فاتورة فتملأ العنوان والسعر والمواد',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _update(() => _showInactive = !_showInactive),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: d.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: d.iconBtnBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 30,
                    height: 18,
                    padding: const EdgeInsets.all(2),
                    alignment: _showInactive
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      color: _showInactive ? d.linkFg : d.rowDivider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('إظهار المعطّلة',
                      style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.navInactiveFg)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        DesktopCtaButton(icon: Icons.add, label: 'حالة جديدة', onTap: () => _openItemSheet()),
      ],
    );
  }

  Widget _kpiStrip(BuildContext context) {
    final d = context.desktop;
    final items = _items ?? const <TreatmentCatalogItem>[];
    final active = items.where((i) => i.isActive).toList();
    final priced = active.where((i) => i.price > 0).toList();
    final avgMargin = priced.isEmpty
        ? null
        : (priced.fold<double>(0, (t, i) => t + i.estimatedProfit / i.price) / priced.length * 100).round();
    final shortCount = active.where((i) => i.materials.any((m) => m.isShort)).length;
    CatalogProfitRow? top;
    // صفّ الفواتير المفتوحة بلا حالة من اللائحة (catalogItemId == null) ليس
    // علاجاً، بل سلّة لكل ما عداها -- ولو دخل المنافسة لفاز بها غالباً
    // وقالت البطاقة «الأعلى ربحاً: علاجات بلا حالة من اللائحة».
    for (final r in _report?.items ?? const <CatalogProfitRow>[]) {
      if (r.catalogItemId == null || r.invoicesCount <= 0) continue;
      if (top == null || r.netProfit > top.netProfit) top = r;
    }

    return Row(
      children: [
        Expanded(
          child: DesktopKpiCard(
            label: 'حالات فعّالة',
            value: '${active.length}',
            suffix: items.length > active.length ? '+ ${items.length - active.length} معطّلة' : null,
            highlight: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'متوسط هامش الربح المتوقَّع',
            value: avgMargin == null ? '—' : '$avgMargin٪',
            valueColor: d.amountIn,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'الأعلى ربحاً — $_reportPeriodLabel',
            value: top?.name ?? '—',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'وصفات فيها مادة ناقصة',
            value: '$shortCount',
            valueColor: shortCount > 0 ? d.amountOut : null,
          ),
        ),
      ],
    );
  }

  // ── جدول اللائحة ────────────────────────────────────────────────────────

  Widget _itemsTable(
      BuildContext context, List<TreatmentCatalogItem> visible, TreatmentCatalogItem? selected) {
    final uses = _reportByItem;
    return DesktopTablePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DesktopTableHeader(columns: [
            (label: 'الحالة', flex: 34, align: TextAlign.start),
            (label: 'التسعيرة', flex: 15, align: TextAlign.start),
            (label: 'تكلفة المواد', flex: 15, align: TextAlign.start),
            (label: 'الربح المتوقَّع', flex: 15, align: TextAlign.start),
            (label: 'الهامش', flex: 16, align: TextAlign.start),
          ]),
          Expanded(
            child: visible.isEmpty
                ? const DesktopEmptyHint(icon: Icons.sell_outlined, text: 'لا حالات في اللائحة بعد')
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final item = visible[i];
                      return DesktopTableRow(
                        selected: item.id == selected?.id,
                        onTap: () => _update(() => _selectedItemId = item.id),
                        onDoubleTap: () => _openItemSheet(item: item),
                        child: _CatalogRow(item: item, invoices: uses[item.id]?.invoicesCount),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── تقرير الربحية ───────────────────────────────────────────────────────

  Widget _reportPanel(BuildContext context) {
    final d = context.desktop;
    final now = DateTime.now();
    final report = _report;
    final rows = [...?report?.items]..sort((a, b) => b.billed.compareTo(a.billed));
    final maxBilled = rows.fold<double>(0, (m, r) => r.billed > m ? r.billed : m);

    return DesktopTablePanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تقرير الربحية — $_reportPeriodLabel',
                          style: AppType.kufi(fontSize: 14, fontWeight: FontWeight.w700, color: d.textPrimary)),
                      Text(
                        'بتاريخ إنشاء الفاتورة لا تحصيلها: ربحية عمل لا تدفّق نقدي · تكلفة المواد مجمّدة من الفواتير',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: 11, color: d.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DesktopMenuButton<String>(
                  label: _reportPeriodLabel,
                  tooltip: 'فترة التقرير',
                  options: [
                    for (var i = 0; i < 12; i++)
                      (
                        value:
                            '${DateTime(now.year, now.month - i, 1).year}-${DateTime(now.year, now.month - i, 1).month}',
                        label:
                            '${_catalogArabicMonths[DateTime(now.year, now.month - i, 1).month - 1]} ${DateTime(now.year, now.month - i, 1).year}',
                      ),
                    (value: 'all', label: 'كل الفترات'),
                  ],
                  onSelected: (value) {
                    _update(() {
                      if (value == 'all') {
                        _reportAllTime = true;
                        _reportYear = null;
                        _reportMonth = null;
                      } else {
                        final parts = value.split('-');
                        _reportAllTime = false;
                        _reportYear = int.parse(parts[0]);
                        _reportMonth = int.parse(parts[1]);
                      }
                    });
                    _loadReport();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isReportLoading && report == null
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: d.linkFg),
                      ),
                    )
                  : rows.isEmpty
                      ? Center(
                          child: Text(
                            report == null
                                ? 'تعذر تحميل التقرير.'
                                : 'لا فواتير من اللائحة في هذه الفترة.',
                            style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final r in rows)
                              _ReportBar(row: r, maxBilled: maxBilled <= 0 ? 1 : maxBilled),
                          ],
                        ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _legendDot(context, const Color(0xFF06B6D4), 'صافي بعد المواد'),
                const SizedBox(width: 16),
                _legendDot(context, const Color(0xFFF59E0B), 'تكلفة المواد'),
                const Spacer(),
                if (report != null)
                  Text(
                    'الصافي: ${formatCatalogMoney(report.netProfit)} ل.س من ${report.invoicesCount} فاتورة',
                    style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.textSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    final d = context.desktop;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: AppType.sans(fontSize: 11, color: d.textSecondary)),
      ],
    );
  }

  // ── لوحة الوصفة ─────────────────────────────────────────────────────────

  Widget _recipePanel(BuildContext context, TreatmentCatalogItem? item) {
    final d = context.desktop;
    if (item == null) {
      return const DesktopCard(
        child: SizedBox(
          height: 160,
          child: DesktopEmptyHint(icon: Icons.receipt_outlined, text: 'اختر حالة من اللائحة'),
        ),
      );
    }
    final margin = item.price > 0 ? (item.estimatedProfit / item.price * 100).round() : null;
    final notes = (item.notes ?? '').trim();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCard(
            glow: true,
            radius: 26,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DesktopEyebrow('وصفة الحالة'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(item.name,
                          style: AppType.kufi(fontSize: 17, fontWeight: FontWeight.w700, color: d.textPrimary)),
                    ),
                    if (!item.isActive) ...[
                      const SizedBox(width: 8),
                      DesktopBadge(label: 'معطّلة', colors: DesktopBadgeColors.neutral(d), fontSize: 10.5),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                DesktopBigAmount(value: formatCatalogMoney(item.price), fontSize: 26),
                const SizedBox(height: 14),
                Container(height: 1, color: d.cardBorder),
                if (item.materials.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text('لا مواد في هذه الوصفة.',
                        style: AppType.sans(fontSize: 12.5, color: d.textSecondary)),
                  )
                else
                  for (final m in item.materials) _RecipeMaterialRow(material: m),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text('تكلفة المواد (بأسعار المخزن اليوم)',
                          style: AppType.sans(fontSize: 12, color: d.textSecondary)),
                    ),
                    Text(formatCatalogMoney(item.materialsCost),
                        style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.amountOut)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('الربح المتوقَّع',
                          style: AppType.sans(fontSize: 12, color: d.textSecondary)),
                    ),
                    Text(
                      '${formatCatalogMoney(item.estimatedProfit)}${margin == null ? '' : ' · $margin٪'}',
                      style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w800, color: d.amountIn),
                    ),
                  ],
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes, style: AppType.sans(fontSize: 12, height: 1.6, color: d.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          DesktopCard(
            padding: const EdgeInsets.all(16),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'الوصفة اقتراح، والفاتورة سجل. ',
                    style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w800, color: d.textPrimary),
                  ),
                  TextSpan(
                    text: 'هذه التكلفة تتحرك مع أسعار المخزن؛ ما يُجمَّد على الفاتورة لحظة فتحها هو الرقم الملزِم.',
                    style: AppType.sans(fontSize: 11.5, height: 1.7, color: d.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DesktopCtaButton(
                  icon: Icons.edit_outlined,
                  label: 'تعديل الحالة',
                  expand: true,
                  onTap: () => _openItemSheet(item: item),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DesktopGhostButton(
                  label: item.isActive ? 'تعطيل' : 'تفعيل',
                  height: 44,
                  onTap: () => _toggleActive(item),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  final TreatmentCatalogItem item;
  final int? invoices;

  const _CatalogRow({required this.item, required this.invoices});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final margin = item.price > 0 ? (item.estimatedProfit / item.price) : 0.0;
    final short = item.materials.where((m) => m.isShort).length;
    Widget money(double v, {Color? color, bool strong = false}) => Text(
          formatCatalogMoney(v),
          style: AppType.sans(
            fontSize: 12.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: color ?? d.navInactiveFg,
          ),
        );

    return Opacity(
      opacity: item.isActive ? 1 : .55,
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                    ),
                    if (!item.isActive) ...[
                      const SizedBox(width: 6),
                      DesktopBadge(label: 'معطّلة', colors: DesktopBadgeColors.neutral(d), fontSize: 10),
                    ],
                    if (short > 0) ...[
                      const SizedBox(width: 6),
                      DesktopBadge(
                        label: short == 1 ? 'مادة ناقصة' : '$short مواد ناقصة',
                        colors: DesktopBadgeColors.waiting(d),
                        fontSize: 10,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.materials.length} مواد في الوصفة${invoices == null ? '' : ' · $invoices فاتورة في فترة التقرير'}',
                  style: AppType.sans(fontSize: 11, color: d.textMuted),
                ),
              ],
            ),
          ),
          Expanded(flex: 15, child: money(item.price, color: d.textPrimary, strong: true)),
          Expanded(flex: 15, child: money(item.materialsCost, color: d.amountOut)),
          Expanded(flex: 15, child: money(item.estimatedProfit, color: d.amountIn, strong: true)),
          Expanded(
            flex: 16,
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: margin.clamp(0, 1).toDouble(),
                      minHeight: 6,
                      color: margin >= .5 ? d.amountIn : (margin >= .25 ? d.linkFg : d.amountOut),
                      backgroundColor: d.rowDivider,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 38,
                  child: Text('${(margin * 100).round()}٪',
                      style: AppType.sans(fontSize: 12, fontWeight: FontWeight.w700, color: d.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBar extends StatelessWidget {
  final CatalogProfitRow row;
  final double maxBilled;

  const _ReportBar({required this.row, required this.maxBilled});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final net = row.netProfit < 0 ? 0.0 : row.netProfit;
    final materials = row.materialsCost < 0 ? 0.0 : row.materialsCost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: row.name,
                    style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: d.textPrimary),
                  ),
                  TextSpan(
                    text: ' (${row.invoicesCount})',
                    style: AppType.sans(fontSize: 11, color: d.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final scale = c.maxWidth / maxBilled;
                return Row(
                  children: [
                    Container(
                      width: (net * scale).clamp(0, c.maxWidth).toDouble(),
                      height: 10,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(999)),
                      ),
                    ),
                    Container(
                      width: (materials * scale).clamp(0, c.maxWidth).toDouble(),
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(999)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              formatCatalogMoney(row.netProfit),
              textAlign: TextAlign.end,
              style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeMaterialRow extends StatelessWidget {
  final CatalogMaterial material;

  const _RecipeMaterialRow({required this.material});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final available = material.availableQuantity;
    final String stock;
    final Color stockColor;
    if (available == null) {
      stock = 'غير مرتبطة بالمخزن';
      stockColor = d.textMuted;
    } else if (material.isShort) {
      stock = 'المتوفّر $available فقط';
      stockColor = d.amountOut;
    } else {
      stock = 'المتوفّر $available';
      stockColor = d.amountIn;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.rowDivider))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(material.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: d.textPrimary)),
                Text('${material.quantity} × ${formatCatalogMoney(material.unitCost)}',
                    style: AppType.sans(fontSize: 11, color: d.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatCatalogMoney(material.totalCost),
                  style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.navInactiveFg)),
              Text(stock, style: AppType.sans(fontSize: 10.5, fontWeight: FontWeight.w600, color: stockColor)),
            ],
          ),
        ],
      ),
    );
  }
}
