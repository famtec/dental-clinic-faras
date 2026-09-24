import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/clinic_doctor.dart';
import '../models/patient.dart';
import '../models/treatment_invoice.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/clinic_doctor_colors.dart';
import '../widgets/desktop_shell.dart';
import '../widgets/desktop_widgets.dart';

/// صفحة «المرضى» على سطح المكتب — جدول بلوحة معاينة (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من `Patients.dc.html` على الكانفاس. **ليست شاشة مستقلة**: تعيش
/// داخل [PatientsListScreen] وتأخذ منه القائمة وحقل البحث ونموذج الإضافة،
/// فيبقى للمرضى مصدر تحميل واحد في التخطيطين، وحقل بحث الترويسة يكتب في
/// الحقل نفسه.
///
/// ما يُحسب هنا ولا يأتي من الخادم مباشرةً:
/// * **آخر زيارة** — آخر موعد ماضٍ للمريض (بمعرّفه لا باسمه) من قائمة
///   المواعيد. الخادم لا يحمل حقلاً كهذا، والمواعيد هي السجلّ الوحيد لحضور
///   المريض. «لم تُسجَّل» حين لا موعد ماضياً له.
/// * **الموعد القادم** — أقرب موعد لم يمضِ بحالة فعّالة.
/// * **آخر العلاجات** — فواتير العلاج (عنوانها وتاريخها وقيمتها). الكانفاس
///   يذكر رقم السن، والفاتورة لا تحمله، فلم يُعرض رقم مخترع.
class DesktopPatientsView extends StatefulWidget {
  final ApiService apiService;
  final List<Patient> patients;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddPatient;
  final ValueChanged<Patient> onOpenPatient;
  final VoidCallback onSessionExpired;

  /// يزداد مع كل إعادة تحميل للمرضى في الشاشة الأمّ، فتُعاد قراءة المواعيد
  /// والفواتير معها (دفعة جديدة من ملف المريض تغيّر الرصيد والعلاجات معاً).
  final int reloadToken;

  const DesktopPatientsView({
    super.key,
    required this.apiService,
    required this.patients,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onAddPatient,
    required this.onOpenPatient,
    required this.onSessionExpired,
    required this.reloadToken,
  });

  @override
  State<DesktopPatientsView> createState() => _DesktopPatientsViewState();
}

enum _BalanceStatus { due, paid, none }

_BalanceStatus _statusOf(Patient p) {
  if (p.remainingBalance > 0) return _BalanceStatus.due;
  if (p.totalTreatmentCost > 0) return _BalanceStatus.paid;
  return _BalanceStatus.none;
}

/// حالات موعد تعني أن المريض حضر أو سيحضر. `no_show` و`rejected` و
/// `cancelled` لا تُحسب زيارةً ولا موعداً قادماً، و`pending_confirmation`
/// طلب لم يُقبل بعد.
const Set<String> _visitStatuses = {'pending', 'checked_in', 'confirmed', 'completed'};

/// لحظة بدء الموعد محلياً. التاريخ من appointmentDate والساعة من نصّ الوقت
/// (انظر [Appointment.startMinutes] لسبب عدم الوثوق بساعة التاريخ).
DateTime? _startOf(Appointment a) {
  final date = a.appointmentDate;
  if (date == null) return null;
  final minutes = a.startMinutes ?? 0;
  return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
}

class _DesktopPatientsViewState extends State<DesktopPatientsView> {
  static const double _rowHeight = 62;
  static const double _previewWidth = 340;

  /// تحت هذا العرض لمساحة الصفحة تختفي لوحة المعاينة ويفتح النقر الملف
  /// الكامل مباشرةً: جدول بستة أعمدة بجانب لوحة 340px يحتاج ~1000px.
  static const double _previewMinWidth = 980;

  int _filter = 0;
  int _page = 0;
  int? _selectedId;

