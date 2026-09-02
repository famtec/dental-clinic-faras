import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/booking_settings.dart';
import '../models/doctor_profile.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/booking_qr_card.dart';

const _weekdayLabels = [
  (value: 0, label: 'الإثنين'),
  (value: 1, label: 'الثلاثاء'),
  (value: 2, label: 'الأربعاء'),
  (value: 3, label: 'الخميس'),
  (value: 4, label: 'الجمعة'),
  (value: 5, label: 'السبت'),
  (value: 6, label: 'الأحد'),
];

const _slotDurationOptions = [15, 20, 30, 45, 60];

/// "حسابي" -- تطابق profile.html بالموقع: بيانات الطبيب/العيادة القابلة
/// للتعديل + تغيير كلمة السر + حالة الاشتراك. يستخدم main.py هنا
/// get_current_doctor_user عمداً (وليس require_active_doctor_user)، فتبقى
/// الشاشة متاحة حتى للحساب المعلَّق/منتهي الاشتراك.
class ProfileScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onSessionExpired;

  const ProfileScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onSessionExpired,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _clinicAddressController = TextEditingController();
  final _clinicPhoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DoctorProfile? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _saveError;

  // -- إعدادات "صفحة الحجز العامة" (قسم منفصل في نفس الشاشة، مطابق لقسم
  // profile.html بالموقع، وله حالة/حفظ مستقلان عن نموذج بيانات الحساب أعلاه).
  final _bookingFormKey = GlobalKey<FormState>();
  final _slugController = TextEditingController();
  final _bookingClinicPhoneController = TextEditingController();
  BookingSettings? _bookingSettings;
  bool _isBookingLoading = true;
  String? _bookingErrorMessage;
  bool _isBookingSaving = false;
  String? _bookingSaveError;
  bool _bookingEnabled = false;
  int _slotDuration = 30;
  TimeOfDay? _workStart;
  TimeOfDay? _workEnd;
  final Set<int> _selectedWorkDays = {};

  // -- صورة الحساب (الأفاتار) -- انظر _buildAvatarPicker/_pickAndUploadAvatar.
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBookingSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clinicNameController.dispose();
    _clinicAddressController.dispose();
    _clinicPhoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _slugController.dispose();
    _bookingClinicPhoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await widget.apiService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = profile.doctorName ?? '';
        _clinicNameController.text = profile.clinicName ?? '';
        _clinicAddressController.text = profile.clinicAddress ?? '';
        _clinicPhoneController.text = profile.clinicPhone ?? '';
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
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل بيانات الحساب. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final newPassword = _newPasswordController.text.trim();
    if (newPassword.isNotEmpty && newPassword != _confirmPasswordController.text.trim()) {
      setState(() => _saveError = 'كلمتا السر غير متطابقتين');
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final updated = await widget.apiService.updateProfile(
        doctorName: _nameController.text.trim(),
        clinicName: _clinicNameController.text.trim(),
        clinicAddress: _clinicAddressController.text.trim(),
        clinicPhone: _clinicPhoneController.text.trim(),
        password: newPassword.isEmpty ? null : newPassword,
      );
      // تحديث الاسم/المستوى المخزَّنين محلياً حتى تعكسهما الشاشات الأخرى
      // (الهيدر في الرئيسية والجدول والمرضى) عند فتحها من جديد.
      final token = await widget.authStorage.getToken();
      final email = await widget.authStorage.getEmail();
      if (token != null && email != null) {
        await widget.authStorage.saveSession(
          token: token,
          email: email,
          doctorName: updated.doctorName,
          tier: updated.tier,
        );
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ بيانات الحساب بنجاح')));
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _saveError = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _saveError = 'تعذر حفظ التعديلات. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// يفتح قائمة اختيار مصدر الصورة (كاميرا/معرض) ثم يرفعها -- نفس سلوك
  /// avatarFileInput في profile.html بالموقع (يقبل PNG/JPG/WEBP فقط، يتحقق
  /// الـ backend من الامتداد وMIME في validate_avatar_file). يُستخدم
  /// XFile.readAsBytes بدل dart:io File مباشرة حتى يعمل هذا على الويب أيضاً.
  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
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
              'تغيير صورة الحساب',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            ListTile(
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.indigo700),
              title: const Text('تصوير بالكاميرا', textAlign: TextAlign.right),
            ),
            ListTile(
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.indigo700),
              title: const Text('اختيار من المعرض', textAlign: TextAlign.right),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر فتح الكاميرا/المعرض.')));
      return;
    }
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      await widget.apiService.uploadAvatar(bytes: bytes, filename: picked.name);
      // إعادة تحميل بيانات الحساب كاملة حتى تعكس avatar_url الجديد القادم من
      // السيرفر (بدل بناء نسخة يدوية من DoctorProfile هنا).
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث صورة الحساب بنجاح')));
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
            .showSnackBar(const SnackBar(content: Text('تعذر رفع صورة الحساب. حاول مرة أخرى.')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  /// دائرة صورة الحساب القابلة للضغط + علامة تعديل صغيرة بجانبها (أسفل يسار
  /// الدائرة تماماً)، مطابقة لـ avatar-edit-btn في profile.html بالموقع.
  /// تعرض الصورة الحقيقية إن وُجدت (avatar_url)، وإلا الأحرف الأولى كما كان.
  Widget _buildAvatarPicker(DoctorProfile? profile) {
    final avatarUrl = profile?.avatarUrl;
    return GestureDetector(
      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
      child: SizedBox(
        width: 74,
        height: 74,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: SizedBox(
                width: 74,
                height: 74,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        '${AppConfig.apiBaseUrl}$avatarUrl',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => InitialsAvatar(
                          name: profile?.doctorName ?? 'ط',
                          size: 74,
                          background: Colors.white.withValues(alpha: .14),
                          foreground: Colors.white,
                        ),
                      )
                    : InitialsAvatar(
                        name: profile?.doctorName ?? 'ط',
                        size: 74,
                        background: Colors.white.withValues(alpha: .14),
                        foreground: Colors.white,
                      ),
              ),
            ),
            if (_isUploadingAvatar)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: .35),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: -2,
              left: -2,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryButtonGradient,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.indigoAccent.withValues(alpha: .4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBookingSettings() async {
    setState(() {
      _isBookingLoading = true;
      _bookingErrorMessage = null;
    });
    try {
      final settings = await widget.apiService.fetchBookingSettings();
      if (!mounted) return;
      setState(() {
        _applyBookingSettings(settings);
        _isBookingLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _bookingErrorMessage = e.message;
        _isBookingLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bookingErrorMessage = 'تعذر تحميل إعدادات الحجز. حاول مرة أخرى.';
        _isBookingLoading = false;
      });
    }
  }

  /// يملأ حقول/حالة نموذج الحجز من استجابة السيرفر -- تُستدعى بعد كل تحميل
  /// وبعد كل حفظ ناجح (السيرفر قد يُطبّع الرابط عبر slugify_booking_candidate،
  /// فيجب دائماً عرض ما رجع منه فعلياً وليس ما أرسله المستخدم حرفياً).
  void _applyBookingSettings(BookingSettings settings) {
    _bookingSettings = settings;
    _slugController.text = settings.bookingSlug ?? '';
    _bookingClinicPhoneController.text = settings.clinicPhone ?? '';
    _bookingEnabled = settings.publicBookingEnabled;
    _slotDuration = settings.slotDurationMinutes ?? 30;
    _workStart = _parseTimeOfDay(settings.workStartTime);
    _workEnd = _parseTimeOfDay(settings.workEndTime);
    _selectedWorkDays
      ..clear()
      ..addAll(settings.workDays);
  }

  TimeOfDay? _parseTimeOfDay(String? raw) {
    if (raw == null || raw.length != 5 || raw[2] != ':') return null;
    final hour = int.tryParse(raw.substring(0, 2));
    final minute = int.tryParse(raw.substring(3, 5));
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String get _fullBookingUrl {
    final slug = _slugController.text.trim();
    if (slug.isEmpty) return '';
    return '${AppConfig.apiBaseUrl}/d/$slug';
  }

  Future<void> _pickWorkTime({required bool isStart}) async {
    final initial = (isStart ? _workStart : _workEnd) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _workStart = picked;
      } else {
        _workEnd = picked;
      }
    });
  }

  Future<void> _copyBookingUrl() async {
    final url = _fullBookingUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('احفظ رابط الحجز (Slug) أولاً.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط 📋')));
  }

  Future<void> _saveBookingSettings() async {
    if (!_bookingFormKey.currentState!.validate()) return;
    setState(() {
      _isBookingSaving = true;
      _bookingSaveError = null;
    });
    try {
      final updated = await widget.apiService.updateBookingSettings(
        bookingSlug: _slugController.text.trim(),
        workDays: _selectedWorkDays.toList(),
        workStartTime: _workStart != null ? _formatTimeOfDay(_workStart!) : '',
        workEndTime: _workEnd != null ? _formatTimeOfDay(_workEnd!) : '',
        slotDurationMinutes: _slotDuration,
        clinicPhone: _bookingClinicPhoneController.text.trim(),
        publicBookingEnabled: _bookingEnabled,
      );
      if (!mounted) return;
      setState(() {
        _applyBookingSettings(updated);
        _isBookingSaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الحجز بنجاح')));
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _bookingSaveError = e.message;
        _isBookingSaving = false;
      });
    } catch (_) {
      setState(() {
        _bookingSaveError = 'تعذر حفظ إعدادات الحجز. حاول مرة أخرى.';
        _isBookingSaving = false;
      });
    }
  }

  /// قسم "صفحة الحجز العامة" -- يطابق القسم الموجود أسفل profile.html
  /// بالموقع تماماً: رابط عام (/d/<slug>) يقدر أي مريض يحجز موعده منه مباشرة
  /// بلا تسجيل دخول، مع رمز QR ومعاينة حية للرابط.
  Widget _buildBookingSettingsSection() {
    return SectionCard(
      child: LoadingErrorEmpty(
        isLoading: _isBookingLoading,
        errorMessage: _bookingErrorMessage,
        isLocked: false,
        onRetry: _loadBookingSettings,
        child: Form(
          key: _bookingFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Switch(
                    value: _bookingEnabled,
                    activeColor: AppColors.emerald500,
                    onChanged: (value) => setState(() => _bookingEnabled = value),
                  ),
                  const Spacer(),
                  const Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('صفحة الحجز العامة',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          SizedBox(height: 2),
                          Text(
                            'رابط عام يقدر أي مريض يحجز موعده منه مباشرة بلا تسجيل دخول',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11, color: AppColors.slate500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _slugController,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'الرابط العام (Slug)',
                  prefixText: '/d/',
                  hintText: 'dr-fares',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_fullBookingUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copyBookingUrl,
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('نسخ الرابط'),
                    ),
                    const Spacer(),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _fullBookingUrl,
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.indigo700, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('رمز QR لعيادتك',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              const SizedBox(height: 4),
              // نفس نص profile.html بالموقع بالحرف.
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'اطبع هذا الرمز وعلّقه بعيادتك -- أي مريض يمسحه بكاميرا هاتفه يوصله مباشرة لصفحة حجز موعده معك.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ),
              const SizedBox(height: 10),
              if (_fullBookingUrl.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.slate300),
                  ),
                  child: const Text(
                    'احفظ رابط الحجز (Slug) أولاً لعرض QR Code الخاص بعيادتك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.slate500, fontSize: 12),
                  ),
                )
              else
                BookingQrCard(
                  doctorName: _nameController.text,
                  bookingUrl: _fullBookingUrl,
                ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _bookingClinicPhoneController,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم واتساب العيادة (لإشعارات الطلبات الجديدة)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _slotDurationOptions.contains(_slotDuration) ? _slotDuration : 30,
                decoration: const InputDecoration(labelText: 'مدة الموعد الواحد'),
                items: _slotDurationOptions
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d دقيقة')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _slotDuration = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'بداية الدوام',
                      time: _workStart,
                      onTap: () => _pickWorkTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeField(
                      label: 'نهاية الدوام',
                      time: _workEnd,
                      onTap: () => _pickWorkTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('أيام العمل', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: _weekdayLabels.map((day) {
                  final selected = _selectedWorkDays.contains(day.value);
                  return FilterChip(
                    label: Text(day.label),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _selectedWorkDays.add(day.value);
                        } else {
                          _selectedWorkDays.remove(day.value);
                        }
                      });
                    },
                    selectedColor: AppColors.emerald50,
                    checkmarkColor: AppColors.emerald700text,
                    labelStyle: TextStyle(
                      color: selected ? AppColors.emerald700text : AppColors.slate600,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(),
              ),
              if (_bookingSaveError != null) ...[
                const SizedBox(height: 10),
                Text(_bookingSaveError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.rose700text)),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'حفظ إعدادات الحجز',
                gradient: AppColors.successButtonGradient,
                isLoading: _isBookingSaving,
                onPressed: _isBookingSaving ? null : _saveBookingSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      body: AtmosphereBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AnimatedHeroHeader(
                padding: EdgeInsets.fromLTRB(
                    12, MediaQuery.of(context).padding.top + 8, 20, 40),
                child: Column(
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
                    _buildAvatarPicker(profile),
                    const SizedBox(height: 12),
                    Text(
                      profile?.doctorName != null && profile!.doctorName!.isNotEmpty
                          ? 'د. ${profile.doctorName}'
                          : 'حسابي',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(profile?.email ?? '',
                        style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5)),
                    const SizedBox(height: 10),
                    if (profile != null) TierBadge(tier: profile.tier),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Transform.translate(
                  offset: const Offset(0, -22),
                  child: LoadingErrorEmpty(
                    isLoading: _isLoading,
                    errorMessage: _errorMessage,
                    isLocked: false,
                    onRetry: _load,
                    child: profile == null
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionCard(
                                child: Row(
                                  children: [
                                    Icon(
                                      profile.subscriptionActive
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      color: profile.subscriptionActive
                                          ? AppColors.emerald600
                                          : AppColors.amber900text,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        profile.subscriptionActive
                                            ? (profile.subscriptionExpiresAt != null
                                                ? 'الاشتراك فعّال حتى ${_formatDate(profile.subscriptionExpiresAt!)}'
                                                : 'الاشتراك فعّال')
                                            : 'الاشتراك غير فعّال حالياً',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Align(
                                      alignment: Alignment.centerRight,
                                      child: Text('معلومات العيادة',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14.5)),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _nameController,
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(labelText: 'اسم الطبيب'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _clinicNameController,
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(labelText: 'اسم العيادة'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _clinicAddressController,
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(labelText: 'عنوان العيادة'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _clinicPhoneController,
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(labelText: 'هاتف العيادة'),
                                    ),
                                    const SizedBox(height: 20),
                                    const Align(
                                      alignment: Alignment.centerRight,
                                      child: Text('تغيير كلمة السر (اختياري)',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14.5)),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _newPasswordController,
                                      textAlign: TextAlign.right,
                                      obscureText: true,
                                      decoration:
                                          const InputDecoration(labelText: 'كلمة السر الجديدة'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _confirmPasswordController,
                                      textAlign: TextAlign.right,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                          labelText: 'تأكيد كلمة السر الجديدة'),
                                    ),
                                    if (_saveError != null) ...[
                                      const SizedBox(height: 10),
                                      Text(_saveError!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: AppColors.rose700text)),
                                    ],
                                    const SizedBox(height: 18),
                                    GradientButton(
                                      label: 'حفظ التعديلات',
                                      isLoading: _isSaving,
                                      onPressed: _isSaving ? null : _save,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildBookingSettingsSection(),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقل اختيار وقت (بداية/نهاية الدوام) بمظهر متوافق مع باقي حقول النموذج،
/// يفتح showTimePicker القياسي عند الضغط عليه.
class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? time;
  final VoidCallback onTap;

  const _TimeField({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.access_time, size: 18, color: AppColors.slate400),
            Text(
              time != null
                  ? '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'
                  : '--:--',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
