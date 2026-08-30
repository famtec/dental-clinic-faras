import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// "مخزن المواد" -- تطابق inventory.html بالموقع: ميزة Premium حصراً (حارس
/// require_premium_user_by_email في main.py يرجع 403 بدل 402 المعتاد -- انظر
/// ApiException.isPremiumRequired). غير المشتركين يرون بطاقة قفل بدل القائمة،
/// بنفس رسالة الموقع حرفياً.
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
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventoryItemSheet(apiService: widget.apiService),
    );
    if (added == true) _load();
  }

  Future<void> _openEditItemSheet(InventoryItem item) async {
    final result = await showModalBottomSheet<bool>(
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
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                        20, MediaQuery.of(context).padding.top + 8, 20, 26),
                    decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // زر رجوع -- انظر نفس التعليق في finance_screen.dart.
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
                          'مخزن المواد',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'متابعة كميات مستلزمات العيادة وتنبيهات النقص',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    child: LoadingErrorEmpty(
                      isLoading: _isLoading,
                      errorMessage: _isPremiumLocked ? null : _errorMessage,
                      isLocked: false,
                      onRetry: _load,
                      child: _isPremiumLocked
                          ? _buildPremiumLockCard()
                          : items.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 48),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.inventory_2_outlined,
                                            size: 44, color: AppColors.slate400),
                                        SizedBox(height: 10),
                                        Text('لا توجد مواد مسجّلة بعد'),
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
              bottom: 20,
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
                color: item.isLowStock ? AppColors.rose50 : AppColors.indigo50,
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
                  Text(item.itemName,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text(
                    'الكمية: ${item.quantity}  •  حد التنبيه: ${item.minAlertQuantity}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: item.isLowStock ? AppColors.rose700text : AppColors.slate500,
                      fontSize: 12,
                      fontWeight: item.isLowStock ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.slate500),
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _alertController.dispose();
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
      if (widget.item == null) {
        await widget.apiService.createInventoryItem(
          itemName: _nameController.text.trim(),
          quantity: quantity,
          minAlertQuantity: alert,
        );
      } else {
        await widget.apiService.updateInventoryItem(
          widget.item!.id,
          itemName: _nameController.text.trim(),
          quantity: quantity,
          minAlertQuantity: alert,
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
