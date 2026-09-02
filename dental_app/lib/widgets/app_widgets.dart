import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
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

/// بطاقة بيضاء بحواف مدوّرة وحدود رفيعة وظل خفيف -- نفس شكل كل بطاقات
/// الموقع/التصميم (rounded-2xl border-slate-200 shadow).
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.slate200),
        boxShadow: [
          BoxShadow(
            color: AppColors.slate900.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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

  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 46,
    this.background = AppColors.indigo50,
    this.foreground = AppColors.indigo700,
  });

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '؟';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final second =
        parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final result = '$first$second'.trim();
    return result.isEmpty ? trimmed[0] : result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
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

  const AppointmentUtilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style = AppointmentUtilityStyle.neutral,
    this.isLoading = false,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
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
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: contentColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLocked ? Icons.lock_outline : Icons.error_outline,
                size: 44,
                color: AppColors.slate400,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate600),
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

/// شارة مستوى الاشتراك (Standard/Premium) -- نفس الشارة البيضاوية شبه
/// الشفافة الموجودة في هيدر كل صفحة بالموقع (tierBadge#) بجانب اسم العيادة.
/// تُكتب "Standard"/"Premium" بالإنكليزية عمداً كما في الموقع تماماً -- ليس
/// خطأ ترجمة.
class TierBadge extends StatelessWidget {
  final String tier;

  const TierBadge({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final label = tier.toLowerCase() == 'premium' ? 'Premium' : 'Standard';
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
class AtmosphereBackground extends StatelessWidget {
  final Widget child;

  const AtmosphereBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 140,
          right: -50,
          child: IgnorePointer(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.indigo600.withValues(alpha: .09),
              ),
            ),
          ),
        ),
        Positioned(
          top: 320,
          left: -60,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.violet600.withValues(alpha: .07),
              ),
            ),
          ),
        ),
        child,
      ],
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

  const GlassNavItem({required this.icon, required this.activeIcon, required this.label});
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + bottomInset),
      decoration: BoxDecoration(
        gradient: AppColors.bottomNavGradient,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++) _tab(i),
        ],
      ),
    );
  }

  Widget _tab(int index) {
    final selected = index == currentIndex;
    final item = items[index];
    final color = selected ? AppColors.cyan300 : Colors.white.withValues(alpha: .62);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? AppColors.cyan400.withValues(alpha: .14) : Colors.transparent,
            border: selected
                ? Border.all(color: AppColors.cyan400.withValues(alpha: .30))
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.cyan400.withValues(alpha: .18),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? item.activeIcon : item.icon, size: 21, color: color),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// زر إضافة عائم دائري بتدرّج لوني -- نفس شكل الأزرار الرئيسية في الموقع
/// (مثل "+ إضافة مريض" و"+ إضافة موعد جديد")، بديل محلي لـ FloatingActionButton
/// القياسي حتى يستخدم تدرّج الموقع بدل لون Material الافتراضي.
class GradientFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const GradientFab({super.key, required this.onPressed, this.icon = Icons.add});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryButtonGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.indigoAccent.withValues(alpha: .40),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pageBg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.slate200),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate700,
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
InputDecoration authInputDecoration({required String hint}) {
  final radius = BorderRadius.circular(12);
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.slate300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.slate300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.indigo500, width: 1.6),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.indigo50.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.indigo800,
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
              color: AppColors.indigo700.withValues(alpha: 0.8),
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
    final borderColor = isError ? AppColors.rose200 : AppColors.emerald200;
    final bgColor = isError ? AppColors.rose50 : AppColors.emerald50;
    final textColor = isError ? AppColors.rose700text : AppColors.emerald700text;
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
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.pageBg, AppColors.indigo50, AppColors.indigo100],
          ),
        ),
        child: Stack(
          children: [
            // نفس radial-gradient(circle_at_top_left, rgba(99,102,241,0.22),
            // transparent_30%) في الموقع.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.0,
                      colors: [AppColors.indigo500.withValues(alpha: 0.22), Colors.transparent],
                      stops: const [0.0, 0.3],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(top: 60, right: -50, child: _blurCircle(180, AppColors.indigo200, 0.35)),
            Positioned(top: 220, left: -60, child: _blurCircle(200, const Color(0xFFC4B5FD), 0.25)),
            Positioned(bottom: 0, right: 60, child: _blurCircle(190, AppColors.indigo200, 0.25)),
          ],
        ),
      ),
    );
  }

  Widget _blurCircle(double size, Color color, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
