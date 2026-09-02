import 'package:flutter/foundation.dart';

/// حالة عامة (singleton) تعكس وضع المزامنة الأوفلاين لكل الشاشات المهتمة،
/// بدل تمرير SyncService عبر كل الـ constructors -- كافٍ لتجربة أولى بشاشة
/// واحدة (المواعيد)، ويمكن توسيعه لاحقاً لبقية الشاشات دون تعديل بنيوي.
///
/// - [pendingCount]: عدد العمليات التي ما زالت بانتظار الاتصال بالإنترنت
///   لترسَل للسيرفر (إضافة/تعديل/حذف تم أوفلاين).
/// - [failedCount]: عمليات رفضها السيرفر رفضاً حقيقياً (وليس بسبب انقطاع
///   الشبكة) ولن تُعاد تلقائياً -- تبقى مسجَّلة محلياً لمراجعة لاحقة.
/// - [isOnline]: آخر حالة اتصال معروفة (تُحدَّث من نجاح/فشل طلبات فعلية،
///   وليس فقط من connectivity_plus -- انظر ConnectivityService).
class OfflineSyncStatus {
  OfflineSyncStatus._();
  static final OfflineSyncStatus instance = OfflineSyncStatus._();

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  final ValueNotifier<int> failedCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
}
