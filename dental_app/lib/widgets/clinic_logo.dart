import 'package:flutter/material.dart';

/// شعار «عيادتي الرقمية» -- نفس شعار الموقع (frontend_web/شعار موقع أسنان
/// رقمي/svg/badge-*.svg) مرسوماً متّجهياً (2026-09-24).
///
/// سنّ بنفسجي بمربّعات «بكسل» شفّافة داخل إطار مستدير بخطوط دارة خفيفة.
/// مرسوم بـ CustomPainter من مسارات الـ SVG نفسها حرفياً (لوحة 160×160) لا
/// صورة نقطية: يبقى حادّاً من 16px في شريط العنوان إلى 120px في شاشة الدخول،
/// ويتبدّل بين نسختَي الموقع الفاتحة والداكنة بلا ملفّين.
class ClinicLogo extends StatelessWidget {
  final double size;

  /// null = يتبع وضع الثيم الحالي.
  final bool? dark;

  /// true = السنّ وحده بلا إطار (فوق خلفية ملوّنة أصلاً).
  final bool markOnly;

  const ClinicLogo({super.key, this.size = 40, this.dark, this.markOnly = false});

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ClinicLogoPainter(dark: isDark, markOnly: markOnly)),
    );
  }
}

class _ClinicLogoPainter extends CustomPainter {
  final bool dark;
  final bool markOnly;

  _ClinicLogoPainter({required this.dark, required this.markOnly});

  // ── ألوان ملفّي badge-light.svg وbadge-dark.svg حرفياً ──
  static const _lightTooth = Color(0xFF5A4BD4);
  static const _lightPixel = Color(0xFFEFEDFB);
  static const _lightBorder = Color(0xFFCDC7F0);
  static const _darkTooth = Color(0xFF8B7BF7);
  static const _darkPixel = Color(0xFF14102E);
  static const _darkBorder = Color(0xFF453A86);

  static Path _toothPath() => Path()
    ..moveTo(80, 38)
    ..cubicTo(64, 38, 56, 32, 48, 36)
    ..cubicTo(36, 42, 36, 62, 42, 78)
    ..cubicTo(47, 92, 48, 106, 51, 122)
    ..cubicTo(53, 134, 57, 142, 63, 142)
    ..cubicTo(70, 142, 72, 130, 74, 118)
    ..cubicTo(75, 110, 77, 106, 80, 106)
    ..cubicTo(83, 106, 85, 110, 86, 118)
    ..cubicTo(88, 130, 90, 142, 97, 142)
    ..cubicTo(103, 142, 107, 134, 109, 122)
    ..cubicTo(112, 106, 113, 92, 118, 78)
    ..cubicTo(124, 62, 124, 42, 112, 36)
    ..cubicTo(104, 32, 96, 38, 80, 38)
    ..close();

  static const List<Offset> _pixels = [
    Offset(40, 52), Offset(52, 52), Offset(64, 52), Offset(76, 64),
    Offset(88, 64), Offset(100, 76), Offset(52, 76), Offset(64, 88),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // السنّ وحده: لوحة مقصوصة حول السنّ (x 36..124، y 32..142) لتملأ المساحة.
    if (markOnly) {
      final s = size.height / 118;
      canvas.translate((size.width - 88 * s) / 2, 0);
      canvas.scale(s);
      canvas.translate(-36, -30);
    } else {
      canvas.scale(size.width / 160, size.height / 160);
      _paintBadge(canvas);
    }

    final tooth = _toothPath();
    canvas.drawPath(tooth, Paint()..color = dark ? _darkTooth : _lightTooth);

    canvas.save();
    canvas.clipPath(tooth);
    final pixel = Paint()
      ..color = (dark ? _darkPixel : _lightPixel).withValues(alpha: dark ? .5 : .45);
    for (final p in _pixels) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(p.dx, p.dy, 7, 7), const Radius.circular(1.5)),
        pixel,
      );
    }
    _paintSignature(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _paintBadge(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4, 152, 152), const Radius.circular(36));
    final fill = Paint();
    if (dark) {
      fill.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2E2470), Color(0xFF120E2C)],
      ).createShader(const Rect.fromLTWH(0, 0, 160, 160));
    } else {
      fill.color = Colors.white;
    }
    canvas.drawRRect(rect, fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dark ? _darkBorder : _lightBorder,
    );

    // خطوط الدارة على الحواف.
    final traces = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = (dark ? _darkTooth : _lightTooth).withValues(alpha: dark ? .32 : .3);
    final path = Path()
      ..moveTo(4, 60)
      ..lineTo(26, 60)
      ..lineTo(26, 96)
      ..lineTo(4, 96)
      ..moveTo(156, 60)
      ..lineTo(134, 60)
      ..lineTo(134, 96)
      ..lineTo(156, 96)
      ..moveTo(60, 4)
      ..lineTo(60, 22)
      ..moveTo(100, 4)
      ..lineTo(100, 22)
      ..moveTo(60, 156)
      ..lineTo(60, 138)
      ..moveTo(100, 156)
      ..lineTo(100, 138);
    canvas.drawPath(path, traces);
  }

  /// توقيع «FARES» الخافت أسفل السنّ -- كما في الملف الأصلي (شفافية 12٪).
  void _paintSignature(Canvas canvas) {
    canvas.save();
    canvas.translate(50, 106);
    canvas.scale(0.45);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / 0.45
      ..strokeCap = StrokeCap.round
      ..color = (dark ? _darkPixel : _lightPixel).withValues(alpha: .12);
    final p = Path()
      // F
      ..moveTo(0, 0)
      ..lineTo(8, 0)
      ..moveTo(0, 0)
      ..lineTo(0, 16)
      ..moveTo(0, 8)
      ..lineTo(6, 8)
      // A
      ..moveTo(14, 16)
      ..lineTo(19, 0)
      ..lineTo(24, 16)
      ..moveTo(16, 10)
      ..lineTo(22, 10)
      // R
      ..moveTo(30, 16)
      ..lineTo(30, 0)
      ..lineTo(37, 0)
      ..lineTo(39, 4)
      ..lineTo(37, 8)
      ..lineTo(30, 8)
      ..moveTo(36, 8)
      ..lineTo(40, 16)
      // E
      ..moveTo(54, 0)
      ..lineTo(46, 0)
      ..lineTo(46, 16)
      ..lineTo(54, 16)
      ..moveTo(46, 8)
      ..lineTo(52, 8)
      // S
      ..moveTo(69, 2)
      ..cubicTo(66, -1, 61, 0, 61, 4)
      ..cubicTo(61, 8, 69, 8, 69, 12)
      ..cubicTo(69, 16, 64, 17, 61, 14);
    canvas.drawPath(p, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClinicLogoPainter old) => old.dark != dark || old.markOnly != markOnly;
}
