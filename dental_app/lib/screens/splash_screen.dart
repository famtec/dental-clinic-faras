import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// شاشة تحميل افتتاحية -- 2026-08-31: تُعرض في main.dart ريثما يتحقق
/// التطبيق من وجود جلسة محفوظة قبل الانتقال لصفحة الرئيسية أو تسجيل
/// الدخول (كانت هذه اللحظة تُعرض سابقاً بمؤشر تحميل رمادي افتراضي بلا أي
/// هوية بصرية). تجمع بين عنصرين من هوية الموقع بالحرف:
///  1. حلقة التحميل الدوّارة (track/ring/core بالضبط -- نفس البنية والألوان
///     والتوقيت في frontend_web/clinic-loader.js: conic-gradient تدور
///     2.1s linear، وقلب أبيض "يتنفّس" 2.6s).
///  2. خلفية زجاجية بيضاء (frosted glass) بتوهّج إندگو/بنفسجي بطيء وناعم
///     خلفها -- نفس أسلوب `.clinic-overlay` (خلفية بيضاء شبه شفافة +
///     backdrop-blur) لكن ممتدة على كامل الشاشة مع توهّج متحرّك بدل الثبات.
/// الشعار هو نفس الشارة المستخدمة في رأسَي شاشتَي تسجيل الدخول/التفعيل
/// (login_screen.dart/register_screen.dart) حتى تبقى الهوية موحّدة عبر
/// الشاشات الثلاث.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _glowA =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 7000))..repeat(reverse: true);
  late final AnimationController _glowB =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 8500))..repeat(reverse: true);
  late final AnimationController _glowC =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 6400))..repeat(reverse: true);
  late final AnimationController _logo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2100))..repeat();
  late final AnimationController _core =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  late final AnimationController _subText =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  late final AnimationController _dot1 =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  late final AnimationController _dot2 =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _dot3 =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  late final Animation<double> _glowACurve = CurvedAnimation(parent: _glowA, curve: Curves.easeInOut);
  late final Animation<double> _glowBCurve = CurvedAnimation(parent: _glowB, curve: Curves.easeInOut);
  late final Animation<double> _glowCCurve = CurvedAnimation(parent: _glowC, curve: Curves.easeInOut);
  late final Animation<double> _logoCurve = CurvedAnimation(parent: _logo, curve: Curves.easeInOut);
  late final Animation<double> _coreCurve = CurvedAnimation(parent: _core, curve: Curves.easeInOut);
  late final Animation<double> _subTextCurve = CurvedAnimation(parent: _subText, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    // نفس تأخير .16s/.32s بين النقاط الثلاث في clinicDotBounce بالموقع.
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _dot2.repeat();
    });
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _dot3.repeat();
    });
  }

  @override
  void dispose() {
    for (final controller in [_glowA, _glowB, _glowC, _logo, _ring, _core, _subText, _dot1, _dot2, _dot3]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _buildGlowLayer()),
          // طبقة زجاجية بيضاء شفّافة فوق التوهّج -- نفس أسلوب
          // rgba(255,255,255,.72)+backdrop-blur(6px) في .clinic-overlay
          // بالموقع، بقيمة تمويه أعلى قليلاً لأنها تغطي الشاشة كاملة هنا.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 28),
                  const Text(
                    'مرحبًا بك في عيادتي الرقمية',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.slate900),
                  ),
                  const SizedBox(height: 8),
                  _buildSubText(),
                  const SizedBox(height: 40),
                  _buildLoaderRing(),
                  const SizedBox(height: 14),
                  _buildDots(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowLayer() {
    return Stack(
      children: [
        _glowBlob(
          curve: _glowACurve,
          size: 260,
          color: AppColors.indigo600,
          top: 90,
          right: -60,
          drift: const Offset(14, -18),
        ),
        _glowBlob(
          curve: _glowBCurve,
          size: 280,
          color: AppColors.violet600,
          top: 340,
          left: -70,
          drift: const Offset(-16, 16),
        ),
        _glowBlob(
          curve: _glowCCurve,
          size: 220,
          color: AppColors.indigo500,
          bottom: 60,
          right: 40,
          drift: const Offset(10, 12),
        ),
      ],
    );
  }

  /// فقاعة توهّج زجاجية بطيئة ناعمة -- نفس أسلوب دوائر AuthPageBackground
  /// الزخرفية (Radial Gradient متلاشية بدل بلور حقيقي)، لكن متحرّكة هنا
  /// (تكبّر/تتلاشى وتنجرف قليلاً) بدل ثابتة، مطابقة لِـ glowDriftA/B/C في
  /// مرجع التصميم.
  Widget _glowBlob({
    required Animation<double> curve,
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? left,
    double? right,
    required Offset drift,
  }) {
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value;
        return Positioned(
          top: top == null ? null : top + drift.dy * t,
          bottom: bottom == null ? null : bottom - drift.dy * t,
          left: left == null ? null : left + drift.dx * t,
          right: right == null ? null : right - drift.dx * t,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.35 + 0.35 * t,
              child: Transform.scale(
                scale: 1 + 0.1 * t,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _logoCurve,
      builder: (context, child) {
        final t = _logoCurve.value;
        return Transform.scale(
          scale: 1 + 0.045 * t,
          child: Container(
            width: 104,
            height: 104,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: AppColors.authCardHeaderGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet600.withValues(alpha: 0.28 + 0.12 * t),
                  blurRadius: 40 + 14 * t,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: const Icon(Icons.medical_services_rounded, size: 50, color: Colors.white),
    );
  }

  Widget _buildSubText() {
    return AnimatedBuilder(
      animation: _subTextCurve,
      builder: (context, child) => Opacity(
        opacity: 1 - 0.25 * _subTextCurve.value,
        child: child,
      ),
      child: const Text(
        'رجاء الانتظار...',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: AppColors.slate500),
      ),
    );
  }

  Widget _buildLoaderRing() {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // المسار الثابت الفاتح -- نفس .clinic-loader-track (حلقة 6px
          // إندگو-50) بالموقع بالحرف.
          const SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 6,
              valueColor: AlwaysStoppedAnimation(AppColors.indigo50),
            ),
          ),
          // الحلقة المتدرّجة الدوّارة -- نفس conic-gradient(from 0deg,
          // #4f46e5,#7c3aed 55%,transparent 78%) في clinic-loader.js
          // بالموقع، بدوران 2.1s خطي متكرر إلى ما لا نهاية، مموَّهة على حلقة
          // CircularProgressIndicator حقيقية بدل قناع CSS نصف قطري.
          RotationTransition(
            turns: _ring,
            child: ShaderMask(
              shaderCallback: (rect) => const SweepGradient(
                colors: [
                  AppColors.indigo600,
                  AppColors.violet600,
                  Colors.transparent,
                  Colors.transparent,
                  AppColors.indigo600,
                ],
                stops: [0.0, 0.55, 0.78, 0.999, 1.0],
              ).createShader(rect),
              child: const SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 6,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
          // القلب الأبيض "المتنفّس" بأيقونة مصغّرة متدرّجة -- نفس
          // .clinic-loader-core بالموقع بالحرف (scale 1 -> 1.035، 2.6s).
          AnimatedBuilder(
            animation: _coreCurve,
            builder: (context, child) => Transform.scale(
              scale: 1 + 0.035 * _coreCurve.value,
              child: child,
            ),
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: AppColors.indigo50),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.indigo600.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [AppColors.indigo600, AppColors.violet600],
                ).createShader(rect),
                child: const Icon(Icons.medical_services_rounded, size: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(_dot1),
        const SizedBox(width: 6),
        _buildDot(_dot2),
        const SizedBox(width: 6),
        _buildDot(_dot3),
      ],
    );
  }

  /// نقطة نابضة -- نفس clinicDotBounce بالموقع (قفزة صغيرة لأعلى + تلاشي
  /// طفيف تتكرر كل 1.3s، بتأخير 0.16s/0.32s بين النقاط الثلاث).
  Widget _buildDot(AnimationController controller) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final bounce = math.sin(controller.value * math.pi);
        return Transform.translate(
          offset: Offset(0, -5 * bounce),
          child: Opacity(opacity: 0.5 + 0.5 * bounce, child: child),
        );
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [AppColors.indigo600, AppColors.violet600]),
        ),
      ),
    );
  }
}
