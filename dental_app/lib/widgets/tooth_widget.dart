import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/dental_chart.dart';

/// رسم السن التشريحي (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// حلّ محلّ الشكل العامّ الواحد (نفس «الفاصولياء» لكل الأسنان، وتاجها مقلوب
/// نحو الجذر). الآن لكل نوع تشريحه من رقم FDI -- كما في مخطط الموقع
/// (TOOTH_SHAPES في patient_record.html) ولكن بتفصيل أكثر:
///
///  * **قاطع** (1-2): تاج مستطيل يتّسع نحو الحافة القاطعة، جذر مخروطي واحد؛
///    الجانبي والقواطع السفلية أنحف.
///  * **ناب** (3): تاج بذروة حادّة وأطول جذر في الفم.
///  * **ضاحك** (4-5): تاج منتفخ بحدبة دهليزية؛ الضاحك الأول العلوي بجذر
///    مشقوق عند الذروة (دهليزي وحنكي).
///  * **رحى** (6-8): تاج عريض بحدبتين وأخدود بينهما، جذران متباعدان،
///    والجذر الحنكي الثالث ظاهر خلفهما في أرحاء الفك العلوي؛ ضرس العقل
///    أقصر جذوراً.
///
/// الاتجاه تشريحي: جذور العلوي إلى أعلى وتاجه نحو مستوى الإطباق، والسفلي
/// معكوس -- التاجان يتقابلان كما في الفم وكما في الموقع.
///
/// المينا بتدرّج (عنق مائل للعاجي، جسم أبيض، حافة شفّافة قليلاً) مع لمعة
/// وتظليل جانبي يعطيان حجماً. لون الحالة يصبغ التاج (والجذر قليلاً)، وثلاث
/// حالات تُرسم بشكلها لا بلونها وحده: **مقلوع** إطار متقطّع بلا حشوة،
/// **لبية** قناة الجذر وحجرة اللبّ ملوّنة، **زراعة** برغي تيتانيوم مكان الجذر.
///
/// الأشكال مرسومة على لوحة ثابتة 44×78 (نفس viewBox الموقع) وتُحجَّم
/// بالتناسب، ومخزّنة مرّة لكل نوع وفكّ -- الرسم يتكرّر 60 مرة في الثانية أثناء
/// وميض المرور.
class ToothShapePainter extends CustomPainter {
  /// رقم السن بترميز FDI -- منه النوع (آحاده) والفكّ (عشراته).
  final int fdi;

  /// لون الحالة المسجّلة. null = سن سليم بلون المينا.
  final Color? statusColor;

  /// مفتاح الحالة الثابتة إن كانت إحداها ([resolveToothStatusKey]) --
  /// لرسم المقلوع واللبية والزراعة بشكلها.
  final String? statusKey;

  /// لون الإطار عند المرور، يطغى على لون الحالة.
  final Color? outline;

  /// شدّة التوهّج (0 = بلا توهّج). يُرسم بظلّ السن نفسه مموّهاً خلفه، لا
  /// مستطيلاً أو دائرة -- فيبدو السن نفسه مضيئاً لا خلفيته.
  final double glow;
  final Color? glowColor;

  ToothShapePainter({
    required this.fdi,
    this.statusColor,
    this.statusKey,
    this.outline,
    this.glow = 0,
    this.glowColor,
  });

  static const double _boxW = 44;
  static const double _boxH = 78;

  static const Color _ivory = Color(0xFFFFFBF3);
  static const Color _enamelStroke = Color(0xFFC9A673);
  static const Color _rootStroke = Color(0xFFD3B68A);
  static const Color _ghost = Color(0xFF94A3B8);

  bool get _isUpper => fdi ~/ 10 == 1 || fdi ~/ 10 == 2;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _ToothGeometry.of((fdi % 10).clamp(1, 8), _isUpper);
    final scale = math.min(size.width / _boxW, size.height / _boxH);
    // بكسل شاشة واحد بوحدات اللوحة: الخطوط تُعطى بالبكسل فتبقى رفيعة حادّة
    // في خلية المخطط الصغيرة ولا تتضخّم في لوحة السن الكبيرة.
    final px = 1 / scale;

