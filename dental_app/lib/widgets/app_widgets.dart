import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../services/offline_sync_status.dart';

import '../theme/app_theme.dart';
import '../utils/tier_access.dart';
import 'clinic_logo.dart';

/// زر بيضاوي بتدرج لوني -- نفس شكل الأزرار الرئيسية في الموقع (تسجيل
/// الدخول، حفظ التعديلات...). يُستخدم في كل الشاشات بدل FilledButton
/// الافتراضي حتى تبقى الأزرار الأساسية متطابقة الشكل بصرياً.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final IconData? icon;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.gradient = AppColors.primaryButtonGradient,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return Opacity(
      opacity: disabled && isLoading == false ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                      ],
                      // Noto Sans Arabic أعرض من Tajawal عند نفس المقاس،
                      // فنصوص كانت تتّسع صارت تلتفّ سطرين داخل زر نصف
                      // العرض ("تخلّف عن الموعد"). FittedBox يصغّرها قليلاً
                      // بدل أن تنكسر، و maxLines يمنع الالتفاف نهائياً.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// شارة نصية صغيرة مستديرة (حالة الموعد، حالة الفاتورة...). تحاكي شكل
/// الشارات في الموقع (badge بخلفية فاتحة ونص بلون مطابق أغمق).
class StatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final bool bold;

  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.bold = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

/// المسافة التي يحجزها الشريط السفلي العائم من حافة الشاشة السفلية:
/// هامشه (16) + ارتفاعه (66) + منطقة الإيماءات الآمنة في الجهاز.
///
/// **لماذا يلزم هذا:** بعد `extendBody: true` في home_screen صار جسم كل
/// تبويب يمتدّ خلف الشريط حتى حافة الشاشة، فأي `bottom:` يُقاس من الحافة لا
/// من أعلى الشريط. الزر العائم الذي كان على `bottom: 20` صار مختبئاً خلف
/// الشريط تماماً. كل ما يجلس أسفل الشاشة (زر عائم، حشوة قائمة) يجمع هذه
/// القيمة أولاً.
///
/// **‼️ `viewPadding` وليس `padding`:** داخل جسم Scaffold مضبوط على
/// `extendBody: true` تستبدل Flutter نفسها قيمة `padding.bottom` بارتفاع
/// الشريط السفلي **كاملاً** (`_BodyBuilder`: `max(padding.bottom,
/// size.height - bottomNavigationBarTop)`) حتى يتفادى أي `SafeArea` داخل
/// الجسم الشريطَ تلقائياً. فحساب `16 + 66 + padding.bottom` هنا كان يجمع
/// الشريط مرتين ⇒ الزر يطفو ~١٤٠ بكسل فوق مكانه. أما `viewPadding` فلا
/// تلمسها Flutter أبداً: تبقى منطقة إيماءات الجهاز الحقيقية وحدها.
///
/// نأخذ `max` بين القراءتين لأنهما تتساويان تحت `extendBody: true` (كلتاهما
/// = أعلى الشريط)، وعند غيابه تبقى `padding.bottom` منطقة إيماءات فقط
/// فيفوز الحساب الصريح. الصيغة صحيحة في الحالتين ولا تضاعف في أيّهما.
double floatingNavInset(BuildContext context) {
  final mq = MediaQuery.of(context);
  // 2026-09-24: تخطيط سطح المكتب ليس فيه شريط سفلي عائم أصلاً -- التنقّل في
  // شريط جانبي (انظر widgets/desktop_shell.dart). فحجز 82px أسفل كل قائمة
  // هناك يترك شريط فراغ ميت في كل صفحة من صفحات نافذة ويندوز. تُضبَط هنا في
  // موضع واحد فتصحّ الاثنتا عشرة نقطة استدعاء معاً بدل تعديل كل شاشة.
  if (mq.size.width >= AppDesktopMetrics.breakpoint) return 16;
  final computed = 16 + 66 + mq.viewPadding.bottom;
  return mq.padding.bottom > computed ? mq.padding.bottom : computed;
}

/// بطاقة بيضاء بحواف مدوّرة وحدود رفيعة وظل خفيف -- نفس شكل كل بطاقات
/// الموقع/التصميم (rounded-2xl border-slate-200 shadow).
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// سطح مصمت بدل الزجاج الشفّاف. الزجاج جميل فوق خلفية الصفحة، لكنه يفضح
  /// ما تحته: بطاقة تطفو فوق ترويسة متدرّجة (بطاقة ملف المريض مثلاً، مسحوبة
  /// 30px فوق الترويسة البنفسجية) يظهر التدرّج من خلال نصفها العلوي ويتوقّف
  /// فجأة عند حدّ الترويسة، فتبدو **مقطوعة أفقياً**. أي بطاقة تتقاطع مع سطح
  /// ملوّن آخر يجب أن تكون معتمة.
  final bool opaque;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.opaque = false,
  });

  @override
  Widget build(BuildContext context) {
    // 2026-09-05: صارت تقرأ AppSurface بدل الأبيض/slate200 الثابتين، فتصبح
    // زجاجية شفّافة في الوضع الليلي ومصمتة بظلّ نيلي ناعم في النهاري -- بلا
    // أي تغيير في توقيعها، فكل مستدعياتها القائمة تعمل كما هي.
    // سطح المكتب (2026-09-24): الشاشات التي تُفتح فوق الغلاف ولا تملك
    // تخطيطاً خاصاً بها (ملف المريض بأقسامه) تأخذ بطاقة سطح المكتب نفسها --
    // سطح معتم وحدّ وظلّ من AppDesktop -- فتتّسق مع بقية الصفحات بلا لمس
    // كل مستدعٍ على حدة. الجوال بلا أي تغيير.
    if (context.isDesktopShell) {
      final d = context.desktop;
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: d.cardBg,
          gradient: d.cardGradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: d.cardBorder),
          boxShadow: d.cardShadow,
        ),
        child: child,
      );
    }
    final surf = context.surface;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: opaque ? surf.sheetBg : surf.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: surf.cardBorder),
        boxShadow: surf.cardShadow,
      ),
      child: child,
    );
  }
}

/// دائرة صورة رمزية بحروف اسم المريض/الطبيب الأولى -- تُستخدم بدل صورة
/// حقيقية غير متوفرة (نفس أسلوب الموقع avatar بالأحرف الأولى).
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color background;
  final Color foreground;
  /// تدرّج بدل اللون المسطّح -- حين يُمرَّر يتجاهل [background].
  final Gradient? gradient;
  /// نصف قطر الحواف. null = دائرة كاملة (السلوك الأصلي).
  final double? borderRadius;
  /// مسافة بين الحرفين، لمطابقة "م ع" في بطاقة المريض بالموقع.
  final bool spacedInitials;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 46,
    this.background = AppColors.indigo50,
    this.foreground = AppColors.indigo700,
    this.gradient,
    this.borderRadius,
    this.spacedInitials = false,
  });

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '؟';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final second =
        parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final joined = spacedInitials && first.isNotEmpty && second.isNotEmpty
        ? '$first $second'
        : '$first$second';
    final result = joined.trim();
    return result.isEmpty ? trimmed[0] : result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            borderRadius == null ? null : BorderRadius.circular(borderRadius!),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

