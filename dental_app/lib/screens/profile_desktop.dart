part of 'profile_screen.dart';

/// صفحة «الإعدادات» (حسابي) على سطح المكتب (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// لا لوحة لها في الكانفاس؛ بُنيت بلغة بقية الغلاف: بطاقة الحساب في عمود
/// جانبي ثابت (الصورة والاسم والباقة وحالة الاشتراك)، والنماذج في عمود
/// عريض بحقلين في السطر بدل عمود حقول بعرض 1100px. نفس وحدات التحكّم ونفس
/// [_formKey] ونفس الحفظ وقسم الحجز العام -- الفرق في التخطيط وحده، ولا يُبنى
/// التخطيطان معاً أبداً فلا يتنازعان المفتاح.
extension _ProfileDesktop on _ProfileScreenState {
  static const double _sideWidth = 340;

  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    final profile = _profile;
    if (_isLoading && profile == null) {
      return Center(child: CircularProgressIndicator(color: d.linkFg));
    }
    if (profile == null) {
      return DesktopErrorState(
        message: _errorMessage ?? 'تعذر تحميل بيانات الحساب.',
        onRetry: _load,
      );
    }

    // الحساب ونموذج العيادة متجاوران في الصف الأول، والحجز العام بعرض
    // الصفحة كاملاً تحتهما: عمود الحساب أقصر من النموذج، ووضع الحجز تحت
    // النموذج وحده كان يحشره في ثلثي العرض ويترك تحت الحساب فراغاً طويلاً.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _ProfileDesktop._sideWidth, child: _accountColumn(context, profile)),
              const SizedBox(width: 22),
              Expanded(child: _clinicForm(context)),
            ],
          ),
          const SizedBox(height: 20),
          _bookingDesktop(context),
        ],
      ),
    );
  }

  Widget _accountColumn(BuildContext context, DoctorProfile profile) {
    final d = context.desktop;
    final name = (profile.doctorName ?? '').trim();
    final active = profile.subscriptionActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // خلفية داكنة متدرّجة في الوضعين: صورة الحساب وشارة الباقة مصمّمتان
        // بالأبيض فوق رأس الجوال المتدرّج، فتُعرضان هنا فوق التدرّج نفسه.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.navy900, AppColors.indigo800, AppColors.violet700],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: d.panelShadow,
          ),
          child: Column(
            children: [
              _buildAvatarPicker(profile),
              const SizedBox(height: 12),
              Text(
                name.isEmpty ? 'حسابي' : 'د. $name',
                textAlign: TextAlign.center,
                style: AppType.kufi(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                profile.email,
                style: AppType.sans(fontSize: 12.5, color: Colors.white.withValues(alpha: .72)),
              ),
              const SizedBox(height: 12),
              TierBadge(tier: profile.tier),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DesktopCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? d.pillDoneBg : d.pillWaitingBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? d.pillDoneBorder : d.pillWaitingBorder),
                ),
                child: Icon(
                  active ? Icons.verified_outlined : Icons.error_outline,
                  size: 19,
                  color: active ? d.pillDoneFg : d.pillWaitingFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الاشتراك', style: AppType.sans(fontSize: 11, color: d.textSecondary)),
                    Text(
                      active
                          ? (profile.subscriptionExpiresAt != null
                              ? 'فعّال حتى ${_formatDate(profile.subscriptionExpiresAt!)}'
                              : 'فعّال')
                          : 'غير فعّال حالياً',
                      style: AppType.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _DesktopThemeCard(),
      ],
    );
  }

  Widget _clinicForm(BuildContext context) {
    final d = context.desktop;

    Widget heading(String text, String? hint) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: AppType.kufi(fontSize: 14.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
            if (hint != null)
              Text(hint, style: AppType.sans(fontSize: 11.5, color: d.textMuted)),
          ],
        );

    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 14),
            Expanded(child: b),
          ],
        );

    TextFormField field(TextEditingController controller, String label,
            {TextInputType? keyboard, bool obscure = false}) =>
        TextFormField(
          controller: controller,
          textAlign: TextAlign.right,
          keyboardType: keyboard,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
        );

    return DesktopCard(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('معلومات العيادة', 'تظهر في الوصفات المطبوعة وصفحة الحجز العامة'),
            const SizedBox(height: 14),
            pair(
              field(_nameController, 'اسم الطبيب'),
              field(_clinicNameController, 'اسم العيادة'),
            ),
            const SizedBox(height: 12),
            pair(
              field(_clinicAddressController, 'عنوان العيادة'),
              field(_clinicPhoneController, 'هاتف العيادة', keyboard: TextInputType.phone),
            ),
            const SizedBox(height: 22),
            Container(height: 1, color: d.cardBorder),
            const SizedBox(height: 18),
            heading('تغيير كلمة السر', 'اختياري — اتركهما فارغين لإبقاء كلمة السر الحالية'),
            const SizedBox(height: 14),
            pair(
              field(_newPasswordController, 'كلمة السر الجديدة', obscure: true),
              field(_confirmPasswordController, 'تأكيد كلمة السر الجديدة', obscure: true),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              Text(_saveError!, style: AppType.sans(fontSize: 12.5, color: d.badgeDot)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: 220,
                child: GradientButton(
                  label: 'حفظ التعديلات',
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── الحجز العام ─────────────────────────────────────────────────────────

  /// ترتيب أيام الأسبوع كما يقرؤه الطبيب هنا: السبت أولاً. القيم نفسها
  /// (0 = الإثنين ... 6 = الأحد، ترقيم الخادم) -- الترتيب للعرض وحده.
  static const List<int> _weekOrder = [5, 6, 0, 1, 2, 3, 4];

  /// «ما يراه المريض» بجملة واحدة محسوبة من النموذج الحالي (قبل الحفظ)،
  /// فيرى الطبيب أثر أي تعديل لحظة كتابته.
  String _bookingSummary() {
    if (!_bookingEnabled) return 'الصفحة متوقفة — لا يستطيع أحد الحجز منها الآن.';
    if (_selectedWorkDays.isEmpty) return 'لم تُحدَّد أيام عمل — لن تظهر أي خانة للحجز.';
    if (_workStart == null || _workEnd == null) {
      return 'لم تُحدَّد ساعات الدوام — لن تظهر أي خانة للحجز.';
    }
    final days = _selectedWorkDays.length;
    final daysLabel = days == 7
        ? 'كل أيام الأسبوع'
        : days == 1
            ? 'يوماً واحداً في الأسبوع'
            : days == 2
                ? 'يومين في الأسبوع'
                : '$days أيام في الأسبوع';
    return 'خانات كل $_slotDuration دقيقة من ${_formatTimeOfDay(_workStart!)} '
        'إلى ${_formatTimeOfDay(_workEnd!)}، $daysLabel. كل طلب يصلك في «المواعيد» لتقبله أو ترفضه.';
  }

  Widget _bookingDesktop(BuildContext context) {
    final d = context.desktop;
    if (_isBookingLoading) {
      return DesktopCard(
        padding: const EdgeInsets.all(22),
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(color: d.linkFg)),
        ),
      );
    }
    if (_bookingErrorMessage != null) {
      return DesktopCard(
        padding: const EdgeInsets.all(22),
        child: SizedBox(
          height: 200,
          child: DesktopErrorState(message: _bookingErrorMessage!, onRetry: _loadBookingSettings),
        ),
      );
    }

    final url = _fullBookingUrl;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text,
              style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
        );

    return DesktopCard(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _bookingFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الترويسة: العنوان وحالة الصفحة ومفتاح تشغيلها.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('صفحة الحجز العامة',
                          style: AppType.kufi(fontSize: 14.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                      Text('رابط عام يحجز منه أي مريض موعده مباشرةً بلا تسجيل دخول',
                          style: AppType.sans(fontSize: 11.5, color: d.textMuted)),
                    ],
                  ),
                ),
                DesktopBadge(
                  label: _bookingEnabled ? 'مفعّلة' : 'متوقفة',
                  colors: _bookingEnabled ? DesktopBadgeColors.done(d) : DesktopBadgeColors.neutral(d),
                  fontSize: 11,
                ),
                const SizedBox(width: 10),
                Switch(
                  value: _bookingEnabled,
                  activeThumbColor: Colors.white,
                  activeTrackColor: d.amountIn,
                  onChanged: (value) => _update(() => _bookingEnabled = value),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: d.cardBorder),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // عمود الإعدادات.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('الرابط'),
                      TextFormField(
                        controller: _slugController,
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'الرابط العام (Slug)',
                          prefixText: '/d/',
                          hintText: 'dr-fares',
                        ),
                        onChanged: (_) => _update(() {}),
                      ),
                      if (url.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: d.fieldBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: d.fieldBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.link, size: 17, color: d.linkFg),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  textDirection: TextDirection.ltr,
                                  style: AppType.sans(
                                      fontSize: 12.5, fontWeight: FontWeight.w700, color: d.linkFg),
                                ),
                              ),
                              const SizedBox(width: 8),
                              DesktopGhostButton(
                                icon: Icons.copy_outlined,
                                label: 'نسخ',
                                height: 34,
                                onTap: _copyBookingUrl,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      label('أيام العمل'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in _ProfileDesktop._weekOrder)
                            DesktopChip(
                              label: _weekdayLabels.firstWhere((day) => day.value == value).label,
                              selected: _selectedWorkDays.contains(value),
                              onTap: () => _update(() {
                                if (!_selectedWorkDays.remove(value)) _selectedWorkDays.add(value);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      label('الدوام والمواعيد'),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeField(
                              label: 'بداية الدوام',
                              time: _workStart,
                              onTap: () => _pickWorkTime(isStart: true),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _TimeField(
                              label: 'نهاية الدوام',
                              time: _workEnd,
                              onTap: () => _pickWorkTime(isStart: false),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue:
                                  _slotDurationOptions.contains(_slotDuration) ? _slotDuration : 30,
                              decoration: const InputDecoration(labelText: 'مدة الموعد الواحد'),
                              items: _slotDurationOptions
                                  .map((m) => DropdownMenuItem(value: m, child: Text('$m دقيقة')))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) _update(() => _slotDuration = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _bookingClinicPhoneController,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم واتساب العيادة (لإشعارات الطلبات الجديدة)',
                        ),
                      ),
                      if (_bookingSaveError != null) ...[
                        const SizedBox(height: 12),
                        Text(_bookingSaveError!, style: AppType.sans(fontSize: 12.5, color: d.badgeDot)),
                      ],
                      const SizedBox(height: 18),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: SizedBox(
                          width: 240,
                          child: GradientButton(
                            label: 'حفظ إعدادات الحجز',
                            gradient: AppColors.successButtonGradient,
                            isLoading: _isBookingSaving,
                            onPressed: _isBookingSaving ? null : _saveBookingSettings,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // العمود الجانبي: ما يراه المريض ورمز QR.
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: d.iconBoxBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: d.iconBoxBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const DesktopEyebrow('ما يراه المريض'),
                            const SizedBox(height: 6),
                            Text(
                              _bookingSummary(),
                              style: AppType.sans(fontSize: 12, height: 1.7, color: d.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('رمز QR لعيادتك',
                          style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        'اطبعه وعلّقه في العيادة — من يمسحه بكاميرا هاتفه يصل مباشرةً لصفحة الحجز.',
                        style: AppType.sans(fontSize: 11, height: 1.6, color: d.textMuted),
                      ),
                      const SizedBox(height: 10),
                      if (url.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                          decoration: BoxDecoration(
                            color: d.fieldBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: d.fieldBorder),
                          ),
                          child: Text(
                            'احفظ رابط الحجز أولاً لعرض رمز QR الخاص بعيادتك.',
                            textAlign: TextAlign.center,
                            style: AppType.sans(fontSize: 12, color: d.textSecondary),
                          ),
                        )
                      else
                        BookingQrCard(doctorName: _nameController.text, bookingUrl: url),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «مظهر التطبيق» على سطح المكتب (2026-09-24) -- نفس [ThemeController] الذي
/// يستعمله مبدّل «المزيد» على الجوال، بشكل شريط مقطّع بثلاث خانات بدل
/// الكبسولات الثلاث الكبيرة. لا «مزيد» في غلاف سطح المكتب، فبلا هذه البطاقة
/// لم يكن هناك طريق للوضع الليلي إطلاقاً.
class _DesktopThemeCard extends StatelessWidget {
  const _DesktopThemeCard();

  static const _options = <({ThemeMode mode, String label, IconData icon})>[
    (mode: ThemeMode.light, label: 'نهاري', icon: Icons.light_mode_outlined),
    (mode: ThemeMode.dark, label: 'ليلي', icon: Icons.dark_mode_outlined),
    (mode: ThemeMode.system, label: 'تلقائي', icon: Icons.brightness_auto_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return DesktopCard(
      padding: const EdgeInsets.all(16),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.instance.mode,
        builder: (context, current, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d.iconBoxBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: d.iconBoxBorder),
                  ),
                  child: Icon(Icons.palette_outlined, size: 19, color: d.iconBoxFg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مظهر التطبيق',
                          style: AppType.sans(
                              fontSize: 13.5, fontWeight: FontWeight.w700, color: d.textPrimary)),
                      Text(
                        current == ThemeMode.system
                            ? 'يتبع إعداد ويندوز تلقائياً'
                            : 'يُحفظ على هذا الجهاز',
                        style: AppType.sans(fontSize: 11, color: d.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: d.fieldBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: d.fieldBorder),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _DesktopThemeSegment(
                        label: _options[i].label,
                        icon: _options[i].icon,
                        selected: current == _options[i].mode,
                        onTap: () => ThemeController.instance.set(_options[i].mode),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopThemeSegment extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopThemeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DesktopThemeSegment> createState() => _DesktopThemeSegmentState();
}

class _DesktopThemeSegmentState extends State<_DesktopThemeSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final on = widget.selected;
    final fg = on ? d.onNavActive : (_hovered ? d.textPrimary : d.navInactiveFg);
    // طبقتان كروابط الشريط الجانبي: التدرّج ثابت في الخارجية، ولون المرور
    // وحده متحرّك في الداخلية -- التحريك بين تدرّج ولون مسطّح يومض.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: on
              ? BoxDecoration(
                  gradient: d.navActiveGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: d.navActiveShadow,
                )
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 38,
            decoration: BoxDecoration(
              color: !on && _hovered ? d.sidebarHover : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
