part of 'today_schedule_screen.dart';

/// صفحة «المواعيد» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من `Appointments.dc.html` على الكانفاس، و**ليست شاشة مواعيد
/// ثانية** (قرار محسوم): هي تخطيط آخر لنفس [TodayScheduleScreenState] --
/// نفس التحميل ونفس شبكة الساعات بأعمدة الأطباء ونفس أوراق الإضافة والتعديل
/// وتغيير الحالة والرد على طلبات الحجز. الجديد هنا ثلاثة أشياء فقط:
///
/// * **متنقّل يوم** (السابق/التالي والعودة لليوم) بدل شريط الأيام الستة --
///   الشاشة العريضة تعرض يوماً كاملاً بشبكته، والشريط قالب جوال.
/// * **مبدّل شبكة/قائمة** للّحظات التي يريد فيها الطبيب قراءة اليوم سطراً
///   سطراً لا مسح أعمدة.
/// * **لوحة تفاصيل جانبية** للموعد المختار بأزرار تأكيد الحضور والتعديل، ولوحة
///   طلبات الحجز تحتها -- النقر على موعد يختاره، والنقر المزدوج يفتح التعديل.
///
/// ملف `part` لا ملف مستقل لأن كل ما سبق حالةٌ ودوالٌّ خاصة بالشاشة الأمّ.
extension _ScheduleDesktop on TodayScheduleScreenState {
  static const double _sidePaneWidth = 320;

