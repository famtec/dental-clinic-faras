import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/patient.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'patient_detail_screen.dart';

class PatientsListScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const PatientsListScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  List<Patient>? _patients;
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSubscriptionBlocked = false;
    });
    try {
      final patients = await widget.apiService.fetchPatients();
      patients.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (!mounted) return;
      setState(() {
        _patients = patients;
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
        _errorMessage = 'تعذر تحميل قائمة المرضى. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _callPatient(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الاتصال.')));
      }
    }
  }

  /// فتح صفحة "حالة المريض" الكاملة (بديل عن الـ bottom sheet المختصر
  /// القديم) -- تعرض المخطط السنّي الحقيقي وفواتير العلاج وسجل الدفعات.
  /// عند الرجوع منها نُحدّث القائمة حتى تنعكس أي تعديلات (مثل رصيد جديد).
  Future<void> _openPatientDetail(Patient patient) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PatientDetailScreen(
          patient: patient,
          apiService: widget.apiService,
          onSessionExpired: widget.onSessionExpired,
        ),
      ),
    );
    if (mounted) _load();
  }

  /// يفتح نموذج "إضافة مريض جديد" في ورقة سفلية -- نفس الحقول المُرسَلة
  /// فعلياً من نموذج الموقع (index.html: الاسم/الهاتف/العمر/ملاحظات طبية).
  /// عند النجاح: تحديث القائمة، ثم الانتقال مباشرة لملف المريض الجديد (نفس
  /// سلوك "التوجيه التلقائي بعد الإضافة" المعتمد في الموقع).
  Future<void> _openAddPatientSheet() async {
    final created = await showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddPatientSheet(apiService: widget.apiService),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    _openPatientDetail(created);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            AnimatedHeroHeader(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'المرضى',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الهاتف',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.85)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.14),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
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
                  onRetry: _load,
                  child: _buildList(),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          bottom: 20,
          end: 20,
          child: GradientFab(onPressed: _openAddPatientSheet),
        ),
      ],
    );
  }

  Widget _buildList() {
    final allPatients = _patients ?? [];
    final query = _searchQuery.trim();
    final filtered = query.isEmpty
        ? allPatients
        : allPatients
            .where((patient) =>
                patient.fullName.contains(query) || patient.phone.contains(query))
            .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: filtered.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Icon(
                  allPatients.isEmpty ? Icons.people_outline : Icons.search_off,
                  size: 56,
                  color: AppColors.slate400,
                ),
                const SizedBox(height: 12),
                Text(
                  allPatients.isEmpty ? 'لا يوجد مرضى مسجّلون بعد' : 'لا نتائج مطابقة',
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final patient = filtered[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _openPatientDetail(patient),
                      child: SectionCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.chevron_left, color: AppColors.slate400),
                            const SizedBox(width: 6),
                            if (patient.phone.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.call, color: AppColors.emerald600),
                                onPressed: () => _callPatient(patient.phone),
                              ),
                            Expanded(
                              // CrossAxisAlignment.start -- تحت اتجاه RTL العام
                              // للتطبيق (main.dart) "start" = يمين، وليس .end
                              // كما كان سابقاً (.end = يسار فعلياً) -- كان هذا
                              // هو سبب ظهور اسم/هاتف المريض ملتصقين بالحافة
                              // اليسرى لعمود Expanded الواسع بدل حافته اليمنى
                              // الملاصقة لبقية الصف، فيبدوان "مكتوبين من
                              // اليسار لليمين". أُصلح 2026-08-31.
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    patient.fullName,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    patient.phone.isEmpty ? 'بدون رقم هاتف' : patient.phone,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: AppColors.slate500, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            InitialsAvatar(name: patient.fullName),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// ورقة "إضافة مريض جديد" -- نفس حقول نموذج الموقع تماماً (index.html
/// يرسل فعلياً فقط: الاسم/الهاتف/العمر المحوَّل لتاريخ ميلاد تقريبي (1
/// يناير من سنة الميلاد المحسوبة)/ملاحظات طبية -- لا يوجد حقل جنس حقيقي في
/// نموذج الموقع نفسه، لذا لم نُضِف واحداً هنا حتى يبقى التطبيق مطابقاً).
class _AddPatientSheet extends StatefulWidget {
  final ApiService apiService;

  const _AddPatientSheet({required this.apiService});

  @override
  State<_AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends State<_AddPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      DateTime? birthDate;
      final ageText = _ageController.text.trim();
      if (ageText.isNotEmpty) {
        final age = int.tryParse(ageText);
        if (age != null && age >= 0) {
          birthDate = DateTime(DateTime.now().year - age, 1, 1);
        }
      }
      final patient = await widget.apiService.createPatient(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        birthDate: birthDate,
        medicalHistory: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(patient);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر إضافة المريض. حاول مرة أخرى.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Form(
          key: _formKey,
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
                'إضافة مريض جديد',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'الاسم الكامل مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageController,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العمر (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                textAlign: TextAlign.right,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملاحظات طبية (اختياري)'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.rose700text),
                ),
              ],
              const SizedBox(height: 18),
              GradientButton(
                label: 'حفظ المريض',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
