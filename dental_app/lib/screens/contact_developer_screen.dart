import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// "تواصل مع المطور" -- نسخة طبق الأصل عن contact_developer.html بالموقع:
/// نفس قنوات التواصل (هاتف/تيليغرام/واتساب/بريد) وبطاقة الدفع عبر شام كاش،
/// حرفياً بنفس الأرقام والروابط. صفحة ثابتة بلا اتصال بالـ backend.
class ContactDeveloperScreen extends StatelessWidget {
  const ContactDeveloperScreen({super.key});

  static const _shamCashQrUrl =
      'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=https%3A%2F%2Fshamcash.app';

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
    return Scaffold(
      body: AtmosphereBackground(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding:
                  EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 20, 30),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
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
                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cyan400.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.cyan400.withValues(alpha: .3)),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: AppColors.cyan300, size: 32),
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
                    subtitle: '0956907698',
                    onTap: () => _open(context, 'tel:0956907698'),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.send_outlined,
                    color: const Color(0xFF38BDF8),
                    title: 'التواصل عبر تيليغرام',
                    subtitle: 'رسائل مباشرة عبر قناة الدعم',
                    onTap: () => _open(context, 'https://t.me/fareshalawi17'),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.chat_outlined,
                    color: AppColors.emerald500,
                    title: 'مراسلة فورية عبر واتساب',
                    subtitle: 'استجابة سريعة للدعم والترقيات',
                    onTap: () => _open(
                        context,
                        'https://wa.me/963956907698?text=%D8%A8%D8%B4%D9%85%D9%87%D9%86%D8%AF%D8%B3%20%D9%81%D8%A7%D8%B1%D8%B3%D8%8C%20%D8%A3%D8%AD%D8%AA%D8%A7%D8%AC%20%D8%A5%D9%84%D9%89%20%D8%A7%D9%84%D8%AF%D8%B9%D9%85%20%D8%A7%D9%84%D9%81%D9%86%D9%8A%20%D8%A3%D9%88%20%D8%AA%D8%B1%D9%82%D9%8A%D8%A9%20%D8%A7%D9%84%D8%A8%D8%A7%D9%82%D8%A9%20%D9%81%D9%8A%20%D8%A7%D9%84%D8%B9%D9%8A%D8%A7%D8%AF%D8%A9%20%D8%A7%D9%84%D8%B1%D9%82%D9%85%D9%8A%D8%A9'),
                  ),
                  const SizedBox(height: 10),
                  _ContactTile(
                    icon: Icons.email_outlined,
                    color: AppColors.violet600,
                    title: 'إرسال بريد إلكتروني رسمي',
                    subtitle: 'fareshalawi17@gmail.com',
                    onTap: () => _open(context, 'mailto:fareshalawi17@gmail.com'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.indigo50,
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.credit_card, color: AppColors.indigo700),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('الدفع الإلكتروني عبر شام كاش',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                  SizedBox(height: 2),
                                  Text('امسح الكود لإتمام الدفع مباشرة',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 11, color: AppColors.slate500)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            child: Image.network(
                              _shamCashQrUrl,
                              width: 150,
                              height: 150,
                              errorBuilder: (context, error, stackTrace) => const SizedBox(
                                width: 150,
                                height: 150,
                                child: Icon(Icons.qr_code_2, size: 60, color: AppColors.slate400),
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
                  const Center(
                    child: Text(
                      'تطوير وإدارة: المهندس فارس حلاوي © 2026',
                      style: TextStyle(fontSize: 11, color: AppColors.slate400),
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
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate500)),
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