    canvas.save();
    canvas.translate((size.width - _boxW * scale) / 2, (size.height - _boxH * scale) / 2);
    canvas.scale(scale);
    if (!_isUpper) {
      canvas.translate(0, _boxH);
      canvas.scale(1, -1);
    }

    if (glow > 0) {
      canvas.drawPath(
        g.silhouette,
        Paint()
          ..color = (glowColor ?? outline ?? _enamelStroke).withValues(alpha: (0.85 * glow).clamp(0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, (4 + 6 * glow) * px),
      );
    }

    if (statusKey == 'extracted') {
      _paintMissing(canvas, g, px);
    } else {
      if (statusKey == 'implant') {
        _paintImplant(canvas, px);
      } else {
        if (g.backRoot != null) _paintRoot(canvas, g.backRoot!, px, back: true);
        _paintRoot(canvas, g.roots, px);
      }
      _paintCrown(canvas, g, px, scale);
      if (statusKey == 'endo') _paintEndo(canvas, g, px);
    }
    canvas.restore();
  }

  // ── الجذور ──────────────────────────────────────────────────────────────

  void _paintRoot(Canvas canvas, Path path, double px, {bool back = false}) {
    var cervical = back ? const Color(0xFFE2CCA6) : const Color(0xFFF4E8D2);
    var apex = back ? const Color(0xFFD0B38A) : const Color(0xFFE4CCA5);
    final c = statusColor;
    if (c != null) {
      cervical = Color.lerp(cervical, c, .14)!;
      apex = Color.lerp(apex, c, .14)!;
    }
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [cervical, apex],
        ).createShader(b),
    );
    canvas.drawPath(path, Paint()..shader = _sideShade(.10, .14).createShader(b));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = c == null ? _rootStroke : Color.lerp(_rootStroke, c, .3)!,
    );
  }

  // ── التاج ───────────────────────────────────────────────────────────────

  void _paintCrown(Canvas canvas, _ToothGeometry g, double px, double scale) {
    final c = statusColor;
    final b = g.crown.getBounds();
    // اللبية حالة جذر: يُصبغ التاج خفيفاً فقط حتى تبقى القناة الملوّنة هي
    // ما تقع عليه العين.
    final tint = statusKey == 'endo' ? .3 : .68;
    final enamel = c == null
        ? const [Color(0xFFF2E3C6), Color(0xFFFFFCF5), Color(0xFFF3EFE8)]
        : [
            Color.lerp(_ivory, c, math.min(1, tint + .22))!,
            Color.lerp(_ivory, c, tint)!,
            Color.lerp(_ivory, c, tint - .1)!,
          ];
    canvas.drawPath(
      g.crown,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: enamel,
          stops: const [0, .45, 1],
        ).createShader(b),
    );
    canvas.drawPath(g.crown, Paint()..shader = _sideShade(.08, .13).createShader(b));

    canvas.save();
    canvas.clipPath(g.crown);
    // لمعة المينا: شريط ضوء مموّه على الوجه الدهليزي.
    canvas.drawOval(
      Rect.fromLTWH(b.left + b.width * .17, b.top + b.height * .2, b.width * .2, b.height * .52),
      Paint()
        ..color = Colors.white.withValues(alpha: c == null ? .8 : .45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.6),
    );
    canvas.restore();

    final stroke = outline ?? (c == null ? _enamelStroke : Color.lerp(c, Colors.black, .25)!);

    // الأخاديد والحواف: تفصيل يتلاشى في الخلايا الصغيرة حتى لا يصير ضجيجاً.
    final detail = ((scale - .45) / .9).clamp(0.0, 1.0);
    if (detail > 0) {
      canvas.drawPath(
        g.grooves,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = .9 * px
          ..color = stroke.withValues(alpha: .4 * detail),
      );
    }

    canvas.drawPath(
      g.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (.9 + .5 * scale) * px
        ..color = stroke,
    );
  }

  // ── الحالات المرسومة بشكلها ──────────────────────────────────────────────

  void _paintEndo(Canvas canvas, _ToothGeometry g, double px) {
    final c = statusColor ?? const Color(0xFFA855F7);
    canvas.save();
    canvas.clipPath(g.crown);
    canvas.drawPath(g.pulp, Paint()..color = c.withValues(alpha: .8));
    canvas.restore();
    canvas.drawPath(
      g.canals,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, 1.1 * px)
        ..color = c.withValues(alpha: .9),
    );
  }

  void _paintImplant(Canvas canvas, double px) {
    final body = Path()
      ..moveTo(16.2, 46)
      ..lineTo(27.8, 46)
      ..lineTo(26.6, 12)
      ..quadraticBezierTo(26, 5.4, 22, 4.4)
      ..quadraticBezierTo(18, 5.4, 17.4, 12)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF94A3B8), Color(0xFFE2E8F0), Color(0xFFCBD5E1), Color(0xFF64748B)],
          stops: [0, .35, .6, 1],
        ).createShader(body.getBounds()),
    );
    final thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.1, .9 * px)
      ..color = const Color(0xFF475569).withValues(alpha: .8);
    for (var y = 40.0; y > 11; y -= 4) {
      final t = (46 - y) / 34;
      canvas.drawLine(
        Offset(16.2 + 1.2 * t - 1.4, y + 1.1),
        Offset(27.8 - 1.2 * t + 1.4, y - 1.1),
        thread,
      );
    }
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = const Color(0xFF475569),
    );
  }

  void _paintMissing(Canvas canvas, _ToothGeometry g, double px) {
    canvas.drawPath(g.silhouette, Paint()..color = _ghost.withValues(alpha: .08));
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2 * px
      ..color = (outline ?? _ghost).withValues(alpha: .9);
    canvas.drawPath(_dashed(g.silhouette, 3.2 * px, 2.6 * px), dash);
  }

  /// تظليل الحافّتين: يعطي التاج والجذر استدارة بدل سطح مسطّح.
  static LinearGradient _sideShade(double start, double end) => LinearGradient(
        colors: [
          Colors.black.withValues(alpha: start),
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: end),
        ],
        stops: const [0, .3, .62, 1],
      );

  static Path _dashed(Path source, double dash, double gap) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        out.addPath(metric.extractPath(d, math.min(d + dash, metric.length)), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant ToothShapePainter oldDelegate) {
    return oldDelegate.fdi != fdi ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.statusKey != statusKey ||
        oldDelegate.outline != outline ||
        oldDelegate.glow != glow ||
        oldDelegate.glowColor != glowColor;
  }
}