  List<ClinicDoctor> _doctors = const [];
  String _ownerName = '';
  Map<int, DateTime> _lastVisit = const {};
  Map<int, Appointment> _nextAppointment = const {};

  final Map<int, List<TreatmentInvoice>> _invoices = {};
  final Set<int> _invoicesLoading = {};
  final Set<int> _invoicesFailed = {};

  @override
  void initState() {
    super.initState();
    _loadSideData();
  }

  @override
  void didUpdateWidget(covariant DesktopPatientsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) _page = 0;
    if (oldWidget.reloadToken != widget.reloadToken) {
      _invoices.clear();
      _invoicesFailed.clear();
      _loadSideData();
    }
  }

  /// المواعيد والأطباء واسم صاحب الحساب. كلها ثانوية: فشلها يترك «آخر
  /// زيارة» على «—» والعمود بلا لون، ولا يحجب الجدول.
  Future<void> _loadSideData() async {
    List<Appointment> appointments = const [];
    try {
      appointments = await widget.apiService.fetchAppointments();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
    } catch (_) {}
    final doctors = await widget.apiService.fetchClinicDoctors();
    String ownerName = '';
    try {
      ownerName = (await widget.apiService.authStorage.getDoctorName())?.trim() ?? '';
    } catch (_) {}

    final now = DateTime.now();
    final last = <int, DateTime>{};
    final next = <int, Appointment>{};
    final nextAt = <int, DateTime>{};
    for (final a in appointments) {
      final pid = a.patientId;
      if (pid == null || !_visitStatuses.contains(a.status.toLowerCase())) continue;
      final at = _startOf(a);
      if (at == null) continue;
      if (at.isBefore(now)) {
        if (last[pid] == null || at.isAfter(last[pid]!)) last[pid] = at;
      } else if (nextAt[pid] == null || at.isBefore(nextAt[pid]!)) {
        nextAt[pid] = at;
        next[pid] = a;
      }
    }

    if (!mounted) return;
    setState(() {
      _doctors = doctors;
      _ownerName = ownerName;
      _lastVisit = last;
      _nextAppointment = next;
    });
    final selected = _selectedId;
    if (selected != null) _ensureInvoices(selected);
  }

  Future<void> _ensureInvoices(int patientId) async {
    if (_invoices.containsKey(patientId) || _invoicesLoading.contains(patientId)) return;
    setState(() {
      _invoicesLoading.add(patientId);
      _invoicesFailed.remove(patientId);
    });
    try {
      final invoices = await widget.apiService.fetchPatientInvoices(patientId);
      invoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _invoices[patientId] = invoices);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) setState(() => _invoicesFailed.add(patientId));
    } catch (_) {
      if (mounted) setState(() => _invoicesFailed.add(patientId));
    } finally {
      if (mounted) setState(() => _invoicesLoading.remove(patientId));
    }
  }

  void _select(Patient patient) {
    if (_selectedId == patient.id) return;
    setState(() => _selectedId = patient.id);
    _ensureInvoices(patient.id);
  }

  bool get _multiDoctor => _doctors.isNotEmpty;

  String _doctorLabel(Patient p) {
    if (p.clinicDoctorId != null) return p.clinicDoctorName ?? '—';
    return _ownerName.isEmpty ? 'الطبيب المدير' : _ownerName;
  }

  List<Patient> _searched() {
    final query = widget.searchQuery.trim();
    if (query.isEmpty) return widget.patients;
    return widget.patients
        .where((p) =>
            p.fullName.contains(query) ||
            p.phone.replaceAll(RegExp(r'\s+'), '').contains(query) ||
            p.id.toString() == query)
        .toList();
  }

  bool _matches(Patient p) {
    switch (_filter) {
      case 1:
        return _statusOf(p) == _BalanceStatus.due;
      case 2:
        return _statusOf(p) == _BalanceStatus.paid;
      case 3:
        return _statusOf(p) == _BalanceStatus.none;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final searched = _searched();
    final filtered = searched.where(_matches).toList();
    int countOf(_BalanceStatus s) => searched.where((p) => _statusOf(p) == s).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showPreview = constraints.maxWidth >= _previewMinWidth;
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(context, searched.length, [
                searched.length,
                countOf(_BalanceStatus.due),
                countOf(_BalanceStatus.paid),
                countOf(_BalanceStatus.none),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _table(context, filtered, showPreview)),
                    if (showPreview) ...[
                      const SizedBox(width: 20),
                      SizedBox(width: _previewWidth, child: _preview(context, filtered)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── شريط الأدوات ────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context, int total, List<int> counts) {
    final d = context.desktop;
    const labels = ['الكل', 'متبقٍ', 'مسدّد', 'لا فواتير'];
    return Row(
      children: [
        SizedBox(
          width: 300,
          height: 42,
          child: TextField(
            controller: widget.searchController,
            onChanged: widget.onSearchChanged,
            style: AppType.sans(fontSize: 13, color: d.fieldFg),
            cursorColor: d.linkFg,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'الاسم، رقم الملف أو الهاتف...',
              hintStyle: AppType.sans(fontSize: 13, color: d.fieldHint),
              prefixIcon: Icon(Icons.search, size: 18, color: d.fieldHint),
              filled: true,
              fillColor: d.cardBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: d.fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: d.linkFg, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < labels.length; i++)
                DesktopChip(
                  label: labels[i],
                  count: counts[i],
                  selected: _filter == i,
                  onTap: () => setState(() {
                    _filter = i;
                    _page = 0;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        DesktopCtaButton(icon: Icons.add, label: 'مريض جديد', onTap: widget.onAddPatient),
      ],
    );
  }

  // ── الجدول ──────────────────────────────────────────────────────────────

  Widget _table(BuildContext context, List<Patient> filtered, bool showPreview) {
    final d = context.desktop;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: d.cardBg,
        gradient: d.cardGradient,
        borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusPanel),
        border: Border.all(color: d.cardBorder),
        boxShadow: d.panelShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // أعمدة تختفي بالترتيب مع ضيق الجدول، الأقلّ حاجةً أولاً.
          final width = constraints.maxWidth;
          final cols = _Columns(
            phone: width >= 560,
            lastVisit: width >= 700,
            doctor: _multiDoctor && width >= 620,
          );
          const headerHeight = 44.0;
          const footerHeight = 58.0;
          final bodyHeight = constraints.maxHeight - headerHeight - footerHeight;
          final perPage = (bodyHeight / _rowHeight).floor().clamp(3, 50);
          final pageCount = filtered.isEmpty ? 1 : (filtered.length / perPage).ceil();
          final page = _page.clamp(0, pageCount - 1);
          final start = page * perPage;
          final rows = filtered.skip(start).take(perPage).toList();

          // المختار يتبع الصفحة المعروضة: لوحة المعاينة لا تعرض مريضاً لا
          // يراه الطبيب في الجدول.
          if (showPreview && rows.isNotEmpty && !rows.any((p) => p.id == _selectedId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _select(rows.first);
            });
          }

          return Column(
            children: [
              SizedBox(height: headerHeight, child: _headerRow(context, cols)),
              Expanded(
                child: rows.isEmpty
                    ? DesktopEmptyHint(
                        icon: widget.searchQuery.trim().isNotEmpty || _filter != 0
                            ? Icons.search_off
                            : Icons.people_outline,
                        text: widget.searchQuery.trim().isNotEmpty || _filter != 0
                            ? 'لا نتائج مطابقة'
                            : 'لا يوجد مرضى مسجّلون بعد',
                      )
                    : Column(
                        children: [
                          for (final p in rows)
                            _PatientRow(
                              height: _rowHeight,
                              patient: p,
                              cols: cols,
                              selected: showPreview && p.id == _selectedId,
                              lastVisit: _lastVisit[p.id],
                              doctorLabel: _doctorLabel(p),
                              doctorColor: clinicDoctorColor(p.clinicDoctorId, _doctors),
                              onTap: () => showPreview ? _select(p) : widget.onOpenPatient(p),
                              onDoubleTap: () => widget.onOpenPatient(p),
                            ),
                        ],
                      ),
              ),
              SizedBox(
                height: footerHeight,
                child: _footer(context, rows.length, filtered.length, page, pageCount),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerRow(BuildContext context, _Columns cols) {
    final d = context.desktop;
    Widget cell(String text, int flex, {TextAlign align = TextAlign.start}) => Expanded(
          flex: flex,
          child: Text(
            text,
            textAlign: align,
            style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.textSecondary),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: d.fieldBg,
        border: Border(bottom: BorderSide(color: d.cardBorder)),
      ),
      child: Row(
        children: [
          cell('المريض', _Columns.patientFlex),
          if (cols.phone) cell('الهاتف', _Columns.phoneFlex),
          if (cols.lastVisit) cell('آخر زيارة', _Columns.lastVisitFlex),
          if (cols.doctor) cell('الطبيب', _Columns.doctorFlex),
          cell('الرصيد (ل.س)', _Columns.balanceFlex, align: TextAlign.end),
          const SizedBox(width: 18),
          cell('الحالة', _Columns.statusFlex),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, int shown, int total, int page, int pageCount) {
    final d = context.desktop;
    // نافذة من خمس صفحات حول الحالية، فلا يتحوّل الشريط إلى ثلاثين زرّاً.
    var first = (page - 2).clamp(0, pageCount - 1);
    final last = (first + 4).clamp(0, pageCount - 1);
    first = (last - 4).clamp(0, pageCount - 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: d.cardBorder))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'عرض $shown من $total',
              style: AppType.sans(fontSize: 12, color: d.textSecondary),
            ),
          ),
          DesktopSquareButton(
            icon: Icons.chevron_right,
            tooltip: 'الصفحة السابقة',
            onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
          ),
          for (var i = first; i <= last; i++) ...[
            const SizedBox(width: 6),
            DesktopSquareButton(
              label: '${i + 1}',
              selected: i == page,
              onTap: i == page ? null : () => setState(() => _page = i),
            ),
          ],
          const SizedBox(width: 6),
          DesktopSquareButton(
            icon: Icons.chevron_left,
            tooltip: 'الصفحة التالية',
            onTap: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
          ),
        ],
      ),
    );
  }

  // ── لوحة المعاينة ───────────────────────────────────────────────────────

  Widget _preview(BuildContext context, List<Patient> filtered) {
    final d = context.desktop;
    Patient? selected;
    for (final p in filtered) {
      if (p.id == _selectedId) selected = p;
    }
    if (selected == null) {
      return DesktopCard(
        child: SizedBox(
          height: 160,
          child: DesktopEmptyHint(icon: Icons.person_search_outlined, text: 'اختر مريضاً من الجدول'),
        ),
      );
    }
    final p = selected;
    final next = _nextAppointment[p.id];
    final age = p.age;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCard(
            glow: true,
            radius: 26,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DesktopInitialsTile(name: p.fullName, seed: p.id, size: 54, radius: 18, fontSize: 16),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.kufi(
                                fontSize: 16, fontWeight: FontWeight.w700, color: d.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            age == null ? 'ملف رقم ${p.id}' : 'ملف رقم ${p.id} · $age سنة',
                            style: AppType.sans(fontSize: 11.5, color: d.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_multiDoctor) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: clinicDoctorColor(p.clinicDoctorId, _doctors),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'الطبيب المعالج: ${_doctorLabel(p)}',
                        style: AppType.sans(fontSize: 12, color: d.textSecondary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: d.liveDot,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: d.liveDotHalo, spreadRadius: 3)],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'الرصيد المتبقّي',
                      style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.linkFg),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: desktopMoney.format(p.remainingBalance),
                        style: AppType.kufi(
                                fontSize: 30, fontWeight: FontWeight.w800, color: d.bigNumber)
                            .copyWith(
                          shadows: d.bigNumberGlow == null
                              ? null
                              : [Shadow(color: d.bigNumberGlow!, blurRadius: 32)],
                        ),
                      ),
                      TextSpan(
                        text: ' ل.س',
                        style: AppType.sans(
                            fontSize: 13, fontWeight: FontWeight.w600, color: d.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: d.cardBorder),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _miniStat(context, 'إجمالي العلاجات',
                            desktopMoney.format(p.totalTreatmentCost), d.textPrimary),
                      ),
                      Container(width: 1, color: d.cardBorder),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _miniStat(
                            context, 'المدفوع', desktopMoney.format(p.paidAmount), d.amountIn),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DesktopCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.iconBoxBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: d.iconBoxBorder),
                  ),
                  child: Icon(Icons.calendar_today_outlined, size: 18, color: d.iconBoxFg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الموعد القادم', style: AppType.sans(fontSize: 11, color: d.textSecondary)),
                      const SizedBox(height: 1),
                      Text(
                        next == null ? 'لا يوجد موعد محجوز' : _nextLabel(next),
                        style: AppType.sans(
                            fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DesktopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'آخر العلاجات',
                  style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                ),
                const SizedBox(height: 8),
                ..._treatments(context, p.id),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DesktopCtaButton(
            icon: Icons.folder_open_outlined,
            label: 'فتح الملف الكامل',
            expand: true,
            onTap: () => widget.onOpenPatient(p),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, Color valueColor) {
    final d = context.desktop;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.sans(fontSize: 11, color: d.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppType.sans(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor),
          ),
        ],
      ),
    );
  }

  List<Widget> _treatments(BuildContext context, int patientId) {
    final d = context.desktop;
    if (_invoicesLoading.contains(patientId) && !_invoices.containsKey(patientId)) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: d.linkFg),
            ),
          ),
        ),
      ];
    }
    if (_invoicesFailed.contains(patientId)) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('تعذر تحميل العلاجات',
                    style: AppType.sans(fontSize: 12, color: d.textSecondary)),
              ),
              DesktopTextLink(
                label: 'إعادة المحاولة',
                onTap: () => _ensureInvoices(patientId),
              ),
            ],
          ),
        ),
      ];
    }
    final invoices = _invoices[patientId] ?? const <TreatmentInvoice>[];
    if (invoices.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('لا علاجات مسجّلة بعد',
              style: AppType.sans(fontSize: 12.5, color: d.textSecondary)),
        ),
      ];
    }
    final shown = invoices.take(4).toList();
    return [
      for (var i = 0; i < shown.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: i == shown.length - 1
                ? null
                : Border(bottom: BorderSide(color: d.rowDivider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown[i].title.trim().isEmpty ? 'علاج' : shown[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                          fontSize: 12.5, fontWeight: FontWeight.w600, color: d.textPrimary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      desktopShortDate(shown[i].createdAt.toLocal()),
                      style: AppType.sans(fontSize: 11, color: d.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                desktopMoney.format(shown[i].totalCost),
                style: AppType.sans(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: d.navInactiveFg),
              ),
            ],
          ),
        ),
    ];
  }

  /// «اليوم · 11:45 ص» / «غداً · 09:00 ص» / «الأحد، 27 سبتمبر · 10:30 ص».
  String _nextLabel(Appointment a) {
    final at = _startOf(a)!;
    final time = desktopClockLabel(a.startMinutes);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'اليوم · $time';
    if (diff == 1) return 'غداً · $time';
    final line = desktopArabicDateLine(at);
    // «الأحد، 27 سبتمبر 2026» ← بلا السنة إن كانت السنة الحالية.
    final withoutYear = at.year == now.year ? line.replaceFirst(' ${at.year}', '') : line;
    return '$withoutYear · $time';
  }
}

