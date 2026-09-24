import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/desktop_widgets.dart';

/// "تواصل مع المطور" -- نسخة طبق الأصل عن contact_developer.html بالموقع:
/// نفس قنوات التواصل (هاتف/تيليغرام/واتساب/بريد) وبطاقة الدفع عبر شام كاش،
/// حرفياً بنفس الأرقام والروابط. صفحة ثابتة بلا اتصال بالـ backend.
class ContactDeveloperScreen extends StatelessWidget {
  const ContactDeveloperScreen({super.key});

  static const _shamCashQrUrl =
      'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=https%3A%2F%2Fshamcash.app';

  // القنوات نفسها في التخطيطين -- مصدر واحد للأرقام والروابط.
  static const _phone = '0956907698';
  static const _telegramUrl = 'https://t.me/fareshalawi17';
  static const _email = 'fareshalawi17@gmail.com';
  static const _whatsappUrl =
      'https://wa.me/963956907698?text=%D8%A8%D8%B4%D9%85%D9%87%D9%86%D8%AF%D8%B3%20%D9%81%D8%A7%D8%B1%D8%B3%D8%8C%20%D8%A3%D8%AD%D8%AA%D8%A7%D8%AC%20%D8%A5%D9%84%D9%89%20%D8%A7%D9%84%D8%AF%D8%B9%D9%85%20%D8%A7%D9%84%D9%81%D9%86%D9%8A%20%D8%A3%D9%88%20%D8%AA%D8%B1%D9%82%D9%8A%D8%A9%20%D8%A7%D9%84%D8%A8%D8%A7%D9%82%D8%A9%20%D9%81%D9%8A%20%D8%A7%D9%84%D8%B9%D9%8A%D8%A7%D8%AF%D8%A9%20%D8%A7%D9%84%D8%B1%D9%82%D9%85%D9%8A%D8%A9';

