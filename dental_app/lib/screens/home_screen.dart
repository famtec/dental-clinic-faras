import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../widgets/app_widgets.dart';
import 'finance_screen.dart';
import 'inventory_screen.dart';
import 'more_menu_screen.dart';
import 'patients_list_screen.dart';
import 'today_schedule_screen.dart';

/// القشرة الرئيسية بشريط تنقل من 5 تبويبات: المرضى / المواعيد / المالية /
/// المخزن / المزيد -- نفس شريط الموقع على الجوال حرفاً بحرف.
///
/// 2026-09-02: كان الشريط أربعة تبويبات أولها "الرئيسية" (لوحة قيادة
/// بإحصائيات ومواعيد قادمة). الموقع لا يملك تلك الشاشة أصلاً -- إحصائياته
/// فوق قائمة المرضى مباشرة -- فدُمجت البطاقات في أعلى تبويب "المرضى"
/// (انظر PatientsListScreen) وحلّت المالية والمخزن محلّ الرئيسية في
/// الشريط، بقرار صريح من المستخدم لتطابق التطبيق مع الموقع تماماً.
/// dashboard_screen.dart ما زال موجوداً على القرص لكنه لم يعد مستخدماً.
class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onLogout;
  /// حلّ محلّ dashboardKey السابق -- إشعار حجز جديد يُحدّث الآن قائمة
  /// المرضى (التي صارت تحمل بطاقات الإحصائيات) بدل لوحة القيادة المحذوفة.
  final GlobalKey<PatientsListScreenState> patientsKey;
  final GlobalKey<TodayScheduleScreenState> todayScheduleKey;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onLogout,
    required this.patientsKey,
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

  /// عدد طلبات الحجز المعلّقة، يُغذّي الشارة الحمراء على تبويب "المواعيد".
  /// يُحدَّث من شاشة المواعيد نفسها بعد كل تحميل، فلا يوجد استطلاع ثانٍ
  /// للسيرفر (الموقع يستطلع كل 4 ثوانٍ لأن صفحاته منفصلة؛ هنا الشاشة
  /// محمَّلة أصلاً داخل نفس الشجرة).
  int _pendingBookingCount = 0;

  /// تستدعيها TodayScheduleScreen بعد كل refresh.
  void setPendingBookingCount(int count) {
    if (!mounted || count == _pendingBookingCount) return;
    setState(() => _pendingBookingCount = count);
  }

  /// يُستدعى من main.dart عند فتح التطبيق عبر إشعار حجز جديد -- ينقل الطبيب
  /// لتبويب "المواعيد" مباشرة حتى لو كان مفتوحاً على تبويب آخر وقتها.
  /// المواعيد ما زالت الفهرس 1 بعد إعادة ترتيب التبويبات، فلا تغيير هنا.
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
        child: PatientsListScreen(
          key: widget.patientsKey,
          apiService: widget.apiService,
          onSessionExpired: widget.onLogout,
        ),
      ),
      _KeepAlivePage(
        child: TodayScheduleScreen(
          key: widget.todayScheduleKey,
          apiService: widget.apiService,
          onSessionExpired: widget.onLogout,
          onPendingCountChanged: setPendingBookingCount,
        ),
      ),
      _KeepAlivePage(
        child: FinanceScreen(
          apiService: widget.apiService,
          onSessionExpired: widget.onLogout,
        ),
      ),
      _KeepAlivePage(
        child: InventoryScreen(
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
      // 2026-09-05: الشريط السفلي صار كبسولة عائمة بهامش من كل جانب، فلو بقي
      // الجسم متوقّفاً عند حافته العليا لظهر شريط من لون الـ Scaffold تحته
      // بلا محتوى. extendBody يمدّ الجسم خلفه فتمرّ الخلفية وكرات الضوء تحت
      // الكبسولة كما في التصميم. الثمن: كل قائمة تحتاج حشوة سفلية 112 =
      // 16 هامش + 66 ارتفاع + تنفّس -- وقد ضُبطت في التبويبات الخمسة كلها.
      extendBody: true,
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
        items: [
          const GlassNavItem(
              icon: Icons.people_outline, activeIcon: Icons.people, label: 'المرضى'),
          GlassNavItem(
            icon: Icons.calendar_today_outlined,
            activeIcon: Icons.calendar_today,
            label: 'المواعيد',
            // شارة طلبات الحجز المعلّقة -- تختفي على تبويب المواعيد نفسه،
            // تماماً كما يتجاهل notification-badge.js صفحة appointments.html.
            badgeCount: _currentIndex == 1 ? 0 : _pendingBookingCount,
          ),
          const GlassNavItem(
              icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'المالية'),
          const GlassNavItem(
              icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'المخزن'),
          const GlassNavItem(
              icon: Icons.more_horiz, activeIcon: Icons.more_horiz, label: 'المزيد'),
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
