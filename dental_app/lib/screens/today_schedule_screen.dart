import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment.dart';
import '../models/patient.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/appointment_status.dart';
import '../widgets/app_widgets.dart';

const _scheduleArabicMonthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// مطابق تماماً لـ normalizeWhatsappPhone() في appointments.html بالموقع
/// (نفس النسخة المكرَّرة أصلاً في patient_detail_screen.dart لهذا الغرض،
/// كل ملف بنسخته الخاصة -- نمط مُتّبع سلفاً في هذا المشروع).
String _normalizeWhatsappPhone(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) {
    digits = '963${digits.substring(1)}';
  } else if (!digits.startsWith('963') && digits.length == 9) {
    digits = '963$digits';
  }
  return digits;
}

/// بطاقة خيار حالة واحدة داخل ورقة "تغيير حالة الموعد" -- تُبرز الحالة
/// الحالية بلون شارتها نفسه (نفس appointmentStatusStyle المستخدَم في بطاقة
/// الموعد وباقي الشاشة).
Widget _statusOptionTile({
  required String label,
  required String statusValue,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  final style = appointmentStatusStyle(statusValue);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? style.background : AppColors.slate100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? style.foreground.withValues(alpha: .35) : AppColors.slate200,
          ),
        ),
        child: Row(
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle, size: 18, color: style.foreground),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: isSelected ? style.foreground : AppColors.slate600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TodayScheduleScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const TodayScheduleScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<TodayScheduleScreen> createState() => TodayScheduleScreenState();
}

