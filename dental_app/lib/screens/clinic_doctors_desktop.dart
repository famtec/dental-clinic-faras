part of 'clinic_doctors_screen.dart';

/// صفحة «الأطباء والنسب» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// مبنيّة من `Doctors.dc.html` على الكانفاس، وتخطيطٌ آخر لنفس
/// [_ClinicDoctorsScreenState]: نفس القائمة ونفس الفترة ونفس أوراق الإضافة
/// والتعديل والتسوية. الفرق أن **كشف الحساب يُعرض بجانب القائمة** بدل صفحة
/// مدفوعة فوقها (الجوال يبقى على [DoctorStatementScreen])، فيتنقّل الطبيب
/// المدير بين أطبائه بنقرة ويبقى المؤشّر العام ظاهراً.
///
/// حلقة «توزيع المحصّل» في الكانفاس صارت أشرطة أفقية: القيم نفسها (حصة كل
/// طبيب وحصة العيادة من المحصّل) بقراءة أدقّ للنسب الصغيرة.
extension _ClinicDoctorsDesktop on _ClinicDoctorsScreenState {
  static const double _listWidth = 360;

  String get _periodKey {
    if (_allTime) return 'all';
    if (_isToday) return 'today';
    final now = DateTime.now();
    return '${_selectedYear ?? now.year}-${_selectedMonth ?? now.month}';
  }

  ClinicDoctor? _desktopSelectedDoctor(List<ClinicDoctor> doctors) {
    if (doctors.isEmpty) return null;
    for (final d in doctors) {
      if (d.id == _selectedDoctorId) return d;
    }
    return doctors.first;
  }

  /// يطلب كشف حساب الطبيب المختار للفترة الحالية، إن لم يكن محمّلاً.
  Future<void> _ensureStatement(ClinicDoctor doctor) async {
    final key = '${doctor.id}|$_periodKey';
    if (_statementKey == key) return;
    _update(() {
      _statementKey = key;
      _statementLoading = true;
      _statementError = null;
    });
    final today = DateTime.now();
    try {
      final statement = await widget.apiService.fetchDoctorStatement(
        doctor.id,
        year: _isToday ? today.year : _selectedYear,
        month: _isToday ? today.month : _selectedMonth,
        day: _isToday ? today.day : null,
        allTime: _allTime,
      );
      if (!mounted || _statementKey != key) return;
      _update(() {
        _statement = statement;
        _statementLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || _statementKey != key) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _update(() {
        _statementError = e.message;
        _statementLoading = false;
      });
    } catch (_) {
      if (!mounted || _statementKey != key) return;
      _update(() {
        _statementError = 'تعذر تحميل كشف الحساب.';
        _statementLoading = false;
      });
    }
  }

  /// بعد أي تغيير يمسّ الأرقام (تسوية، تعديل نسبة، حذف): القائمة والكشف معاً.
  void _reloadAll() {
    _update(() => _statementKey = null);
    _load();
  }

  Future<void> _confirmDeletePayoutDesktop(ClinicDoctor doctor, DoctorPayoutRow payout) async {
    final d = context.desktop;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surface.sheetBg,
        title: Text('حذف التسوية؟',
            style: AppType.kufi(fontSize: 15, fontWeight: FontWeight.w700, color: d.textPrimary)),
        content: Text(
          'حذف تسوية بمبلغ ${formatDoctorsMoney(payout.amount)} ل.س يُعيد '
          'المبلغ إلى الرصيد المستحق للطبيب.',
          style: AppType.sans(fontSize: 13.5, height: 1.7, color: d.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('حذف', style: TextStyle(color: d.badgeDot)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteDoctorPayout(doctor.id, payout.id);
      if (!mounted) return;
      _toast('تم حذف التسوية');
      _reloadAll();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      _toast(e.message);
    } catch (_) {
      _toast('تعذر حذف التسوية.');
    }
  }

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    if (_isLoading && _doctors == null) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (_isPremiumLocked) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _buildPremiumLockCard(),
        ),
      );
    }
    if (_errorMessage != null && _doctors == null) {
      return DesktopErrorState(message: _errorMessage!, onRetry: _load);
    }

