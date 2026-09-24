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

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: _ProfileDesktop._sideWidth, child: _accountColumn(context, profile)),
          const SizedBox(width: 22),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _clinicForm(context),
                  const SizedBox(height: 18),
                  _buildBookingSettingsSection(),
                ],
              ),
            ),
          ),
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
}