/// أيّ الأعمدة تُعرض، وأوزانها. الأوزان ثابتة في الترويسة والصفوف معاً،
/// فلا تنزاح الترويسة عن عمودها.
class _Columns {
  final bool phone;
  final bool lastVisit;
  final bool doctor;

  const _Columns({required this.phone, required this.lastVisit, required this.doctor});

  static const int patientFlex = 30;
  static const int phoneFlex = 16;
  static const int lastVisitFlex = 14;
  static const int doctorFlex = 18;
  static const int balanceFlex = 14;
  static const int statusFlex = 12;
}

class _PatientRow extends StatefulWidget {
  final double height;
  final Patient patient;
  final _Columns cols;
  final bool selected;
  final DateTime? lastVisit;
  final String doctorLabel;
  final Color doctorColor;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _PatientRow({
    required this.height,
    required this.patient,
    required this.cols,
    required this.selected,
    required this.lastVisit,
    required this.doctorLabel,
    required this.doctorColor,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_PatientRow> createState() => _PatientRowState();
}

class _PatientRowState extends State<_PatientRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final p = widget.patient;
    final status = _statusOf(p);
    final cols = widget.cols;

    Widget text(String value, {Color? color, TextDirection? direction}) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: direction,
          style: AppType.sans(fontSize: 12.5, color: color ?? d.navInactiveFg),
        );

