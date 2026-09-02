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
  // PageController بدل IndexedStack السابق -- يمنح انيميشن انزلاق حقيقي بين
  // التبويبات (slide) عند الانتقال، مع احترام اتجاه RTL العام للتطبيق
  // تلقائياً (PageView يقرأ Directionality المحيطة لتحديد جهة "التقدّم")،
  // فتبويب "المزيد" (index 3، أقصى اليسار بصرياً) ينزلق من اليسار، وتبويب
  // "الرئيسية" (index 0، أقصى اليمين) ينزلق من اليمين، دون أي حساب يدوي
  // للاتجاه. بطلب المستخدم 2026-08-31.
  late final PageController _pageController = PageController(initialPage: _currentIndex);

  /// يُستدعى من main.dart عند فتح التطبيق عبر إشعار حجز جديد -- ينقل الطبيب
  /// لتبويب "الجدول" (الفهرس 1 الآن بعد إضافة تبويب الرئيسية) مباشرة حتى لو
  /// كان مفتوحاً على تبويب آخر وقتها. الاسم أُبقي كما هو (showTodayTab)
  /// حفاظاً على التوافق مع main.dart دون تعديل غير ضروري هناك.
  void showTodayTab() => _goToTab(1);

  /// الانتقال المتحرّك الموحّد بين التبويبات -- يُستخدم من شريط التنقل
  /// السفلي، ومن "عرض الكل" بلوحة المواعيد القادمة في الرئيسية، ومن
  /// showTodayTab أعلاه، حتى يبقى سلوك الانزلاق متسقاً من كل نقاط الدخول.
  void _goToTab(int index) {
    if (!mounted || index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // كل شاشة مغلَّفة بـ _KeepAlivePage حتى تبقى حيّة داخل PageView تماماً
    // كما كانت IndexedStack تفعل سابقاً -- todayScheduleKey.currentState
    // يبقى صالحاً حتى لو كان الطبيب على تبويب آخر لحظة وصول إشعار جديد، وهذا
    // هو ما يسمح لـ main.dart بنداء refresh() عليه مباشرة.
    final screens = [
      _KeepAlivePage(
        child: DashboardScreen(
          key: widget.dashboardKey,
          apiService: widget.apiService,
          authStorage: widget.authStorage,
          onSessionExpired: widget.onLogout,
          onLogout: widget.onLogout,
          onSeeFullSchedule: () => _goToTab(1),
        ),
      ),
      _KeepAlivePage(
        child: TodayScheduleScreen(
          key: widget.todayScheduleKey,
          apiService: widget.apiService,
          onSessionExpired: widget.onLogout,
        ),
      ),
      _KeepAlivePage(
        child: PatientsListScreen(
          apiService: widget.apiService,
          onSessionExpired: widget.onLogout,
        ),
      ),
      _KeepAlivePage(
        child: MoreMenuScreen(
          apiService: widget.apiService,
          authStorage: widget.authStorage,
          onLogout: widget.onLogout,
          onSessionExpired: widget.onLogout,
        ),
      ),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        // بلا سحب يدوي بين التبويبات -- التنقل يبقى عبر الشريط السفلي فقط
        // (نفس سلوك IndexedStack السابق)، والانزلاق هنا مقصور على الانيميشن
        // المتحرّك عند الضغط على تبويب، لا على سحب المستخدم بإصبعه.
        physics: const NeverScrollableScrollPhysics(),
        children: screens,
      ),
      // شريط تنقل سفلي زجاجي داكن متوهّج -- بدل NavigationBar الأبيض
      // المسطّح القديم، ليطابق هوية الموقع (الهيدر العلوي/القائمة المنسدلة
      // الداكنة + توهّج التبويب النشط بالسيان) تماماً كما في التصميم المعتمد.
      bottomNavigationBar: GlassBottomNav(
        currentIndex: _currentIndex,
        onTap: _goToTab,
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

/// يبقي شاشة التبويب حيّة (حالتها وبياناتها المحمَّلة) حتى وهي خارج نطاق
/// العرض داخل PageView -- تماماً كما كانت IndexedStack تفعل بإبقاء الأربع
/// شاشات في الشجرة دائماً. بدون هذا الغلاف، PageView قد يتخلّص من شاشة
/// ابتعدت عن نطاق العرض فتفقد تمريرها/بياناتها عند العودة إليها.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