/// مسارات سن واحد على لوحة 44×78 باتجاه الفك العلوي (الجذور أعلى، الحافة
/// القاطعة/الإطباقية عند y≈76، الملتقى المينائي الملاطي عند y≈43).
class _ToothGeometry {
  final Path crown;
  final Path roots;

  /// الجذر الحنكي خلف الجذرين الدهليزيين (أرحاء الفك العلوي وحدها).
  final Path? backRoot;
  final Path canals;
  final Path pulp;
  final Path grooves;
  final Path silhouette;

  _ToothGeometry._({
    required this.crown,
    required this.roots,
    required this.backRoot,
    required this.canals,
    required this.pulp,
    required this.grooves,
    required this.silhouette,
  });

  static final Map<int, _ToothGeometry> _cache = {};

  static _ToothGeometry of(int order, bool upper) =>
      _cache.putIfAbsent(order * 2 + (upper ? 1 : 0), () => _build(order, upper));

  // عرض كل سن نسبةً إلى شكله الأساسي: الجانبي أنحف من المركزي، والقواطع
  // السفلية أنحف الأسنان، والأرحاء تصغر قليلاً نحو الخلف.
  static const Map<int, double> _upperWidth = {
    1: 1.0, 2: .86, 3: 1.0, 4: 1.0, 5: .96, 6: 1.0, 7: .95, 8: .88,
  };
  static const Map<int, double> _lowerWidth = {
    1: .8, 2: .84, 3: .95, 4: .96, 5: .98, 6: 1.0, 7: .97, 8: .92,
  };

