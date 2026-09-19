import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inventory_item.dart';
import '../models/treatment_catalog_item.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// شاشة "لائحة أسعار العلاجات" -- نقل صفحة treatment_catalog.html إلى
/// التطبيق، 2026-09-18.
///
/// المبدأ الذي يجب أن تحفظه هذه الشاشة كاملاً: **الوصفة اقتراح، والفاتورة
/// سجل.** تكلفة المواد والربح المعروضان هنا يُحسبان بأسعار المخزن لحظة
/// العرض ويتحركان معها، ولا يصيران رقماً ملزِماً إلا حين تُجمَّد على فاتورة
/// وقت التنفيذ. لذلك تُسمّى هنا "متوقَّعة" في كل موضع، ولا يُعرَض أي منها
/// بوصفه ربحاً محقَّقاً -- الربح المحقَّق مكانه تقرير الربحية بالأسفل
/// (ومصدره الفواتير المجمَّدة لا اللائحة).
///
/// المسار محروس باشتراك نشط فقط لا بباقة مدفوعة، فلا بطاقة قفل باقة هنا.

const List<String> _catalogArabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// أرقام لاتينية بفواصل آلاف -- الأرقام العربية-الهندية ممنوعة في المشروع.
final NumberFormat _catalogMoneyFormat = NumberFormat('#,##0', 'en_US');

String formatCatalogMoney(double value) {
  if (!value.isFinite) return '0';
  return _catalogMoneyFormat.format(value.round());
}

class TreatmentCatalogScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const TreatmentCatalogScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<TreatmentCatalogScreen> createState() => _TreatmentCatalogScreenState();
}

class _TreatmentCatalogScreenState extends State<TreatmentCatalogScreen> {
  List<TreatmentCatalogItem>? _items;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showInactive = true;

  /// تقرير الربحية ثانوي: فشلُه لا يمنع عرض اللائحة، تماماً كما تفعل شاشة
  /// المالية مع قائمة الأشهر. المسار حديث وقد لا يكون منشوراً على الخادم بعد.
  CatalogProfitReport? _report;
  bool _isReportLoading = false;
  int? _reportYear;
  int? _reportMonth;
  bool _reportAllTime = false;

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
      final items = await widget.apiService
          .fetchTreatmentCatalog(includeInactive: _showInactive);
      if (!mounted) return;
      setState(() {
        _items = items;
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
        _errorMessage = 'تعذر تحميل لائحة الأسعار. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isReportLoading = true);
    try {
      final report = await widget.apiService.fetchTreatmentCatalogProfitReport(
        year: _reportYear,
        month: _reportMonth,
        allTime: _reportAllTime,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _isReportLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _isReportLoading = false;
      });
    }
  }

