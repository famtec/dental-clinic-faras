import 'package:flutter/material.dart';

import '../models/finance_summary.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

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

class _FinanceScreenState extends State<FinanceScreen> {
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
        await showModalBottomSheet<({bool inventorySynced, String? inventoryAction})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(apiService: widget.apiService),
    );
    if (result != null) {
      _loadMonths();
      _loadSummary();
      if (!mounted) return;
      // نفس رسالة النجاح "الأغنى" التي يعرضها submitExpense() بالموقع عند
      // نجاح الربط بمخزن المواد (finance.html).
      final message = result.inventorySynced
          ? 'تم حفظ المصروف بنجاح، و${result.inventoryAction == 'created' ? 'تمت إضافتها كمادة جديدة' : 'تم تحديث كميتها'} في مخزن المواد.'
          : 'تم حفظ المصروف بنجاح.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _money(double value) => value.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      body: AtmosphereBackground(
        child: RefreshIndicator(
          onRefresh: _loadSummary,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AnimatedHeroHeader(
                padding: EdgeInsets.fromLTRB(
                    20, MediaQuery.of(context).padding.top + 8, 20, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // زر رجوع -- الشاشة تُفتح دائماً عبر Navigator.push من تبويب
                    // "المزيد"، وبلا AppBar هنا لا يوجد أي طريق آخر للعودة (تمت
                    // إضافته بعد أن لاحظ الطبيب غيابه 2026-08-29).
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_forward, color: Colors.white),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const Text(
                      'التقارير المالية',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'متابعة الدخل والمصروفات وصافي الأرباح شهرياً',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(26),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 22, horizontal: 12),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.smartStatGradient,
                                      borderRadius: BorderRadius.circular(26),
                                      border: Border.all(
                                          color: Colors.white.withValues(alpha: .14)),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          'صافي الربح',
                                          style: TextStyle(
                                              color: Colors.white.withValues(alpha: .7),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _money(summary.netProfit),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 30,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _statColumn(
                                                'إجمالي الدخل',
                                                _money(summary.totalIncome),
                                                AppColors.cyan300,
                                              ),
                                            ),
                                            Container(
                                                width: 1,
                                                height: 34,
                                                color: Colors.white.withValues(alpha: .14)),
                                            Expanded(
                                              child: _statColumn(
                                                'إجمالي المصروفات',
                                                _money(summary.totalExpenses),
                                                const Color(0xFFFCA5A5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
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

  Widget _statColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .68),
                fontSize: 10.5,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// زر قائمة منسدلة لاختيار فترة التقرير -- مطابق حرفياً للقائمة المنسدلة
  /// الحالية في finance.html (#monthSelect/#monthSelectTrigger): "اليوم"
  /// أولاً، ثم الأشهر التي فيها حركات فعلية (الأحدث أولاً، والشهر الحالي
  /// مضمون الوجود دائماً حتى بلا حركات -- انظر get_finance_available_months
  /// بالـ main.py)، ثم "كل الوقت (الإجمالي التراكمي)" أخيراً. الاختيار
  /// الافتراضي يبقى أول شهر (الشهر الحالي) وليس "اليوم" -- نفس سلوك
  /// populateMonthSelect() بالموقع، الذي يضيف خيار اليوم بلا تغيير الافتراضي.
  Widget _buildMonthSelector() {
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
        const Text(
          'عرض التقرير المالي لشهر',
          textAlign: TextAlign.right,
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.indigo700),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.slate500),
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
          style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.slate200,
                    borderRadius: BorderRadius.circular(999),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.indigo600.withValues(alpha: .18)),
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
          const Text(
            'إن وجدت مادة بنفس الاسم في المخزن سيتم زيادة كميتها تلقائياً، وإلا سيتم إنشاء مادة جديدة.',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: AppColors.slate500),
          ),
        ],
      ),
    );
  }
}
