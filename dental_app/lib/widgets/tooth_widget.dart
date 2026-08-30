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

  ToothShapePainter({
    required this.fill,
    required this.stroke,
    required this.isUpper,
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
        oldDelegate.isUpper != isUpper;
  }
}

/// خلية سن واحدة قابلة للنقر ضمن المخطط -- تعرض شكل السن ملوّناً حسب حالته
/// الحالية (أو اللون الافتراضي إن لم تُسجَّل له أي حالة)، ورقمه بترميز FDI.
class ToothCell extends StatelessWidget {
  final int fdiNumber;
  final String? statusKey;
  final bool isUpper;
  final VoidCallback onTap;

  const ToothCell({
    super.key,
    required this.fdiNumber,
    required this.statusKey,
    required this.isUpper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final option = toothStatusByKey(statusKey);
    final fill = option?.color.withValues(alpha: 0.28) ?? toothDefaultFill;
    final stroke = option?.color ?? toothDefaultStroke;
    final number = Text(
      '$fdiNumber',
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: option != null ? stroke : const Color(0xFF94A3B8),
      ),
    );
    final shape = SizedBox(
      width: 22,
      height: 30,
      child: CustomPaint(
        painter: ToothShapePainter(fill: fill, stroke: stroke, isUpper: isUpper),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: isUpper
              ? [shape, const SizedBox(height: 2), number]
              : [number, const SizedBox(height: 2), shape],
        ),
      ),
    );
  }
}
