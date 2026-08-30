import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/patient.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/appointment_status.dart';
import '../widgets/app_widgets.dart';

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
        _errorMessage = 'تعذر تحميل جدول اليوم. حاول مرة أخرى.';
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
                    'جدول اليوم',
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
                final style = appointmentStatusStyle(appointment.status);

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
                        ),
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