  /// اليوم المعروض. «عرض الكل» (مفتاح فارغ) لا معنى له في شبكة يوم واحد،
  /// فيُقرأ كاليوم الحالي -- و[_buildDesktop] يثبّته مفتاحاً فعلياً.
  DateTime get _desktopDay {
    final parts = _selectedDayKey.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<Appointment> get _desktopDayAppointments {
    final key = _dayKey(_desktopDay);
    return _allNormalAppointments
        .where((a) => _dayKey(a.appointmentDate) == key)
        .toList()
      ..sort((a, b) => (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0));
  }

  /// الموعد المعروض في لوحة التفاصيل: المختار إن كان في اليوم المعروض، وإلا
  /// أول موعد فيه -- فلا تبقى اللوحة فارغة ولا تعرض موعداً من يوم آخر.
  Appointment? _desktopSelected() {
    final list = _desktopDayAppointments;
    if (list.isEmpty) return null;
    for (final a in list) {
      if (a.id == _selectedAppointmentId) return a;
    }
    return list.first;
  }

  void _goToDay(DateTime day) {
    _update(() => _selectedAppointmentId = null);
    _selectDay(_dayKey(day));
  }

  // DateTime(y, m, d ± 1) لا add(Duration(days: 1)): الأخيرة تنزاح ساعةً
  // يوم تغيير التوقيت الصيفي فتقع على اليوم نفسه.
  void _shiftDay(int delta) {
    final day = _desktopDay;
    _goToDay(DateTime(day.year, day.month, day.day + delta));
  }

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    if (_selectedDayKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedDayKey.isEmpty) _selectDay(_dayKey(DateTime.now()));
      });
    }
    if (_isLoading && _appointments == null) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (_errorMessage != null && _appointments == null) {
      return DesktopErrorState(message: _errorMessage!, onRetry: refresh);
    }

    final appointments = _desktopDayAppointments;
    final selected = _desktopSelected();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHeader(context, appointments),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _desktopMainPanel(context, appointments, selected)),
                const SizedBox(width: 20),
                SizedBox(
                  width: _ScheduleDesktop._sidePaneWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _desktopDetailsCard(context, selected),
                      const SizedBox(height: 14),
                      Expanded(child: _desktopRequestsCard(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── الترويسة: متنقّل اليوم + مبدّل العرض + موعد جديد ─────────────────────

  Widget _desktopHeader(BuildContext context, List<Appointment> appointments) {
    final d = context.desktop;
    final day = _desktopDay;
    final now = DateTime.now();
    final isToday = _dayKey(day) == _dayKey(now);
    final line = desktopArabicDateLine(day);
    final dateLabel = day.year == now.year ? line.replaceFirst(' ${day.year}', '') : line;
    final doctorCount = 1 + _clinicDoctors.length;

    final count = appointments.length;
    final countWord = count == 0
        ? 'لا مواعيد في هذا اليوم'
        : count == 1
            ? 'موعد واحد'
            : count == 2
                ? 'موعدان'
                : count <= 10
                    ? '$count مواعيد'
                    : '$count موعداً';
    final summary = count > 0 && doctorCount > 1 ? '$countWord عبر $doctorCount أطباء' : countWord;

    return Row(
      children: [
        DesktopSquareButton(
          icon: Icons.chevron_right,
          tooltip: 'اليوم السابق',
          size: 36,
          onTap: () => _shiftDay(-1),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: isToday ? 'اليوم' : 'العودة إلى اليوم',
          child: MouseRegion(
            cursor: isToday ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: isToday ? null : () => _goToDay(now),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: d.fieldBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: d.iconBtnBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dateLabel,
                      style: AppType.sans(
                          fontSize: 13, fontWeight: FontWeight.w700, color: d.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: d.iconBoxBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isToday ? 'اليوم' : 'العودة لليوم',
                        style: AppType.sans(
                            fontSize: 10.5, fontWeight: FontWeight.w700, color: d.linkFg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        DesktopSquareButton(
          icon: Icons.chevron_left,
          tooltip: 'اليوم التالي',
          size: 36,
          onTap: () => _shiftDay(1),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            summary,
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
        _desktopViewSwitch(context),
        const SizedBox(width: 10),
        DesktopCtaButton(icon: Icons.add, label: 'موعد جديد', onTap: _openAddAppointmentSheet),
      ],
    );
  }

  Widget _desktopViewSwitch(BuildContext context) {
    final d = context.desktop;
    Widget segment(String label, IconData icon, bool on, VoidCallback onTap) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? d.cardBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: .10),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: on ? d.linkFg : d.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: on ? d.linkFg : d.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: d.fieldBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: d.iconBtnBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('شبكة الساعات', Icons.view_week_outlined, !_desktopListView,
              () => _update(() => _desktopListView = false)),
          const SizedBox(width: 2),
          segment('قائمة', Icons.format_list_bulleted, _desktopListView,
              () => _update(() => _desktopListView = true)),
        ],
      ),
    );
  }

  // ── اللوحة الرئيسية: الشبكة أو القائمة ──────────────────────────────────

  Widget _desktopMainPanel(
      BuildContext context, List<Appointment> appointments, Appointment? selected) {
    final d = context.desktop;
    final Widget body;
    if (!_desktopListView) {
      // الشبكة تُعرض حتى ليوم فارغ: أعمدة الأطباء وساعات العمل الفارغة هي
      // الجواب على «متى أستطيع الحجز؟»، ورسالة «لا مواعيد» لا تجيب عنه.
      body = _buildHourColumnsGrid(appointments, fillHeight: true, framed: false);
    } else if (appointments.isEmpty) {
      body = const DesktopEmptyHint(
        icon: Icons.event_available_outlined,
        text: 'لا توجد مواعيد في هذا اليوم',
      );
    } else {
      body = _desktopList(context, appointments, selected);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: d.cardBg,
        gradient: d.cardGradient,
        borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusPanel),
        border: Border.all(color: d.cardBorder),
        boxShadow: d.panelShadow,
      ),
      child: body,
    );
  }

  Widget _desktopList(
      BuildContext context, List<Appointment> appointments, Appointment? selected) {
    final d = context.desktop;
    final multiDoctor = _clinicDoctors.isNotEmpty;

    Widget head(String text, int flex) => Expanded(
          flex: flex,
          child: Text(
            text,
            style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.textSecondary),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: d.fieldBg,
            border: Border(bottom: BorderSide(color: d.cardBorder)),
          ),
          child: Row(
            children: [
              head('الوقت', 14),
              head('المريض', 24),
              if (multiDoctor) head('الطبيب', 20),
              head('النوع', 22),
              head('المدة', 12),
              head('الحالة', 16),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: appointments.length,
            itemBuilder: (context, i) {
              final a = appointments[i];
              return _DesktopAppointmentRow(
                appointment: a,
                selected: a.id == selected?.id,
                showDoctor: multiDoctor,
                doctorName: a.clinicDoctorName ?? _ownerLabel,
                doctorColor: clinicDoctorColor(a.clinicDoctorId, _clinicDoctors),
                onTap: () => _update(() => _selectedAppointmentId = a.id),
                onDoubleTap: () => _openEditAppointmentSheet(a),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── لوحة التفاصيل ───────────────────────────────────────────────────────

  Widget _desktopDetailsCard(BuildContext context, Appointment? a) {
    final d = context.desktop;
    if (a == null) {
      return const DesktopCard(
        glow: true,
        radius: 26,
        padding: EdgeInsets.all(20),
        child: SizedBox(
          height: 150,
          child: DesktopEmptyHint(
            icon: Icons.touch_app_outlined,
            text: 'لا مواعيد في هذا اليوم',
          ),
        ),
      );
    }

    final updating = _updatingIds.contains(a.id);
    final phone = (a.patientPhone ?? '').trim();
    final notes = (a.notes ?? '').trim();
    final checkedIn = a.status.toLowerCase() == 'checked_in';

    Widget kv(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(label, style: AppType.sans(fontSize: 12.5, color: d.textSecondary)),
              const SizedBox(width: 12),
              Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: value)),
            ],
          ),
        );
    Widget strong(String text, {TextDirection? direction}) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: direction,
          style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary),
        );

    return DesktopCard(
      glow: true,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              Expanded(
                child: Text(
                  'الموعد المحدَّد',
                  style: AppType.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: d.linkFg),
                ),
              ),
              desktopStatusPill(context, a.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desktopClockLabel(a.startMinutes),
            style: AppType.kufi(fontSize: 28, fontWeight: FontWeight.w800, color: d.bigNumber)
                .copyWith(
              shadows: d.bigNumberGlow == null
                  ? null
                  : [Shadow(color: d.bigNumberGlow!, blurRadius: 32)],
            ),
          ),
          Text(
            'حتى ${desktopClockLabel(a.endMinutes)} · ${a.durationLabel}',
            style: AppType.sans(fontSize: 12, color: d.textSecondary),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: d.cardBorder),
          const SizedBox(height: 14),
          kv('المريض', strong(a.patientName.isEmpty ? '—' : a.patientName)),
          if (_clinicDoctors.isNotEmpty)
            kv(
              'الطبيب',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: clinicDoctorColor(a.clinicDoctorId, _clinicDoctors),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: strong(a.clinicDoctorName ?? _ownerLabel)),
                ],
              ),
            ),
          kv('نوع الموعد', strong(a.procedureType.isEmpty ? '—' : a.procedureType)),
          if (phone.isNotEmpty) kv('الهاتف', strong(phone, direction: TextDirection.ltr)),
          if (notes.isNotEmpty && notes != a.procedureType)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(fontSize: 12, color: d.textMuted),
              ),
            ),
          const SizedBox(height: 6),
          if (updating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 19),
              child: LinearProgressIndicator(minHeight: 3, color: d.linkFg),
            )
          else
            Row(
              children: [
                Expanded(
                  child: checkedIn
                      ? DesktopCtaButton(
                          icon: Icons.swap_horiz,
                          label: 'تغيير الحالة',
                          expand: true,
                          onTap: () => _openStatusPicker(a),
                        )
                      : DesktopCtaButton(
                          icon: Icons.check,
                          label: 'تأكيد الحضور',
                          expand: true,
                          onTap: () => _setStatus(a, 'checked_in'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DesktopGhostButton(
                    icon: Icons.edit_outlined,
                    label: 'تعديل',
                    height: 44,
                    onTap: () => _openEditAppointmentSheet(a),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!checkedIn)
                DesktopTextLink(label: 'تغيير الحالة', onTap: () => _openStatusPicker(a)),
              const Spacer(),
              if (phone.isNotEmpty)
                DesktopTextLink(label: 'تذكير واتساب', onTap: () => _sendWhatsappReminder(a)),
            ],
          ),
        ],
      ),
    );
  }

  // ── طلبات الحجز ─────────────────────────────────────────────────────────

  Widget _desktopRequestsCard(BuildContext context) {
    final d = context.desktop;
    final requests = _bookingRequests;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طلبات الحجز',
                  style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                ),
              ),
              if (requests.isNotEmpty)
                DesktopBadge(
                  label: '${requests.length} بانتظار الرد',
                  colors: DesktopBadgeColors.waiting(d),
                  fontSize: 11,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text('من صفحة الحجز العامة', style: AppType.sans(fontSize: 11, color: d.textMuted)),
          const SizedBox(height: 10),
          Expanded(
            child: requests.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد طلبات حجز جديدة حالياً.',
                      style: AppType.sans(fontSize: 12.5, color: d.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: requests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      return _DesktopRequestTile(
                        request: r,
                        updating: _updatingIds.contains(r.id),
                        onAccept: () => _respond(r, 'accept'),
                        onReject: () => _respond(r, 'reject'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// صفّ موعد في عرض القائمة.
class _DesktopAppointmentRow extends StatefulWidget {
  final Appointment appointment;
  final bool selected;
  final bool showDoctor;
  final String doctorName;
  final Color doctorColor;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _DesktopAppointmentRow({
    required this.appointment,
    required this.selected,
    required this.showDoctor,
    required this.doctorName,
    required this.doctorColor,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_DesktopAppointmentRow> createState() => _DesktopAppointmentRowState();
}

class _DesktopAppointmentRowState extends State<_DesktopAppointmentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final a = widget.appointment;
    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);
    Widget text(String value, {bool strong = false}) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(
            fontSize: 12.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            color: strong ? d.textPrimary : d.navInactiveFg,
          ),
        );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          height: 52,
          padding: const EdgeInsetsDirectional.only(start: 15, end: 18),
          decoration: BoxDecoration(
            color: widget.selected
                ? d.linkFg.withValues(alpha: d.isDark ? .14 : .05)
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
              cell(14, text(desktopClockLabel(a.startMinutes), strong: true)),
              cell(24, text(a.patientName.isEmpty ? '—' : a.patientName)),
              if (widget.showDoctor)
                cell(
                  20,
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: widget.doctorColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: text(widget.doctorName)),
                    ],
                  ),
                ),
              cell(22, text(a.procedureType.isEmpty ? '—' : a.procedureType)),
              cell(12, text(a.durationLabel)),
              cell(
                16,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: desktopStatusPill(context, a.status),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// طلب حجز وارد من صفحة الحجز العامة، بزرَّي قبول ورفض.
class _DesktopRequestTile extends StatelessWidget {
  final Appointment request;
  final bool updating;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _DesktopRequestTile({
    required this.request,
    required this.updating,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final date = request.appointmentDate;
    final now = DateTime.now();
    String when = desktopClockLabel(request.startMinutes);
    if (date != null) {
      final line = desktopArabicDateLine(date);
      final dayLabel = date.year == now.year ? line.replaceFirst(' ${date.year}', '') : line;
      when = '$dayLabel · $when';
    }
    final phone = (request.patientPhone ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: d.rowHover,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.patientName.isEmpty ? '—' : request.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                          fontSize: 13, fontWeight: FontWeight.w700, color: d.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(when, style: AppType.sans(fontSize: 11, color: d.textSecondary)),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: AppType.sans(fontSize: 11, color: d.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (updating)
            LinearProgressIndicator(minHeight: 3, color: d.linkFg)
          else
            Row(
              children: [
                Expanded(
                  child: _RequestButton(
                    label: 'قبول',
                    background: d.amountIn,
                    foreground: const Color(0xFFFFFFFF),
                    onTap: onAccept,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _RequestButton(
                    label: 'رفض',
                    background: d.cardBg,
                    foreground: d.navInactiveFg,
                    border: d.iconBtnBorder,
                    onTap: onReject,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RequestButton extends StatefulWidget {
  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback onTap;

  const _RequestButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  @override
  State<_RequestButton> createState() => _RequestButtonState();
}

class _RequestButtonState extends State<_RequestButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _hovered ? .88 : 1,
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.background,
              borderRadius: BorderRadius.circular(10),
              border: widget.border == null ? null : Border.all(color: widget.border!),
            ),
            child: Text(
              widget.label,
              style: AppType.sans(fontSize: 12, fontWeight: FontWeight.w700, color: widget.foreground),
            ),
          ),
        ),
      ),
    );
  }
}
