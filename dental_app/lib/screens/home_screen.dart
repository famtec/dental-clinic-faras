import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../widgets/app_widgets.dart';
import 'dashboard_screen.dart';
import 'more_menu_screen.dart';
import 'patients_list_screen.dart';
import 'today_schedule_screen.dart';

/// القشرة الرئيسية بشريط تنقل من 4 تبويبات: الرئيسية / المواعيد / المرضى /
/// المزيد (بوابة التقارير المالية، مخزن المواد، حسابي، وتواصل مع المطور) --
/// بلا AppBar عام لأن كل شاشة لها رأسها المتدرّج الخاص المطابق للموقع.
class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onLogout;
  final GlobalKey<DashboardScreenState> dashboardKey;
  final GlobalKey<TodayScheduleScreenState> todayScheduleKey;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onLogout,
    required this.dashboardKey,
    required this.todayScheduleKey,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  /// يُستدعى من main.dart عند فتح التطبيق عبر إشعار حجز جديد -- ينقل الطبيب
  /// لتبويب "الجدول" (الفهرس 1 الآن بعد إضافة تبويب الرئيسية) مباشرة حتى لو
  /// كان مفتوحاً على تبويب آخر وقتها. الاسم أُبقي كما هو (showTodayTab)
  /// حفاظاً على التوافق مع main.dart دون تعديل غير ضروري هناك.
  void showTodayTab() {
    if (mounted) setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack يبقي حالة الشاشات الأربع حيّة دائماً بصرف النظر عن
    // التبويب الظاهر، لذا يبقى todayScheduleKey.currentState صالحاً حتى لو
    // كان الطبيب على تبويب آخر لحظة وصول إشعار جديد -- هذا هو ما يسمح
    // لـ main.dart بنداء refresh() عليه مباشرة.
    final screens = [
      DashboardScreen(
        key: widget.dashboardKey,
        apiService: widget.apiService,
        authStorage: widget.authStorage,
        onSessionExpired: widget.onLogout,
        onLogout: widget.onLogout,
        onSeeFullSchedule: () => setState(() => _currentIndex = 1),
      ),
      TodayScheduleScreen(
        key: widget.todayScheduleKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
      PatientsListScreen(
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
      MoreMenuScreen(
        apiService: widget.apiService,
        authStorage: widget.authStorage,
        onLogout: widget.onLogout,
        onSessionExpired: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      // شريط تنقل سفلي زجاجي داكن متوهّج -- بدل NavigationBar الأبيض
      // المسطّح القديم، ليطابق هوية الموقع (الهيدر العلوي/القائمة المنسدلة
      // الداكنة + توهّج التبويب النشط بالسيان) تماماً كما في التصميم المعتمد.
      bottomNavigationBar: GlassBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          GlassNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'الرئيسية'),
          GlassNavItem(icon: Icons.today_outlined, activeIcon: Icons.today, label: 'المواعيد'),
          GlassNavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'المرضى'),
          GlassNavItem(icon: Icons.apps_outlined, activeIcon: Icons.apps, label: 'المزيد'),
        ],
      ),
    );
  }
}
