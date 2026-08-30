import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../utils/appointment_status.dart';
import '../widgets/app_widgets.dart';

/// "الرئيسية" -- لوحة اليوم الأولى التي يراها الطبيب: رأس متدرّج بالتحية
/// والتاريخ، بطاقة إحصائيات طافية (عدد مواعيد اليوم / قيد الانتظار / من دخل
/// العيادة)، وقائمة مصغّرة بأقرب المواعيد القادمة مع أزرار الإجراء الصحيحة.
class DashboardScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onSessionExpired;
  final VoidCallback onSeeFullSchedule;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onSessionExpired,
    required this.onSeeFullSchedule,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  List<Appointment>? _todayAppointments;
  String? _doctorName;
  String _tier = 'standard';
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  final Set<int> _updatingIds = {};

  @override
  void initState() {
    super.initState();
    _loadDoctorName();
    _loadTier();
    refresh();
  }

  Future<void> _loadDoctorName() async {
    final name = await widget.authStorage.getDoctorName();
    if (!mounted) return;
    setState(() => _doctorName = name);
  }

  /// شارة مستوى الاشتراك في الهيدر -- نفس tierBadge# في هيدر الموقع.
  Future<void> _loadTier() async {
    final tier = await widget.authStorage.getTier();
    if (!mounted || tier == null || tier.isEmpty) return;
    setState(() => _tier = tier);
  }

  /// عام حتى تقدر HomeScreen تستدعيه عند فتح التطبيق من إشعار حجز جديد، تماماً
  /// كما يُستدعى refresh() الخاص بجدول اليوم.
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
        _todayAppointments = today;
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
        _errorMessage = 'تعذر تحميل بيانات اليوم. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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

  String get _greeting {
    final hour = DateTime.now().hour;
    return hour < 12 ? 'صباح الخير' : 'مساء الخير';
  }

  String get _formattedDate {
    const weekdays = [
      'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
    ];
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final now = DateTime.now();
    final weekday = weekdays[now.weekday - 1];
    return '$weekday، ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _todayAppointments ?? [];
    final pendingCount = appointments.where((a) => a.status.toLowerCase() == 'pending').length;
    final checkedInCount =
        appointments.where((a) => a.status.toLowerCase() == 'checked_in').length;

    return AtmosphereBackground(
      child: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // رأس متدرّج بالتحية والتاريخ + شارة الاشتراك -- نفس هيدر الموقع.
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 20, 20, 44),
            decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onLogout,
                      tooltip: 'تسجيل الخروج',
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                    const Spacer(),
                    TierBadge(tier: _tier),
                  ],
                ),
                Text(
                  '$_greeting${_doctorName != null && _doctorName!.isNotEmpty ? '، د. $_doctorName' : ''}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formattedDate,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                ),
              ],
            ),
          ),
          // بطاقة "Smart Stat" الزجاجية الداكنة المتوهّجة -- بدل البطاقة
          // البيضاء المسطّحة القديمة، طبق الأصل عن index.html بالموقع.
          Transform.translate(
            offset: const Offset(0, -30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SmartStatCard(
                stats: [
                  (value: '${appointments.length}', label: 'مواعيد اليوم'),
                  (value: '$pendingCount', label: 'قيد الانتظار'),
                  (value: '$checkedInCount', label: 'دخلوا العيادة'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.onSeeFullSchedule,
                      child: const Text('عرض الكل'),
                    ),
                    const Spacer(),
                    const Text(
                      'المواعيد القادمة',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(
                          _isSubscriptionBlocked ? Icons.lock_outline : Icons.error_outline,
                          size: 40,
                          color: AppColors.slate400,
                        ),
                        const SizedBox(height: 10),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        OutlinedButton(onPressed: refresh, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  )
                else if (appointments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.event_available_outlined, size: 44, color: AppColors.slate400),
                          SizedBox(height: 10),
                          Text('لا توجد مواعيد اليوم'),
                        ],
                      ),
                    ),
                  )
                else
                  ...appointments.take(5).map((appointment) {
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            if (appointment.procedureType.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(appointment.procedureType,
                                    style: const TextStyle(color: AppColors.slate500, fontSize: 12.5)),
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
                  }),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
