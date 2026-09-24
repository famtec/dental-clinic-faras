part of 'inventory_screen.dart';

/// صفحة «المخزن» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// الكانفاس لا يرسم هذه الصفحة (المخزن عنصر سابع أُضيف للشريط بقرار
/// المستخدم)، فبُنيت بلغة بقية صفحات الغلاف: شريط مؤشرات، جدول بشرائح
/// تصفية وبحث، وبطاقة جانبية لما يحتاج إعادة طلب. تخطيطٌ آخر لنفس
/// [_InventoryScreenState]: نفس التحميل ونفس ورقة المادة ونفس الحذف.
///
/// «قيمة المخزون» تُجمع من المواد التي لها تكلفة وحدة مسجّلة وحدها، ويُذكر
/// عدد المواد بلا تكلفة بجانبها -- فلا يُقرأ الرقم كقيمة المخزن كاملاً.
extension _InventoryDesktop on _InventoryScreenState {
  static const double _sideWidth = 320;

  List<InventoryItem> _filtered(List<InventoryItem> items) {
    final query = _desktopQuery.trim();
    return items.where((item) {
      if (query.isNotEmpty && !item.itemName.contains(query)) return false;
      if (_desktopFilter == 1) return item.isLowStock;
      if (_desktopFilter == 2) return !item.isLowStock;
      return true;
    }).toList()
      ..sort((a, b) {
        // الناقص أولاً: هو ما جاء الطبيب ليراه.
        if (a.isLowStock != b.isLowStock) return a.isLowStock ? -1 : 1;
        return a.itemName.compareTo(b.itemName);
      });
  }

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    if (_isLoading && _items == null) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (_isPremiumLocked) {
      return DesktopLockedFeature(
        tierLabel: 'PREMIUM',
        title: 'مخزن المواد متاح في الباقة الفخمة',
        // النصّ ثابت لا رسالة الخادم: رسالة الخادم تحمل «(Premium)» داخل
        // الجملة فتنقلب عند التفاف السطر، والشارة فوقها تحمل الاسم أصلاً.
        message: 'إدارة المخزن والمستودع الطبي متاحة حصرياً لمشتركي الباقة الفخمة: '
            'كميات المواد وحدود التنبيه وتكلفتها، وربطها بالمصاريف ووصفات العلاج.',
        onContact: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ContactDeveloperScreen()),
        ),
        onActivate: widget.apiService.tryUpgradeTier,
        onActivated: _load,
      );
    }
    if (_errorMessage != null && _items == null) {
      return DesktopErrorState(message: _errorMessage!, onRetry: _load);
    }

    final items = _items ?? const <InventoryItem>[];
    final low = items.where((i) => i.isLowStock).toList()
      ..sort((a, b) => (a.quantity - a.minAlertQuantity).compareTo(b.quantity - b.minAlertQuantity));

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الكميات تنقص تلقائياً مع مواد الفواتير وتزيد مع مصاريف الشراء',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              DesktopCtaButton(icon: Icons.add, label: 'مادة جديدة', onTap: _openAddItemSheet),
            ],
          ),
          const SizedBox(height: 16),
          _kpiStrip(context, items, low.length),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _table(context, items, low.length)),
                const SizedBox(width: 20),
                SizedBox(width: _InventoryDesktop._sideWidth, child: _reorderCard(context, low)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiStrip(BuildContext context, List<InventoryItem> items, int lowCount) {
    final d = context.desktop;
    final costed = items.where((i) => i.hasUnitCost).toList();
    final value = costed.fold<double>(0, (t, i) => t + i.unitCost * i.quantity);
    final uncosted = items.length - costed.length;
    return Row(
      children: [
        Expanded(
          child: DesktopKpiCard(label: 'مواد مسجّلة', value: '${items.length}', highlight: true),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'تحت حدّ التنبيه',
            value: '$lowCount',
            valueColor: lowCount > 0 ? d.amountOut : d.amountIn,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'قيمة المخزون بتكلفة الوحدة',
            value: desktopMoney.format(value),
            suffix: 'ل.س',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'مواد بلا تكلفة وحدة',
            value: '$uncosted',
            suffix: uncosted > 0 ? 'لا تدخل في القيمة' : null,
            valueColor: uncosted > 0 ? d.textSecondary : null,
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<InventoryItem> items, int lowCount) {
    final d = context.desktop;
    final rows = _filtered(items);
    const labels = ['الكل', 'ناقصة', 'متوفرة'];
    final counts = [items.length, lowCount, items.length - lowCount];

    return DesktopTablePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                // البحث ينكمش قبل الشرائح والزر: على نافذة 1280px لا يتّسع
                // الثلاثة بعرضها الكامل في سطر واحد.
                Flexible(
                  child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: SizedBox(
                  height: 40,
                  child: TextField(
                    onChanged: (v) => _update(() => _desktopQuery = v),
                    style: AppType.sans(fontSize: 13, color: d.fieldFg),
                    cursorColor: d.linkFg,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ابحث باسم المادة...',
                      hintStyle: AppType.sans(fontSize: 13, color: d.fieldHint),
                      prefixIcon: Icon(Icons.search, size: 18, color: d.fieldHint),
                      filled: true,
                      fillColor: d.fieldBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: d.fieldBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: d.linkFg, width: 1.6),
                      ),
                    ),
                  ),
                  ),
                  ),
                ),
                const SizedBox(width: 12),
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  DesktopChip(
                    label: labels[i],
                    count: counts[i],
                    selected: _desktopFilter == i,
                    onTap: () => _update(() => _desktopFilter = i),
                  ),
                ],
              ],
            ),
          ),
          const DesktopTableHeader(columns: [
            (label: 'المادة', flex: 30, align: TextAlign.start),
            (label: 'الكمية', flex: 22, align: TextAlign.start),
            (label: 'حدّ التنبيه', flex: 11, align: TextAlign.start),
            (label: 'تكلفة الوحدة', flex: 13, align: TextAlign.start),
            (label: 'القيمة', flex: 13, align: TextAlign.start),
          ], trailingWidth: _InventoryRow.actionsWidth),
          Expanded(
            child: rows.isEmpty
                ? DesktopEmptyHint(
                    icon: items.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                    text: items.isEmpty ? 'لا توجد مواد مسجّلة بعد' : 'لا نتائج مطابقة',
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _InventoryRow(
                      item: rows[i],
                      onEdit: () => _openEditItemSheet(rows[i]),
                      onDelete: () => _confirmDelete(rows[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reorderCard(BuildContext context, List<InventoryItem> low) {
    final d = context.desktop;
    return DesktopCard(
      glow: true,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DesktopEyebrow('تحتاج إعادة طلب'),
          const SizedBox(height: 6),
          Text(
            low.isEmpty ? 'كل المواد فوق حدّ التنبيه' : '${low.length} ${low.length == 1 ? 'مادة' : 'مواد'} عند الحدّ أو دونه',
            style: AppType.kufi(fontSize: 15, fontWeight: FontWeight.w700, color: d.textPrimary),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: d.cardBorder),
          Expanded(
            child: low.isEmpty
                ? Center(child: Icon(Icons.check_circle_outline, size: 40, color: d.amountIn))
                : ListView(
                    padding: const EdgeInsets.only(top: 4),
                    children: [
                      for (final item in low)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: d.rowDivider)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.itemName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppType.sans(
                                            fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                                    Text('الحدّ ${item.minAlertQuantity}',
                                        style: AppType.sans(fontSize: 11, color: d.textMuted)),
                                  ],
                                ),
                              ),
                              Text('${item.quantity}',
                                  style: AppType.kufi(
                                      fontSize: 16, fontWeight: FontWeight.w800, color: d.amountOut)),
                              const SizedBox(width: 10),
                              DesktopSquareButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'تعديل الكمية',
                                size: 30,
                                onTap: () => _openEditItemSheet(item),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            'المصروف المسجّل في المالية مع خيار «إضافة إلى المخزن» يزيد الكمية هنا تلقائياً.',
            style: AppType.sans(fontSize: 11.5, height: 1.6, color: d.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InventoryRow({required this.item, required this.onEdit, required this.onDelete});

  /// زرّان بعرض 30 وفاصل 6 وهامش 10 -- انظر [DesktopTableHeader.trailingWidth].
  static const double actionsWidth = 76;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final low = item.isLowStock;
    // الشريط مقياسه ثلاثة أضعاف حدّ التنبيه: عند الحدّ ثلثٌ، وفوق الثلاثة
    // أضعاف ممتلئ. بلا حدّ مسجّل لا مقياس، فيمتلئ إن وُجدت كمية.
    final scale = item.minAlertQuantity > 0 ? item.minAlertQuantity * 3 : 1;
    final fill = (item.quantity / scale).clamp(0, 1).toDouble();
    final colors = low ? DesktopBadgeColors.waiting(d) : DesktopBadgeColors.done(d);

    return DesktopTableRow(
      onDoubleTap: onEdit,
      child: Row(
        children: [
          Expanded(
            flex: 30,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: low ? colors.bg : d.iconBoxBg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: low ? colors.border : d.iconBoxBorder),
                  ),
                  child: Icon(
                    low ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                    size: 17,
                    color: low ? colors.fg : d.iconBoxFg,
                  ),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(item.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(fontSize: 13, fontWeight: FontWeight.w700, color: d.textPrimary)),
                ),
                if (item.isPendingSync) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'بانتظار الاتصال للمزامنة',
                    child: Icon(Icons.cloud_off_outlined, size: 14, color: d.warnBoxFg),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 22,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('${item.quantity}',
                      style: AppType.sans(
                          fontSize: 13, fontWeight: FontWeight.w800, color: low ? d.amountOut : d.textPrimary)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: fill,
                      minHeight: 6,
                      color: low ? const Color(0xFFF59E0B) : d.amountIn,
                      backgroundColor: d.rowDivider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            flex: 11,
            child: Text('${item.minAlertQuantity}',
                style: AppType.sans(fontSize: 12.5, color: d.navInactiveFg)),
          ),
          Expanded(
            flex: 13,
            child: Text(item.hasUnitCost ? formatUnitCostAr(item.unitCost) : '—',
                style: AppType.sans(fontSize: 12.5, color: item.hasUnitCost ? d.navInactiveFg : d.textMuted)),
          ),
          Expanded(
            flex: 13,
            child: Text(
              item.hasUnitCost ? desktopMoney.format(item.unitCost * item.quantity) : '—',
              style: AppType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: item.hasUnitCost ? d.textPrimary : d.textMuted),
            ),
          ),
          SizedBox(
            width: actionsWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DesktopSquareButton(icon: Icons.edit_outlined, tooltip: 'تعديل', size: 30, onTap: onEdit),
                const SizedBox(width: 6),
                DesktopSquareButton(icon: Icons.delete_outline, tooltip: 'حذف', size: 30, onTap: onDelete),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
