import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../theme/app_theme.dart';

/// لبنات صفحات سطح المكتب المشتركة (2026-09-24).
///
/// نُقلت من `desktop_home_screen.dart` حين صارت صفحتا المرضى والمواعيد
/// تحتاجانها: لوحة واحدة وزرّ إجراء واحد وشارة حالة واحدة، فلا تتباعد حدود
/// اللوحات وظلالها بين صفحة وأخرى. كل الألوان من `context.desktop`.

final NumberFormat desktopMoney = NumberFormat('#,##0', 'en_US');

/// «09:00 ص» / «01:30 م» — نفس صياغة الكانفاس، بأرقام غربية كبقية الموقع
/// والتطبيق (انظر [[dental_project_locale_digits_fix]]).
String desktopClockLabel(int? minutes) {
  if (minutes == null) return '—';
  final normalized = minutes % (24 * 60);
  final hour24 = normalized ~/ 60;
  final minute = normalized % 60;
  final isPm = hour24 >= 12;
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final hh = hour12.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');
  return '$hh:$mm ${isPm ? 'م' : 'ص'}';
}

/// الأحرف الأولى لاسم المريض/الطبيب داخل المربّع الملوّن.
String desktopInitials(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && w != 'د.' && w != 'د')
      .toList();
  if (words.isEmpty) return '؟';
  if (words.length == 1) return words.first.substring(0, 1);
  return '${words[0].substring(0, 1)}.${words[1].substring(0, 1)}';
}

/// لوحة بيضاء/زجاجية بعنوان ورابط إجراء اختياري. [shrink] لِلوحة تأخذ
/// ارتفاع محتواها (الأطباء اليوم) بدل أن تتمدّد.
class DesktopPanel extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;
  final bool shrink;

  const DesktopPanel({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.shrink = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final content = Column(
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppType.kufi(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: d.textPrimary,
                ),
              ),
            ),
            if (actionLabel != null)
              DesktopTextLink(label: actionLabel!, onTap: onAction),
          ],
        ),
        const SizedBox(height: 12),
        if (shrink) child else Expanded(child: child),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: d.cardBg,
        gradient: d.cardGradient,
        borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusPanel),
        border: Border.all(color: d.cardBorder),
        boxShadow: d.panelShadow,
      ),
      child: content,
    );
  }
}

class DesktopTextLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const DesktopTextLink({super.key, required this.label, required this.onTap});

  @override
  State<DesktopTextLink> createState() => _DesktopTextLinkState();
}

class _DesktopTextLinkState extends State<DesktopTextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style:
              AppType.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: d.linkFg,
              ).copyWith(
                decoration: _hovered ? TextDecoration.underline : null,
                decorationColor: d.linkFg,
              ),
        ),
      ),
    );
  }
}

/// شارة الحالة بألوان سطح المكتب. الحالات الثلاث التي تظهر في جدول اليوم
/// فعلاً: تمّ/دخل العيادة (أخضر)، قيد الانتظار (كهرماني)، وما عداهما نيلي.
Widget desktopStatusPill(BuildContext context, String status) {
  final d = context.desktop;
  late final Color fg;
  late final Color bg;
  late final Color border;
  switch (status.toLowerCase()) {
    case 'checked_in':
    case 'confirmed':
    case 'completed':
      fg = d.pillDoneFg;
      bg = d.pillDoneBg;
      border = d.pillDoneBorder;
      break;
    case 'pending':
      fg = d.pillWaitingFg;
      bg = d.pillWaitingBg;
      border = d.pillWaitingBorder;
      break;
    default:
      fg = d.pillUpcomingFg;
      bg = d.pillUpcomingBg;
      border = d.pillUpcomingBorder;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Text(
      appointmentStatusLabelsAr[status.toLowerCase()] ?? status,
      style: AppType.sans(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    ),
  );
}

class DesktopEmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const DesktopEmptyHint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: d.textMuted),
          const SizedBox(height: 10),
          Text(text, style: AppType.sans(fontSize: 13, color: d.textSecondary)),
        ],
      ),
    );
  }
}

class DesktopErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const DesktopErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: d.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.sans(fontSize: 13.5, color: d.textSecondary),
          ),
          const SizedBox(height: 16),
          DesktopCtaButton(
            icon: Icons.refresh,
            label: 'إعادة المحاولة',
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// زرّ الإجراء الرئيسي بسلّم التمييز.
class DesktopCtaButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// يملأ عرض الحاوية بنصّ متوسّط («فتح الملف الكامل» أسفل لوحة المعاينة).
  final bool expand;

  const DesktopCtaButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.expand = false,
  });

  @override
  State<DesktopCtaButton> createState() => _DesktopCtaButtonState();
}

class _DesktopCtaButtonState extends State<DesktopCtaButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: d.ctaGradient,
              borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusCta),
              boxShadow: d.ctaShadow,
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 16, color: d.onCta),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: AppType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: d.onCta,
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

/// زرّ ثانوي بإطار نيلي خفيف («تعديل»، «تغيير الحالة»).
class DesktopGhostButton extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final double height;

  const DesktopGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 40,
  });

  @override
  State<DesktopGhostButton> createState() => _DesktopGhostButtonState();
}

