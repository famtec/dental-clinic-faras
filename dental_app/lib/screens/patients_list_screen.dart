import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/patient.dart';
import '../models/patient_stats.dart';
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
  State<PatientsListScreen> createState() => PatientsListScreenState();
}

/// عامّ (لا خاص) لأن main.dart يمسك GlobalKey<PatientsListScreenState> وينادي
/// refresh() عند وصول إشعار حجز جديد -- الدور الذي كانت تؤدّيه لوحة القيادة
/// قبل دمجها هنا.
class PatientsListScreenState extends State<PatientsListScreen> {
  List<Patient>? _patients;
  PatientStats? _stats;
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  String _searchQuery = '';

  /// 0 = الكل، 1 = عليه رصيد، 2 = مسدّد. تصفية محلية بحتة على القائمة
  /// المحمَّلة أصلاً -- لا نداء إضافي للسيرفر، والأعداد على الشرائح محسوبة
  /// من نفس القائمة لا مخمَّنة.
  int _filterIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  /// يُستدعى من main.dart عبر GlobalKey عند فتح التطبيق من إشعار حجز جديد.
  Future<void> refresh() async {
    await _load();
    await _loadStats();
  }

  /// بطاقات الإحصائيات فوق القائمة -- نفس GET /api/patients/stats الذي
  /// يستخدمه الموقع في index.html. فشلها لا يمسّ القائمة إطلاقاً: تبقى
  /// البطاقات على "--" بدل إظهار خطأ يحجب المرضى.
  Future<void> _loadStats() async {
    try {
      final stats = await widget.apiService.fetchPatientStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // تُترك البطاقات على قيمتها الافتراضية.
    }
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

  /// سطر الترحيب تحت اسم العيادة. العدد يأتي من نفس إحصائيات السيرفر التي
  /// تغذّي بطاقة الرأس، فإن لم تصل بعد يبقى السطر تحية مجرّدة بلا رقم مخترع.
  String _greetingLine() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'صباح الخير'
        : hour < 17
            ? 'نهارك سعيد'
            : 'مساء الخير';
    final active = _stats?.activeAppointments;
    if (active == null) return greeting;
    if (active == 0) return '$greeting · لا مواعيد نشطة حالياً';
    if (active == 1) return '$greeting · لديك موعد نشط واحد';
    if (active == 2) return '$greeting · لديك موعدان نشطان';
    if (active <= 10) return '$greeting · لديك $active مواعيد نشطة';
    return '$greeting · لديك $active موعداً نشطاً';
  }

  @override
  Widget build(BuildContext context) {
    // AtmosphereBackground صارت تغلّف الشاشة كاملةً (لا منطقة القائمة وحدها)
    // حتى تمرّ كرات الضوء خلف الترويسة أيضاً كما في التصميم -- الترويسة لم
    // تعد كتلة داكنة مصمتة تحجبها.
    return AtmosphereBackground(
      child: Stack(
        children: [
          Column(
            children: [
              ClinicTopBar(subtitle: _greetingLine()),
              const OfflineSyncBanner(),
              Expanded(
                child: LoadingErrorEmpty(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  isLocked: _isSubscriptionBlocked,
                  onRetry: _load,
                  child: _buildList(),
                ),
              ),
            ],
          ),
          // الزر العائم على الجهة الأخرى (end = يسار الشاشة تحت RTL)
          // مطابقةً للتصميم. المسافة من الأسفل تُحسَب من فوق الشريط العائم
          // لا من حافة الشاشة -- بعد extendBody صار الجسم يمتدّ خلف الشريط،
          // فـ bottom:20 كان يخفي الزر تحته تماماً (انظر floatingNavInset).
          PositionedDirectional(
            bottom: floatingNavInset(context) + 16,
            end: 18,
            child: GradientFab(
              onPressed: _openAddPatientSheet,
              label: 'مريض جديد',
            ),
          ),
        ],
      ),
    );
  }

  /// سطر "34 سنة · 0991234567" تحت الاسم -- نفس تركيبة بطاقة الموقع.
  /// الهاتف بلا مسافات عمداً: أرقام مفصولة بمسافات تنقلب ترتيباً داخل نص
  /// عربي (RTL) فتظهر "567 234 0991".
  String _patientMetaLine(Patient patient) {
    final parts = <String>[];
    final age = patient.age;
    if (age != null) parts.add('$age سنة');
    final phone = patient.phone.replaceAll(RegExp(r'\s+'), '');
    parts.add(phone.isEmpty ? 'بدون رقم هاتف' : phone);
    return parts.join(' · ');
  }