  String get _reportPeriodLabel {
    if (_reportAllTime) return 'كل الفترات';
    final now = DateTime.now();
    final year = _reportYear ?? now.year;
    final month = _reportMonth ?? now.month;
    return '${_catalogArabicMonths[month - 1]} $year';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openItemSheet({TreatmentCatalogItem? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CatalogItemSheet(apiService: widget.apiService, item: item),
    );
    if (saved == true) {
      _toast(item == null ? 'تمت إضافة الحالة' : 'تم تحديث الحالة');
      _load();
    }
  }

  Future<void> _toggleActive(TreatmentCatalogItem item) async {
    try {
      await widget.apiService
          .updateTreatmentCatalogItem(item.id, isActive: !item.isActive);
      if (!mounted) return;
      _toast(item.isActive ? 'تم تعطيل الحالة' : 'تم تفعيل الحالة');
      _load();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } catch (_) {
      _toast('تعذر تغيير حالة التسعيرة.');
    }
  }

  Future<void> _confirmDelete(TreatmentCatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surface.sheetBg,
        title: Text('حذف «${item.name}»؟',
            style: AppType.kufi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.surface.textPrimary)),
        content: Text(
          'الفواتير التي نُفِّذت بهذه الحالة لا تتأثر: عنوانها وسعرها '
          'وموادها مجمَّدة عليها. الحذف يُخرِجها من اللائحة فقط.',
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
      await widget.apiService.deleteTreatmentCatalogItem(item.id);
      if (!mounted) return;
      _toast('تم حذف الحالة');
      _load();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } catch (_) {
      _toast('تعذر حذف الحالة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final items = _items ?? const <TreatmentCatalogItem>[];
    return Scaffold(
      backgroundColor: surf.pageBg,
      appBar: AppBar(
        backgroundColor: surf.cardBg,
        surfaceTintColor: Colors.transparent,
        title: Text('لائحة أسعار العلاجات',
            style: AppType.kufi(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: surf.textPrimary)),
      ),
      floatingActionButton: GradientFab(onPressed: () => _openItemSheet()),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            LoadingErrorEmpty(
              isLoading: _isLoading,
              errorMessage: _errorMessage,
              isLocked: false,
              onRetry: _load,
              child: _buildContent(items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<TreatmentCatalogItem> items) {
    final surf = context.surface;
    final active = items.where((i) => i.isActive).toList();
    final avgPrice = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (sum, i) => sum + i.price) / active.length;
    final avgMaterials = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (sum, i) => sum + i.materialsCost) /
            active.length;
    final avgProfit = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (sum, i) => sum + i.estimatedProfit) /
            active.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmartStatCard(stats: [
          SmartStat(
            value: formatCatalogMoney(avgPrice),
            label: 'متوسط التسعيرة',
            icon: Icons.sell_outlined,
            iconColor: AppColors.indigo700,
            iconBackground: AppColors.indigo50,
          ),
          SmartStat(
            value: formatCatalogMoney(avgMaterials),
            label: 'متوسط تكلفة المواد',
            icon: Icons.inventory_2_outlined,
            iconColor: AppColors.amber800text,
            iconBackground: AppColors.amber100,
          ),
          SmartStat(
            value: formatCatalogMoney(avgProfit),
            label: 'متوسط الربح المتوقَّع',
            icon: Icons.trending_up,
            iconColor: AppColors.emerald700text,
            iconBackground: AppColors.emerald50,
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'المتوسطات للحالات المفعَّلة، وتكلفة المواد محسوبة بأسعار المخزن '
          'الحالية فتتحرك معها. الرقم الملزِم هو ما يُجمَّد على الفاتورة وقت '
          'التنفيذ.',
          style: TextStyle(color: surf.textMuted, fontSize: 11.5, height: 1.8),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('الحالات المسجَّلة',
                style: AppType.kufi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: surf.textPrimary)),
            const SizedBox(width: 8),
            Text(
              items.length == 1 ? 'حالة واحدة' : '${items.length} حالة',
              style: TextStyle(
                  color: surf.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Switch(
              value: _showInactive,
              onChanged: (value) {
                setState(() => _showInactive = value);
                _load();
              },
            ),
            Expanded(
              child: Text('إظهار الحالات المعطَّلة',
                  style: TextStyle(fontSize: 12.5, color: surf.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.price_change_outlined,
                      size: 44, color: surf.textMuted),
                  const SizedBox(height: 10),
                  Text('لا حالات في اللائحة بعد',
                      style: TextStyle(color: surf.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    'سجّل تسعيرة كل علاج ومواده المعتادة، فتُفتَح فواتيره '
                    'بضغطة وتُخصَم مواده تلقائياً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: surf.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          ...items.map(_buildItemCard),
        const SizedBox(height: 10),
        _buildProfitReport(),
      ],
    );
  }

  Widget _buildItemCard(TreatmentCatalogItem item) {
    final surf = context.surface;
    final margin = item.estimatedMarginPercent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.kufi(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: surf.textPrimary)),
                ),
                const SizedBox(width: 8),
                item.isActive
                    ? SoftStatusPill(
                        label: 'مفعّلة',
                        foreground: surf.pillPaidFg,
                        background: surf.pillPaidBg,
                        border: surf.pillPaidBorder,
                      )
                    : SoftStatusPill(
                        label: 'معطّلة',
                        foreground: surf.pillNoneFg,
                        background: surf.pillNoneBg,
                        border: surf.pillNoneBorder,
                      ),
              ],
            ),
            if (item.notes != null) ...[
              const SizedBox(height: 4),
              Text(item.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: surf.textMuted)),
            ],
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: surf.iconBoxBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: surf.iconBoxBorder),
              ),
              child: Row(
                children: [
                  _figure('التسعيرة', formatCatalogMoney(item.price),
                      surf.textPrimary),
                  Container(width: 1, height: 26, color: surf.divider),
                  _figure('تكلفة المواد', formatCatalogMoney(item.materialsCost),
                      AppColors.amber800text),
                  Container(width: 1, height: 26, color: surf.divider),
                  _figure(
                    'الربح المتوقَّع',
                    margin == null
                        ? formatCatalogMoney(item.estimatedProfit)
                        : '${formatCatalogMoney(item.estimatedProfit)} · ${margin.round()}%',
                    item.estimatedProfit < 0
                        ? AppColors.rose700text
                        : AppColors.emerald700text,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 15, color: surf.textMuted),
                const SizedBox(width: 6),
                Text('المواد المعتادة',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: surf.textSecondary)),
                const Spacer(),
                if (item.hasShortMaterial)
                  SoftStatusPill(
                    label: 'المخزن لا يكفي',
                    foreground: surf.warnFg,
                    background: surf.warnBg,
                    border: surf.warnBorder,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!item.hasMaterials)
              Text('بلا مواد مرتبطة',
                  style: TextStyle(fontSize: 12, color: surf.textMuted))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final material in item.materials)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: material.isShort ? surf.warnBg : surf.chipBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: material.isShort
                                ? surf.warnBorder
                                : surf.chipBorder),
                      ),
                      child: Text(
                        '${material.itemName} × ${material.quantity}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: material.isShort ? surf.warnFg : surf.chipFg),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                SoftIconButton(
                  icon: Icons.edit_outlined,
                  foreground: AppColors.indigo700,
                  tooltip: 'تعديل الحالة',
                  onPressed: () => _openItemSheet(item: item),
                ),
                const SizedBox(width: 8),
                SoftIconButton(
                  icon: item.isActive
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                  foreground: item.isActive
                      ? AppColors.amber800text
                      : AppColors.emerald700text,
                  tooltip: item.isActive ? 'تعطيل الحالة' : 'تفعيل الحالة',
                  onPressed: () => _toggleActive(item),
                ),
                const Spacer(),
                SoftIconButton(
                  icon: Icons.delete_outline,
                  foreground: AppColors.rose700text,
                  tooltip: 'حذف الحالة',
                  onPressed: () => _confirmDelete(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _figure(String label, String value, Color valueColor) {
    final surf = context.surface;
    return Expanded(
      child: Column(
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: surf.textMuted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitReport() {
    final surf = context.surface;
    final report = _report;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('ربحية العلاجات',
                  style: AppType.kufi(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary)),
              const Spacer(),
              _buildReportPeriodButton(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'محسوبة بتاريخ إنشاء الفاتورة لا بتاريخ تحصيلها: ربحية عمل لا '
            'تدفّق نقدي. التدفّق النقدي في شاشة التقارير المالية.',
            style: TextStyle(fontSize: 11, color: surf.textMuted, height: 1.8),
          ),
          const SizedBox(height: 10),
          if (_isReportLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else if (report == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('تقرير الربحية غير متاح الآن.',
                  style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
            )
          else ...[
            Row(
              children: [
                _figure('عدد الفواتير', '${report.invoicesCount}',
                    surf.textPrimary),
                Container(width: 1, height: 26, color: surf.divider),
                _figure('المفوتَر', formatCatalogMoney(report.billed),
                    surf.textPrimary),
                Container(width: 1, height: 26, color: surf.divider),
                _figure('صافي الربح', formatCatalogMoney(report.netProfit),
                    report.netProfit < 0
                        ? AppColors.rose700text
                        : AppColors.emerald700text),
              ],
            ),
            if (report.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text('لا فواتير في هذه الفترة.',
                    style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
              )
            else
              for (final row in report.items)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(row.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: surf.textPrimary)),
                          ),
                          Text(
                            '${formatCatalogMoney(row.netProfit)} ل.س',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: row.netProfit < 0
                                    ? AppColors.rose700text
                                    : AppColors.emerald700text),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${row.invoicesCount} فاتورة · مفوتَر '
                        '${formatCatalogMoney(row.billed)} · مواد '
                        '${formatCatalogMoney(row.materialsCost)}',
                        style: TextStyle(fontSize: 10.5, color: surf.textMuted),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportPeriodButton() {
    final surf = context.surface;
    final now = DateTime.now();
    final months = <({int year, int month})>[
      for (var i = 0; i < 12; i += 1)
        (
          year: DateTime(now.year, now.month - i, 1).year,
          month: DateTime(now.year, now.month - i, 1).month,
        ),
    ];
    return PopupMenuButton<String>(
      color: surf.sheetBg,
      tooltip: 'فترة التقرير',
      onSelected: (value) {
        setState(() {
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
      itemBuilder: (_) => [
        for (final entry in months)
          PopupMenuItem(
            value: '${entry.year}-${entry.month}',
            child: Text(
                '${_catalogArabicMonths[entry.month - 1]} ${entry.year}',
                style: TextStyle(color: surf.textPrimary)),
          ),
        PopupMenuItem(
          value: 'all',
          child: Text('كل الفترات', style: TextStyle(color: surf.textPrimary)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: surf.chipBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: surf.chipBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_reportPeriodLabel,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: surf.chipFg)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 16, color: surf.chipFg),
          ],
        ),
      ),
    );
  }
}

/// ========================= ورقة الحالة العلاجية =========================

class _CatalogItemSheet extends StatefulWidget {
  final ApiService apiService;
  final TreatmentCatalogItem? item;

  const _CatalogItemSheet({required this.apiService, this.item});

  @override
  State<_CatalogItemSheet> createState() => _CatalogItemSheetState();
}

class _CatalogItemSheetState extends State<_CatalogItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _notesController;

  /// نسخة قابلة للتحرير من وصفة الحالة. تُرسَل كاملةً عند الحفظ مع علم
  /// replaceMaterials، لأن الخادم يميّز "لا تمسّ الوصفة" من "أفرِغها".
  late List<CatalogMaterial> _materials;

  List<InventoryItem>? _inventory;
  bool _isSaving = false;
  String? _error;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _priceController =
        TextEditingController(text: item == null ? '' : _trimZeros(item.price));
    _notesController = TextEditingController(text: item?.notes ?? '');
    _materials = [...(item?.materials ?? const <CatalogMaterial>[])];
    _loadInventory();
  }

  static String _trimZeros(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// المخزن محروس بباقة Premium فيعيد 403 لحساب أدنى. ذلك ليس خطأ يُعرَض:
  /// تبقى إضافة المواد بالاسم متاحة، وتختفي قائمة الاختيار وحدها.
  Future<void> _loadInventory() async {
    try {
      final items = await widget.apiService.fetchInventory();
      if (!mounted) return;
      setState(() => _inventory = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inventory = const []);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _estimatedMaterialsCost => _materials.fold<double>(
      0,
      (sum, material) =>
          sum + (material.unitCost * material.quantity));

  Future<void> _addMaterial() async {
    final added = await showModalBottomSheet<CatalogMaterial>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaterialPickerSheet(inventory: _inventory ?? const []),
    );
    if (added == null) return;
    setState(() {
      // نفس المادة مرتين تُدمَج بجمع الكمية بدل سطرين متكرّرين: الخادم
      // يخصم السطرين كليهما، لكن الطبيب يقرأ سطرين كأنهما مادتان مختلفتان.
      final index = _materials.indexWhere((m) =>
          (m.inventoryItemId != null &&
              m.inventoryItemId == added.inventoryItemId) ||
          (m.inventoryItemId == null &&
              added.inventoryItemId == null &&
              m.itemName == added.itemName));
      if (index >= 0) {
        final existing = _materials[index];
        _materials[index] = CatalogMaterial(
          id: existing.id,
          inventoryItemId: existing.inventoryItemId,
          itemName: existing.itemName,
          quantity: existing.quantity + added.quantity,
          unitCost: existing.unitCost,
          totalCost: existing.unitCost * (existing.quantity + added.quantity),
          availableQuantity: existing.availableQuantity,
        );
      } else {
        _materials.add(added);
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    try {
      if (_isEdit) {
        await widget.apiService.updateTreatmentCatalogItem(
          widget.item!.id,
          name: _nameController.text.trim(),
          price: price,
          notes: _notesController.text.trim(),
          // دائماً true في التحرير: الورقة تعرض الوصفة كاملةً وتُحرِّرها،
          // فحالتها المعروضة هي الحقيقة المقصودة -- بما فيها إفراغها.
          replaceMaterials: true,
          materials: _materials,
        );
      } else {
        await widget.apiService.createTreatmentCatalogItem(
          name: _nameController.text.trim(),
          price: price,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          materials: _materials,
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
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final profit = price - _estimatedMaterialsCost;
    return _SheetShell(
      title: _isEdit ? 'تعديل الحالة العلاجية' : 'إضافة حالة علاجية جديدة',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetField(
              label: 'اسم الحالة',
              controller: _nameController,
              hint: 'حشوة ضوئية سطح واحد',
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'اسم الحالة مطلوب' : null,
            ),
            _SheetField(
              label: 'تسعيرة العلاج (ل.س)',
              controller: _priceController,
              hint: '0',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'التسعيرة مطلوبة';
                final parsed = double.tryParse(text);
                if (parsed == null || !parsed.isFinite) return 'اكتب رقماً صحيحاً';
                if (parsed < 0) return 'التسعيرة لا تكون سالبة';
                return null;
              },
            ),
            _SheetField(
              label: 'ملاحظة (اختياري)',
              controller: _notesController,
              hint: 'تفاصيل تخص هذه الحالة',
              maxLines: 2,
            ),
            Row(
              children: [
                Text('المواد المعتادة',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: surf.heroCaption)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addMaterial,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('إضافة المادة'),
                ),
              ],
            ),
            if (_materials.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('لا مواد لهذه الحالة.',
                    style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
              )
            else
              for (var i = 0; i < _materials.length; i += 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(11, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: surf.iconBoxBg,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: surf.iconBoxBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_materials[i].itemName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: surf.textPrimary)),
                              Text(
                                _materials[i].unitCost > 0
                                    ? '${_materials[i].quantity} × ${formatCatalogMoney(_materials[i].unitCost)} ل.س'
                                    : '${_materials[i].quantity} وحدة',
                                style: TextStyle(
                                    fontSize: 10.5, color: surf.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline,
                              size: 19, color: AppColors.rose700text),
                          tooltip: 'إزالة المادة',
                          onPressed: () =>
                              setState(() => _materials.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: surf.chipBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: surf.chipBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'تكلفة المواد ${formatCatalogMoney(_estimatedMaterialsCost)} ل.س',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: surf.chipFg),
                    ),
                  ),
                  Text(
                    'ربح متوقَّع ${formatCatalogMoney(profit)} ل.س',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: profit < 0
                            ? AppColors.rose700text
                            : AppColors.emerald700text),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: AppColors.rose700text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            GradientButton(
              label: _isEdit ? 'حفظ التعديلات' : 'إضافة الحالة',
              icon: Icons.check,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _submit,
            ),
            const SizedBox(height: 8),
            Text(
              'المواد هنا اقتراح يُملأ تلقائياً عند فتح فاتورة بهذه الحالة، '
              'ويبقى قابلاً للتعديل على كل فاتورة. لا يُخصَم شيء من المخزن '
              'الآن.',
              textAlign: TextAlign.center,
              style: TextStyle(color: surf.textMuted, fontSize: 11.5, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// ====================== ورقة اختيار مادة من المخزن ======================

class _MaterialPickerSheet extends StatefulWidget {
  final List<InventoryItem> inventory;

  const _MaterialPickerSheet({required this.inventory});

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  InventoryItem? _selected;
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (quantity <= 0) {
      setState(() => _error = 'الكمية يجب أن تكون 1 على الأقل');
      return;
    }
    final item = _selected;
    if (item == null && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'اختر مادة من المخزن أو اكتب اسمها');
      return;
    }
    Navigator.of(context).pop(CatalogMaterial(
      inventoryItemId: item?.id,
      itemName: item?.itemName ?? _nameController.text.trim(),
      quantity: quantity,
      unitCost: item?.unitCost ?? 0,
      totalCost: (item?.unitCost ?? 0) * quantity,
      availableQuantity: item?.quantity,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return _SheetShell(
      title: 'إضافة مادة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('المادة من المخزن',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: surf.heroCaption)),
          const SizedBox(height: 6),
          if (widget.inventory.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'لا توجد مواد في مخزنك. أضِف المادة إلى «مخزن المواد» أولاً، '
                'ثم اربطها بهذه الحالة -- الوصفة تربط مواد موجودة ولا تُنشئ '
                'مواد جديدة.',
                style: TextStyle(color: surf.textMuted, fontSize: 12, height: 1.7),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: surf.fieldBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: surf.fieldBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<InventoryItem?>(
                  value: _selected,
                  isExpanded: true,
                  hint: Text('اختر مادة',
                      style: TextStyle(color: surf.fieldHint)),
                  dropdownColor: surf.sheetBg,
                  borderRadius: BorderRadius.circular(14),
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: surf.textSecondary),
                  items: [
                    const DropdownMenuItem<InventoryItem?>(
                      value: null,
                      child: Text('-- بكتابة الاسم --', textAlign: TextAlign.right),
                    ),
                    for (final item in widget.inventory)
                      DropdownMenuItem<InventoryItem?>(
                        value: item,
                        child: Text(
                          item.unitCost > 0
                              ? '${item.itemName} (${formatCatalogMoney(item.unitCost)} ل.س)'
                              : item.itemName,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _selected = value;
                    _error = null;
                  }),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_selected == null)
            _SheetField(
              label: 'اسم المادة كما هو في المخزن',
              controller: _nameController,
              hint: 'مادة حشو ضوئي',
            ),
          _SheetField(
            label: 'الكمية',
            controller: _quantityController,
            hint: '1',
            keyboardType: TextInputType.number,
          ),
          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(
                    color: AppColors.rose700text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          GradientButton(
            label: 'إضافة',
            icon: Icons.add,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          Text(
            'المادة يجب أن تكون مسجَّلة في مخزنك مسبقاً: الاسم هنا طريق بديل '
            'للاختيار لا طريق لإنشاء مادة جديدة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: surf.textMuted, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    );
  }
}

/// ========================= عناصر مشتركة للأوراق =========================
///
/// نسخة مستقلة عن مثيلتها في clinic_doctors_screen.dart عن قصد: كلٌّ خاصّ
/// بشاشته، والمشروع يتبع هذا النمط أصلاً (انظر _normalizeWhatsappPhone
/// المكرَّرة في ملفّين). توحيدهما في app_widgets يخلط تبويبات لا تتشارك
/// شيئاً غير شكل الورقة.

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
  final ValueChanged<String>? onChanged;
  final int maxLines;

  const _SheetField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.validator,
    this.onChanged,
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
            onChanged: onChanged,
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