    final badge = switch (status) {
      _BalanceStatus.due => DesktopBadge(label: 'متبقٍ', colors: DesktopBadgeColors.waiting(d)),
      _BalanceStatus.paid => DesktopBadge(label: 'مسدّد', colors: DesktopBadgeColors.done(d)),
      _BalanceStatus.none => DesktopBadge(label: 'لا فواتير', colors: DesktopBadgeColors.neutral(d)),
    };

    final selectedBg = d.linkFg.withValues(alpha: d.isDark ? .14 : .05);
    final phone = p.phone.replaceAll(RegExp(r'\s+'), '');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          height: widget.height,
          padding: const EdgeInsetsDirectional.only(start: 15, end: 18),
          decoration: BoxDecoration(
            color: widget.selected
                ? selectedBg
                : (_hovered ? d.rowHover : Colors.transparent),
            border: BorderDirectional(
              start: BorderSide(
                color: widget.selected ? d.linkFg : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: d.rowDivider),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _Columns.patientFlex,
                child: Row(
                  children: [
                    DesktopInitialsTile(name: p.fullName, seed: p.id),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.sans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: d.textPrimary),
                                ),
                              ),
                              if (p.isPendingSync) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'بانتظار الاتصال للمزامنة',
                                  child: Icon(Icons.cloud_off_outlined,
                                      size: 14, color: d.warnBoxFg),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            p.id > 0 ? 'ملف رقم ${p.id}' : 'ملف جديد',
                            style: AppType.sans(fontSize: 11, color: d.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (cols.phone)
                Expanded(
                  flex: _Columns.phoneFlex,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: text(phone.isEmpty ? '—' : phone, direction: TextDirection.ltr),
                  ),
                ),
              if (cols.lastVisit)
                Expanded(
                  flex: _Columns.lastVisitFlex,
                  child: text(
                    widget.lastVisit == null ? 'لم تُسجَّل' : desktopShortDate(widget.lastVisit!),
                    color: widget.lastVisit == null ? d.textMuted : null,
                  ),
                ),
              if (cols.doctor)
                Expanded(
                  flex: _Columns.doctorFlex,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: widget.doctorColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: text(widget.doctorLabel)),
                    ],
                  ),
                ),
              Expanded(
                flex: _Columns.balanceFlex,
                child: Text(
                  desktopMoney.format(p.remainingBalance),
                  textAlign: TextAlign.end,
                  style: AppType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: status == _BalanceStatus.due ? d.warnBoxFg : d.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: _Columns.statusFlex,
                child: Align(alignment: AlignmentDirectional.centerStart, child: badge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
