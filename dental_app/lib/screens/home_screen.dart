import 'package:flutter/material.dart';

import '../models/booking_settings.dart';
import '../models/doctor_profile.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_shell.dart';
import 'clinic_doctors_screen.dart';
import 'contact_developer_screen.dart';
import 'desktop_home_screen.dart';
import 'finance_screen.dart';
import 'inventory_screen.dart';
import 'more_menu_screen.dart';
import 'patients_list_screen.dart';
import 'profile_screen.dart';
import 'today_schedule_screen.dart';
import 'treatment_catalog_screen.dart';

/// القشرة الرئيسية. تخطيطان لبنية واحدة:
///
/// * **تحت [AppDesktopMetrics.breakpoint]** (الجوال والنوافذ الضيّقة): شريط
///   تنقل سفلي زجاجي من 5 تبويبات -- المرضى / المواعيد / المالية / المخزن /
///   المزيد. **لم يتغيّر فيه شيء إطلاقاً** عند إضافة تخطيط سطح المكتب
///   (2026-09-22): نفس PageView ونفس الانزلاق ونفس GlassBottomNav.
/// * **فوق العتبة** (نافذة ويندوز): شريط جانبي ثابت بسبعة عناصر +
///   الإعدادات، وترويسة علوية -- انظر `widgets/desktop_shell.dart`.
///
/// 2026-09-02: كان الشريط أربعة تبويبات أولها "الرئيسية" (لوحة قيادة
/// بإحصائيات ومواعيد قادمة). الموقع لا يملك تلك الشاشة أصلاً -- إحصائياته
/// فوق قائمة المرضى مباشرة -- فدُمجت البطاقات في أعلى تبويب "المرضى"
/// (انظر PatientsListScreen) وحلّت المالية والمخزن محلّ الرئيسية في
/// الشريط، بقرار صريح من المستخدم لتطابق التطبيق مع الموقع تماماً.
/// dashboard_screen.dart ما زال موجوداً على القرص لكنه لم يعد مستخدماً.
///
/// 2026-09-22: تصميم سطح المكتب **يعيد** «الرئيسية» كصفحة أولى في الشريط
/// الجانبي وكهبوط افتراضي، لكنها لوحة جديدة مبنية من الكانفاس
/// (`desktop_home_screen.dart`) لا إحياء لـ dashboard_screen.dart (تلك
/// سابقة لنظام «الليل النيلي» ولم تُهاجَر إليه). تخطيط الجوال يبقى بلا
/// «رئيسية» كما هو: إحصائياته فوق قائمة المرضى، مطابقةً للموقع.
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

/// صفحات الشريط الجانبي على سطح المكتب. الترتيب هو ترتيب الكانفاس، مع
/// «المخزن» مُدرَجاً سابعاً بقرار المستخدم 2026-09-22 (الكانفاس لا يذكره،
/// وإخفاؤه كان سيجعل شاشة كاملة غير قابلة للوصول إلا بتصغير النافذة).
const int _dHome = 0;
const int _dPatients = 1;
const int _dAppointments = 2;
const int _dFinance = 3;
const int _dInventory = 4;
const int _dDoctors = 5;
const int _dPricing = 6;

/// فهرس الإعدادات داخل IndexedStack وحده -- ليس عنصراً في قائمة الشريط
/// (موضعه أسفله بعد فاصل)، فيُمثَّل بـ [_settingsSelected] لا بفهرس.
const int _dSettingsStackIndex = 7;

/// جرد الصفحات بترتيبها الموضعي. الثوابت أعلاه أرقام موضعية بحتة: ترتيب
/// عناصر الشريط الجانبي وترتيب أبناء [IndexedStack] يجب أن يتطابقا حرفياً،
/// فإن أُعيد ترتيب أحدهما أو أُعيد ترقيم الثوابت بلا الآخر ظهرت شاشة مكان
/// أخرى **بصمت** (ينقر الطبيب «المالية» فتفتح «المخزن»). هذا الجرد يجعل
/// [_assertDesktopPageOrder] تصرخ بالخلل في وضع التطوير بدل أن يُكتشف
/// بالاستعمال.
const List<int> _desktopPageOrder = [
  _dHome,
  _dPatients,
  _dAppointments,
  _dFinance,
  _dInventory,
  _dDoctors,
  _dPricing,
];