  /// شعار المطور (assets/brand) -- نسخة لكل وضع حتى يبقى مقروءاً.
  static String _logoAsset(bool dark) =>
      dark ? 'assets/brand/fares-logo-on-dark.png' : 'assets/brand/fares-logo-on-light.png';
  static String _iconAsset(bool dark) =>
      dark ? 'assets/brand/fares-icon-dark.png' : 'assets/brand/fares-icon-light.png';

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح التطبيق المطلوب.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح التطبيق المطلوب.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopShell) return _buildDesktop(context);
    final surf = context.surface;
    return Scaffold(
      body: AtmosphereBackground(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            AnimatedHeroHeader(
              padding:
                  EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 20, 30),
              child: Column(
                children: [
                  // زر رجوع -- انظر نفس التعليق في finance_screen.dart.
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      ),
                      const Spacer(),
                    ],
                  ),
                  // شعار المطور بدل أيقونة البرق (2026-09-24): الأيقونة المربّعة
                  // الفاتحة في الوضع النهاري والداكنة في الليلي.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      _iconAsset(surf.isDark),
                      width: 72,
                      height: 72,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'المهندس فارس حلاوي\nمطور المنصة السحابية الشاملة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'بوابتك الأسرع للدعم الفني، الترقية، التطوير، وضبط منصة العيادة الرقمية بأعلى كفاءة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12.5, height: 1.6),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ContactTile(
                    icon: Icons.call_outlined,
                    color: AppColors.cyan400,
                    title: 'اتصال هاتفي مباشر',
                    subtitle: _phone,
                    onTap: () => _open(context, 'tel:$_phone'),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.send_outlined,
                    color: const Color(0xFF38BDF8),
                    title: 'التواصل عبر تيليغرام',
                    subtitle: 'رسائل مباشرة عبر قناة الدعم',
                    onTap: () => _open(context, _telegramUrl),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.chat_outlined,
                    color: AppColors.emerald500,
                    title: 'مراسلة فورية عبر واتساب',
                    subtitle: 'استجابة سريعة للدعم والترقيات',
                    onTap: () => _open(context, _whatsappUrl),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.email_outlined,
                    color: AppColors.violet600,
                    title: 'إرسال بريد إلكتروني رسمي',
                    subtitle: _email,
                    onTap: () => _open(context, 'mailto:$_email'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surf.iconBoxBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.indigo600.withValues(alpha: .18)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: surf.iconBoxBg,
                                border: Border.all(color: surf.iconBoxBorder),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.credit_card,
                                  color: surf.iconBoxFg),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('الدفع الإلكتروني عبر شام كاش',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                  SizedBox(height: 2),
                                  Text('امسح الكود لإتمام الدفع مباشرة',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 11, color: surf.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            // يبقى أبيض في الوضعين عمداً: رمز QR يحتاج هامشاً
                            // أبيض ليقرأه الماسح، وخلفية داكنة تكسر قراءته.
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            child: Image.network(
                              _shamCashQrUrl,
                              width: 150,
                              height: 150,
                              errorBuilder: (context, error, stackTrace) => SizedBox(
                                width: 150,
                                height: 150,
                                child: Icon(Icons.qr_code_2, size: 60, color: surf.textMuted),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'يرجى إرسال صورة إشعار للتأكد من إتمام عملية الشراء',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.indigo700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'تطوير وإدارة: المهندس فارس حلاوي © 2026',
                      style: TextStyle(fontSize: 11, color: surf.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ── سطح المكتب ──────────────────────────────────────────────────────────

  /// على نافذة ويندوز كانت الصفحة رأساً متدرّجاً بعرض الشاشة وبطاقات قنوات
  /// بعرض 1500px. هنا: ترويسة بلون الصفحة، وبطاقة تعريف بشعار المطور في
  /// عمود جانبي، وقنوات التواصل شبكةً بجانبها، وبطاقة الدفع تحتها.
  Widget _buildDesktop(BuildContext context) {
    final d = context.desktop;
    final channels = <({IconData icon, Color color, String title, String subtitle, String url, bool ltr})>[
      (icon: Icons.call_outlined, color: const Color(0xFF06B6D4), title: 'اتصال هاتفي مباشر',
          subtitle: _phone, url: 'tel:$_phone', ltr: true),
      (icon: Icons.chat_outlined, color: const Color(0xFF10B981), title: 'مراسلة فورية عبر واتساب',
          subtitle: 'استجابة سريعة للدعم والترقيات', url: _whatsappUrl, ltr: false),
      (icon: Icons.send_outlined, color: const Color(0xFF38BDF8), title: 'التواصل عبر تيليغرام',
          subtitle: 'رسائل مباشرة عبر قناة الدعم', url: _telegramUrl, ltr: false),
      (icon: Icons.email_outlined, color: const Color(0xFF8B5CF6), title: 'بريد إلكتروني رسمي',
          subtitle: _email, url: 'mailto:$_email', ltr: true),
    ];

    return Scaffold(
      backgroundColor: d.shellBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppDesktopMetrics.topBarHeight,
            padding: AppDesktopMetrics.topBarPadding,
            decoration: BoxDecoration(
              color: d.shellBg,
              border: Border(bottom: BorderSide(color: d.topBarBorder)),
            ),
            child: Row(
              children: [
                DesktopSquareButton(
                  icon: Icons.arrow_forward,
                  tooltip: 'رجوع',
                  size: 40,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تواصل مع المطور',
                        style: AppType.kufi(fontSize: 19, fontWeight: FontWeight.w700, color: d.textPrimary)),
                    Text('الدعم الفني، الترقية وأكواد التفعيل، وتطوير ميزات لعيادتك',
                        style: AppType.sans(fontSize: 12, color: d.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 400, child: _desktopBrandCard(context)),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('قنوات التواصل',
                                style: AppType.kufi(
                                    fontSize: 15, fontWeight: FontWeight.w700, color: d.textPrimary)),
                            const SizedBox(height: 12),
                            for (var row = 0; row < channels.length; row += 2) ...[
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = row; i < row + 2 && i < channels.length; i++) ...[
                                      if (i > row) const SizedBox(width: 14),
                                      Expanded(
                                        child: _DesktopChannelCard(
                                          icon: channels[i].icon,
                                          color: channels[i].color,
                                          title: channels[i].title,
                                          subtitle: channels[i].subtitle,
                                          ltrSubtitle: channels[i].ltr,
                                          onTap: () => _open(context, channels[i].url),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            const SizedBox(height: 4),
                            _desktopPaymentCard(context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopBrandCard(BuildContext context) {
    final d = context.desktop;
    const services = [
      (Icons.support_agent_outlined, 'الدعم الفني وحلّ المشاكل'),
      (Icons.workspace_premium_outlined, 'الترقية وأكواد التفعيل'),
      (Icons.auto_awesome_outlined, 'تطوير ميزات خاصة بعيادتك'),
    ];
    return DesktopCard(
      glow: true,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(
            _logoAsset(d.isDark),
            height: 104,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(height: 20),
          Text(
            'مطوّر المنصة السحابية الشاملة',
            textAlign: TextAlign.center,
            style: AppType.kufi(fontSize: 16, fontWeight: FontWeight.w700, color: d.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'بوابتك الأسرع للدعم الفني، الترقية، التطوير، وضبط منصة العيادة الرقمية بأعلى كفاءة.',
            textAlign: TextAlign.center,
            style: AppType.sans(fontSize: 12.5, height: 1.8, color: d.textSecondary),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: d.cardBorder),
          const SizedBox(height: 14),
          for (final (icon, label) in services)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.iconBoxBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: d.iconBoxBorder),
                    ),
                    child: Icon(icon, size: 16, color: d.iconBoxFg),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(label,
                        style: AppType.sans(fontSize: 13, fontWeight: FontWeight.w600, color: d.textPrimary)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'تطوير وإدارة: المهندس فارس حلاوي © 2026',
            textAlign: TextAlign.center,
            style: AppType.sans(fontSize: 11, color: d.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _desktopPaymentCard(BuildContext context) {
    final d = context.desktop;
    return DesktopCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            // أبيض في الوضعين عمداً: رمز QR يحتاج هامشاً أبيض ليقرأه الماسح.
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              // إطار رفيع: أبيض على بطاقة بيضاء في الوضع النهاري يختفي حدّه.
              border: Border.all(color: d.cardBorder),
            ),
            child: Image.network(
              _shamCashQrUrl,
              width: 132,
              height: 132,
              errorBuilder: (context, error, stackTrace) => SizedBox(
                width: 132,
                height: 132,
                child: Icon(Icons.qr_code_2, size: 56, color: d.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.credit_card, size: 18, color: d.iconBoxFg),
                    const SizedBox(width: 8),
                    Text('الدفع الإلكتروني عبر شام كاش',
                        style: AppType.kufi(fontSize: 15, fontWeight: FontWeight.w700, color: d.textPrimary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('امسح الرمز بتطبيق شام كاش لإتمام الدفع مباشرة.',
                    style: AppType.sans(fontSize: 12.5, height: 1.7, color: d.textSecondary)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: d.iconBoxBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: d.iconBoxBorder),
                  ),
                  child: Text(
                    'يرجى إرسال صورة إشعار الدفع للتأكد من إتمام عملية الشراء.',
                    style: AppType.sans(fontSize: 12, fontWeight: FontWeight.w700, color: d.linkFg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة قناة تواصل على سطح المكتب: أيقونة ملوّنة وعنوان وتفصيل، وسهم.
class _DesktopChannelCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool ltrSubtitle;
  final VoidCallback onTap;

  const _DesktopChannelCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.ltrSubtitle,
    required this.onTap,
  });

  @override
  State<_DesktopChannelCard> createState() => _DesktopChannelCardState();
}

class _DesktopChannelCardState extends State<_DesktopChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final c = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hovered ? c.withValues(alpha: d.isDark ? .12 : .06) : d.cardBg,
            borderRadius: BorderRadius.circular(AppDesktopMetrics.radiusCard),
            border: Border.all(color: _hovered ? c.withValues(alpha: .45) : d.cardBorder),
            boxShadow: d.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: .35)),
                ),
                child: Icon(widget.icon, color: c, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: AppType.sans(fontSize: 14, fontWeight: FontWeight.w700, color: d.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      textDirection: widget.ltrSubtitle ? TextDirection.ltr : null,
                      style: AppType.sans(fontSize: 12, color: d.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: _hovered ? c : d.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: .25)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: .35)),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(title,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11.5, color: surf.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