class TodayScheduleScreenState extends State<TodayScheduleScreen> {
  List<Appointment>? _appointments;
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  final Set<int> _updatingIds = {};
  final Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// عام حتى تقدر HomeScreen تستدعيه عند فتح التطبيق من إشعار حجز جديد.
  Future<void> refresh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSubscriptionBlocked = false;
    });
    try {
      final all = await widget.apiService.fetchAppointments();
      final today = all.where((appointment) => appointment.isToday).toList()
        ..sort((a, b) => a.appointmentTime.compareTo(b.appointmentTime));
      if (!mounted) return;
      setState(() {
        _appointments = today;
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
        _isSubscriptionBlocked = e.isSubscriptionBlocked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل المواعيد. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  /// تحديث حالة موعد عادي -- القيم المقبولة فعلياً من الـ backend لهذا
  /// المسار حصراً هي checked_in / no_show / pending (انظر
  /// AppointmentStatusUpdate في main.py). طلبات pending_confirmation لها
  /// مسار مختلف تماماً عبر _respond أدناه.
  Future<void> _setStatus(Appointment appointment, String status) async {
    setState(() => _updatingIds.add(appointment.id));
    try {
      await widget.apiService.updateAppointmentStatus(appointment.id, status);
      await refresh();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر تحديث حالة الموعد. حاول مرة أخرى.')));
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(appointment.id));
    }
  }

  /// قبول/رفض طلب حجز عام وارد (pending_confirmation) -- مسار /respond
  /// المستقل، وليس /status.
  Future<void> _respond(Appointment appointment, String decision) async {
    setState(() => _updatingIds.add(appointment.id));
    try {
      await widget.apiService.respondToBooking(appointment.id, decision);
      await refresh();
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر الرد على طلب الحجز. حاول مرة أخرى.')));
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(appointment.id));
    }
  }

  /// يفتح نموذج "إضافة موعد جديد" -- نفس زر appointments.html بالموقع.
  /// عند النجاح يُحدَّث جدول اليوم فوراً فيظهر الموعد الجديد إن كان لليوم
  /// الحالي.
  Future<void> _openAddAppointmentSheet() async {
    final created = await showModalBottomSheet<Appointment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddAppointmentSheet(apiService: widget.apiService),
    );
    if (created != null && mounted) refresh();
  }

  /// ورقة "تغيير حالة الموعد" -- تفتح عند الضغط على اسم المريض في البطاقة،
  /// بدل قائمة <select> المنسدلة الدائمة الظهور في appointments.html
  /// بالموقع (renderAppointmentStatusSelect) والتي لا تناسب مساحة شاشة
  /// الجوال؛ الخيارات الثلاثة نفسها بنفس الترتيب (قيد الانتظار/دخل
  /// العيادة/تخلّف عن الموعد)، وتستخدم _setStatus أدناه نفسها.
  Future<void> _openStatusPicker(Appointment appointment) async {
    const options = <(String, String)>[
      ('pending', 'قيد الانتظار'),
      ('checked_in', 'دخل العيادة'),
      ('no_show', 'تخلّف عن الموعد'),
    ];
    final currentStatus = appointment.status.toLowerCase();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                'تغيير حالة موعد ${appointment.patientName}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              for (final option in options) ...[
                _statusOptionTile(
                  label: option.$2,
                  statusValue: option.$1,
                  isSelected: currentStatus == option.$1,
                  onTap: () => Navigator.of(sheetContext).pop(option.$1),
                ),
                if (option != options.last) const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
    if (selected != null && selected != currentStatus) {
      await _setStatus(appointment, selected);
    }
  }

  /// ورقة تعديل موعد قائم -- تاريخ/وقت/وصف فقط (نفس ما يقبله PUT
  /// /api/appointments/{id} فعلياً عبر AppointmentUpdate في main.py، والذي
  /// لا يتضمن patient_id أصلاً)، لذا لا يوجد اختيار مريض هنا خلافاً لورقة
  /// الإضافة -- المريض معروض للقراءة فقط، تماماً كإمكانية الموقع الحقيقية
  /// رغم أن نموذج الموقع يعرض حقل بحث المريض ظاهرياً.
  Future<void> _openEditAppointmentSheet(Appointment appointment) async {
    final notes = appointment.notes?.trim();
    final initialDescription =
        (notes != null && notes.isNotEmpty) ? notes : appointment.procedureType;
    final descriptionController = TextEditingController(text: initialDescription);
    DateTime selectedDate = appointment.appointmentDate ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    if (appointment.appointmentTime.length >= 5) {
      selectedTime = TimeOfDay(
        hour: int.tryParse(appointment.appointmentTime.substring(0, 2)) ?? TimeOfDay.now().hour,
        minute:
            int.tryParse(appointment.appointmentTime.substring(3, 5)) ?? TimeOfDay.now().minute,
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isSaving = false;
        String? error;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            String formattedDate() =>
                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
            String formattedTime() =>
                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: sheetContext,
                initialDate: selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null) setSheetState(() => selectedDate = picked);
            }

            Future<void> pickTime() async {
              final picked = await showTimePicker(context: sheetContext, initialTime: selectedTime);
              if (picked != null) setSheetState(() => selectedTime = picked);
            }

            Future<void> submit() async {
              final description = descriptionController.text.trim();
              if (description.isEmpty) {
                setSheetState(() => error = 'يرجى تعبئة وصف الموعد قبل الحفظ.');
                return;
              }
              setSheetState(() {
                isSaving = true;
                error = null;
              });
              final combinedDateTime = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );
              try {
                await widget.apiService.updateAppointment(
                  appointment.id,
                  appointmentDateTime: combinedDateTime,
                  time: formattedTime(),
                  description: description,
                );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('تم تحديث الموعد بنجاح')));
                  await refresh();
                }
              } on ApiException catch (e) {
                if (e.isSessionExpired) {
                  widget.onSessionExpired();
                  return;
                }
                setSheetState(() {
                  isSaving = false;
                  error = e.message;
                });
              } catch (_) {
                setSheetState(() {
                  isSaving = false;
                  error = 'تعذر تحديث الموعد الآن. يرجى المحاولة لاحقاً.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SingleChildScrollView(
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
                        'تعديل موعد ${appointment.patientName}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pickDate,
                              child: Text(formattedDate()),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pickTime,
                              child: Text(formattedTime()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'الوصف / الملاحظات'),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.rose700text)),
                      ],
                      const SizedBox(height: 18),
                      GradientButton(
                        label: 'حفظ التعديلات',
                        isLoading: isSaving,
                        onPressed: isSaving ? null : submit,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    descriptionController.dispose();
  }

  Future<void> _confirmDeleteAppointment(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الموعد'),
        content: const Text('هل أنت متأكد من حذف هذا الموعد نهائياً؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف', style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingIds.add(appointment.id));
    try {
      await widget.apiService.deleteAppointment(appointment.id);
      if (!mounted) return;
      setState(() {
        _appointments = (_appointments ?? []).where((a) => a.id != appointment.id).toList();
        _deletingIds.remove(appointment.id);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حذف الموعد بنجاح')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() => _deletingIds.remove(appointment.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(appointment.id));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الموعد الآن. يرجى المحاولة لاحقاً.')));
    }
  }

  /// إرسال تذكير عبر واتساب لهاتف المريض -- مطابق تماماً لِـ
  /// sendWhatsappReminder() في appointments.html بالموقع (نفس نص الرسالة
  /// العربي حرفياً). يستخدم appointment.patientPhone القادم مباشرة من
  /// AppointmentResponse بدل تحميل قائمة مرضى منفصلة.
  Future<void> _sendWhatsappReminder(Appointment appointment) async {
    final normalizedPhone = _normalizeWhatsappPhone(appointment.patientPhone ?? '');
    if (normalizedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر إرسال التذكير: رقم هاتف المريض غير متوفر أو غير صالح.')));
      return;
    }

    final doctorName = await widget.apiService.authStorage.getDoctorName();
    final doctorLabel =
        (doctorName != null && doctorName.trim().isNotEmpty) ? doctorName.trim() : 'الطبيب المدخل';
    final appointmentDate = appointment.appointmentDate;
    final dateLabel = appointmentDate != null
        ? '${appointmentDate.day} ${_scheduleArabicMonthNames[appointmentDate.month - 1]} ${appointmentDate.year}'
        : 'غير محدد';
    final timeLabel =
        appointment.appointmentTime.isNotEmpty ? appointment.appointmentTime : 'غير محدد';
    final message =
        'مرحباً سيد/ة ${appointment.patientName}، نذكركم بموعدكم القادم في العيادة $doctorLabel اليوم '
        '$dateLabel عند الساعة $timeLabel. نتمنى لكم دوام الصحة والعافية. 🦷✨';
    final uri = Uri.parse('https://wa.me/$normalizedPhone?text=${Uri.encodeComponent(message)}');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 18),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'المواعيد',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AtmosphereBackground(
                child: LoadingErrorEmpty(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  isLocked: _isSubscriptionBlocked,
                  onRetry: refresh,
                  child: _buildList(),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          bottom: 20,
          end: 20,
          child: GradientFab(onPressed: _openAddAppointmentSheet),
        ),
      ],
    );
  }

  Widget _buildList() {
    final appointments = _appointments ?? [];

    return RefreshIndicator(
      onRefresh: refresh,
      child: appointments.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.event_available_outlined, size: 56, color: AppColors.slate400),
                SizedBox(height: 12),
                Text('لا توجد مواعيد اليوم', textAlign: TextAlign.center),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final appointment = appointments[index];
                final isUpdating = _updatingIds.contains(appointment.id);
                final isDeleting = _deletingIds.contains(appointment.id);
                final style = appointmentStatusStyle(appointment.status);
                final normalizedStatus = appointment.status.toLowerCase();
                // نفس شرط استثناء الموقع في appointments.html
                // (loadAppointments -> normalAppointments): طلبات الحجز
                // pending_confirmation لها لوحتها الخاصة أعلاه (قبول/رفض)،
                // والمرفوضة rejected حالة نهائية -- لا يظهر لهما صف
                // الإجراءات (تعديل/حذف/تذكير واتساب) ولا قائمة تغيير الحالة
                // عند الضغط على الاسم، تماماً كجدول الموقع الرئيسي.
                final showTableActions =
                    normalizedStatus != 'pending_confirmation' && normalizedStatus != 'rejected';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            StatusBadge(
                              label: appointment.statusLabel,
                              background: style.background,
                              foreground: style.foreground,
                            ),
                            const Spacer(),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.indigo50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                appointment.appointmentTime,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: AppColors.indigo700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // اسم المريض قابل للضغط لمن لهم صف إجراءات (انظر
                        // showTableActions أعلاه) -- يفتح ورقة "تغيير حالة
                        // الموعد" بدل القائمة المنسدلة الدائمة الظهور في
                        // الموقع، حسب طلب المستخدم صراحةً.
                        if (showTableActions)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _openStatusPicker(appointment),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      appointment.patientName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.unfold_more,
                                      size: 17, color: AppColors.indigo600),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            appointment.patientName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        if (appointment.procedureType.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(appointment.procedureType,
                                style: const TextStyle(color: AppColors.slate500)),
                          ),
                        AppointmentActionButtons(
                          status: appointment.status,
                          isUpdating: isUpdating,
                          onCheckIn: () => _setStatus(appointment, 'checked_in'),
                          onNoShow: () => _setStatus(appointment, 'no_show'),
                          onAccept: () => _respond(appointment, 'accept'),
                          onReject: () => _respond(appointment, 'reject'),
                          // زرا "دخل العيادة"/"تخلّف عن الموعد" ألغيا هنا
                          // بطلب المستخدم 2026-08-30 -- أصبحا تكراراً بلا
                          // فائدة بعد إضافة ورقة "تغيير حالة الموعد" التي
                          // تفتح بالضغط على اسم المريض وتغطي هذين الخيارين
                          // بالضبط. طلبات pending_confirmation (قبول/رفض)
                          // غير متأثرة، تبقى ظاهرة كما هي.
                          showPendingActions: false,
                        ),
                        // صف "تعديل/حذف/تذكير واتساب" -- كبسولات فاتحة
                        // مطابقة تماماً لأزرار appointment-action-btn في
                        // appointments.html بالموقع (edit/delete بلون
                        // الإندگو الموحَّد، وواتساب وحده أخضر).
                        if (showTableActions) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: AppointmentUtilityButton(
                                  label: 'تعديل',
                                  icon: Icons.edit_outlined,
                                  onPressed: () => _openEditAppointmentSheet(appointment),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppointmentUtilityButton(
                                  label: 'حذف',
                                  icon: Icons.delete_outline,
                                  isLoading: isDeleting,
                                  onPressed: isDeleting
                                      ? null
                                      : () => _confirmDeleteAppointment(appointment),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppointmentUtilityButton(
                                  label: 'واتساب',
                                  icon: Icons.chat_bubble_outline,
                                  style: AppointmentUtilityStyle.whatsapp,
                                  onPressed: () => _sendWhatsappReminder(appointment),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// ورقة "إضافة موعد جديد" -- نفس حقول appointments.html بالموقع: اختيار
/// مريض من قائمة مرضى الطبيب، التاريخ، الوقت، ووصف الإجراء (كلها مطلوبة
/// عند الـ backend -- انظر AppointmentCreate في main.py).
class _AddAppointmentSheet extends StatefulWidget {
  final ApiService apiService;

  const _AddAppointmentSheet({required this.apiService});

  @override
  State<_AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends State<_AddAppointmentSheet> {
  final _descriptionController = TextEditingController();
  final _patientSearchController = TextEditingController();
  List<Patient>? _patients;
  String? _loadError;
  Patient? _selectedPatient;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    try {
      final patients = await widget.apiService.fetchPatients();
      patients.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (!mounted) return;
      setState(() => _patients = patients);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'تعذر تحميل قائمة المرضى.');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  String get _formattedDate =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  String get _formattedTime =>
      '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final patient = _selectedPatient;
    if (patient == null) {
      setState(() => _errorMessage = 'اختر المريض أولاً');
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _errorMessage = 'وصف الإجراء مطلوب');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final appointment = await widget.apiService.createAppointment(
        patientId: patient.id,
        date: _formattedDate,
        time: _formattedTime,
        description: description,
      );
      if (!mounted) return;
      Navigator.of(context).pop(appointment);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر حجز الموعد. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _patientSearchController.text.trim();
    final patients = _patients ?? [];
    final filteredPatients = query.isEmpty
        ? patients
        : patients.where((p) => p.fullName.contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate200,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'إضافة موعد جديد',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _patientSearchController,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'اختر المريض',
                hintText: _selectedPatient?.fullName ?? 'ابحث عن مريض...',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.rose700text)),
              )
            else if (_patients == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredPatients.length,
                    itemBuilder: (context, index) {
                      final patient = filteredPatients[index];
                      final selected = _selectedPatient?.id == patient.id;
                      return ListTile(
                        dense: true,
                        title: Text(patient.fullName, textAlign: TextAlign.right),
                        subtitle: patient.phone.isEmpty
                            ? null
                            : Text(patient.phone, textAlign: TextAlign.right),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: AppColors.indigo600)
                            : null,
                        onTap: () => setState(() {
                          _selectedPatient = patient;
                          _patientSearchController.text = patient.fullName;
                        }),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickDate,
                    child: Text(_formattedDate),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickTime,
                    child: Text(_formattedTime),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'وصف الإجراء'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.rose700text),
              ),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: 'حجز الموعد',
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