    final doctors = _doctors ?? const <ClinicDoctor>[];
    final selected = _desktopSelectedDoctor(doctors);
    if (selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureStatement(selected);
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopHeader(context),
          const SizedBox(height: 16),
          _kpiStrip(context, doctors),
          const SizedBox(height: 18),
          Expanded(
            child: doctors.isEmpty
                ? DesktopTablePanel(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const DesktopEmptyHint(
                            icon: Icons.medical_services_outlined,
                            text: 'لا أطباء مساعدين بعد',
                          ),
                          const SizedBox(height: 16),
                          DesktopCtaButton(
                            icon: Icons.person_add_alt_1_outlined,
                            label: 'إضافة طبيب',
                            onTap: () => _openDoctorSheet(),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _ClinicDoctorsDesktop._listWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _doctorsList(context, doctors, selected)),
                            const SizedBox(height: 14),
                            _distributionCard(context, doctors),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: _statementPanel(context, selected!)),
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
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 18; i++)
        (year: DateTime(now.year, now.month - i, 1).year, month: DateTime(now.year, now.month - i, 1).month),
    ];
    return Row(
      children: [
        DesktopMenuButton<String>(
          label: _periodLabel,
          tooltip: 'الفترة',
          options: [
            (value: 'today', label: 'اليوم'),
            for (final m in months)
              (value: '${m.year}-${m.month}', label: '${_doctorsArabicMonths[m.month - 1]} ${m.year}'),
            (value: 'all', label: 'كل الفترات'),
          ],
          onSelected: (value) {
            if (value == _periodKey) return;
            if (value == 'today') {
              _selectPeriod(isToday: true);
            } else if (value == 'all') {
              _selectPeriod(allTime: true);
            } else {
              final parts = value.split('-');
              _selectPeriod(year: int.parse(parts[0]), month: int.parse(parts[1]));
            }
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'النسبة تُحسب على المبلغ المحصّل فعلاً، لا على قيمة الفاتورة',
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
          icon: Icons.person_add_alt_1_outlined,
          label: 'إضافة طبيب',
          onTap: () => _openDoctorSheet(),
        ),
      ],
    );
  }