  static _ToothGeometry _build(int order, bool upper) {
    final Path crown;
    Path roots;
    Path? backRoot;
    Path canals;
    final Path pulp;
    final Path grooves;

    if (order <= 2) {
      crown = Path()
        ..moveTo(13.2, 43)
        ..quadraticBezierTo(22, 37.4, 30.8, 43)
        ..cubicTo(32, 51, 33.8, 61, 33.5, 70)
        ..quadraticBezierTo(33.3, 75.6, 28.6, 75.8)
        ..lineTo(15.4, 75.8)
        ..quadraticBezierTo(10.7, 75.6, 10.5, 70)
        ..cubicTo(10.2, 61, 12, 51, 13.2, 43)
        ..close();
      roots = Path()
        ..moveTo(14.4, 45)
        ..cubicTo(13.8, 31, 17.2, 11, 20.6, 4)
        ..quadraticBezierTo(22, 1.6, 23.4, 4)
        ..cubicTo(26.8, 11, 30.2, 31, 29.6, 45)
        ..close();
      canals = Path()
        ..moveTo(22, 48)
        ..quadraticBezierTo(22.3, 26, 22, 6);
      pulp = Path()
        ..moveTo(19.4, 45.5)
        ..quadraticBezierTo(22, 43.6, 24.6, 45.5)
        ..lineTo(23.4, 56)
        ..quadraticBezierTo(22, 58, 20.6, 56)
        ..close();
      grooves = Path()
        ..moveTo(18.2, 75)
        ..quadraticBezierTo(18.4, 70.5, 19, 66.5)
        ..moveTo(25.8, 75)
        ..quadraticBezierTo(25.6, 70.5, 25, 66.5);
    } else if (order == 3) {
      crown = Path()
        ..moveTo(12.6, 42)
        ..quadraticBezierTo(22, 35.6, 31.4, 42)
        ..cubicTo(33.6, 49, 34.8, 57, 33, 63.5)
        ..cubicTo(31.2, 68.5, 25.8, 73.4, 23.3, 76.2)
        ..quadraticBezierTo(22, 77.6, 20.7, 76.2)
        ..cubicTo(18.2, 73.4, 12.8, 68.5, 11, 63.5)
        ..cubicTo(9.2, 57, 10.4, 49, 12.6, 42)
        ..close();
      roots = Path()
        ..moveTo(13.6, 44)
        ..cubicTo(13, 28, 16.6, 8, 20.4, 2)
        ..quadraticBezierTo(22, 0, 23.6, 2)
        ..cubicTo(27.4, 8, 31, 28, 30.4, 44)
        ..close();
      canals = Path()
        ..moveTo(22, 47)
        ..quadraticBezierTo(22.3, 24, 22, 4.5);
      pulp = Path()
        ..moveTo(19, 44.5)
        ..quadraticBezierTo(22, 42.4, 25, 44.5)
        ..lineTo(23.3, 58)
        ..quadraticBezierTo(22, 60.5, 20.7, 58)
        ..close();
      grooves = Path()
        ..moveTo(22, 74.5)
        ..quadraticBezierTo(22.5, 66, 22, 57);
    } else if (order <= 5) {
      crown = Path()
        ..moveTo(12.4, 44)
        ..quadraticBezierTo(22, 38.6, 31.6, 44)
        ..cubicTo(34.4, 51, 35.4, 59, 33.8, 65.5)
        ..cubicTo(31.6, 70.5, 25.6, 74.2, 22, 76.3)
        ..cubicTo(18.4, 74.2, 12.4, 70.5, 10.2, 65.5)
        ..cubicTo(8.6, 59, 9.6, 51, 12.4, 44)
        ..close();
      if (upper && order == 4) {
        roots = Path()
          ..moveTo(13.4, 46)
          ..cubicTo(13, 32, 14.6, 14, 17, 5)
          ..quadraticBezierTo(18.4, 2.4, 19.8, 5)
          ..cubicTo(20.6, 10, 21, 16, 22, 21)
          ..cubicTo(23, 16, 23.4, 10, 24.2, 5)
          ..quadraticBezierTo(25.6, 2.4, 27, 5)
          ..cubicTo(29.4, 14, 31, 32, 30.6, 46)
          ..close();
        canals = Path()
          ..moveTo(22, 48)
          ..quadraticBezierTo(21.2, 30, 18.4, 7.5)
          ..moveTo(22, 48)
          ..quadraticBezierTo(22.8, 30, 25.6, 7.5);
      } else {
        roots = Path()
          ..moveTo(13.4, 46)
          ..cubicTo(13, 31, 16.6, 10, 20.4, 3.4)
          ..quadraticBezierTo(22, 1, 23.6, 3.4)
          ..cubicTo(27.4, 10, 31, 31, 30.6, 46)
          ..close();
        canals = Path()
          ..moveTo(22, 48)
          ..quadraticBezierTo(22.3, 26, 22, 6);
      }
      pulp = Path()
        ..moveTo(17.4, 46.5)
        ..quadraticBezierTo(22, 43.6, 26.6, 46.5)
        ..lineTo(25, 55.5)
        ..quadraticBezierTo(22, 58, 19, 55.5)
        ..close();
      grooves = Path()
        ..moveTo(22, 75)
        ..quadraticBezierTo(22.4, 69, 22, 62.5);
    } else {
      crown = Path()
        ..moveTo(7, 44.5)
        ..cubicTo(14, 40.5, 30, 40.5, 37, 44.5)
        ..cubicTo(40.2, 50.5, 41.6, 58, 40.2, 65)
        ..cubicTo(39.4, 71, 35.4, 75.8, 31, 75.8)
        ..cubicTo(27, 75.8, 24.6, 72.4, 22, 71.8)
        ..cubicTo(19.4, 72.4, 17, 75.8, 13, 75.8)
        ..cubicTo(8.6, 75.8, 4.6, 71, 3.8, 65)
        ..cubicTo(2.4, 58, 3.8, 50.5, 7, 44.5)
        ..close();
      roots = Path()
        ..moveTo(7.8, 46)
        ..cubicTo(5.4, 32, 5.8, 15, 9.4, 5.6)
        ..quadraticBezierTo(11.4, 2.6, 13.4, 5.6)
        ..cubicTo(15.2, 15, 16.4, 26, 19.4, 33.4)
        ..quadraticBezierTo(22, 37.6, 24.6, 33.4)
        ..cubicTo(27.6, 26, 28.8, 15, 30.6, 5.6)
        ..quadraticBezierTo(32.6, 2.6, 34.6, 5.6)
        ..cubicTo(38.2, 15, 38.6, 32, 36.2, 46)
        ..close();
      if (upper) {
        backRoot = Path()
          ..moveTo(15.6, 42)
          ..cubicTo(15.2, 28, 18.2, 12, 20.8, 4.6)
          ..quadraticBezierTo(22.2, 2.2, 23.6, 4.6)
          ..cubicTo(26.2, 12, 28.8, 28, 28.4, 42)
          ..close();
      }
      canals = Path()
        ..moveTo(12.8, 48)
        ..quadraticBezierTo(11.6, 28, 11.4, 7.5)
        ..moveTo(31.2, 48)
        ..quadraticBezierTo(32.4, 28, 32.6, 7.5);
      pulp = Path()
        ..moveTo(11.5, 47.5)
        ..cubicTo(12, 50.5, 13, 54, 14.6, 55.6)
        ..quadraticBezierTo(22, 57.8, 29.4, 55.6)
        ..cubicTo(31, 54, 32, 50.5, 32.5, 47.5)
        ..quadraticBezierTo(22, 44.6, 11.5, 47.5)
        ..close();
      grooves = Path()
        ..moveTo(22, 71.8)
        ..quadraticBezierTo(21.5, 66, 22.2, 60);
    }

    // الأرحاء الخلفية أقصر جذوراً، وضرس العقل أقصرها.
    final rootLength = order == 8 ? .8 : (order == 7 ? .94 : 1.0);
    if (rootLength != 1.0) {
      final m = _scaleY(rootLength, 44);
      roots = roots.transform(m);
      backRoot = backRoot?.transform(m);
      canals = canals.transform(m);
    }

    final w = _scaleX((upper ? _upperWidth : _lowerWidth)[order]!, 22);
    final c = crown.transform(w);
    final r = roots.transform(w);
    final br = backRoot?.transform(w);
    var silhouette = Path.combine(PathOperation.union, c, r);
    if (br != null) silhouette = Path.combine(PathOperation.union, silhouette, br);

    return _ToothGeometry._(
      crown: c,
      roots: r,
      backRoot: br,
      canals: canals.transform(w),
      pulp: pulp.transform(w),
      grooves: grooves.transform(w),
      silhouette: silhouette,
    );
  }

