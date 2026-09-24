part of 'patient_detail_screen.dart';

/// «حالة المريض» على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// على الجوال عمود واحد تحت ترويسة متدرّجة. على نافذة ويندوز كان العمود
/// نفسه يمتدّ بعرض 1500px: مخطط أسنان بعرض الشاشة، وكل قسم تحت الآخر فيمرّر
/// الطبيب طويلاً ليصل إلى الفواتير. هنا:
///
/// * **ترويسة سطح مكتب** بلون الصفحة: رجوع، اسم المريض ورقم ملفه، وأزرار
///   الإجراءات الثلاثة الأكثر استعمالاً (تعديل، موعد، فاتورة).
/// * **عمودان**: عمود جانبي ثابت العرض (بطاقة المريض والرصيد، المواعيد،
///   الوصفات) وعمود عريض (مخطط الأسنان، الفواتير، الأرشيف).
///
/// الأقسام نفسها لم تُعَد كتابتها: كلها تمرّ بـ SectionCard التي تأخذ بطاقة
/// سطح المكتب تلقائياً فوق العتبة، ونفس الأوراق والحوارات ونفس المنطق.
extension _PatientDetailDesktop on _PatientDetailScreenState {
  static const double _sideWidth = 380;

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    return Scaffold(
      backgroundColor: d.shellBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopTopBar(context),
          const OfflineSyncBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _PatientDetailDesktop._sideWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _desktopPatientCard(context),
                        const SizedBox(height: 18),
                        _buildAppointmentsSection(),
                        const SizedBox(height: 18),
                        _buildPrescriptionsSection(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildChartCard(),
                        const SizedBox(height: 18),
                        _buildInvoicesSection(),
                        const SizedBox(height: 18),
                        _buildArchiveSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopTopBar(BuildContext context) {
    final d = context.desktop;
    final age = _patient.age;
    final meta = [
      if (_patient.id > 0) 'ملف رقم ${_patient.id}',
      if (age != null) '$age سنة',
    ].join(' · ');

    return Container(
      height: AppDesktopMetrics.topBarHeight,
      padding: AppDesktopMetrics.topBarPadding,
      decoration: BoxDecoration(
        color: d.shellBg,
        border: Border(bottom: BorderSide(color: d.topBarBorder)),
      ),
      child: Row(
        children: [
          DesktopSquareButton(
            icon: Icons.arrow_forward,
            tooltip: 'رجوع إلى المرضى',
            size: 40,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          DesktopInitialsTile(name: _patient.fullName, seed: _patient.id, size: 44, radius: 14, fontSize: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _patient.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.kufi(fontSize: 19, fontWeight: FontWeight.w700, color: d.textPrimary),
                      ),
                    ),
                    if (_patient.isPendingSync) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'بانتظار الاتصال للمزامنة',
                        child: Icon(Icons.cloud_off_outlined, size: 16, color: d.warnBoxFg),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta, style: AppType.sans(fontSize: 12, color: d.textSecondary)),
              ],
            ),
          ),
          DesktopGhostButton(
            icon: Icons.edit_outlined,
            label: 'تعديل البيانات',
            onTap: _openEditPatientSheet,
          ),
          const SizedBox(width: 8),
          DesktopGhostButton(
            icon: Icons.event_outlined,
            label: 'موعد جديد',
            onTap: () => _openAppointmentFormSheet(),
          ),
          const SizedBox(width: 8),
          DesktopCtaButton(
            icon: Icons.add,
            label: 'فاتورة جديدة',
            onTap: _openCreateInvoiceDialog,
          ),
        ],
      ),
    );
  }

  Widget _desktopPatientCard(BuildContext context) {
    final d = context.desktop;
    final phone = _patient.phone.replaceAll(RegExp(r'\s+'), '');
    final history = (_patient.medicalHistory ?? '').trim();
    final doctor = _patient.clinicDoctorId == null ? null : _patient.clinicDoctorName;

    Widget info(IconData icon, String label, String value, {TextDirection? direction}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: d.textMuted),
              const SizedBox(width: 8),
              Text(label, style: AppType.sans(fontSize: 12.5, color: d.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: direction,
                    style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        );

    return DesktopCard(
      glow: true,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DesktopEyebrow('الرصيد المتبقّي'),
          const SizedBox(height: 6),
          DesktopBigAmount(value: desktopMoney.format(_patientRemainingBalance), fontSize: 30),
          const SizedBox(height: 16),
          DesktopFiguresRow(
            figures: [
              DesktopFigure(
                label: 'إجمالي العلاجات',
                value: desktopMoney.format(_patient.totalTreatmentCost),
              ),
              DesktopFigure(
                label: 'المدفوع',
                value: desktopMoney.format(_patient.paidAmount),
                color: d.amountIn,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: d.cardBorder),
          const SizedBox(height: 14),
          info(Icons.call_outlined, 'الهاتف', phone.isEmpty ? '—' : phone, direction: TextDirection.ltr),
          if (doctor != null) info(Icons.medical_services_outlined, 'الطبيب المعالج', doctor),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: d.warnBoxBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: d.warnBoxBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: d.warnBoxFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      history,
                      style: AppType.sans(fontSize: 12.5, height: 1.6, color: d.warnBoxFg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