  Widget _kpiStrip(BuildContext context, List<ClinicDoctor> doctors) {
    final d = context.desktop;
    double sum(double Function(ClinicDoctor) pick) =>
        doctors.fold<double>(0, (total, doc) => total + pick(doc));
    final collected = sum((x) => x.periodCollected);
    final clinic = sum((x) => x.periodClinicShare);
    final doctorsShare = sum((x) => x.periodDoctorShare);
    final balance = sum((x) => x.balanceDue);
    return Row(
      children: [
        Expanded(
          child: DesktopKpiCard(
            label: 'إجمالي المحصّل — $_periodLabel',
            value: formatDoctorsMoney(collected),
            suffix: 'ل.س',
            highlight: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'حصة العيادة',
            value: formatDoctorsMoney(clinic),
            suffix: 'ل.س',
            valueColor: d.amountIn,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'مستحقات الأطباء في الفترة',
            value: formatDoctorsMoney(doctorsShare),
            suffix: 'ل.س',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DesktopKpiCard(
            label: 'رصيد غير مسدَّد (تراكمي)',
            value: formatDoctorsMoney(balance),
            suffix: 'ل.س',
            valueColor: balance > 0 ? d.amountOut : null,
          ),
        ),
      ],
    );
  }

  // ── قائمة الأطباء ───────────────────────────────────────────────────────

  Widget _doctorsList(BuildContext context, List<ClinicDoctor> doctors, ClinicDoctor? selected) {
    final d = context.desktop;
    final active = doctors.where((x) => x.isActive).length;
    return DesktopTablePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'الأطباء المساعدون',
                    style: AppType.kufi(fontSize: 14, fontWeight: FontWeight.w700, color: d.textPrimary),
                  ),
                ),
                Text(
                  '$active فعّال · ${doctors.length - active} معطّل',
                  style: AppType.sans(fontSize: 11.5, color: d.textSecondary),
                ),
              ],
            ),
          ),
          Container(height: 1, color: d.cardBorder),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: doctors.length,
              itemBuilder: (context, i) {
                final doc = doctors[i];
                return DesktopTableRow(
                  selected: doc.id == selected?.id,
                  onTap: () => _update(() => _selectedDoctorId = doc.id),
                  padding: const EdgeInsetsDirectional.fromSTEB(15, 12, 16, 12),
                  child: _DoctorListTile(
                    doctor: doc,
                    color: clinicDoctorColor(doc.id, doctors),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionCard(BuildContext context, List<ClinicDoctor> doctors) {
    final d = context.desktop;
    final collected = doctors.fold<double>(0, (t, x) => t + x.periodCollected);
    final clinic = doctors.fold<double>(0, (t, x) => t + x.periodClinicShare);
    final rows = <({String label, double value, Color color})>[
      for (final doc in [...doctors]..sort((a, b) => b.periodDoctorShare.compareTo(a.periodDoctorShare)))
        if (doc.periodDoctorShare > 0)
          (label: doc.fullName, value: doc.periodDoctorShare, color: clinicDoctorColor(doc.id, doctors)),
      (label: 'حصة العيادة', value: clinic, color: d.linkFg),
    ];

    return DesktopCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('توزيع المحصّل',
              style: AppType.kufi(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
          Text('من كل ليرة دخلت العيادة في الفترة',
              style: AppType.sans(fontSize: 11, color: d.textMuted)),
          const SizedBox(height: 12),
          if (collected <= 0)
            Text('لا تحصيل في هذه الفترة.', style: AppType.sans(fontSize: 12, color: d.textSecondary))
          else
            for (final r in rows) ...[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: 12, color: d.textPrimary)),
                  ),
                  Text('${(r.value / collected * 100).round()}٪',
                      style: AppType.sans(fontSize: 12, fontWeight: FontWeight.w700, color: d.textPrimary)),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (r.value / collected).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  color: r.color,
                  backgroundColor: d.rowDivider,
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  // ── كشف الحساب ──────────────────────────────────────────────────────────

  Widget _statementPanel(BuildContext context, ClinicDoctor doctor) {
    final d = context.desktop;
    final doctors = _doctors ?? const <ClinicDoctor>[];
    final statement = _statement;
    final fresh = statement != null && _statementKey == '${doctor.id}|$_periodKey' && !_statementLoading;
    final period = fresh ? statement.period : null;

    return DesktopTablePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCard(
            glow: true,
            flat: true,
            radius: 0,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: clinicDoctorColor(doctor.id, doctors),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        desktopInitials(doctor.fullName),
                        style: AppType.kufi(
                            fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFFFFFFFF)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const DesktopEyebrow('كشف حساب'),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  doctor.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.kufi(
                                      fontSize: 18, fontWeight: FontWeight.w700, color: d.textPrimary),
                                ),
                              ),
                              if (!doctor.isActive) ...[
                                const SizedBox(width: 8),
                                DesktopBadge(
                                    label: 'معطّل', colors: DesktopBadgeColors.neutral(d), fontSize: 10.5),
                              ],
                            ],
                          ),
                          Text(
                            '${(doctor.specialty ?? '').trim().isEmpty ? 'طبيب في العيادة' : doctor.specialty} · النسبة الحالية ${formatDoctorsPercent(doctor.commissionPercent)}٪',
                            style: AppType.sans(fontSize: 12, color: d.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    DesktopGhostButton(
                      label: doctor.isActive ? 'تعطيل' : 'تفعيل',
                      onTap: () => _toggleActive(doctor),
                    ),
                    const SizedBox(width: 8),
                    DesktopGhostButton(
                      icon: Icons.edit_outlined,
                      label: 'تعديل',
                      onTap: () => _openDoctorSheet(doctor: doctor),
                    ),
                    const SizedBox(width: 8),
                    DesktopCtaButton(
                      icon: Icons.payments_outlined,
                      label: 'تسجيل تسوية',
                      onTap: () => _openPayoutSheet(doctor),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DesktopFiguresRow(
                  figures: [
                    DesktopFigure(
                      label: 'المحصّل من عمله',
                      value: formatDoctorsMoney(period?.collected ?? doctor.periodCollected),
                    ),
                    DesktopFigure(
                      label: 'حصّته',
                      value: formatDoctorsMoney(period?.doctorShare ?? doctor.periodDoctorShare),
                      color: d.linkFg,
                    ),
                    DesktopFigure(
                      label: 'المسدَّد له',
                      value: formatDoctorsMoney(period?.paidOut ?? 0),
                      color: d.amountIn,
                    ),
                    DesktopFigure(
                      label: 'الرصيد المستحق (تراكمي)',
                      value: formatDoctorsMoney(doctor.balanceDue),
                      color: doctor.balanceDue > 0 ? d.amountOut : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: d.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              children: [
                for (final (i, label) in const ['الكل', 'الاستحقاقات', 'التسويات'].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  DesktopChip(
                    label: label,
                    selected: _statementTab == i,
                    onTap: () => _update(() => _statementTab = i),
                  ),
                ],
                const SizedBox(width: 14),
                Icon(Icons.info_outline, size: 15, color: d.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'النسبة تُجمَّد لحظة الدفعة — تعديلها يسري على العمل القادم فقط',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(fontSize: 11.5, color: d.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const DesktopTableHeader(columns: [
            (label: 'البيان', flex: 36, align: TextAlign.start),
            (label: 'التاريخ', flex: 14, align: TextAlign.start),
            (label: 'المحصّل', flex: 14, align: TextAlign.start),
            (label: 'النسبة المطبّقة', flex: 13, align: TextAlign.start),
            (label: 'له / عليه', flex: 16, align: TextAlign.end),
            (label: '', flex: 5, align: TextAlign.start),
          ]),
          Expanded(child: _statementRows(context, doctor, fresh ? statement : null)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: d.cardBorder))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'حصة العيادة = المحصّل − حصة الطبيب، فيتطابق المجموع مع المحصّل دائماً',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(fontSize: 11.5, color: d.textMuted),
                  ),
                ),
                Text('الرصيد المستحق: ', style: AppType.sans(fontSize: 12, color: d.textSecondary)),
                Text(
                  '${formatDoctorsMoney(doctor.balanceDue)} ل.س',
                  style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w800, color: d.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statementRows(BuildContext context, ClinicDoctor doctor, DoctorStatement? statement) {
    final d = context.desktop;
    if (statement == null) {
      if (_statementError != null && !_statementLoading) {
        return DesktopErrorState(
          message: _statementError!,
          onRetry: () {
            _update(() => _statementKey = null);
            _ensureStatement(doctor);
          },
        );
      }
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: d.linkFg),
        ),
      );
    }

    final entries = <({DateTime? at, Widget row})>[
      if (_statementTab != 2)
        for (final e in statement.earnings)
          (at: e.earnedAt, row: _EarningRow(earning: e)),
      if (_statementTab != 1)
        for (final p in statement.payouts)
          (
            at: p.paidAt,
            row: _PayoutRow(payout: p, onDelete: () => _confirmDeletePayoutDesktop(doctor, p)),
          ),
    ]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));

    if (entries.isEmpty) {
      return DesktopEmptyHint(
        icon: Icons.receipt_long_outlined,
        text: _statementTab == 2 ? 'لا تسويات في هذه الفترة' : 'لا حركات في هذه الفترة',
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [for (final e in entries) e.row],
    );
  }
}

class _DoctorListTile extends StatelessWidget {
  final ClinicDoctor doctor;
  final Color color;

  const _DoctorListTile({required this.doctor, required this.color});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final specialty = (doctor.specialty ?? '').trim();
    return Opacity(
      opacity: doctor.isActive ? 1 : .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
                child: Text(
                  desktopInitials(doctor.fullName),
                  style: AppType.kufi(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFFFFFFFF)),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            doctor.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                          ),
                        ),
                        if (!doctor.isActive) ...[
                          const SizedBox(width: 6),
                          DesktopBadge(label: 'معطّل', colors: DesktopBadgeColors.neutral(d), fontSize: 10),
                        ],
                      ],
                    ),
                    Text(
                      specialty.isEmpty ? 'طبيب في العيادة' : specialty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(fontSize: 11.5, color: d.textSecondary),
                    ),
                  ],
                ),
              ),
              DesktopBadge(
                label: '${formatDoctorsPercent(doctor.commissionPercent)}٪',
                colors: DesktopBadgeColors.upcoming(d),
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text('الرصيد المستحق', style: AppType.sans(fontSize: 11.5, color: d.textSecondary)),
              const Spacer(),
              Text(
                '${formatDoctorsMoney(doctor.balanceDue)} ل.س',
                style: AppType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: doctor.balanceDue > 0 ? d.amountOut : d.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningRow extends StatelessWidget {
  final DoctorEarningRow earning;

  const _EarningRow({required this.earning});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final date = earning.earnedAt;
    final patient = (earning.patientName ?? '').trim();
    final description = (earning.description ?? '').trim();
    return DesktopTableRow(
      child: Row(
        children: [
          Expanded(
            flex: 36,
            child: Row(
              children: [
                DesktopBadge(label: 'استحقاق', colors: DesktopBadgeColors.upcoming(d), fontSize: 10.5),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.isEmpty ? 'دفعة مريض' : patient,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                      ),
                      if (description.isNotEmpty || earning.isAdjusted)
                        Text(
                          earning.isAdjusted
                              ? '${description.isEmpty ? '' : '$description · '}عُدّلت الدفعة'
                              : description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(fontSize: 11, color: d.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(date == null ? '—' : desktopShortDate(date),
                style: AppType.sans(fontSize: 12.5, color: d.navInactiveFg)),
          ),
          Expanded(
            flex: 14,
            child: Text(formatDoctorsMoney(earning.grossAmount),
                style: AppType.sans(fontSize: 12.5, color: d.navInactiveFg)),
          ),
          Expanded(
            flex: 13,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: DesktopBadge(
                label: '${formatDoctorsPercent(earning.appliedPercent)}٪',
                colors: DesktopBadgeColors.neutral(d),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              '+${formatDoctorsMoney(earning.doctorShare)}',
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: AppType.sans(fontSize: 13, fontWeight: FontWeight.w700, color: d.amountIn),
            ),
          ),
          const Expanded(flex: 5, child: SizedBox()),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final DoctorPayoutRow payout;
  final VoidCallback onDelete;

  const _PayoutRow({required this.payout, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final date = payout.paidAt;
    final note = (payout.note ?? '').trim();
    return DesktopTableRow(
      child: Row(
        children: [
          Expanded(
            flex: 36,
            child: Row(
              children: [
                DesktopBadge(label: 'تسوية', colors: DesktopBadgeColors.waiting(d), fontSize: 10.5),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تسوية مدفوعة للطبيب',
                          style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                      if (note.isNotEmpty)
                        Text(note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(fontSize: 11, color: d.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(date == null ? '—' : desktopShortDate(date),
                style: AppType.sans(fontSize: 12.5, color: d.navInactiveFg)),
          ),
          Expanded(flex: 14, child: Text('—', style: AppType.sans(fontSize: 12.5, color: d.textMuted))),
          const Expanded(flex: 13, child: SizedBox()),
          Expanded(
            flex: 16,
            child: Text(
              '−${formatDoctorsMoney(payout.amount)}',
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: AppType.sans(fontSize: 13, fontWeight: FontWeight.w700, color: d.amountOut),
            ),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DesktopSquareButton(
                icon: Icons.delete_outline,
                tooltip: 'حذف التسوية',
                size: 30,
                onTap: onDelete,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
