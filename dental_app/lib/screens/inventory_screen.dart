import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../models/inventory_item.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_widgets.dart';
import 'contact_developer_screen.dart';

part 'inventory_desktop.dart';

/// "مخزن المواد" -- تطابق inventory.html بالموقع: ميزة Premium حصراً (حارس
/// require_premium_user_by_email في main.py يرجع 403 بدل 402 المعتاد -- انظر
/// ApiException.isPremiumRequired). غير المشتركين يرون بطاقة قفل بدل القائمة،
/// بنفس رسالة الموقع حرفياً.
/// تنسيق تكلفة الوحدة -- أرقام **لاتينية** إلزاماً بلا استثناء في كل هذا
/// المشروع (انظر جولة 2026-08-25 التي حوّلت الموقع كله من الأرقام الهندية)،
/// ولهذا اللغة 'en_US' لا 'ar': النمط نفسه ونفس حدّ المنزلتين الذي يعرضه
/// formatUnitCost في inventory.html بالموقع.
final NumberFormat _unitCostFormat = NumberFormat('#,##0.##', 'en_US');

String formatUnitCostAr(num? value) {
  final number = (value ?? 0).toDouble();
  if (!number.isFinite) return '0';
  return _unitCostFormat.format(number);
}

/// نتيجة حاسبة تكلفة الجرعة: قيمة صالحة أو رسالة خطأ عربية جاهزة للعرض.
class DoseCostOutcome {
  final double? value;
  final int? doses;
  final String? error;

  const DoseCostOutcome.ok(this.value, this.doses) : error = null;
  const DoseCostOutcome.failed(this.error) : value = null, doses = null;

  bool get isValid => error == null && value != null;
}

/// حاسبة تكلفة الجرعة -- منقولة حرفياً عن computeDoseCost في inventory.html.
///
/// عبوة الكومبوزت تُشترى مرة وتُستهلك على عشرات الحشوات، والكمية في المخزن
/// عدد صحيح فلا تُخصم بالكسور. الحل أن تكون الوحدة المسجَّلة **الجرعة** لا
/// العبوة، وهذه الحاسبة تحوّل السعر بلا حساب يدوي. حسابية بحتة: لا ترسل
/// شيئاً ولا تحفظ شيئاً.
///
/// ★ انحراف واحد مقصود عن الموقع، لا تُرجِعه: في JS قيمة `Number('')` صفر،
/// فالموقع يقرأ **سعر عبوة فارغاً** كأنه صفر ويعرض "تكلفة الجرعة: 0 ل.س"
/// (يظهر فقط إن عبّأ الطبيب عدد الجرعات وحده، لأن renderDoseCalc تتجاهل
/// الحالتين الفارغتين معاً). هنا يُرفَض الفارغ برسالة صريحة: حقل فارغ ليس
/// سعراً صفراً. تحقَّق آلياً: 90 حالة من 90 مطابقة للموقع عند تعبئة الحقلين،
/// والفرق في الحالة الفارغة وحدها. والموقع يستحق نفس الإصلاح.
DoseCostOutcome computeDoseCost(String packPriceText, String dosesText) {
  final packPrice = double.tryParse(packPriceText.trim());
  final doses = double.tryParse(dosesText.trim());
  if (packPrice == null || !packPrice.isFinite || packPrice < 0) {
    return const DoseCostOutcome.failed('سعر العبوة يجب أن يكون رقماً صفراً أو أكثر.');
  }
  if (doses == null || !doses.isFinite || doses <= 0) {
    return const DoseCostOutcome.failed('عدد الجرعات يجب أن يكون أكبر من صفر.');
  }
  // تقريب لمنزلتين: عمود unit_cost في القاعدة Numeric(12,2)، فرقم بثلاث
  // منازل سيُقرَّب هناك على أي حال ويجعل ما يراه الطبيب مخالفاً لما يُحفَظ.
  final value = (packPrice / doses * 100).round() / 100;
  return DoseCostOutcome.ok(value, doses.round());
}

class InventoryScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const InventoryScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem>? _items;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPremiumLocked = false;

  // ── سطح المكتب (انظر inventory_desktop.dart) ──
  String _desktopQuery = '';
  /// 0 = الكل، 1 = ناقصة، 2 = متوفرة.
  int _desktopFilter = 0;

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
    });
    try {
      final items = await widget.apiService.fetchInventory();
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
        _isPremiumLocked = e.isPremiumRequired || e.isSubscriptionBlocked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل مخزن المواد. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddItemSheet() async {
    final added = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventoryItemSheet(apiService: widget.apiService),
    );
    if (added == true) _load();
  }

  Future<void> _openEditItemSheet(InventoryItem item) async {
    final result = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventoryItemSheet(apiService: widget.apiService, item: item),
    );
    if (result == true) _load();
  }

  Future<void> _confirmDelete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المادة'),
        content: Text('هل تريد حذف "${item.itemName}" من المخزن؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف', style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteInventoryItem(item.id);
      _load();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر حذف المادة. حاول مرة أخرى.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopShell) return _buildDesktop(context);
    final items = _items ?? [];
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
                    padding: EdgeInsets.fromLTRB(20, 16, 20, floatingNavInset(context) + 84),
                    child: LoadingErrorEmpty(
                      isLoading: _isLoading,
                      errorMessage: _isPremiumLocked ? null : _errorMessage,
                      isLocked: false,
                      onRetry: _load,
                      child: _isPremiumLocked
                          ? _buildPremiumLockCard()
                          : items.isEmpty
                              ? Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 48),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.inventory_2_outlined,
                                            size: 44,
                                            color: context.surface.textMuted),
                                        const SizedBox(height: 10),
                                        Text(
                                          'لا توجد مواد مسجّلة بعد',
                                          style: TextStyle(
                                              color: context
                                                  .surface.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  children: items.map(_buildItemCard).toList(),
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isPremiumLocked)
            PositionedDirectional(
              bottom: floatingNavInset(context) + 16,
              end: 20,
              child: GradientFab(onPressed: _openAddItemSheet),
            ),
        ],
      ),
    );
  }

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
            child: const Text('PREMIUM PLAN',
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
                'إدارة المخزن والمستودع الطبي متاحة حصرياً لمشتركي الباقة الفخمة (Premium).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.6),
          ),
          const SizedBox(height: 6),
          Text(
            'تواصل مع المطور لتفعيل الباقة الفخمة والحصول على كود الترقية.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(InventoryItem item) {
    final surf = context.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.isLowStock
                    ? AppColors.rose500.withValues(alpha: surf.isDark ? .14 : .08)
                    : surf.iconBoxBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.isLowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                color: item.isLowStock ? AppColors.rose700text : AppColors.indigo700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(item.itemName,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14.5)),
                      ),
                      // مادة أُنشئت/عُدِّلت/حُذفت أوفلاين وما زالت بانتظار
                      // الاتصال بالإنترنت -- انظر OfflineAwareApiService.
                      // أُضيف 2026-09-02.
                      if (item.isPendingSync) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.cloud_off_outlined,
                            size: 14, color: AppColors.amber900),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.hasUnitCost
                        ? 'الكمية: ${item.quantity}  •  حد التنبيه: ${item.minAlertQuantity}  •  الوحدة: ${formatUnitCostAr(item.unitCost)} ل.س'
                        : 'الكمية: ${item.quantity}  •  حد التنبيه: ${item.minAlertQuantity}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: item.isLowStock
                          ? (surf.isDark ? AppColors.rose400 : AppColors.rose700text)
                          : surf.textSecondary,
                      fontSize: 12,
                      fontWeight: item.isLowStock ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: surf.textSecondary),
              onSelected: (value) {
                if (value == 'edit') _openEditItemSheet(item);
                if (value == 'delete') _confirmDelete(item);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryItemSheet extends StatefulWidget {
  final ApiService apiService;
  final InventoryItem? item;

  const _InventoryItemSheet({required this.apiService, this.item});

  @override
  State<_InventoryItemSheet> createState() => _InventoryItemSheetState();
}

class _InventoryItemSheetState extends State<_InventoryItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _alertController;
  late final TextEditingController _unitCostController;
  // حقلا الحاسبة واجهة بحتة: لا يُرسَلان ولا يُحفَظان، يملأان حقل التكلفة فقط.
  final _packPriceController = TextEditingController();
  final _dosesController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.itemName ?? '');
    _quantityController =
        TextEditingController(text: widget.item?.quantity.toString() ?? '');
    _alertController =
        TextEditingController(text: widget.item?.minAlertQuantity.toString() ?? '5');
    // التكلفة صفراً تعني "غير مسجَّلة"، فيُفتَح الحقل فارغاً لا بصفر يوهم
    // الطبيب أنه سجّلها فعلاً.
    final existingCost = widget.item?.unitCost ?? 0;
    _unitCostController = TextEditingController(
        text: existingCost > 0 ? _trimZeros(existingCost) : '');
    _packPriceController.addListener(_onDoseInputChanged);
    _dosesController.addListener(_onDoseInputChanged);
  }

  /// "1500" لا "1500.0"، و"1500.25" كما هي -- الحقل نصّي يقرأه الطبيب.
  static String _trimZeros(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  void _onDoseInputChanged() => setState(() {});

  /// نتيجة الحاسبة الحيّة، أو null إن كان الحقلان فارغين معاً.
  DoseCostOutcome? get _doseOutcome {
    final priceText = _packPriceController.text.trim();
    final dosesText = _dosesController.text.trim();
    if (priceText.isEmpty && dosesText.isEmpty) return null;
    return computeDoseCost(priceText, dosesText);
  }

  void _applyDoseCost() {
    final outcome = _doseOutcome;
    if (outcome == null || !outcome.isValid) return;
    setState(() {
      _unitCostController.text = _trimZeros(outcome.value!);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'تم وضع ${formatUnitCostAr(outcome.value)} ل.س في تكلفة الوحدة'),
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _alertController.dispose();
    _unitCostController.dispose();
    _packPriceController.removeListener(_onDoseInputChanged);
    _dosesController.removeListener(_onDoseInputChanged);
    _packPriceController.dispose();
    _dosesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final quantity = int.parse(_quantityController.text.trim());
      final alert = int.parse(_alertController.text.trim());
      // حقل فارغ في الإنشاء = لا تُرسِل التكلفة (الخادم يضع صفراً). وفي
      // التعديل يُرسَل صفر صريح: إفراغ الحقل يعني "امسح التكلفة" لا "لا
      // تغيير"، وإلا صار محو تكلفة سُجّلت بالخطأ مستحيلاً من التطبيق.
      final unitCostText = _unitCostController.text.trim();
      final double? unitCost = unitCostText.isEmpty
          ? (widget.item == null ? null : 0)
          : double.tryParse(unitCostText);
      if (widget.item == null) {
        await widget.apiService.createInventoryItem(
          itemName: _nameController.text.trim(),
          quantity: quantity,
          minAlertQuantity: alert,
          unitCost: unitCost,
        );
      } else {
        await widget.apiService.updateInventoryItem(
          widget.item!.id,
          itemName: _nameController.text.trim(),
          quantity: quantity,
          minAlertQuantity: alert,
          unitCost: unitCost,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر حفظ المادة. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
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
              Text(
                isEdit ? 'تعديل المادة' : 'إضافة مادة جديدة',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'اسم المادة'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'اسم المادة مطلوب' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'الكمية'),
                      validator: (value) {
                        final parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null || parsed < 0) return 'قيمة غير صحيحة';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _alertController,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'حد التنبيه الأدنى'),
                      validator: (value) {
                        final parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null || parsed < 0) return 'قيمة غير صحيحة';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitCostController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'تكلفة الوحدة (اختياري)',
                  helperText: 'الوحدة = أصغر ما تستهلكه في علاج واحد، لا أصغر ما تشتريه',
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  final parsed = double.tryParse(text);
                  if (parsed == null || !parsed.isFinite || parsed < 0) {
                    return 'قيمة غير صحيحة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              // ==============================================================
              // حاسبة تكلفة الجرعة -- منقولة عن inventory.html بالموقع
              // ==============================================================
              // للمواد التي تُشترى عبوةً وتُستهلك جرعةً (كومبوزت، بوندينغ،
              // حمض حفر): تحوّل سعر العبوة إلى تكلفة جرعة وتضعها في الحقل
              // أعلاه. لا ترسل شيئاً للخادم ولا تحفظ شيئاً.
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: surf.iconBoxBg,
                  border: Border.all(color: surf.iconBoxBorder),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'حاسبة تكلفة الجرعة',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: surf.iconBoxFg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'عبوة تُشترى مرة وتُستهلك على عشرات العلاجات لا تُخصم بالكسور — أدخل سعر العبوة وعدد الجرعات فيها.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                          color: surf.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _packPriceController,
                            textAlign: TextAlign.right,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'سعر العبوة'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _dosesController,
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'عدد الجرعات'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final outcome = _doseOutcome;
                      final message = outcome == null
                          ? 'أدخل الرقمين لتظهر تكلفة الجرعة.'
                          : (outcome.error ??
                              // تذكير الكمية مقصود: أكثر خطأ متوقَّع هو إدخال
                              // «1» في الكمية (عبوة واحدة) بينما الوحدة
                              // المسجَّلة صارت الجرعة.
                              'تكلفة الجرعة: ${formatUnitCostAr(outcome.value)} ل.س — وإن كنت تُدخل عبوة واحدة فالكمية = ${formatUnitCostAr(outcome.doses)}');
                      final color = outcome == null
                          ? surf.textSecondary
                          : (outcome.error != null
                              ? AppColors.rose700text
                              : AppColors.emerald700text);
                      return Text(
                        message,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            fontWeight: FontWeight.w700,
                            color: color),
                      );
                    }),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed:
                          (_doseOutcome?.isValid ?? false) ? _applyDoseCost : null,
                      child: const Text('ضع النتيجة في تكلفة الوحدة'),
                    ),
                  ],
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
                label: isEdit ? 'حفظ التعديلات' : 'إضافة المادة',
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
