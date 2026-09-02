import 'package:connectivity_plus/connectivity_plus.dart';

/// غلاف رفيع فوق connectivity_plus -- يكتشف *توفر واجهة شبكة* (واي فاي/بيانات
/// جوّال) لا اتصالاً فعلياً بالإنترنت (قد تكون الشبكة متصلة بموجّه بلا
/// إنترنت فعلي). لهذا يبقى هذا مجرد "إشارة مبكرة" لمحاولة المزامنة فوراً؛
/// المصدر الموثوق الحقيقي لكون التطبيق أوفلاين فعلاً يبقى فشل/نجاح طلبات
/// الشبكة نفسها في ApiService (انظر OfflineAwareApiService).
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));

  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }
}