/// تتحقّق أن الثوابت 0..n-1 بلا فجوة ولا تكرار، وأن الإعدادات تأتي بعدها
/// مباشرةً. تُستدعى داخل `assert` فتُحذَف كلياً من بناء الإصدار.
bool _assertDesktopPageOrder(int destinationCount, int stackLength) {
  if (destinationCount != _desktopPageOrder.length) return false;
  if (stackLength != _dSettingsStackIndex + 1) return false;
  for (var i = 0; i < _desktopPageOrder.length; i++) {
    if (_desktopPageOrder[i] != i) return false;
  }
  return true;
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  // PageController بدل IndexedStack السابق -- يمنح انيميشن انزلاق حقيقي بين
  // التبويبات (slide) عند الانتقال، مع احترام اتجاه RTL العام للتطبيق
  // تلقائياً (PageView يقرأ Directionality المحيطة لتحديد جهة "التقدّم")،
  // فتبويب "المزيد" (index 4، أقصى اليسار بصرياً) ينزلق من اليسار، وتبويب
  // "المرضى" (index 0، أقصى اليمين) ينزلق من اليمين، دون أي حساب يدوي
  // للاتجاه. بطلب المستخدم 2026-08-31.
  late final PageController _pageController = PageController(initialPage: _currentIndex);

  /// الصفحة المفتوحة في تخطيط سطح المكتب، و«هل الإعدادات مفتوحة». الحالتان
  /// مستقلتان عن [_currentIndex] لأن فضاء الفهرسة مختلف (٨ صفحات مقابل ٥
  /// تبويبات)، وتُزامَنان عند تجاوز العتبة في [didChangeDependencies].
  int _desktopIndex = _dHome;
  bool _settingsSelected = false;

  /// آخر تخطيط بُني به. null = لم يُبنَ بعد.
  bool? _wasDesktop;

  /// ملف الطبيب لبطاقة الشريط الجانبي وترويسته، وإعدادات الحجز لسطر حالة
  /// العيادة. لا يُطلَبان على الجوال إطلاقاً -- التخطيط الضيّق لا يعرضهما،
  /// فلا مبرّر لطلبَي شبكة إضافيين عند كل إقلاع.
  DoctorProfile? _profile;
  BookingSettings? _booking;
  bool _chromeRequested = false;

  /// نصّ حقل البحث في الترويسة. يُدفَع إلى شاشة المرضى عبر مفتاحها العام.
  final TextEditingController _searchController = TextEditingController();

  /// الصفحات التي بُنيت فعلاً في IndexedStack. **هذا ليس تحسيناً بل إصلاح
  /// انحدار**: IndexedStack يبني كل أبنائه فوراً (يخطّطهم جميعاً ويرسم
  /// واحداً)، فالنسخة الأولى من هذا الغلاف كانت تُشعل `initState` لثماني
  /// شاشات معاً عند أول إقلاع على ويندوز -- ثماني شاشات × طلباتها = وابل
  /// طلبات على خادم Render يستيقظ من نوم بارد. الآن الصفحة غير المزارة
  /// تبقى [SizedBox.shrink]، وتُبنى عند أول زيارة، وتبقى حيّة بعدها.
  /// (تخطيط الجوال لا يعاني هذا: PageView يبني بطلب ومع KeepAlive يُبقي
  /// ما زُيرَ فقط.)
  final Set<int> _builtDesktopPages = <int>{};

  /// مفاتيح عامة للشاشات المشتركة بين التخطيطين. إعادة استعمال نفس المفتاح
  /// في الشجرتين تجعل Flutter **ينقل** حالة الشاشة عند تجاوز العتبة بدل أن
  /// يهدمها ويعيد تحميلها من الشبكة (GlobalKey reparenting) -- بلا هذا،
  /// تكبير النافذة كان يعيد تحميل كل شاشة من الصفر.
  final GlobalKey _financeKey = GlobalKey();
  final GlobalKey _inventoryKey = GlobalKey();
  final GlobalKey _doctorsKey = GlobalKey();
  final GlobalKey _pricingKey = GlobalKey();
  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey _moreKey = GlobalKey();
  final GlobalKey<DesktopHomeScreenState> _desktopHomeKey =
      GlobalKey<DesktopHomeScreenState>();

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
  /// لشاشة "المواعيد" مباشرة حتى لو كان مفتوحاً على شاشة أخرى وقتها، في
  /// التخطيطين معاً.
  void showTodayTab() {
    if (_wasDesktop ?? false) {
      _goToDesktopPage(_dAppointments);
    } else {
      _goToTab(1);
    }
  }

  /// إشعار «دفعة بانتظار تأكيدك» (2026-09-25) يفتح المالية، حيث بطاقة
  /// الدفعات المعلّقة.
  void showFinanceTab() {
    if (_wasDesktop ?? false) {
      _goToDesktopPage(_dFinance);
    } else {
      _goToTab(2);
    }
  }

  /// الانتقال المتحرّك الموحّد بين تبويبات الجوال -- يُستخدم من شريط التنقل
  /// السفلي، ومن showTodayTab أعلاه، حتى يبقى سلوك الانزلاق متسقاً من كل
  /// نقاط الدخول.
  void _goToTab(int index) {
    if (!mounted || index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _goToDesktopPage(int index) {
    if (!mounted) return;
    if (index == _desktopIndex && !_settingsSelected) return;
    setState(() {
      _desktopIndex = index;
      _settingsSelected = false;
    });
    // العودة إلى «الرئيسية» تُحدّثها إن تجاوزت بياناتها دقيقة ونصفاً --
    // الطبيب يعود إليها بعد قبول موعد أو تسجيل دفعة ليرى الأثر، لكن
    // التنقّل السريع بين الصفحات لا يُشعل ستّة طلبات في كل نقرة. بعد
    // الإطار لأن الصفحة قد تكون تُبنى الآن لأول مرة (IndexedStack الكسول).
    if (index == _dHome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _desktopHomeKey.currentState?.refreshIfStale();
      });
    }
  }

  /// حقل البحث في الترويسة يبحث في **المرضى**: هو المكان الوحيد الذي فيه
  /// بحث فعلي في التطبيق، والنصّ يُدفَع إلى الشاشة نفسها فيظهر في حقلها
  /// أيضاً (انظر PatientsListScreenState.applyExternalSearch). الكتابة تنقل
  /// إلى صفحة المرضى تلقائياً، وإلا فلتَر الطبيب قائمةً لا يراها.
  void _applyDesktopSearch(String query) {
    final needsNavigation = query.trim().isNotEmpty &&
        (_desktopIndex != _dPatients || _settingsSelected);
    if (!needsNavigation) {
      widget.patientsKey.currentState?.applyExternalSearch(query);
      return;
    }
    _goToDesktopPage(_dPatients);
    // شاشة المرضى قد لا تكون مبنية بعد (IndexedStack الكسول)، فمفتاحها
    // العام يعطي null في هذه اللحظة. التطبيق بعد الإطار لا قبله، وإلا ضاع
    // أول حرف يكتبه الطبيب صامتاً.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.patientsKey.currentState?.applyExternalSearch(query);
    });
  }

  /// «عرض الكل ←» في لوحة التحكم، وزرّ «حجز موعد جديد» فيها.
  ///
  /// الزرّ لا يكتفي بالانتقال: يفتح **نموذج الإضافة نفسه** في شاشة المواعيد
  /// عبر [TodayScheduleScreenState.openAddAppointmentSheet]. زرّ مكتوب عليه
  /// «حجز موعد جديد» ثم لا يحجز شيئاً — بل يُنزل الطبيب أمام زرّ ثانٍ عليه
  /// أن يجده — وعدٌ مكسور، ونسخة ثانية من النموذج كانت ستعني نموذجَي حجز
  /// يجب أن يُصلَح أي خلل فيهما معاً.
  void _openAppointmentsPage({bool openSheet = false}) {
    _goToDesktopPage(_dAppointments);
    if (!openSheet) return;
    // الشاشة قد تُبنى الآن لأول مرة (IndexedStack الكسول)، فمفتاحها العام
    // يعطي null قبل انتهاء هذا الإطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.todayScheduleKey.currentState?.openAddAppointmentSheet();
    });
  }

  void _goToDesktopSettings() {
    if (!mounted || _settingsSelected) return;
    setState(() => _settingsSelected = true);
  }

  /// تبويب الجوال المقابل لكل صفحة سطح مكتب. «الرئيسية» تقابل «المرضى» لأن
  /// إحصائيات الجوال تعيش فوق قائمة المرضى أصلاً (انظر شرح الصنف)، والأطباء
  /// ولائحة الأسعار تقابلان «المزيد» لأنهما يُفتحان منه على الجوال.
  static const List<int> _desktopToTab = [0, 0, 1, 2, 3, 4, 4];

  /// صفحة سطح المكتب المقابلة لكل تبويب جوال. ‎-1 = الإعدادات (تبويب
  /// «المزيد» أقرب ما يقابله على سطح المكتب).
  static const List<int> _tabToDesktop = [_dPatients, _dAppointments, _dFinance, _dInventory, -1];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery.sizeOf يُنشئ تبعية، فهذا المسار يُستدعى تلقائياً عند كل
    // تغيير لحجم نافذة ويندوز -- وهو المكان الصحيح للمزامنة، لا build (لا
    // يجوز setState فيه).
    final isDesktop = MediaQuery.sizeOf(context).width >= AppDesktopMetrics.breakpoint;
    final previous = _wasDesktop;
    _wasDesktop = isDesktop;

    if (isDesktop && !_chromeRequested) {
      _chromeRequested = true;
      _loadDesktopChrome();
    }

    if (previous == null || previous == isDesktop) return;

    if (isDesktop) {
      final mapped = _tabToDesktop[_currentIndex];
      _settingsSelected = mapped < 0;
      if (mapped >= 0) _desktopIndex = mapped;
    } else {
      _currentIndex = _settingsSelected ? 4 : _desktopToTab[_desktopIndex];
      // PageView لم يُبنَ بعد في هذا الإطار، فلا عميل للـ controller الآن.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_currentIndex);
      });
    }
  }

  /// زر الخروج على سطح المكتب أيقونة صغيرة بلا نص (بطاقة الطبيب أسفل
  /// الشريط)، بخلاف صفّ «تسجيل الخروج» العريض في شاشة «المزيد» على الجوال
  /// الذي يُستدعى مباشرةً بلا تأكيد. نقرة خاطئة على أيقونة 32×32 محتملة
  /// فعلاً، فالتأكيد هنا ليس زينة.
  Future<void> _confirmLogoutThenOut() async {
    // التوكنات تُقرأ قبل await لا داخل الـ builder: استعمال context بعد
    // انتظار غير متزامن هو بالضبط ما يحذّر منه use_build_context_synchronously.
    final surf = context.surface;
    final dangerColor = context.desktop.badgeDot;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surf.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'تسجيل الخروج',
          style: AppType.kufi(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: surf.textPrimary,
          ),
        ),
        content: Text(
          'سيُطلب منك إدخال بريدك وكلمة السر عند الدخول مرّة أخرى.',
          style: AppType.sans(fontSize: 13.5, height: 1.7, color: surf.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'إلغاء',
              style: AppType.sans(fontWeight: FontWeight.w700, color: surf.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'خروج',
              style: AppType.sans(fontWeight: FontWeight.w700, color: dangerColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  /// بيانات غلاف سطح المكتب وحده: اسم الطبيب وباقته وصورته للشريط الجانبي،
  /// وأيام وساعات العمل لسطر حالة العيادة في الترويسة. الطلبان مستقلّان
  /// فيُطلَقان معاً، وفشل أحدهما لا يُسقط الآخر.
  Future<void> _loadDesktopChrome() async {
    final profileFuture = widget.apiService.fetchProfile();
    final bookingFuture = widget.apiService.fetchBookingSettings();
    try {
      final profile = await profileFuture;
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // فشل جلب الملف لا يمنع استخدام التطبيق: الشريط الجانبي يعرض بطاقة
      // الطبيب بلا اسم ولا شارة باقة، وكل الشاشات تعمل كما هي. يُعاد الطلب
      // عند إعادة تشغيل التطبيق لا بحلقة إعادة محاولة صامتة.
    }
    try {
      final booking = await bookingFuture;
      if (mounted) setState(() => _booking = booking);
    } catch (_) {
      // بلا إعدادات حجز يبقى سطر الترويسة تاريخاً مجرّداً -- انظر
      // [_clinicStatusPrefix]: لا جملة حالة بلا بيانات تُحسب منها.
    }
  }

  /// «العيادة مفتوحة الآن» / «العيادة تفتح 09:00» / «انتهى دوام اليوم» /
  /// «اليوم يوم إجازة» -- **محسوبة من `work_days` و`work_start_time` و
  /// `work_end_time` الحقيقية** لا مكتوبة كما في الكانفاس. null عند غياب
  /// البيانات أو نقصها، فيظهر التاريخ وحده: قول «مفتوحة الآن» لعيادة مغلقة
  /// خطأ يثق به الطبيب ثم يكتشفه من مريض واقف على الباب.
  ///
  /// ترقيم الأيام 0 = الإثنين ... 6 = الأحد، مطابق لـ `_weekdayLabels` في
  /// profile_screen.dart و`weekday()` في بايثون -- لا لـ `DateTime.weekday`
  /// (1 = الإثنين)، ومن هنا الطرح.
  String? get _clinicStatusPrefix {
    final booking = _booking;
    if (booking == null || booking.workDays.isEmpty) return null;
    final now = DateTime.now();
    if (!booking.workDays.contains(now.weekday - 1)) return 'اليوم يوم إجازة';
    final start = _parseClockMinutes(booking.workStartTime);
    final end = _parseClockMinutes(booking.workEndTime);
    if (start == null || end == null) return null;
    final minutes = now.hour * 60 + now.minute;
    if (minutes < start) return 'العيادة تفتح ${booking.workStartTime}';
    if (minutes >= end) return 'انتهى دوام اليوم';
    return 'العيادة مفتوحة الآن';
  }

  /// هل العيادة مفتوحة الآن فعلاً؟ null = غير معروف (لا إعدادات حجز أو
  /// ساقطة)، فتبقى النقطة الحيّة على لونها التصميمي بلا ادّعاء.
  bool? get _clinicOpenNow {
    final booking = _booking;
    if (booking == null || booking.workDays.isEmpty) return null;
    if (!booking.workDays.contains(DateTime.now().weekday - 1)) return false;
    final start = _parseClockMinutes(booking.workStartTime);
    final end = _parseClockMinutes(booking.workEndTime);
    if (start == null || end == null) return null;
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    return minutes >= start && minutes < end;
  }

  /// "09:00" أو "9:00" ← 540. null لأي شيء آخر (بما فيه "09:00:00" غير
  /// المتوقَّع، فلا يُفترض شكل ثم يُحسب عليه وقت خاطئ).
  static int? _parseClockMinutes(String? value) {
    final parts = (value ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── الشاشات ─────────────────────────────────────────────────────────────

  Widget get _patientsScreen => PatientsListScreen(
        key: widget.patientsKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  Widget get _appointmentsScreen => TodayScheduleScreen(
        key: widget.todayScheduleKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
        onPendingCountChanged: setPendingBookingCount,
      );

  Widget get _financeScreen => FinanceScreen(
        key: _financeKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  Widget get _inventoryScreen => InventoryScreen(
        key: _inventoryKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppDesktopMetrics.breakpoint
        ? _buildDesktop(context)
        : _buildMobile();
  }

  // ── تخطيط سطح المكتب ────────────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context) {
    // IndexedStack لا PageView: الانزلاق الأفقي حركة لمس، ولا معنى لها بين
    // صفحات يُنتقَل بينها بنقرة على شريط جانبي ثابت. الثمانية كلها تبقى في
    // الشجرة، فتبقى حالة كل شاشة وتمريرها كما تركها الطبيب.
    final pages = <Widget>[
      DesktopHomeScreen(
        key: _desktopHomeKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
        doctorName: _profile?.doctorName,
        onOpenAppointments: _openAppointmentsPage,
        onOpenFinance: () => _goToDesktopPage(_dFinance),
      ),
      _patientsScreen,
      _appointmentsScreen,
      _financeScreen,
      _inventoryScreen,
      ClinicDoctorsScreen(
        key: _doctorsKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
      TreatmentCatalogScreen(
        key: _pricingKey,
        apiService: widget.apiService,
        onSessionExpired: widget.onLogout,
      ),
      ProfileScreen(
        key: _profileKey,
        apiService: widget.apiService,
        authStorage: widget.authStorage,
        onSessionExpired: widget.onLogout,
      ),
    ];

    final destinations = <DesktopDestination>[
      const DesktopDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'الرئيسية',
        pageTitle: 'لوحة التحكم',
      ),
      const DesktopDestination(
        icon: Icons.people_outline,
        activeIcon: Icons.people,
        label: 'المرضى',
      ),
      DesktopDestination(
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today,
        label: 'المواعيد',
        // تختفي على صفحة المواعيد نفسها، تماماً كما يتجاهل
        // notification-badge.js صفحة appointments.html بالموقع.
        badgeCount: _desktopIndex == _dAppointments && !_settingsSelected
            ? 0
            : _pendingBookingCount,
      ),
      const DesktopDestination(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        label: 'المالية',
      ),
      const DesktopDestination(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        label: 'المخزن',
        pageTitle: 'مخزن المواد',
      ),
      // تبقى معروضة لكل الباقات عمداً: الحارس الحقيقي في الخادم (403)،
      // والشاشة نفسها تعرض حالة الترقية عند رفضه -- نفس نمط شاشة المخزن
      // الموثَّق في utils/tier_access.dart. إخفاؤها كان سيُزيح فهرسة
      // العناصر تبعاً لطلب شبكة لم يعد بعد.
      const DesktopDestination(
        icon: Icons.percent_outlined,
        activeIcon: Icons.percent,
        label: 'الأطباء والنسب',
      ),
      const DesktopDestination(
        icon: Icons.sell_outlined,
        activeIcon: Icons.sell,
        label: 'لائحة الأسعار',
        pageTitle: 'لائحة أسعار العلاجات',
      ),
    ];

    assert(_assertDesktopPageOrder(destinations.length, pages.length));

    // تُسجَّل الصفحة المعروضة هنا لا في [_goToDesktopPage]: المزامنة عند
    // تجاوز العتبة تغيّر [_desktopIndex] من didChangeDependencies أيضاً،
    // فالتسجيل في مكان واحد قبل البناء يغطّي كل مسارات الوصول. عملية
    // مجموعة خالصة (idempotent) لا تستدعي إعادة بناء.
    final activeIndex = _settingsSelected ? _dSettingsStackIndex : _desktopIndex;
    _builtDesktopPages.add(activeIndex);

    return Scaffold(
      body: DesktopShell(
        destinations: destinations,
        currentIndex: _desktopIndex,
        onSelect: _goToDesktopPage,
        settingsSelected: _settingsSelected,
        onSettingsTap: _goToDesktopSettings,
        profile: _profile,
        onLogout: _confirmLogoutThenOut,
        // صفحة مدفوعة فوق الغلاف كما تُفتح من «المزيد» على الجوال -- لا صفحة
        // تاسعة في الشريط: هي نقطة دعم نادرة الاستعمال لا قسم عمل يومي.
        onContactDeveloper: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ContactDeveloperScreen()),
        ),
        notificationCount: _pendingBookingCount,
        onNotificationsTap: () => _goToDesktopPage(_dAppointments),
        statusPrefix: _clinicStatusPrefix,
        clinicOpen: _clinicOpenNow,
        searchController: _searchController,
        onSearchChanged: _applyDesktopSearch,
        child: IndexedStack(
          index: activeIndex,
          children: [
            for (var i = 0; i < pages.length; i++)
              _builtDesktopPages.contains(i)
                  ? pages[i]
                  : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  // ── تخطيط الجوال (كما كان حرفياً) ───────────────────────────────────────

  Widget _buildMobile() {
    // كل شاشة مغلَّفة بـ _KeepAlivePage حتى تبقى حيّة داخل PageView تماماً
    // كما كانت IndexedStack تفعل سابقاً -- todayScheduleKey.currentState
    // يبقى صالحاً حتى لو كان الطبيب على تبويب آخر لحظة وصول إشعار جديد، وهذا
    // هو ما يسمح لـ main.dart بنداء refresh() عليه مباشرة.
    final screens = [
      _KeepAlivePage(child: _patientsScreen),
      _KeepAlivePage(child: _appointmentsScreen),
      _KeepAlivePage(child: _financeScreen),
      _KeepAlivePage(child: _inventoryScreen),
      _KeepAlivePage(
        child: MoreMenuScreen(
          key: _moreKey,
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
