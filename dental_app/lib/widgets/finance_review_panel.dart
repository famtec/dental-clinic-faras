import 'package:flutter/material.dart';

import '../models/pending_payment.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'app_sheet.dart';
import 'app_widgets.dart';

/// لوحة المراجعة المالية للطبيب المدير (2026-09-25) -- في صفحة المالية على
/// الجوال وسطح المكتب معاً:
///
/// 1. **دفعات بانتظار تأكيدك**: ما سجّله الأطباء المساعدون من مبالغ استلموها.
///    لا تدخل أي رقم قبل التأكيد، فالبطاقة تذكير بمال خارج الحسابات بعد.
/// 2. **إقفال الشهر**: للشهر المعروض إن انتهى. الشهر المقفل لا تُسجَّل فيه
///    حركة ولا تُعدَّل ولا تُحذف (الخادم يفرض ذلك في كل المسارات).
///
/// تختفي البطاقتان حين لا شيء تقولانه: لا دفعات معلّقة، والشهر الحالي لم
/// ينتهِ بعد.
class FinanceReviewPanel extends StatefulWidget {
  final ApiService apiService;

  /// الشهر المعروض في صفحة المالية؛ null في «اليوم» و«كل الوقت».
  final int? year;
  final int? month;

  /// المسافة تحت اللوحة حين تظهر (لا شيء حين تختفي).
  final double bottomSpacing;

  /// بعد أي تأكيد أو إقفال -- لتُعيد الصفحة تحميل أرقامها.
  final VoidCallback onChanged;
  final VoidCallback onSessionExpired;

  const FinanceReviewPanel({
    super.key,
    required this.apiService,
    required this.year,
    required this.month,
    required this.onChanged,
    required this.onSessionExpired,
    this.bottomSpacing = 0,
  });

  @override
  State<FinanceReviewPanel> createState() => FinanceReviewPanelState();
}

