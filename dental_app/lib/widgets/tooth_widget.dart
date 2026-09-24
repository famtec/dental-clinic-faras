import 'package:flutter/material.dart';

import '../utils/dental_chart.dart';

/// رسم مبسّط لشكل السن (تاج مقوّس من فوق وجذر مستدق من تحت للفك العلوي،
/// والعكس للفك السفلي) -- يحاكي روح مخطط الأسنان الحقيقي في الموقع (تاج +
/// جذر) عبر Path مرسوم مباشرة بدل SVG ثابت، حتى يتكيّف بسلاسة مع حجم
/// الخلية ولون الحالة.
class ToothShapePainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  final bool isUpper;

  /// شدّة التوهّج (0 = بلا توهّج). يُرسم بمسار السن نفسه مموّهاً خلفه، لا
  /// مستطيلاً أو دائرة -- فيبدو السن نفسه مضيئاً لا خلفيته.
  final double glow;
  final Color? glowColor;

  ToothShapePainter({
    required this.fill,
    required this.stroke,
    required this.isUpper,
    this.glow = 0,
    this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (isUpper) {
      path.moveTo(w * 0.5, 0);
      path.cubicTo(w * 0.05, 0, 0, h * 0.28, w * 0.12, h * 0.55);
      path.cubicTo(w * 0.22, h * 0.85, w * 0.32, h, w * 0.42, h * 0.62);
      path.cubicTo(w * 0.46, h * 0.5, w * 0.54, h * 0.5, w * 0.58, h * 0.62);
      path.cubicTo(w * 0.68, h, w * 0.78, h * 0.85, w * 0.88, h * 0.55);
      path.cubicTo(w, h * 0.28, w * 0.95, 0, w * 0.5, 0);
    } else {
      path.moveTo(w * 0.5, h);
      path.cubicTo(w * 0.05, h, 0, h * 0.72, w * 0.12, h * 0.45);
      path.cubicTo(w * 0.22, h * 0.15, w * 0.32, 0, w * 0.42, h * 0.38);
      path.cubicTo(w * 0.46, h * 0.5, w * 0.54, h * 0.5, w * 0.58, h * 0.38);
      path.cubicTo(w * 0.68, 0, w * 0.78, h * 0.15, w * 0.88, h * 0.45);
      path.cubicTo(w, h * 0.72, w * 0.95, h, w * 0.5, h);
    }
    path.close();
    if (glow > 0) {
      final color = glowColor ?? stroke;
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: (0.85 * glow).clamp(0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 6 * glow),
      );
    }
    canvas.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant ToothShapePainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.isUpper != isUpper ||
        oldDelegate.glow != glow ||
        oldDelegate.glowColor != glowColor;
  }
}

/// خلية سن واحدة قابلة للنقر ضمن المخطط -- تعرض شكل السن ملوّناً حسب حالته
/// الحالية (أو اللون الافتراضي إن لم تُسجَّل له أي حالة)، ورقمه بترميز FDI.
///
/// عند مرور مؤشّر الفأرة (سطح المكتب، 2026-09-24): يتوهّج السن بلون حالته
/// (أو بالنيلي إن لم تكن له حالة) توهّجاً نابضاً ما دام المؤشّر فوقه، ويكبر
/// قليلاً ويتلوّن رقمه -- فيعرف الطبيب أيّ سن سيفتح قبل أن ينقر. على الجوال
/// لا مؤشّر فلا يتغيّر شيء.
class ToothCell extends StatefulWidget {
  final int fdiNumber;
  final String? statusKey;
  final bool isUpper;
  final VoidCallback onTap;

  /// مقاس رسم السن. الافتراضي (22×30) هو مقاس المخطط الكامل القديم؛ عرض
  /// الأرباع يمرّر مقاساً أكبر لأن ثمانية أسنان فقط تتقاسم عرض الشاشة.
  final double shapeWidth;
  final double shapeHeight;
  final double numberFontSize;

  const ToothCell({
    super.key,
    required this.fdiNumber,
    required this.statusKey,
    required this.isUpper,
    required this.onTap,
    this.shapeWidth = 22,
    this.shapeHeight = 30,
    this.numberFontSize = 9.5,
  });

  @override
  State<ToothCell> createState() => _ToothCellState();
}

class _ToothCellState extends State<ToothCell> with SingleTickerProviderStateMixin {
  /// لون التوهّج لسن بلا حالة مسجّلة -- نيلي التمييز نفسه في التطبيق.
  static const Color _neutralGlow = Color(0xFF6366F1);

  // نبض 0..1 ذهاباً وإياباً ما دام المؤشّر فوق السن.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  bool _hovered = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    if (value) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2026-08-30: يحلّ الحالة عبر resolveToothStatus بدل toothStatusByKey
    // مباشرة، حتى يُلوَّن السن أيضاً عندما يحمل حالة "مخصصة" (اسم ولون من
    // اختيار الطبيب) أو قيمة لون قديمة موروثة من نسخة سابقة من الموقع، لا
    // فقط إحدى الحالات الثابتة الثمانية.
    final resolved = resolveToothStatus(widget.statusKey);
    final fill = resolved?.color.withValues(alpha: 0.28) ?? toothDefaultFill;
    final stroke = resolved?.color ?? toothDefaultStroke;
    final accent = resolved?.color ?? _neutralGlow;

    final number = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 150),
      style: TextStyle(
        fontSize: widget.numberFontSize,
        fontWeight: _hovered ? FontWeight.w800 : FontWeight.w700,
        color: _hovered
            ? accent
            : (resolved != null ? stroke : const Color(0xFF94A3B8)),
      ),
      child: Text('${widget.fdiNumber}'),
    );

    final shape = AnimatedScale(
      scale: _hovered ? 1.12 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: SizedBox(
        width: widget.shapeWidth,
        height: widget.shapeHeight,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => CustomPaint(
            painter: ToothShapePainter(
              fill: _hovered ? Color.lerp(fill, accent, 0.18)! : fill,
              stroke: _hovered ? accent : stroke,
              isUpper: widget.isUpper,
              // بين 0.45 و1: لا يخبو كلياً بين النبضتين فيبدو وميضاً لا إطفاءً.
              glow: _hovered ? 0.45 + 0.55 * Curves.easeInOut.transform(_pulse.value) : 0,
              glowColor: accent,
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.isUpper
                ? [shape, const SizedBox(height: 2), number]
                : [number, const SizedBox(height: 2), shape],
          ),
        ),
      ),
    );
  }
}
