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

/// أسماء أيام الأسبوع بالعربية، مرتّبة على ترتيب DateTime.weekday
/// (1 = الإثنين ... 7 = الأحد) -- تُستخدم في سطر التاريخ أعلى الشاشة.
const _scheduleArabicWeekdays = <String>[
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// بطاقة خيار حالة واحدة داخل ورقة "تغيير حالة الموعد" -- تُبرز الحالة
/// الحالية بلون شارتها نفسه (نفس appointmentStatusStyle المستخدَم في بطاقة
/// الموعد وباقي الشاشة).
Widget _statusOptionTile({
  required BuildContext context,
  required String label,
  required String statusValue,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  final surf = context.surface;
  final style = appointmentStatusStyle(statusValue, isDark: surf.isDark);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? style.background : surf.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? style.foreground.withValues(alpha: .35)
                : surf.chipBorder,
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
                  color: isSelected ? style.foreground : surf.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// كبسولة يوم واحد داخل شريط الأيام -- طبق الأصل عن ‎.week-day في
/// appointments.html: اسم اليوم فوق الرقم، ونقطة سفلية للأيام التي فيها
/// مواعيد، والمحدَّد بتدرّج نيلي/بنفسجي.
class _WeekDayChip extends StatelessWidget {
  final String topLabel;
  final String bottomLabel;
  final double bottomFontSize;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;

  const _WeekDayChip({
    required this.topLabel,
    required this.bottomLabel,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
    this.bottomFontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected ? surf.accentGradient : null,
            color: isSelected ? null : surf.chipBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.transparent : surf.chipBorder,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: surf.accentGlow,
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                topLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? surf.onAccent.withValues(alpha: .85)
                      : surf.textMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                bottomLabel,
                style: TextStyle(
                  fontSize: bottomFontSize,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? surf.onAccent : surf.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !isBusy
                      ? Colors.transparent
                      : (isSelected ? surf.onAccent : surf.accentSolid),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TodayScheduleScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  /// يُبلّغ القشرة الرئيسية بعدد طلبات الحجز المعلّقة بعد كل تحميل، لتضيء
  /// الشارة الحمراء على تبويب "المواعيد". تمريره اختياري حتى تبقى الشاشة
  /// قابلة للاستخدام وحدها في أي سياق آخر (اختبار مثلاً).
  final ValueChanged<int>? onPendingCountChanged;

  const TodayScheduleScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
    this.onPendingCountChanged,
  });

  @override
  State<TodayScheduleScreen> createState() => TodayScheduleScreenState();
}

class TodayScheduleScreenState extends State<TodayScheduleScreen> {
  List<Appointment>? _appointments;
  /// كل المواعيد العادية بأي تاريخ -- المصدر الذي يفلتره شريط الأيام.
  List<Appointment> _allNormalAppointments = const [];
  /// '' تعني "عرض الكل". تبدأ باليوم الحالي فيبقى سلوك الشاشة الافتراضي
  /// كما كان تماماً قبل إضافة الشريط.
  String _selectedDayKey = '';
  // طلبات الحجز العام (pending_confirmation) -- بلا قيد تاريخ اليوم (تماماً
  // كـ bookingRequests في appointments.html بالموقع)، لها لوحتها الخاصة
  // بالأعلى (انظر _buildBookingRequestsSection). أُضيف 2026-08-31.
  List<Appointment> _bookingRequests = [];
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  final Set<int> _updatingIds = {};
  final Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
      // نفس فلترة loadAppointments() في appointments.html بالموقع تماماً:
      // طلبات pending_confirmation تُستبعد من الجدول العادي ولها لوحتها
      // الخاصة (بأي تاريخ، وليس اليوم فقط -- طلب وصل لموعد الأسبوع القادم
      // ما زال يحتاج رداً الآن)، وrejected تختفي كلياً من العمل اليومي.
      final bookingRequests = all
          .where((appointment) => appointment.status.toLowerCase() == 'pending_confirmation')
          .toList()
        ..sort((a, b) {
          final dateCompare =
              (a.appointmentDate ?? DateTime(0)).compareTo(b.appointmentDate ?? DateTime(0));
          return dateCompare != 0
              ? dateCompare
              : a.appointmentTime.compareTo(b.appointmentTime);
        });
      // كل المواعيد العادية بأي تاريخ -- شريط الأيام يفلترها محلياً بلا أي
      // طلب إضافي للسيرفر. قبل هذا الشريط كانت الشاشة تحتفظ بمواعيد اليوم
      // وحدها، فلم يكن هناك أي وسيلة لرؤية يوم آخر من التطبيق.
      final normal = all.where((appointment) {
        final status = appointment.status.toLowerCase();
        return status != 'pending_confirmation' && status != 'rejected';
      }).toList()
        ..sort((a, b) => a.appointmentTime.compareTo(b.appointmentTime));
      if (!mounted) return;
      setState(() {
        _allNormalAppointments = normal;
        _appointments = _filterAppointmentsForSelectedDay(normal);
        _bookingRequests = bookingRequests;
        _isLoading = false;
      });
      widget.onPendingCountChanged?.call(bookingRequests.length);
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
    final surf = context.surface;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: surf.sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                    color: surf.divider,
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
                  context: sheetContext,
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
                decoration: BoxDecoration(
                  color: context.surface.sheetBg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
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
                            color: context.surface.divider,
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

  /// مفتاح يوم محلي (YYYY-MM-DD). يُبنى من مكوّنات التاريخ المحلية عمداً لا
  /// من toIso8601String() في UTC، وإلا انتقلت مواعيد المساء إلى اليوم التالي.
  String _dayKey(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  List<Appointment> _filterAppointmentsForSelectedDay(List<Appointment> source) {
    if (_selectedDayKey.isEmpty) return source;
    return source
        .where((appointment) => _dayKey(appointment.appointmentDate) == _selectedDayKey)
        .toList();
  }

  void _selectDay(String dayKey) {
    setState(() {
      _selectedDayKey = dayKey;
      _appointments = _filterAppointmentsForSelectedDay(_allNormalAppointments);
    });
  }

  /// شريط أيام الأسبوع -- طبق الأصل عن ‎#weekStrip في appointments.html:
  /// كبسولة "عرض الكل" ثم ستة أيام تبدأ من الأمس، ونقطة تحت كل يوم فيه
  /// مواعيد فعلاً.
  Widget _buildWeekStrip() {
    const dayNames = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];
    final busyDays = _allNormalAppointments
        .map((appointment) => _dayKey(appointment.appointmentDate))
        .where((key) => key.isNotEmpty)
        .toSet();

    final start = DateTime.now().subtract(const Duration(days: 1));
    final chips = <Widget>[
      Expanded(
        child: _WeekDayChip(
          topLabel: 'عرض',
          bottomLabel: 'الكل',
          bottomFontSize: 12,
          isSelected: _selectedDayKey.isEmpty,
          isBusy: false,
          onTap: () => _selectDay(''),
        ),
      ),
    ];

    for (var i = 0; i < 6; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      final key = _dayKey(date);
      chips.add(const SizedBox(width: 6));
      chips.add(
        Expanded(
          child: _WeekDayChip(
            topLabel: dayNames[date.weekday % 7],
            bottomLabel: date.day.toString().padLeft(2, '0'),
            isSelected: _selectedDayKey == key,
            isBusy: busyDays.contains(key),
            onTap: () => _selectDay(key),
          ),
        ),
      );
    }

    return Row(children: chips);
  }

  /// سطر التاريخ تحت اسم العيادة -- تاريخ اليوم الفعلي، لا اليوم المختار
  /// في شريط الأيام: الترويسة تقول "أين نحن الآن"، والشريط هو أداة التنقّل.
  String _todayLabel() {
    final now = DateTime.now();
    final weekday = _scheduleArabicWeekdays[now.weekday - 1];
    final month = _scheduleArabicMonthNames[now.month - 1];
    return '$weekday · ${now.day} $month ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-05: الخلفية الجوّية تغلّف الشاشة كاملةً بدل منطقة القائمة
    // وحدها. حين كانت داخل Expanded كانت كرات الضوء تُقصّ عند حافتها العليا
    // فيظهر **خطّ أفقي حادّ تحت الترويسة مباشرة** -- وهو "الحدود" التي رآها
    // المستخدم على شاشة المواعيد. الآن تمرّ الكرات خلف الترويسة بلا فاصل.
    return AtmosphereBackground(
      child: Stack(
        children: [
          Column(
            children: [
              ClinicTopBar(subtitle: _todayLabel()),
              const OfflineSyncBanner(),
              Expanded(
                child: LoadingErrorEmpty(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  isLocked: _isSubscriptionBlocked,
                  onRetry: refresh,
                  child: _buildList(),
                ),
              ),
            ],
          ),
          PositionedDirectional(
            bottom: floatingNavInset(context) + 16,
            end: 20,
            child: GradientFab(onPressed: _openAddAppointmentSheet),
          ),
        ],
      ),
    );
  }

  /// القائمة الكاملة القابلة للتمرير: لوحة "طلبات حجز جديدة" الكهرمانية
  /// بالأعلى، ثم إطار "المواعيد" الأبيض تحتها -- طبق الأصل عن ترتيب
  /// bookingRequestsSection وقسم "المواعيد" في appointments.html بالموقع
  /// (نفس الحدود/الخلفيات/العناوين)، بدل القائمة المسطّحة السابقة التي كانت
  /// تخلط طلبات الحجز مع المواعيد العادية بلا تمييز بصري. أُعيد تنظيمه
  /// 2026-08-31.
  Widget _buildList() {
    final appointments = _appointments ?? [];

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, floatingNavInset(context) + 84),
        children: [
          _buildWeekStrip(),
          const SizedBox(height: 13),
          _buildBookingRequestsSection(),
          const SizedBox(height: 16),
          _buildAppointmentsFrame(appointments),
        ],
      ),
    );
  }

  /// لوحة "طلبات حجز جديدة" -- طبق الأصل عن bookingRequestsSection في
  /// appointments.html بالموقع (نفس الحدود/الخلفية الكهرمانية، نفس نص
  /// العنوان والوصف وشارة العدد، وتظهر دائماً حتى عند عدم وجود طلبات -- مع
  /// نص "لا توجد طلبات حجز جديدة حالياً." تماماً كالموقع، بدل إخفاء اللوحة
  /// كلياً). أزرار قبول/رفض في [_BookingRequestCard] بنفس ألوان
  /// btn-accept-request/btn-reject-request الحقيقية (كبسولة فاتحة -- التدرج
  /// المملوء هناك حالة :hover لماوس سطح مكتب فقط، لا تنطبق على تطبيق جوّال).
  Widget _buildBookingRequestsSection() {
    final surf = context.surface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf.warnBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: surf.warnBorder),
        boxShadow: surf.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_outlined,
                            size: 18, color: surf.warnFg),
                        const SizedBox(width: 8),
                        Text(
                          'طلبات حجز جديدة',
                          style: AppType.kufi(
                            color: surf.warnFg,
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'طلبات وصلت من صفحة الحجز العامة وبانتظار ردّك (قبول أو رفض).',
                      textAlign: TextAlign.right,
                      // amber900text قيمته فعلياً amber-700 الحقيقي (انظر
                      // تعليقها في app_theme.dart) -- هذا هو استخدامها الصحيح.
                      style: TextStyle(
                          color: surf.warnFg.withValues(alpha: .8), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: surf.warnFg.withValues(alpha: surf.isDark ? .16 : .22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_bookingRequests.length}',
                  style: AppType.kufi(
                      color: surf.warnFg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_bookingRequests.isEmpty)
            Text(
              'لا توجد طلبات حجز جديدة حالياً.',
              style: TextStyle(color: surf.textSecondary, fontSize: 13),
            )
          else
            Column(
              children: [
                for (final request in _bookingRequests) ...[
                  _BookingRequestCard(
                    appointment: request,
                    isUpdating: _updatingIds.contains(request.id),
                    onAccept: () => _respond(request, 'accept'),
                    onReject: () => _respond(request, 'reject'),
                  ),
                  if (request != _bookingRequests.last) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// إطار "المواعيد" الأبيض -- طبق الأصل عن القسم الثاني في
  /// appointments.html بالموقع (بطاقة بيضاء بحدود slate-200 وعنوان + شارة
  /// "محدث تلقائيًا")؛ يحتوي بطاقات مواعيد اليوم (نفس تصميم SectionCard
  /// المعتمد لكل موعد، انظر [_buildAppointmentCard]).
  Widget _buildAppointmentsFrame(List<Appointment> appointments) {
    final surf = context.surface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surf.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: surf.cardBorder),
        boxShadow: surf.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // نفس text-indigo-900 الحقيقي في الموقع (indigo800 هنا قيمته
              // فعلياً indigo-900 رغم اسمها -- انظر تعليقها في app_theme.dart).
              Text(
                'المواعيد',
                style: AppType.kufi(
                    color: surf.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                    letterSpacing: -0.4),
              ),
              const SizedBox(width: 8),
              Text(
                appointments.length == 1 ? 'موعد واحد' : '${appointments.length} مواعيد',
                style: TextStyle(
                    color: surf.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: surf.iconBoxBg,
                  border: Border.all(color: surf.iconBoxBorder),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'محدث تلقائيًا',
                  style: TextStyle(
                      color: surf.iconBoxFg,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (appointments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_available_outlined,
                        size: 44, color: surf.textMuted),
                    const SizedBox(height: 10),
                    Text(
                      'لا توجد مواعيد في هذا اليوم',
                      style: TextStyle(color: surf.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final appointment in appointments) ...[
                  _buildAppointmentCard(appointment),
                  if (appointment != appointments.last) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// بطاقة موعد واحد داخل إطار "المواعيد" -- بلا تغيير عن التصميم المعتمد
  /// سابقاً، استُخرجت فقط إلى دالة مستقلة لاستخدامها من [_buildAppointmentsFrame].
  /// pending_confirmation/rejected لم يعودا يصلان إلى هنا إطلاقاً بعد فلترة
  /// [refresh] الجديدة (لهما لوحتهما/حالتهما الخاصة)، لذا صف
  /// تعديل/حذف/واتساب وقائمة تغيير الحالة تظهر دائماً لكل بطاقة هنا -- تماماً
  /// كجدول الموقع الرئيسي بعد استبعاد normalAppointments لهاتين الحالتين.
  Widget _buildAppointmentCard(Appointment appointment) {
    final isUpdating = _updatingIds.contains(appointment.id);
    final isDeleting = _deletingIds.contains(appointment.id);
    final surf = context.surface;
    final style =
        appointmentStatusStyle(appointment.status, isDark: surf.isDark);

    return SectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الصف العلوي: شارة وقت متدرّجة على اليمين (‎.ap-cell-time في
          // appointments.html) واسم المريض والإجراء بجانبها.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اسم المريض قابل للضغط -- يفتح ورقة "تغيير حالة الموعد"
                    // بدل القائمة المنسدلة الدائمة الظهور في الموقع.
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
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.kufi(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: surf.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.unfold_more,
                                size: 16, color: surf.accentSolid),
                            // موعد أُنشئ/عُدِّل أوفلاين وما زال بانتظار الاتصال
                            // بالإنترنت ليصل فعلياً للسيرفر -- انظر
                            // OfflineAwareApiService.
                            if (appointment.isPendingSync) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.cloud_off_outlined,
                                  size: 15, color: surf.pillDueFg),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (appointment.procedureType.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          appointment.procedureType,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: surf.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 7),
                    // شارة الحالة -- بمظهر كبسولة الموقع، وتفتح نفس ورقة
                    // تغيير الحالة عند الضغط (الموقع يستخدم قائمة منسدلة،
                    // والتطبيق ورقة سفلية؛ المظهر واحد والوظيفة محفوظة).
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _openStatusPicker(appointment),
                        child: StatusBadge(
                          label: appointment.statusLabel,
                          background: style.background,
                          foreground: style.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Container(
                width: 60,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryButtonGradient,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.violet600.withValues(alpha: .45),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Text(
                  appointment.appointmentTime.isEmpty
                      ? '--:--'
                      : appointment.appointmentTime,
                  textAlign: TextAlign.center,
                  style: AppType.kufi(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          AppointmentActionButtons(
            status: appointment.status,
            isUpdating: isUpdating,
            onCheckIn: () => _setStatus(appointment, 'checked_in'),
            onNoShow: () => _setStatus(appointment, 'no_show'),
            onAccept: () => _respond(appointment, 'accept'),
            onReject: () => _respond(appointment, 'reject'),
            // زرا "دخل العيادة"/"تخلّف عن الموعد" ألغيا هنا بطلب المستخدم
            // 2026-08-30 -- أصبحا تكراراً بلا فائدة بعد إضافة ورقة "تغيير
            // حالة الموعد" أعلاه التي تفتح بالضغط على اسم المريض وتغطي هذين
            // الخيارين بالضبط.
            showPendingActions: false,
          ),
          // صف "تعديل/حذف/تذكير واتساب" -- كبسولات فاتحة مطابقة تماماً
          // لأزرار appointment-action-btn في appointments.html بالموقع.
          const SizedBox(height: 10),
          // أزرار بأيقونات فقط بمقاس 40px -- نفس ما تعرضه بطاقة الموقع على
          // الجوال بعد إخفاء نصوصها (‎.appointment-action-btn > span).
          Row(
            children: [
              AppointmentUtilityButton(
                label: 'تعديل',
                icon: Icons.edit_outlined,
                iconOnly: true,
                onPressed: () => _openEditAppointmentSheet(appointment),
              ),
              const SizedBox(width: 6),
              AppointmentUtilityButton(
                label: 'حذف',
                icon: Icons.delete_outline,
                iconOnly: true,
                isLoading: isDeleting,
                onPressed:
                    isDeleting ? null : () => _confirmDeleteAppointment(appointment),
              ),
              const SizedBox(width: 6),
              AppointmentUtilityButton(
                label: 'واتساب',
                icon: Icons.chat_bubble_outline,
                iconOnly: true,
                style: AppointmentUtilityStyle.whatsapp,
                onPressed: () => _sendWhatsappReminder(appointment),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة طلب حجز واحد داخل لوحة "طلبات حجز جديدة" -- طبق الأصل عن العنصر
/// الذي يبنيه renderBookingRequests() في appointments.html بالموقع: اسم
/// المريض ورقم هاتفه، تاريخ ووقت الطلب، ملاحظاته إن وُجدت، ثم زرّا قبول/رفض
/// (كبسولتان فاتحتان -- انظر AppointmentUtilityStyle.whatsapp/reject).
/// أُضيف 2026-08-31.
class _BookingRequestCard extends StatelessWidget {
  final Appointment appointment;
  final bool isUpdating;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _BookingRequestCard({
    required this.appointment,
    required this.isUpdating,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final date = appointment.appointmentDate;
    final dateLabel = date != null
        ? '${date.day} ${_scheduleArabicMonthNames[date.month - 1]} ${date.year}'
        : '—';
    final phone = appointment.patientPhone?.trim();
    final notes = appointment.notes?.trim();
    final surf = context.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surf.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: surf.warnBorder),
        boxShadow: surf.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                appointment.patientName,
                style: AppType.kufi(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: surf.textPrimary,
                    letterSpacing: -0.2),
              ),
              if (phone != null && phone.isNotEmpty)
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: AppType.kufi(
                      fontSize: 12, color: surf.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 13, color: surf.textSecondary),
              const SizedBox(width: 5),
              Text(dateLabel,
                  style: TextStyle(fontSize: 12, color: surf.textSecondary)),
              const SizedBox(width: 8),
              Text('—',
                  style: TextStyle(fontSize: 12, color: surf.textSecondary)),
              const SizedBox(width: 8),
              Icon(Icons.schedule, size: 13, color: surf.textSecondary),
              const SizedBox(width: 5),
              Text(appointment.appointmentTime,
                  style: TextStyle(fontSize: 12, color: surf.textSecondary)),
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.description_outlined,
                    size: 12, color: surf.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    notes,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, color: surf.textMuted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (isUpdating)
            const LinearProgressIndicator(minHeight: 3)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppointmentUtilityButton(
                  label: 'قبول',
                  icon: Icons.check,
                  style: AppointmentUtilityStyle.whatsapp,
                  onPressed: onAccept,
                ),
                const SizedBox(width: 8),
                AppointmentUtilityButton(
                  label: 'رفض',
                  icon: Icons.close,
                  style: AppointmentUtilityStyle.reject,
                  onPressed: onReject,
                ),
              ],
            ),
        ],
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
        // تُستخدَم فقط إن تعذّر الوصول للسيرفر الآن (بلا إنترنت) لعرض اسم/
        // هاتف المريض على الموعد المؤقت ريثما تصل المزامنة -- لا تأثير لهما
        // على المسار المتصل بالإنترنت العادي.
        patientNameHint: patient.fullName,
        patientPhoneHint: patient.phone,
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
        decoration: BoxDecoration(
          color: context.surface.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                  color: context.surface.divider,
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