  static Float64List _scaleX(double k, double cx) =>
      Float64List.fromList([k, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, cx - cx * k, 0, 0, 1]);

  static Float64List _scaleY(double k, double cy) =>
      Float64List.fromList([1, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, cy - cy * k, 0, 1]);
}

/// خلية سن واحدة قابلة للنقر ضمن المخطط -- تعرض شكل السن ملوّناً حسب حالته
/// الحالية (أو اللون الافتراضي إن لم تُسجَّل له أي حالة)، ورقمه بترميز FDI.
///
/// عند مرور مؤشّر الفأرة (سطح المكتب، 2026-09-24): يتوهّج السن بلون حالته
/// (أو بالنيلي إن لم تكن له حالة) توهّجاً نابضاً ما دام المؤشّر فوقه، ويكبر
/// قليلاً ويتلوّن رقمه -- فيعرف الطبيب أيّ سن سيفتح قبل أن ينقر. على الجوال
/// (2026-09-25) نفس الوميض ما دام الإصبع على السن: ردّ فعل فوري للّمس بدل
/// تموّج InkWell الذي تخفيه خلفية البطاقة.
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

  /// محدَّد في وضع «تحديد عدة أسنان» -- إطار نيلي ثابت وعلامة صح.
  final bool selected;

  const ToothCell({
    super.key,
    required this.fdiNumber,
    required this.statusKey,
    required this.isUpper,
    required this.onTap,
    this.shapeWidth = 22,
    this.shapeHeight = 30,
    this.numberFontSize = 9.5,
    this.selected = false,
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
  bool _pressed = false;

  /// المرور بالفأرة أو اللمس -- الحالتان بنفس المظهر.
  bool get _active => _hovered || _pressed;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _update({bool? hovered, bool? pressed}) {
    final wasActive = _active;
    setState(() {
      _hovered = hovered ?? _hovered;
      _pressed = pressed ?? _pressed;
    });
    if (_active == wasActive) return;
    if (_active) {
      // يبدأ من ذروة الوميض: اللمسة قصيرة، والنبض من الصفر لا يُرى قبل الرفع.
      _pulse.value = 1;
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
    final accent = resolved?.color ?? _neutralGlow;

    final number = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 150),
      style: TextStyle(
        fontSize: widget.numberFontSize,
        fontWeight: _active ? FontWeight.w800 : FontWeight.w700,
        color: _active
            ? accent
            : (resolved?.color ?? const Color(0xFF94A3B8)),
      ),
      child: Text('${widget.fdiNumber}'),
    );

    final selected = widget.selected;
    final shape = AnimatedScale(
      scale: _active ? 1.12 : (selected ? 1.06 : 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: SizedBox(
        width: widget.shapeWidth,
        height: widget.shapeHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: ToothShapePainter(
                    fdi: widget.fdiNumber,
                    statusColor: resolved?.color,
                    statusKey: resolveToothStatusKey(widget.statusKey),
                    outline: _active ? accent : (selected ? _neutralGlow : null),
                    // بين 0.45 و1: لا يخبو كلياً بين النبضتين فيبدو وميضاً لا إطفاءً.
                    glow: _active
                        ? 0.45 + 0.55 * Curves.easeInOut.transform(_pulse.value)
                        : (selected ? 0.5 : 0),
                    glowColor: _active ? accent : _neutralGlow,
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: _neutralGlow,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _update(hovered: true),
      onExit: (_) => _update(hovered: false),
      child: InkWell(
        onTap: () {
          _update(pressed: false);
          widget.onTap();
        },
        onTapDown: (_) => _update(pressed: true),
        onTapCancel: () => _update(pressed: false),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
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