class _DesktopGhostButtonState extends State<DesktopGhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered && enabled ? d.iconBoxBg : d.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: d.iconBoxBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: enabled ? d.linkFg : d.textMuted),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: AppType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: enabled ? d.linkFg : d.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريحة تصفية بعدّاد («الكل 8»). المختارة ممتلئة بلون الرابط.
class DesktopChip extends StatefulWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const DesktopChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  State<DesktopChip> createState() => _DesktopChipState();
}

class _DesktopChipState extends State<DesktopChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final on = widget.selected;
    final fg = on ? d.onCta : d.navInactiveFg;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? d.linkFg : d.cardBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: on ? d.linkFg : (_hovered ? d.iconBoxBorder : d.iconBtnBorder),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${widget.count}',
                  style: AppType.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg.withValues(alpha: .8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// زرّ مربّع صغير (ترقيم الصفحات، التنقّل بين الأيام). [selected] يملؤه
/// بلون الرابط كرقم الصفحة الحالية في الكانفاس.
class DesktopSquareButton extends StatefulWidget {
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  const DesktopSquareButton({
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    this.selected = false,
    this.onTap,
    this.size = 34,
  });

  @override
  State<DesktopSquareButton> createState() => _DesktopSquareButtonState();
}

class _DesktopSquareButtonState extends State<DesktopSquareButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final enabled = widget.onTap != null;
    final fg = widget.selected
        ? d.onCta
        : (enabled ? d.iconBtnFg : d.textMuted.withValues(alpha: .5));
    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? d.linkFg
                : (_hovered && enabled ? d.iconBtnHover : d.iconBtnBg),
            borderRadius: BorderRadius.circular(10),
            border: widget.selected ? null : Border.all(color: d.iconBtnBorder),
          ),
          child: widget.icon != null
              ? Icon(widget.icon, size: 15, color: fg)
              : Text(
                  widget.label ?? '',
                  style: AppType.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
                ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// ألوان شارة: نصّ وخلفية وإطار.
class DesktopBadgeColors {
  final Color fg;
  final Color bg;
  final Color border;

  const DesktopBadgeColors(this.fg, this.bg, this.border);

  static DesktopBadgeColors done(AppDesktop d) =>
      DesktopBadgeColors(d.pillDoneFg, d.pillDoneBg, d.pillDoneBorder);
  static DesktopBadgeColors waiting(AppDesktop d) =>
      DesktopBadgeColors(d.pillWaitingFg, d.pillWaitingBg, d.pillWaitingBorder);
  static DesktopBadgeColors upcoming(AppDesktop d) =>
      DesktopBadgeColors(d.pillUpcomingFg, d.pillUpcomingBg, d.pillUpcomingBorder);

  /// رمادي محايد («لا فواتير»). مشتقّ من توكنات الجدول لا لون جديد، فيبقى
  /// صحيحاً في الوضعين.
  static DesktopBadgeColors neutral(AppDesktop d) =>
      DesktopBadgeColors(d.textSecondary, d.rowDivider, d.cardBorder);
}

/// شارة كبسولة بنصّ.
class DesktopBadge extends StatelessWidget {
  final String label;
  final DesktopBadgeColors colors;
  final double fontSize;

  const DesktopBadge({
    super.key,
    required this.label,
    required this.colors,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppType.sans(fontSize: fontSize, fontWeight: FontWeight.w700, color: colors.fg),
      ),
    );
  }
}

/// تدرّجات مربّعات الأحرف الأولى للمرضى -- الثلاثة نفسها في الكانفاس، تُختار
/// بمعرّف المريض فيبقى لونه ثابتاً مهما تغيّر ترتيب الجدول أو تصفيته.
const List<LinearGradient> kDesktopAvatarGradients = [
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6366F1), Color(0xFF7C3AED)],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4338CA), Color(0xFF9333EA)],
  ),
  LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0891B2), Color(0xFF4F46E5)],
  ),
];

/// مربّع الأحرف الأولى بتدرّج.
class DesktopInitialsTile extends StatelessWidget {
  final String name;
  final int seed;
  final double size;
  final double radius;
  final double fontSize;

  const DesktopInitialsTile({
    super.key,
    required this.name,
    required this.seed,
    this.size = 38,
    this.radius = 13,
    this.fontSize = 12.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: kDesktopAvatarGradients[seed.abs() % kDesktopAvatarGradients.length],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        desktopInitials(name),
        style: AppType.kufi(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

/// بطاقة بلا عنوان (لوحات المعاينة الجانبية). [glow] يضيف كرتَي الضوء
/// البنفسجية والسماوية خلف المحتوى كما في بطاقة الرأس بالكانفاس.
class DesktopCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;
  final double radius;

  const DesktopCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    this.glow = false,
    this.radius = AppDesktopMetrics.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: d.cardBg,
        gradient: d.cardGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: d.cardBorder),
        boxShadow: glow ? d.panelShadow : d.cardShadow,
      ),
      child: Stack(
        children: [
          if (glow) ...[
            PositionedDirectional(
              top: -60,
              end: -50,
              child: _GlowBlob(
                  color: const Color(0xFFA78BFA).withValues(alpha: .28), size: 190),
            ),
            PositionedDirectional(
              bottom: -70,
              start: -40,
              child: _GlowBlob(
                  color: const Color(0xFF22D3EE).withValues(alpha: .18), size: 170),
            ),
          ],
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// «22 سبتمبر» -- تاريخ قصير بلا يوم أسبوع ولا سنة، للجداول واللوحات.
String desktopShortDate(DateTime date) {
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  return '${date.day} ${months[date.month - 1]}';
}