class FinanceReviewPanelState extends State<FinanceReviewPanel> {
  PendingSummary _pending = const PendingSummary();
  List<ClosedPeriod> _closed = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        widget.apiService.fetchPendingPaymentsCount(),
        widget.apiService.fetchClosedPeriods(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0] as PendingSummary;
        _closed = results[1] as List<ClosedPeriod>;
      });
    } on ApiException catch (e) {
      if (e.isSessionExpired) widget.onSessionExpired();
    } catch (_) {
      // لوحة ثانوية: فشلها يُخفيها ولا يمسّ أرقام الصفحة.
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPending() async {
    final changed = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      desktopWidth: 640,
      builder: (_) =>
          PendingPaymentsSheet(apiService: widget.apiService, onSessionExpired: widget.onSessionExpired),
    );
    // الورقة تُغلق بالسحب أو بزرّ الحوار دون نتيجة أحياناً، فالمرجع هو تغيّر
    // العدد لا القيمة الراجعة وحدها.
    final before = _pending.count;
    await refresh();
    if (changed == true || _pending.count != before) widget.onChanged();
  }

  ClosedPeriod? get _closedForMonth {
    final year = widget.year;
    final month = widget.month;
    if (year == null || month == null) return null;
    for (final period in _closed) {
      if (period.year == year && period.month == month) return period;
    }
    return null;
  }

  bool get _monthEnded {
    final year = widget.year;
    final month = widget.month;
    if (year == null || month == null) return false;
    return !DateTime(year, month + 1, 1).isAfter(DateTime.now());
  }

  Future<void> _closeMonth() async {
    final year = widget.year!;
    final month = widget.month!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إقفال شهر $month/$year؟'),
        content: const Text(
          'بعد الإقفال لا تُسجَّل في هذا الشهر دفعة ولا مصروف ولا تسوية، ولا '
          'تُعدَّل حركاته ولا تُحذف -- فتبقى أرقامه ونسب الأطباء فيه كما هي الآن. '
          'تستطيع فتح القفل لاحقاً إن احتجت لتصحيح.',
          style: TextStyle(height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إقفال الشهر'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.apiService.closeFinanceMonth(year, month);
      _toast('تم إقفال شهر $month/$year');
      await refresh();
      widget.onChanged();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopenMonth(ClosedPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('فتح قفل شهر ${period.month}/${period.year}؟'),
        content: const Text(
          'يصبح الشهر قابلاً للتعديل من جديد. أقفله مرة أخرى بعد التصحيح.',
          style: TextStyle(height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('فتح القفل'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.apiService.reopenFinanceMonth(period.year, period.month);
      _toast('تم فتح قفل شهر ${period.month}/${period.year}');
      await refresh();
      widget.onChanged();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final closed = _closedForMonth;
    final children = <Widget>[];

    if (_pending.count > 0) {
      children.add(
        _PanelCard(
          icon: Icons.hourglass_top_rounded,
          foreground: surf.pillDueFg,
          background: surf.pillDueBg,
          border: surf.pillDueBorder,
          title: _pending.count == 1 ? 'دفعة بانتظار تأكيدك' : '${_pending.count} دفعات بانتظار تأكيدك',
          subtitle:
              'مجموعها ${formatGroupedMoney(_pending.amount)} ل.س — استلمها أطباء مساعدون، '
              'ولا تدخل الحسابات قبل تأكيدك.',
          action: FilledButton(onPressed: _openPending, child: const Text('مراجعة')),
        ),
      );
    }

    if (closed != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        _PanelCard(
          icon: Icons.lock_outline,
          foreground: surf.pillPaidFg,
          background: surf.pillPaidBg,
          border: surf.pillPaidBorder,
          title: 'شهر ${closed.month}/${closed.year} مُقفل',
          subtitle:
              'لا تُسجَّل فيه حركة ولا تُعدَّل. الدخل عند الإقفال '
              '${formatGroupedMoney(closed.totalIncome)} ل.س، والمصاريف '
              '${formatGroupedMoney(closed.totalExpenses)} ل.س، وحصص الأطباء '
              '${formatGroupedMoney(closed.doctorsShare)} ل.س.',
          action: TextButton(
            onPressed: _busy ? null : () => _reopenMonth(closed),
            child: const Text('فتح القفل'),
          ),
        ),
      );
    } else if (_monthEnded) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        _PanelCard(
          icon: Icons.lock_open_outlined,
          foreground: surf.textSecondary,
          background: surf.iconBoxBg,
          border: surf.iconBoxBorder,
          title: 'إقفال شهر ${widget.month}/${widget.year}',
          subtitle: 'بعد مراجعة أرقامه وتسليم نسب الأطباء، أقفله حتى لا تتغيّر حركاته لاحقاً.',
          action: OutlinedButton(onPressed: _busy ? null : _closeMonth, child: const Text('إقفال')),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
  final String title;
  final String subtitle;
  final Widget action;

  const _PanelCard({
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: surf.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.6, color: surf.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          action,
        ],
      ),
    );
  }
}

String formatPendingDate(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${value.year}/${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
}

/// سطر دفعة معلّقة -- في ورقة المراجعة وفي فاتورة المريض. الأزرار تُمرَّر
/// من المستدعي (تأكيد/رفض للمدير، إلغاء للمساعد).
class PendingPaymentTile extends StatelessWidget {
  final PendingPayment payment;
  final bool showPatient;
  final List<Widget> actions;

  const PendingPaymentTile({
    super.key,
    required this.payment,
    this.showPatient = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final lines = <String>[
      if (showPatient && payment.patientName != null)
        '${payment.patientName}${payment.invoiceTitle != null ? ' — ${payment.invoiceTitle}' : ''}',
      '${payment.staffName ?? 'طبيب مساعد'} · ${formatPendingDate(payment.recordedAt)}',
      if (payment.description != null) payment.description!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: surf.pillDueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: surf.pillDueBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top_rounded, size: 16, color: surf.pillDueFg),
              const SizedBox(width: 6),
              Text(
                '${formatGroupedMoney(payment.amount)} ل.س',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: surf.textPrimary),
              ),
              const Spacer(),
              Text(
                'بانتظار التأكيد',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: surf.pillDueFg),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Text(line, style: TextStyle(fontSize: 11.5, height: 1.5, color: surf.textSecondary)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: actions),
          ],
        ],
      ),
    );
  }
}

/// سؤال سبب الرفض (اختياري). null = أُلغي الرفض.
Future<String?> askRejectReason(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('رفض الدفعة'),
      content: TextField(
        controller: controller,
        maxLength: 300,
        decoration: const InputDecoration(
          labelText: 'السبب (اختياري)',
          hintText: 'مثال: لم يصل المبلغ للصندوق',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.rose500),
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('رفض'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// ورقة مراجعة الدفعات المعلّقة (للمدير). تُرجع true إن تغيّر شيء.
class PendingPaymentsSheet extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const PendingPaymentsSheet({super.key, required this.apiService, required this.onSessionExpired});

  @override
  State<PendingPaymentsSheet> createState() => _PendingPaymentsSheetState();
}

class _PendingPaymentsSheetState extends State<PendingPaymentsSheet> {
  List<PendingPayment>? _items;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.apiService.fetchPendingPayments();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(PendingPayment item, {required bool confirm}) async {
    String? note;
    if (!confirm) {
      note = await askRejectReason(context);
      if (note == null) return;
    }
    setState(() => _busy.add(item.id));
    try {
      if (confirm) {
        await widget.apiService.confirmPendingPayment(item.id);
      } else {
        await widget.apiService.rejectPendingPayment(item.id, note: note);
      }
      if (!mounted) return;
      setState(() => _items = [...?_items]..removeWhere((p) => p.id == item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(confirm ? 'تم تأكيد الدفعة وإضافتها للحسابات' : 'تم رفض الدفعة')),
      );
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final items = _items;
    return Container(
      decoration: BoxDecoration(
        color: surf.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BottomSheetOnly(
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: surf.divider, borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'دفعات بانتظار تأكيدك',
              style: AppType.kufi(fontSize: 16, fontWeight: FontWeight.w700, color: surf.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'أكّد الدفعة بعد أن يصل مبلغها إلى صندوق العيادة: تُسجَّل بتاريخ استلام الطبيب لها، '
              'وتُحسب نسبته منها.',
              style: TextStyle(fontSize: 12, height: 1.6, color: surf.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.rose700text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
            ],
            if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('لا دفعات بانتظار التأكيد.', style: TextStyle(color: surf.textMuted)),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      PendingPaymentTile(
                        payment: item,
                        showPatient: true,
                        actions: [
                          TextButton(
                            onPressed: _busy.contains(item.id) ? null : () => _act(item, confirm: false),
                            child: const Text('رفض', style: TextStyle(color: AppColors.rose700text)),
                          ),
                          FilledButton.icon(
                            onPressed: _busy.contains(item.id) ? null : () => _act(item, confirm: true),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('تأكيد الاستلام'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