/// أزرار إجراء الموعد حسب حالته الفعلية المقبولة من الـ backend:
/// - pending_confirmation (طلب حجز عام وارد من صفحة الحجز): قبول/رفض عبر
///   respondToBooking (decision: accept/reject) -- تظهر دائماً، لأنها إجراء
///   مختلف تماماً عن مجرد تغيير حالة (تحوّل طلب الحجز إلى موعد حقيقي)، ولا
///   تُغطّى بورقة "تغيير حالة الموعد" أدناه.
/// - pending (موعد عادي بانتظار الدوام): دخل العيادة/تخلّف عبر
///   updateAppointmentStatus (status: checked_in/no_show) -- تُعرض فقط عند
///   [showPendingActions] (افتراضياً true). عُطِّلت 2026-08-30 في
///   today_schedule_screen.dart تحديداً بعد إضافة ورقة "تغيير حالة الموعد"
///   التي تفتح بالضغط على اسم المريض وتغطي نفس الخيارين تماماً (أصبح
///   الزرّان الظاهران دوماً تكراراً بلا فائدة إضافية هناك حسب طلب
///   المستخدم)؛ تُركت true افتراضياً حتى تبقى dashboard_screen.dart (التي
///   لا تملك ورقة تغيير الحالة هذه) تعمل دون أي تغيير.
/// أي حالة أخرى (checked_in/no_show/rejected/...) نهائية ولا تعرض أزراراً.
/// هذا المكوّن هو مصدر الحقيقة الوحيد لمفردات الحالة حتى لا تتكرر (ولا
/// ينحرف بعضها عن بعض كما حدث سابقاً حين استخدمت الشاشة القديمة قيماً غير
/// مقبولة من الـ backend مثل confirmed/cancelled/completed).
class AppointmentActionButtons extends StatelessWidget {
  final String status;
  final bool isUpdating;
  final VoidCallback onCheckIn;
  final VoidCallback onNoShow;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool showPendingActions;

