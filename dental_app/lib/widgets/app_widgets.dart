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
///   respondToBooking (decision: accept/reject).
/// - pending (موعد عادي بانتظار الدوام): دخل العيادة/تخلّف عبر
///   updateAppointmentStatus (status: checked_in/no_show).
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

  const AppointmentActionButtons({
    super.key,
    required this.status,
    required this.isUpdating,
    required this.onCheckIn,
    required this.onNoShow,
    required this.onAccept,
    required this.onReject,
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
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.rose700text,
                  side: const BorderSide(color: AppColors.rose200),
                ),
                child: const Text('رفض'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GradientButton(
                label: 'قبول',
                onPressed: onAccept,
                gradient: AppColors.successButtonGradient,
              ),
            ),
          ],
        ),
      );
    }
    if (normalized == 'pending') {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onNoShow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.rose700text,
                  side: const BorderSide(color: AppColors.rose200),
                ),
                child: const Text('تخلّف عن الموعد'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GradientButton(
                label: 'دخل العيادة',
                onPressed: onCheckIn,
                gradient: AppColors.successButtonGradient,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
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

/// بطاقة "Smart Stat" الزجاجية الداكنة المتوهّجة -- تحاكي بطاقات الإحصاء في
/// index.html بالموقع (تدرّج كحلي/إنديغو/بنفسجي غامق + توهّج سيان وبنفسجي
/// خلفها). تحل محل البطاقة البيضاء المسطّحة القديمة في الشاشة الرئيسية.
class SmartStatCard extends StatelessWidget {
  final List<({String value, String label})> stats;

  const SmartStatCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
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
                    Container(width: 1, height: 34, color: Colors.white.withValues(alpha: .14)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          stats[i].value,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          stats[i].label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .68),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
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