  /// التصفية المحلية للشرائح الثلاث. "مسدّد" تعني: له فواتير فعلاً ولا
  /// رصيد متبقٍ -- مريض بلا أي فاتورة ليس مسدّداً، هو ببساطة خارج التصنيف
  /// المالي، فلا يظهر تحت أيٍّ من الشريحتين.
  bool _matchesFilter(Patient patient) {
    switch (_filterIndex) {
      case 1:
        return patient.remainingBalance > 0;
      case 2:
        return patient.totalTreatmentCost > 0 && patient.remainingBalance <= 0;
      default:
        return true;
    }
  }

  Widget _buildList() {
    final surf = context.surface;
    final allPatients = _patients ?? [];
    final query = _searchQuery.trim();
    // البحث أولاً ثم التصفية: أعداد الشرائح محسوبة على نتيجة البحث لا على
    // القائمة كاملةً، فلا يعِد الرقمُ الطبيبَ بمرضى لن يراهم وهو يبحث.
    final searched = query.isEmpty
        ? allPatients
        : allPatients
            .where((patient) =>
                patient.fullName.contains(query) || patient.phone.contains(query))
            .toList();
    final filtered = searched.where(_matchesFilter).toList();

    final dueCount = searched.where((p) => p.remainingBalance > 0).length;
    final paidCount = searched
        .where((p) => p.totalTreatmentCost > 0 && p.remainingBalance <= 0)
        .length;

    // العنصر 0 هو رأس القائمة (بطاقة الرأس + البحث + الشرائح) حتى يتمرّر مع
    // المرضى بدل أن يبقى مثبّتاً فوقهم.
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(18, 12, 18, floatingNavInset(context) + 84),
        itemCount: filtered.length + 1 + (filtered.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroCard(stats: _stats),
                const SizedBox(height: 15),
                SoftSearchField(
                  hintText: 'ابحث بالاسم أو رقم الهاتف',
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 13),
                FilterChipsBar(
                  labels: const ['الكل', 'عليه رصيد', 'مسدّد'],
                  counts: [searched.length, dueCount, paidCount],
                  selectedIndex: _filterIndex,
                  onSelect: (value) => setState(() => _filterIndex = value),
                ),
                const SizedBox(height: 13),
              ],
            );
          }

          if (filtered.isEmpty) {
            final isSearchOrFilter = query.isNotEmpty || _filterIndex != 0;
            return Padding(
              padding: const EdgeInsets.only(top: 56),
              child: Column(
                children: [
                  Icon(
                    isSearchOrFilter ? Icons.search_off : Icons.people_outline,
                    size: 52,
                    color: surf.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSearchOrFilter
                        ? 'لا نتائج مطابقة'
                        : 'لا يوجد مرضى مسجّلون بعد',
                    textAlign: TextAlign.center,
                    style: AppType.kufi(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: surf.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final patient = filtered[index - 1];
          return _PatientCard(
            patient: patient,
            metaLine: _patientMetaLine(patient),
            onOpen: () => _openPatientDetail(patient),
            onCall: patient.phone.isEmpty
                ? null
                : () => _callPatient(patient.phone),
          );
        },
      ),
    );
  }
}

/// بطاقة الرأس في شاشة المرضى -- حلّت محلّ بطاقات الإحصاء الداكنة الثلاث
/// المتلاصقة. البنية نفسها في الوضعين: رقم مالي واحد كبير يحمل الثقل
/// البصري، وتحته صفّ عدّادَين بحدّ علوي وفاصل رأسي. الإحصائيات هي نفسها
/// التي كانت تُعرض سابقاً (GET /api/patients/stats) بلا أي تغيير في
/// المصدر -- التغيير في العرض وحده.
class _HeroCard extends StatelessWidget {
  final PatientStats? stats;

  const _HeroCard({required this.stats});

  static String _formatCount(int? value) => value == null ? '--' : '$value';

  static String _formatMoney(double? value) {
    if (value == null) return '--';
    final digits = value.round().abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final data = stats;
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulseDot(),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'المستحقات المالية بالخارج',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: surf.heroCaption,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          HeroBigNumber(
            value: _formatMoney(data?.pendingBalances),
            unit: 'ل.س',
          ),
          HeroStatsRow(
            children: [
              HeroMiniStat(
                icon: Icons.groups_outlined,
                value: _formatCount(data?.totalPatients),
                label: 'مريض في العيادة',
              ),
              HeroMiniStat(
                icon: Icons.event_available_outlined,
                value: _formatCount(data?.activeAppointments),
                label: 'موعد نشط',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة المريض في القائمة. الترتيب انقلب عمّا كان: الصورة الرمزية أولاً
/// (يمين الشاشة تحت RTL) ثم الاسم ثم أزرار الإجراءات في أقصى اليسار --
/// وهذا ترتيب التصميم المعتمد، وهو أيضاً الأسهل مسحاً بالعين: العين تبدأ من
/// الهوية لا من الأزرار.
class _PatientCard extends StatelessWidget {
  final Patient patient;
  final String metaLine;
  final VoidCallback onOpen;
  final VoidCallback? onCall;

  const _PatientCard({
    required this.patient,
    required this.metaLine,
    required this.onOpen,
    this.onCall,
  });

  /// ثلاثة تدرّجات للصورة الرمزية تتناوب حسب الاسم، فلا تبدو القائمة صفّاً
  /// واحداً من البطاقات المتطابقة. الاختيار من مجموع رموز الاسم لا من
  /// hashCode -- الأخير غير مضمون الثبات، فقد يتبدّل لون المريض بين تشغيل
  /// وآخر بلا سبب مفهوم للطبيب.
  static const _avatarGradients = <LinearGradient>[
    LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF6366F1), Color(0xFF7C3AED)],
    ),
    LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF4338CA), Color(0xFF9333EA)],
    ),
    LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF0891B2), Color(0xFF4F46E5)],
    ),
  ];

  String _formatAmount(double value) {
    final digits = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// شارة الحالة المالية. نموذج Patient في التطبيق يحمل
  /// totalTreatmentCost/paidAmount/remainingBalance (وهي بيانات لا تُرجعها
  /// قائمة المرضى في الموقع أصلاً)، فالشارة تعرض الحالة المالية الحقيقية.
  /// لا تُخترع أي قيمة.
  Widget _statusPill(BuildContext context) {
    final surf = context.surface;
    final remaining = patient.remainingBalance;
    final hasInvoice = patient.totalTreatmentCost > 0;

    if (!hasInvoice) {
      return SoftStatusPill(
        label: 'لا فواتير بعد',
        foreground: surf.pillNoneFg,
        background: surf.pillNoneBg,
        border: surf.pillNoneBorder,
      );
    }
    if (remaining > 0) {
      return SoftStatusPill(
        label: 'متبقٍ ${_formatAmount(remaining)}',
        foreground: surf.pillDueFg,
        background: surf.pillDueBg,
        border: surf.pillDueBorder,
      );
    }
    return SoftStatusPill(
      label: 'مسدّد بالكامل',
      foreground: surf.pillPaidFg,
      background: surf.pillPaidBg,
      border: surf.pillPaidBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    var sum = 0;
    for (final unit in patient.fullName.codeUnits) {
      sum += unit;
    }
    final gradient = _avatarGradients[sum % _avatarGradients.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: surf.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: surf.cardBorder),
              boxShadow: surf.cardShadow,
            ),
            child: Row(
              children: [
                InitialsAvatar(
                  name: patient.fullName,
                  size: 42,
                  borderRadius: 15,
                  spacedInitials: true,
                  gradient: gradient,
                  foreground: Colors.white,
                ),
                const SizedBox(width: 11),
                Expanded(
                  // CrossAxisAlignment.start -- تحت اتجاه RTL العام للتطبيق
                  // "start" = يمين، و .end = يسار فعلياً (إصلاح 2026-08-31).
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              patient.fullName,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.kufi(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: surf.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          // مريض أُنشئ/عُدّل أوفلاين وما زال بانتظار الاتصال
                          // ليصل فعلاً للسيرفر (انظر OfflineAwareApiService).
                          if (patient.isPendingSync) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.cloud_off_outlined,
                                size: 14, color: surf.pillDueFg),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metaLine,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.kufi(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: surf.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _statusPill(context),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SoftIconButton(
                      icon: Icons.folder_open_outlined,
                      foreground: surf.iconBoxFg,
                      tooltip: 'فتح الملف الطبي',
                      onPressed: onOpen,
                    ),
                    if (onCall != null) ...[
                      const SizedBox(height: 6),
                      // الاتصال بديل زر الحذف الموجود في الموقع: الحذف من
                      // قائمة على الهاتف أخطر بكثير من نفعه.
                      SoftIconButton(
                        icon: Icons.call_outlined,
                        foreground: surf.pillPaidFg,
                        tooltip: 'اتصال',
                        onPressed: onCall!,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
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
    final surf = context.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                    color: surf.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
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