  const AppointmentActionButtons({
    super.key,
    required this.status,
    required this.isUpdating,
    required this.onCheckIn,
    required this.onNoShow,
    required this.onAccept,
    required this.onReject,
    this.showPendingActions = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isUpdating) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final normalized = status.toLowerCase();
    if (normalized == 'pending_confirmation') {
      // ترتيب وتلوين مطابقان تماماً لِـ accept-request-btn/reject-request-btn
      // في appointments.html بالموقع: زرّان مملوءان بتدرّج لوني (لا حدود
      // فارغة)، "قبول" أخضر أولاً/على اليمين، "رفض" أحمر ثانياً/على اليسار
      // (نفس ترتيب DOM في الموقع، الذي يضع زر القبول أولاً).
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'قبول',
                onPressed: onAccept,
                gradient: AppColors.successButtonGradient,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GradientButton(
                label: 'رفض',
                onPressed: onReject,
                gradient: AppColors.dangerButtonGradient,
              ),
            ),
          ],
        ),
      );
    }
    if (normalized == 'pending' && showPendingActions) {
      // نفس منطق الأزرار المملوءة أعلاه، بترتيب مماثل (الإجراء الإيجابي
      // "دخل العيادة" أولاً/على اليمين) -- الموقع نفسه يستخدم هنا قائمة
      // منسدلة واحدة بدل زرين (renderAppointmentStatusSelect في
      // appointments.html)، لكن زرين واضحين أنسب للمس على الجوال؛ الألوان
      // والتعبئة مطابقة لنفس نظام الموقع اللوني (أخضر للنجاح، أحمر للتخلف).
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'دخل العيادة',
                onPressed: onCheckIn,
                gradient: AppColors.successButtonGradient,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GradientButton(
                label: 'تخلّف عن الموعد',
                onPressed: onNoShow,
                gradient: AppColors.dangerButtonGradient,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// نمط زر إجراء موعد كبسولي فاتح -- [neutral] لـ"تعديل"/"حذف" (كلاهما نفس
/// عائلة الإندگو الفاتحة، تطابقاً مع توحيد الموقع 2026-08-29 لهذين الزرين
/// على لون واحد بدل الأحمر/الأخضر الصريح)، و[whatsapp] وحده أخضر (استثناء
/// هوية علامة تجارية حقيقية، نفس مبدأ contact_developer_screen.dart).
/// 2026-08-31: أُضيف [reject] (وردي فاتح) لزر "رفض" في بطاقات "طلبات حجز
/// جديدة" -- زر "قبول" في نفس البطاقات يستخدم [whatsapp] مباشرة بلا حاجة
/// لقيمة جديدة، لأن btn-whatsapp-reminder وbtn-accept-request يتشاركان
/// فعلياً نفس تعريف CSS بالحرف في appointments.html بالموقع.
enum AppointmentUtilityStyle { neutral, whatsapp, reject }

/// زر إجراء صغير بشكل كبسولة فاتحة اللون -- مطابق تماماً لأزرار
/// .appointment-action-btn (تعديل/حذف/تذكير واتساب) في appointments.html
/// بالموقع: خلفية متدرجة فاتحة + حدود ملونة + أيقونة ونص بلون داكن من نفس
/// العائلة، بدل OutlinedButton الفارغ المستخدم سابقاً لهذه الإجراءات.
/// أُضيف 2026-08-30، ويُستخدم في today_schedule_screen.dart لبطاقة الموعد.
class AppointmentUtilityButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppointmentUtilityStyle style;
  final bool isLoading;

  /// مربّع 40x40 بالأيقونة وحدها -- [label] يبقى مطلوباً ويُستخدم كـ Tooltip
  /// ولقارئ الشاشة. هذا ما تعرضه بطاقة الموقع على الجوال بعد إخفاء النصوص.
  final bool iconOnly;

  const AppointmentUtilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style = AppointmentUtilityStyle.neutral,
    this.isLoading = false,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final Gradient gradient;
    final Color borderColor;
    final Color contentColor;
    switch (style) {
      case AppointmentUtilityStyle.whatsapp:
        gradient = AppColors.appointmentWhatsappGradient;
        borderColor = AppColors.emerald200;
        contentColor = AppColors.emerald700;
        break;
      case AppointmentUtilityStyle.reject:
        gradient = AppColors.appointmentRejectGradient;
        borderColor = AppColors.rose200;
        contentColor = AppColors.rose700text;
        break;
      case AppointmentUtilityStyle.neutral:
        gradient = AppColors.appointmentUtilityGradient;
        borderColor = AppColors.indigo200;
        contentColor = AppColors.indigoAccent;
        break;
    }
    final disabled = onPressed == null || isLoading;

    return Opacity(
      opacity: disabled && !isLoading ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onPressed,
          child: Container(
            width: iconOnly ? 40 : null,
            height: iconOnly ? 40 : null,
            alignment: iconOnly ? Alignment.center : null,
            padding: iconOnly
                ? null
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(iconOnly ? 13 : 12),
              border: Border.all(color: borderColor),
            ),
            child: isLoading
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(contentColor),
                    ),
                  )
                : iconOnly
                    ? Tooltip(
                        message: label,
                        child: Icon(icon, size: 17, color: contentColor),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 15, color: contentColor),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: contentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

/// حالة فارغة/تحميل/خطأ موحّدة لقوائم الشاشات (نفس الأسلوب في كل مكان).
class LoadingErrorEmpty extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final bool isLocked;
  final VoidCallback onRetry;
  final Widget child;

  const LoadingErrorEmpty({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.isLocked,
    required this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      final surf = context.surface;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLocked ? Icons.lock_outline : Icons.error_outline,
                size: 44,
                color: surf.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: surf.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    return child;
  }
}

/// شارة الباقة -- نفس الشارة البيضاوية شبه الشفافة الموجودة في هيدر كل
/// صفحة بالموقع (tierBadge#) بجانب اسم العيادة. يُكتب الاسم بالإنكليزية
/// عمداً كما في الموقع تماماً -- ليس خطأ ترجمة.
///
/// 2026-09-14: النص يأتي من [ClinicTier.badgeLabel] لا من مقارنة نصّية،
/// فباقة العيادات تظهر "Premium Plus" بدل أن تسقط على "Standard".
class TierBadge extends StatelessWidget {
  final String tier;

  const TierBadge({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final label = ClinicTier.badgeLabel(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
        color: Colors.white.withValues(alpha: .10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// بيانات عمود واحد في [SmartStatCard] -- أيقونة ولونها الخاصان بالإضافة
/// للقيمة والتسمية، حتى يميَّز كل عدّاد بهويته اللونية الخاصة (نفس تمييز
/// بطاقات "SMART STAT" الثلاث في index.html بالموقع: سيان لإجمالي المرضى/
/// بنفسجي للمواعيد النشطة والمعلقة/زمردي للمستحقات المالية). أُضيف
/// 2026-08-31 مع تحديث هوية الشاشة الرئيسية.
class SmartStat {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Color? valueColor;

  const SmartStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.valueColor,
  });
}

/// بطاقة "Smart Stat" الزجاجية الداكنة المتوهّجة -- تحاكي بطاقات الإحصاء في
/// index.html بالموقع (تدرّج كحلي/إنديغو/بنفسجي غامق + توهّج سيان وبنفسجي
/// خلفها). تحل محل البطاقة البيضاء المسطّحة القديمة في الشاشة الرئيسية.
/// 2026-08-31: أضيفت أيقونة ملوّنة فوق كل عمود (انظر [SmartStat]) بدل
/// الأعمدة الرمادية الموحّدة سابقاً -- خيار "B" المعتمد من مالك المنتج من
/// بين نموذجين مُقترحين (النموذج الآخر كان ثلاث بطاقات منفصلة طبق الأصل عن
/// الموقع، لكنه كان يتطلّب تمريراً أطول على الجوال).
class SmartStatCard extends StatelessWidget {
  final List<SmartStat> stats;

  const SmartStatCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          gradient: AppColors.smartStatGradient,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          boxShadow: [
            BoxShadow(
              color: AppColors.indigo800.withValues(alpha: .35),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              left: -10,
              child: _glow(120, AppColors.cyan400.withValues(alpha: .22)),
            ),
            Positioned(
              bottom: -30,
              right: -10,
              child: _glow(120, AppColors.purple600.withValues(alpha: .22)),
            ),
            Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i != 0)
                    Container(width: 1, height: 60, color: Colors.white.withValues(alpha: .14)),
                  Expanded(child: _column(stats[i])),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(SmartStat stat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: stat.iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, size: 16, color: stat.iconColor),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              style: TextStyle(
                color: stat.valueColor ?? Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .66),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// رأس متدرّج بنفسجي بحركة تنفّس لطيفة -- بديل مباشر عن
/// `Container(decoration: BoxDecoration(gradient: AppColors.heroGradient))`
/// المستخدَم بنفس الشكل تماماً (width: double.infinity + padding + child)
/// في رأس كل شاشة رئيسية بالتطبيق (الرئيسية/المواعيد/المرضى/حالة المريض/
/// المزيد/التقارير المالية/مخزن المواد/حسابي/تواصل مع المطور). يستخدم نفس
/// ألوان heroGradient بالضبط (AppColors.heroGradient.colors) بلا أي تغيير
/// بصري في الألوان نفسها -- فقط زاوية التدرّج (begin/end) تتأرجح ببطء
/// وسلاسة بدل أن تكون ثابتة، فيبدو التدرّج حياً/متحركاً بدل ساكن مسطّح. حركة
/// هادئة مقصودة (7 ثوانٍ لكل اتجاه، Curves.easeInOut) تناسب هوية تطبيق طبي
/// احترافي، لا وميض سريع ملفت. أُضيف 2026-08-31 بطلب المستخدم.
class AnimatedHeroHeader extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AnimatedHeroHeader({super.key, required this.child, this.padding});

  @override
  State<AnimatedHeroHeader> createState() => _AnimatedHeroHeaderState();
}

class _AnimatedHeroHeaderState extends State<AnimatedHeroHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  late final Animation<Alignment> _begin = AlignmentTween(
    begin: const Alignment(-0.9, -1),
    end: const Alignment(-0.3, -0.35),
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  late final Animation<Alignment> _end = AlignmentTween(
    begin: const Alignment(0.9, 1),
    end: const Alignment(0.3, 0.35),
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: double.infinity,
        padding: widget.padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: _begin.value,
            end: _end.value,
            colors: AppColors.heroGradient.colors,
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// خلفية جوّية فاتحة -- دوائر ضبابية ملوّنة معلّقة خلف المحتوى، نفس أسلوب
/// الخلفية في كل صفحات الموقع الفاتحة (index.html وغيرها) بدل الخلفية
/// البيضاء/الرمادية المسطّحة السابقة. تُستخدم كغلاف Stack خلف محتوى الشاشة.
/// 2026-09-05 -- أُعيدت كتابتها لنظام «الليل النيلي»: ثلاث كرات ضوء تنجرف
/// ببطء خلف المحتوى، وهي المصدر البصري الوحيد للعمق في الوضعين. ليلاً هي
/// مصدر الإضاءة فعلياً على سطح ‎#07061A؛ نهاراً تصير تلويناً بنفسجياً خفيفاً
/// على الأبيض -- نفس المواضع ونفس التوقيت، اللون وحده يتبدّل.
///
/// التمويه: تدرّج شعاعي يتلاشى إلى شفاف كامل، لا `ImageFiltered` بـ blur --
/// الأخير يعيد رسم ثلاث طبقات ضبابية في كل إطار على شاشة متحرّكة أصلاً،
/// والفرق البصري لا يُذكر مقابل كلفته على أجهزة الفئة المتوسطة.
class AtmosphereBackground extends StatefulWidget {
  final Widget child;

  const AtmosphereBackground({super.key, required this.child});

  @override
  State<AtmosphereBackground> createState() => _AtmosphereBackgroundState();
}

class _AtmosphereBackgroundState extends State<AtmosphereBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat(reverse: true);

  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _orb({
    required double size,
    required Color color,
    required Offset drift,
    double? top,
    double? bottom,
    double? start,
    double? end,
  }) {
    return PositionedDirectional(
      top: top,
      bottom: bottom,
      start: start,
      end: end,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Transform.translate(
            offset: Offset(drift.dx * _t.value, drift.dy * _t.value),
            child: child,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return ColoredBox(
      color: surf.pageBg,
      // Stack يقصّ افتراضياً (Clip.hardEdge)، وهذا مقصود: الكرات موضوعة
      // بإزاحات سالبة فتظهر أنصافها فقط من حواف الشاشة كما في التصميم.
      child: Stack(
        children: [
          _orb(
            size: 300,
            color: surf.orb1,
            top: -120,
            end: -80,
            drift: const Offset(-22, 26),
          ),
          _orb(
            size: 260,
            color: surf.orb2,
            top: 120,
            start: -110,
            drift: const Offset(26, -20),
          ),
          _orb(
            size: 240,
            color: surf.orb3,
            bottom: -70,
            end: -60,
            drift: const Offset(22, -26),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// شريط التنقل السفلي الزجاجي الداكن المتوهّج -- المكافئ الجوّالي للهيدر
/// العلوي وقائمة الهمبرغر في نسخة الويب (bg-[#1e1b4b]/85 + backdrop-blur،
/// وتبويب نشط بتوهّج سيان). يحل محل NavigationBar الأبيض المسطّح القديم.
class GlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// عدد يظهر في شارة حمراء فوق الأيقونة (طلبات الحجز المعلّقة) -- 0 يعني
  /// بلا شارة. نفس شارة notification-badge.js على تبويب "المواعيد" بالموقع.
  final int badgeCount;

  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// حصّة العرض التي يأخذها التبويب النشط مقابل ١ لغيره -- هي `flex: 1.45`
  /// في التصميم. العرض يُحسَب يدوياً بدل `Expanded(flex:)` لأن flex عدد صحيح
  /// ولا يتحرّك: تغييره يقفز قفزة واحدة، بينما AnimatedContainer بعرض محسوب
  /// ينزلق فعلاً.
  static const _activeFlex = 1.45;
  static const _gap = 4.0;
  static const _innerPadding = 8.0;

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // 2026-09-05: الشريط صار **عائماً** لا ملتصقاً بحافة الشاشة -- كبسولة
    // بحوافّ 26 وهامش 16 من كل جانب، تماماً كما في التصميم المعتمد. لهذا
    // اختفت الحواف العلوية وحدها (BorderRadius.vertical) وصار الحدّ محيطاً.
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Container(
        height: 66,
        padding: const EdgeInsets.all(_innerPadding),
        decoration: BoxDecoration(
          color: surf.navBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: surf.navBorder),
          boxShadow: surf.navShadow,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // نصف بكسل احتياطي: مجموع العروض المحسوبة + الفواصل يساوي العرض
            // المتاح بالضبط رياضياً، وأي خطأ فاصلة عائمة يجعل Row يبلّغ عن
            // تجاوز. الخصم أرخص من التعامل مع شريط عليه خطوط التحذير.
            final available =
                constraints.maxWidth - _gap * (items.length - 1) - 0.5;
            // مجموع الحصص: النشط 1.45 والبقية 1 لكلٍّ.
            final unit = available / (items.length - 1 + _activeFlex);
            return Row(
              // stretch حتى تملأ كبسولة التبويب النشط ارتفاع الشريط كاملاً
              // بدل أن تنكمش على ارتفاع الأيقونة والنص. آمنة هنا تحديداً لأن
              // الأب حاوية بارتفاع ثابت (66) لا قائمة قابلة للتمرير -- تلك
              // الحالة هي التي تعطي maxHeight لانهائياً وتُسقط الإطار.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  _tab(
                    context: context,
                    index: i,
                    width: i == currentIndex ? unit * _activeFlex : unit,
                    surf: surf,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tab({
    required BuildContext context,
    required int index,
    required double width,
    required AppSurface surf,
  }) {
    final selected = index == currentIndex;
    final item = items[index];
    final color = selected ? surf.onAccent : surf.navInactive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          width: width,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            gradient: selected ? surf.accentGradient : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: surf.accentGlow,
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stack مع clipBehavior: none حتى تخرج الشارة عن حدود الأيقونة
              // بدل أن تُقصّ عند حافتها.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? item.activeIcon : item.icon,
                      size: 20, color: color),
                  if (item.badgeCount > 0)
                    PositionedDirectional(
                      top: -5,
                      end: -8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.rose500,
                          borderRadius: BorderRadius.circular(999),
                          // حلقة بلون الشريط نفسه تفصل الشارة عن الأيقونة
                          // مهما كان الوضع -- بديل ‎box-shadow 0 0 0 2px
                          // في التصميم.
                          border: Border.all(color: surf.navBg, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.rose500.withValues(alpha: .6),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ترويسة علوية موحّدة لكل تبويبات التطبيق -- طبق الأصل عن الترويسة الداكنة
/// المضغوطة في الموقع على الجوال: مربّع الشعار، اسم العيادة، ثم شارة الباقة.
/// مبنية فوق [AnimatedHeroHeader] فتحتفظ بانيميشن التدرّج "المتنفّس" الذي
/// كانت عليه ترويسات الشاشات قبل التوحيد.
class ClinicTopBar extends StatefulWidget {
  /// عنصر اختياري في أقصى اليسار (زر إشعارات، رجوع، إضافة...) -- المكان
  /// الذي تضع فيه صفحات الموقع أزرارها في الترويسة نفسها.
  final Widget? trailing;

  /// سطر رمادي صغير تحت اسم العيادة (تحية، تاريخ اليوم، عدد المواعيد...).
  /// اختياري: الشاشات التي لا تمرّره تبقى بسطر واحد كما كانت.
  final String? subtitle;

  const ClinicTopBar({super.key, this.trailing, this.subtitle});

  @override
  State<ClinicTopBar> createState() => _ClinicTopBarState();
}

class _ClinicTopBarState extends State<ClinicTopBar> {
  final AuthStorage _authStorage = AuthStorage();
  String _clinicName = 'عيادة الطبيب';
  String _tier = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _authStorage.getDoctorName();
    final tier = await _authStorage.getTier();
    if (!mounted) return;
    setState(() {
      if (name != null && name.trim().isNotEmpty) {
        _clinicName = 'عيادة ${name.trim()}';
      }
      _tier = tier ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-05: لم تعد ترويسة داكنة بتدرّج -- في نظام «الليل النيلي»
    // الترويسة تجلس مباشرة على خلفية الصفحة (وكرات الضوء تمرّ خلفها)، فصارت
    // شفّافة تماماً وتستمدّ ألوانها من AppSurface. AnimatedHeroHeader بقيت
    // موجودة كما هي للشاشات التي ما زالت تستعملها (ملف المريض، حسابي...).
    final surf = context.surface;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + 14,
        18,
        0,
      ),
      child: Row(
        children: [
          // شعار الموقع (2026-09-25) بدل أيقونة الحقيبة الطبية.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet600.withValues(alpha: .22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const ClinicLogo(size: 42),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _clinicName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppType.kufi(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: surf.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: surf.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // شارة الباقة مرسومة هنا بتوكنات AppSurface بدل [TierBadge] --
          // تلك مبنية على أبيض شفاف فوق ترويسة داكنة، وتختفي تماماً على
          // خلفية بيضاء. TierBadge تُركت كما هي لأن شاشات أخرى ما زالت
          // تضعها فوق ترويسات داكنة.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: surf.tierBorder),
              color: surf.tierBg,
            ),
            child: Text(
              ClinicTier.badgeLabel(_tier),
              style: TextStyle(
                color: surf.tierFg,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 6),
            widget.trailing!,
          ],
        ],
      ),
    );
  }
}

/// شريط رفيع يعكس حالة المزامنة الأوفلاين (انظر OfflineSyncStatus/
/// OfflineAwareApiService) -- يظهر فقط عند وجود ما يستحق إخبار الطبيب به
/// (عمليات بانتظار الاتصال، أو عمليات رفضها السيرفر رفضاً حقيقياً)، ويختفي
/// تلقائياً بعد اكتمال المزامنة. عام (غير خاص بملف واحد) منذ 2026-09-02 --
/// كان خاصاً بشاشة المواعيد وحدها (_OfflineSyncBanner في
/// today_schedule_screen.dart) قبل توسيع دعم العمل بدون إنترنت لبقية
/// الشاشات (مرضى/مخزون/مالية/ملف مريض)، فنُقل هنا ليُستخدَم من الجميع بلا
/// تكرار. الرسائل عامة عمداً ("عملية/عمليات") لأنها لا تميّز نوع الكيان
/// (موعد/مريض/مادة مخزون/فاتورة) -- التفاصيل تظهر بدلاً من ذلك كأيقونة
/// "قيد المزامنة" صغيرة بجانب كل سجل معلَّق تحديداً.
class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: OfflineSyncStatus.instance.pendingCount,
      builder: (context, pending, _) {
        return ValueListenableBuilder<int>(
          valueListenable: OfflineSyncStatus.instance.failedCount,
          builder: (context, failed, _) {
            if (pending == 0 && failed == 0) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: OfflineSyncStatus.instance.isOnline,
              builder: (context, online, _) {
                final messages = <String>[];
                if (pending > 0) {
                  messages.add(online
                      ? 'جارٍ مزامنة $pending ${pending == 1 ? 'عملية' : 'عمليات'}...'
                      : 'غير متصل بالإنترنت -- $pending ${pending == 1 ? 'عملية' : 'عمليات'} ستُرفَع تلقائياً عند عودة الاتصال');
                }
                if (failed > 0) {
                  messages.add(
                      'تعذّرت مزامنة $failed ${failed == 1 ? 'عملية' : 'عمليات'} بسبب رفض من السيرفر');
                }
                final isWarning = failed > 0 || !online;
                final surf = context.surface;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: isWarning ? surf.warnBg : surf.chipBg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        online ? Icons.sync : Icons.cloud_off_outlined,
                        size: 15,
                        color: isWarning ? surf.warnFg : surf.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          messages.join(' -- '),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isWarning ? surf.warnFg : surf.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// زر إضافة عائم دائري بتدرّج لوني -- نفس شكل الأزرار الرئيسية في الموقع
/// (مثل "+ إضافة مريض" و"+ إضافة موعد جديد")، بديل محلي لـ FloatingActionButton
/// القياسي حتى يستخدم تدرّج الموقع بدل لون Material الافتراضي.
class GradientFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  /// حين يُمرَّر نص يصبح الزر شريطاً ممتداً بأيقونة ونص (نفس زر "مريض
  /// جديد" العائم في الموقع)، وإلا يبقى دائرة 56px كما كان.
  final String? label;

  const GradientFab({
    super.key,
    required this.onPressed,
    this.icon = Icons.add,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    // 2026-09-05: صار كبسولة كاملة الاستدارة (999) بتدرّج التمييز وتوهّجه من
    // AppSurface، بدل مستطيل نصف قطره 20 بتدرّج نيلي/بنفسجي ثابت. النصّ
    // والأيقونة يستعملان onAccent لأن التمييز الليلي فاتح ويحتاج نصّاً
    // داكناً، بينما النهاري مُغمَّق ويحتاج نصّاً أبيض.
    final surf = context.surface;
    final text = label;
    final shape = text == null
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));

    return Material(
      color: Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: Container(
          width: text == null ? 56 : null,
          height: text == null ? 56 : 52,
          alignment: Alignment.center,
          padding: text == null
              ? null
              : const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            shape: text == null ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: text == null ? null : BorderRadius.circular(999),
            gradient: surf.accentGradient,
            boxShadow: [
              BoxShadow(
                color: surf.accentGlow,
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: text == null
              ? Icon(icon, color: surf.onAccent, size: 26)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: surf.onAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: AppType.kufi(
                        color: surf.onAccent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// -- 2026-08-31: مكوّنات مشتركة لشاشتَي تسجيل الدخول (login_screen.dart)
// وتفعيل الحساب الجديدة (register_screen.dart) -- تحاكي بالضبط بنية
// login.html/register.html بالموقع: بطاقة بيضاء + رأس بتدرّج + حقول داخل
// إطار فاتح (field-focus) + صندوق حالة/مؤشر أعلى النموذج + صف الرابط
// السفلي. مُركزة هنا حتى تبقى الشاشتان متطابقتَي الشكل تماماً كنسختَي
// الموقع، ولأي شاشة مصادقة مستقبلية أن تعيد استخدامها.

/// إطار الحقل الفاتح المستدير (field-focus) -- نفس
/// `.field-focus { rounded-[24px] border-slate-200 bg-slate-50/70 p-3 }` في
/// الموقع. label + trailing اختياري (مثل زر "إظهار" كلمة المرور) في صف
/// علوي، ثم [child] (حقل الإدخال نفسه)، ثم [footer] اختياري لأي نص/شريط
/// مساعد أسفل الحقل (تلميح، شريط قوة كلمة المرور...).
class AuthFieldWrapper extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final Widget child;
  final Widget? footer;

  const AuthFieldWrapper({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surf.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: surf.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: surf.textSecondary,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// ديكوريشن حقل الإدخال الأبيض داخل [AuthFieldWrapper] -- مطابق تماماً
/// لِـ `rounded-xl border-slate-300 bg-white focus:border-indigo-500
/// focus:ring-4 focus:ring-indigo-100` في login.html/register.html.
/// [context] اختياري للتوافق مع أي استدعاء قديم؛ حين يُمرَّر تتبع ألوان
/// الحقل وضع الإضاءة بدل أن تبقى بيضاء ثابتة داخل بطاقة داكنة.
InputDecoration authInputDecoration({
  required String hint,
  BuildContext? context,
}) {
  final surf = context == null ? AppSurface.light : context.surface;
  final radius = BorderRadius.circular(12);
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: surf.fieldHint, fontSize: 13),
    filled: true,
    fillColor: surf.fieldBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: surf.fieldBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: surf.fieldBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: surf.accentSolid, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.rose400),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.rose400, width: 1.6),
    ),
    errorStyle: const TextStyle(color: AppColors.rose600, fontSize: 11.5),
  );
}

/// صندوق "حالة الجاهزية"/"مؤشر التفعيل" أعلى نموذج الدخول/التسجيل -- نفس
/// `rounded-2xl border-indigo-100 bg-indigo-50/80` في الموقع، بشارة دائرية
/// [badgeText] وسطر تلميح [hint] أسفله.
class AuthStatusBanner extends StatelessWidget {
  final String title;
  final String badgeText;
  final String hint;
  final Color badgeBackground;
  final Color badgeColor;

  const AuthStatusBanner({
    super.key,
    required this.title,
    required this.badgeText,
    required this.hint,
    this.badgeBackground = Colors.white,
    this.badgeColor = AppColors.indigoAccent,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surf.iconBoxBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surf.iconBoxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: surf.isDark ? surf.textPrimary : AppColors.indigo800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.7,
              // ملاحظة: indigo700 هنا هي الثابت الذي يحمل قيمة Tailwind
              // indigo-800 الحقيقية فعلياً (تسمية قديمة موروثة في هذا
              // الملف -- انظر تعليق الألوان في app_theme.dart)، وهي المطابقة
              // الصحيحة لِـ text-indigo-800/80 في login.html/register.html
              // بالموقع (وليس indigo800 التي تحمل قيمة indigo-900 فعلياً).
              color: surf.iconBoxFg.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف الرابط السفلي ("لا تملك حسابًا بعد؟" / "هل الحساب مفعّل بالفعل؟") --
/// نفس `rounded-2xl bg-slate-50` في الموقع، بنص عادي على اليمين ورابط
/// إندگو غامق قابل للنقر على اليسار (RTL).
class AuthBottomLinkRow extends StatelessWidget {
  final String text;
  final String linkText;
  final VoidCallback onTap;

  const AuthBottomLinkRow({
    super.key,
    required this.text,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(fontSize: 13, color: AppColors.slate600)),
          InkWell(
            onTap: onTap,
            child: Text(
              linkText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.indigoAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// توست عائم من الأعلى -- نفس دالة `showPremiumToast()` في login.html
/// بالموقع بالحرف: كبسولة بتدرّج وردي/أحمر (خطأ) أو أخضر/سماوي (نجاح)،
/// تنزلق من الأعلى (fade+slide 220ms)، تبقى ~4.5 ثانية ثم تختفي (250ms).
/// تُستخدم في شاشة تسجيل الدخول تحديداً لأن الموقع لا يستخدم صندوق رسالة
/// ثابت هناك (register.html وحده يستخدم صندوق رسالة ثابت -- انظر
/// AuthMessageBox أدناه).
void showAuthToast(BuildContext context, String message, {bool isError = true}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AuthToast(
      message: message,
      isError: isError,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AuthToast extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDone;

  const _AuthToast({
    required this.message,
    required this.isError,
    required this.onDone,
  });

  @override
  State<_AuthToast> createState() => _AuthToastState();
}

class _AuthToastState extends State<_AuthToast> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _visible = true);
      await Future.delayed(const Duration(milliseconds: 4500));
      if (!mounted) return;
      setState(() => _visible = false);
      await Future.delayed(const Duration(milliseconds: 250));
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.isError
        ? const LinearGradient(colors: [AppColors.rose500, AppColors.red600])
        : const LinearGradient(colors: [AppColors.emerald500, AppColors.cyan500]);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          offset: _visible ? Offset.zero : const Offset(0, -0.4),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _visible ? 1 : 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// صندوق رسالة ثابت -- نفس `#messageBox` في register.html بالموقع
/// (rounded-2xl border px-4 py-3 نص+حدود وردية للخطأ أو خضراء للنجاح).
class AuthMessageBox extends StatelessWidget {
  final String message;
  final bool isError;

  const AuthMessageBox({super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    // الدلالة ثابتة (أحمر خطأ، أخضر نجاح) لكن الدرجات الفاتحة المصمتة
    // rose50/emerald50 تصير بقعتين ساطعتين داخل بطاقة داكنة.
    final base = isError ? AppColors.rose500 : AppColors.emerald500;
    final borderColor = base.withValues(alpha: surf.isDark ? .30 : .35);
    final bgColor = base.withValues(alpha: surf.isDark ? .12 : .08);
    final textColor = isError
        ? (surf.isDark ? AppColors.rose400 : AppColors.rose700text)
        : surf.pillPaidFg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        message,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }
}

/// خلفية صفحات تسجيل الدخول/تفعيل الحساب -- نفس الخلفية الشبكية الفاتحة
/// ودوائرها الزخرفية الباهتة في login.html/register.html بالموقع
/// (radial-gradient + linear-gradient بألوان slate-50/indigo-50/indigo-100،
/// مع ثلاث دوائر blur-3xl). الدوائر هنا Radial Gradient متلاشية بدل بلور
/// حقيقي (أخف أداءً على الجوال، ونفس الأثر البصري تقريباً).
class AuthPageBackground extends StatelessWidget {
  const AuthPageBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // 2026-09-06: كانت تدرّجاً نيلياً فاتحاً ثابتاً، فتبقى شاشات المصادقة
    // نهارية داخل الوضع الليلي ثم يقفز التطبيق إلى ‎#07061A بعد الدخول
    // مباشرة. صارت تقرأ نفس توكنات AtmosphereBackground: السطح وكرات الضوء
    // بمواضعها -- بلا انجراف هنا عمداً، فشاشة الدخول لحظة سكون لا حركة.
    final surf = context.surface;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: surf.pageBg),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.0,
                      colors: [
                        surf.accentSolid
                            .withValues(alpha: surf.isDark ? 0.18 : 0.16),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(top: 60, right: -50, child: _blurCircle(220, surf.orb1)),
            Positioned(top: 220, left: -60, child: _blurCircle(240, surf.orb2)),
            Positioned(bottom: 0, right: 60, child: _blurCircle(200, surf.orb3)),
          ],
        ),
      ),
    );
  }

  Widget _blurCircle(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مكوّنات نظام «الليل النيلي» (2026-09-05)
// ═══════════════════════════════════════════════════════════════════════════
// بنية واحدة لوضعين لونيين: كل ما هنا يقرأ [AppSurface] عبر `context.surface`
// ولا يحمل أي لون ثابت. المقاسات وأنصاف الأقطار والحركات متطابقة في
// الوضعين -- اللون وحده يتبدّل، وهذا هو نص طلب المستخدم.

/// بطاقة الرأس: الحاوية التي تحمل الرقم الكبير وصفّ العدّادين في أعلى كل
/// تبويب. تحمل ثلاث طبقات فوق بعضها:
///   1. لون السطح + الحدّ + الظلّ (من AppSurface).
///   2. غَسلة شعاعية بنفسجية في الزاوية العليا -- تعطي البطاقة عمقاً بلا
///      تدرّج صريح يُثقل التصميم.
///   3. لمعة تمرّ عرضياً كل ٨ ثوانٍ. لونها أبيض شفاف ليلاً ونيلي شفاف
///      نهاراً، لأن اللمعة البيضاء تختفي تماماً على سطح أبيض.
/// اللمعة تسافر من اليمين لليسار فيزيائياً (Positioned.right) في الوضعين --
/// اتجاهها ليس اتجاه قراءة بل اتجاه ضوء، فلا ينعكس مع RTL.
class HeroPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const HeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(17, 16, 17, 16),
    this.radius = 26,
  });

  @override
  State<HeroPanel> createState() => _HeroPanelState();
}

class _HeroPanelState extends State<HeroPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  // اللمعة تعبر في أول ٥٥٪ من الدورة ثم تتوقف خارج الإطار حتى نهايتها --
  // فتظهر كومضة عابرة كل ٨ ثوانٍ لا كشريط يتحرّك بلا انقطاع.
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.55, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final radius = BorderRadius.circular(widget.radius);

    return Container(
      decoration: BoxDecoration(
        color: surf.heroBg,
        borderRadius: radius,
        border: Border.all(color: surf.heroBorder),
        boxShadow: surf.heroShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.8, -1.1),
                      radius: 1.1,
                      colors: [surf.heroWash, surf.heroWash.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return AnimatedBuilder(
                      animation: _sweep,
                      builder: (context, _) {
                        return Stack(
                          children: [
                            Positioned(
                              right: -90 + _sweep.value * (width + 180),
                              top: -40,
                              bottom: -40,
                              width: 80,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.skewX(-0.28),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [
                                        surf.sheen.withValues(alpha: 0),
                                        surf.sheen,
                                        surf.sheen.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(padding: widget.padding, child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// النقطة "الحيّة" النابضة بجانب عنوان بطاقة الرأس -- إشارة إلى أن الرقم
/// أدناه محسوب من بيانات السيرفر لا مخزَّن مسبقاً. الهالة حولها ثابتة
/// والنبض في الشفافية وحدها (أرخص من تحريك ظلّ، ولا يحرّك التخطيط).
class LivePulseDot extends StatefulWidget {
  const LivePulseDot({super.key});

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 1, end: .35)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: surf.liveDot,
          boxShadow: [
            BoxShadow(color: surf.liveDotHalo, blurRadius: 0, spreadRadius: 3),
          ],
        ),
      ),
    );
  }
}

/// الرقم الكبير في بطاقة الرأس + وحدته الصغيرة بجانبه. التوهّج خلفه يأتي من
/// [AppSurface.bigNumberGlow] وهو null نهاراً عمداً: التوهّج على أبيض يقرأ
/// كضبابية لا كفخامة، والوزن هناك يأتي من اللون الداكن نفسه.
class HeroBigNumber extends StatelessWidget {
  final String value;
  final String? unit;
  final double fontSize;

  const HeroBigNumber({
    super.key,
    required this.value,
    this.unit,
    this.fontSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final glow = surf.bigNumberGlow;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.kufi(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: surf.bigNumber,
              letterSpacing: -1.2,
              height: 1.15,
            ).copyWith(
              shadows: glow == null
                  ? null
                  : [Shadow(color: glow.withValues(alpha: .55), blurRadius: 32)],
            ),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 5),
          Text(
            unit!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: surf.bigNumberUnit,
            ),
          ),
        ],
      ],
    );
  }
}

/// عدّاد صغير داخل صفّ العدّادين أسفل الرقم الكبير: صندوق أيقونة، ثم الرقم
/// فوق تسميته.
class HeroMiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const HeroMiniStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: surf.iconBoxBg,
            border: Border.all(color: surf.iconBoxBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 16, color: surf.iconBoxFg),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppType.kufi(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: surf.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: surf.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// صفّ العدّادين أسفل الرقم الكبير: حدّ علوي رفيع، وفاصل رأسي بين كل عدّاد
/// والذي يليه. ارتفاع الفاصل ثابت (34) عمداً بدل `CrossAxisAlignment.stretch`
/// داخل IntrinsicHeight -- الأخير يعطي `maxHeight: infinity` داخل قائمة
/// قابلة للتمرير فينهار الإطار (وقعنا في هذا فعلاً 2026-09-02).
class HeroStatsRow extends StatelessWidget {
  final List<Widget> children;

  const HeroStatsRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final row = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        row.add(Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 13),
          color: surf.divider,
        ));
      }
      row.add(Expanded(child: children[i]));
    }
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: surf.divider)),
      ),
      child: Row(children: row),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// حركة الأرقام والبطاقات (2026-09-25)
// ═══════════════════════════════════════════════════════════════════════════
// صفحتا المالية والأطباء كانتا تعرضان أرقامهما جامدة دفعة واحدة. هذه ثلاث
// أدوات صغيرة مشتركة: رقم يعدّ إلى قيمته، شريط يمتلئ، وبطاقة تظهر منزلقة.
// كلها تحترم «تقليل الحركة» في إعدادات الجهاز (MediaQuery.disableAnimations)
// فتعرض الحالة النهائية فوراً.

/// مبلغ بفواصل الآلاف بلا كسور: 1,250,000 -- نفس صيغة بطاقة المرضى.
String formatGroupedMoney(double value) {
  if (!value.isFinite) return '0';
  final digits = value.round().abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// رقم يعدّ من الصفر إلى [value] عند الظهور، ومن قيمته السابقة إلى الجديدة
/// عند تغيّرها (تبديل الشهر) -- TweenAnimationBuilder يبدأ دائماً من القيمة
/// المعروضة لحظتها، فلا قفزة إلى الصفر بين فترتين.
class AnimatedNumber extends StatelessWidget {
  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  const AnimatedNumber({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 950),
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => builder(context, animated),
    );
  }
}

/// شريط يمتلئ من بدايته (يمين الشاشة في RTL) إلى عرضه الكامل. يُلفّ حول
/// الشريط الجاهز كما هو -- لا يحتاج الشريط أن يعرف شيئاً عن الحركة.
class BarReveal extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const BarReveal({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1100),
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutQuart,
      builder: (context, t, bar) => ClipRect(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: t,
          child: bar,
        ),
      ),
      child: child,
    );
  }
}

/// ظهور البطاقة: شفافية + انزلاق خفيف للأعلى، بعد تأخير [delay] -- تأخيرات
/// متدرّجة على بطاقات متتالية تجعلها تتوالى بدل أن تقفز معاً.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 14,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offsetY),
          child: child,
        ),
      ),
    );
  }
}

/// شريط نسبتين (واردات/مصاريف، حصص الأطباء/حصة العيادة) بلونين ومفتاح
/// تحته، يمتلئ متحرّكاً. [first] و[second] قيم خام؛ النسب تُحسب هنا.
class HeroSplitBar extends StatelessWidget {
  final double first;
  final double second;
  final Color firstColor;
  final Color secondColor;
  final String firstLabel;
  final String secondLabel;

  const HeroSplitBar({
    super.key,
    required this.first,
    required this.second,
    required this.firstColor,
    required this.secondColor,
    required this.firstLabel,
    required this.secondLabel,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final a = first < 0 ? 0.0 : first;
    final b = second < 0 ? 0.0 : second;
    final total = a + b;
    final firstShare = total > 0 ? (a / total * 100).round() : 50;
    final secondShare = 100 - firstShare;

    Widget legend(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: surf.textSecondary),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: surf.divider,
            borderRadius: BorderRadius.circular(999),
          ),
          child: BarReveal(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              // ارتفاع صريح: BarReveal يرخي القيود (Align)، و ColoredBox بلا
              // ابن ينكمش حينها إلى صفر فيختفي الشريط.
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (firstShare > 0) Expanded(flex: firstShare, child: ColoredBox(color: firstColor)),
                    if (secondShare > 0) Expanded(flex: secondShare, child: ColoredBox(color: secondColor)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            legend(firstColor, total > 0 ? '$firstLabel $firstShare%' : firstLabel),
            const Spacer(),
            legend(secondColor, total > 0 ? '$secondLabel $secondShare%' : secondLabel),
          ],
        ),
      ],
    );
  }
}

/// شريط شرائح التصفية. الشريحة النشطة تأخذ تدرّج التمييز ونصّ [onAccent]،
/// والساكنة تبقى بلون السطح وحدّه. العدّ اختياري لكل شريحة.
class FilterChipsBar extends StatelessWidget {
  final List<String> labels;
  final List<int>? counts;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const FilterChipsBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: i == selectedIndex ? null : surf.chipBg,
                  gradient: i == selectedIndex ? surf.accentGradient : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: i == selectedIndex
                        ? Colors.transparent
                        : surf.chipBorder,
                  ),
                  boxShadow: i == selectedIndex
                      ? [
                          BoxShadow(
                            color: surf.accentGlow,
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: i == selectedIndex ? surf.onAccent : surf.chipFg,
                      ),
                    ),
                    if (counts != null && i < counts!.length) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${counts![i]}',
                        style: AppType.kufi(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: (i == selectedIndex
                                  ? surf.onAccent
                                  : surf.chipFg)
                              .withValues(alpha: .68),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// حقل بحث كبسولي بظلّ ناعم بدل الحدّ الرمادي الصلب.
class SoftSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;

  /// اختياري. يلزم فقط حين يُضبَط نصّ البحث من خارج الحقل (حقل بحث ترويسة
  /// سطح المكتب يدفع كلمته إلى شاشة المرضى) -- بلا وحدة تحكّم يتغيّر الفلتر
  /// ويبقى الحقل فارغاً أمام الطبيب، فلا يفهم لماذا اختفى نصف مرضاه.
  final TextEditingController? controller;

  const SoftSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: surf.cardShadow,
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: surf.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: surf.fieldHint,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: surf.fieldHint),
          filled: true,
          fillColor: surf.fieldBg,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: surf.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: surf.accentSolid, width: 1.4),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: surf.fieldBorder),
          ),
        ),
      ),
    );
  }
}

/// زر أيقونة مربّع 34px داخل البطاقات (فتح الملف، اتصال، تعديل، واتساب).
/// لونه الأمامي يُمرَّر صراحةً لأن دلالته لونية (نيلي = ملف، أخضر = اتصال)
/// وهي ثابتة في الوضعين، بينما خلفيته وحدّه من AppSurface.
class SoftIconButton extends StatelessWidget {
  final IconData icon;
  final Color foreground;
  final String tooltip;
  final VoidCallback onPressed;

  const SoftIconButton({
    super.key,
    required this.icon,
    required this.foreground,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: surf.actionBg,
              border: Border.all(color: surf.actionBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// شارة حالة صغيرة بنقطة ملوّنة -- الحالة المالية على بطاقة المريض، وحالة
/// الموعد على بطاقة الموعد.
class SoftStatusPill extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final Color border;

  const SoftStatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: foreground),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppType.kufi(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
