import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'contact_developer_screen.dart';
import 'finance_screen.dart';
import 'inventory_screen.dart';
import 'profile_screen.dart';

/// تبويب "المزيد" -- بوابة التنقل لبقية صفحات الموقع التي لا مكان لها في
/// شريط التنقل السفلي ذي الثلاث تبويبات (التقارير المالية / مخزن المواد /
/// حسابي / تواصل مع المطور)، تماماً كما تظهر في هيدر/قائمة الموقع. يحوي
/// أيضاً زر تسجيل الخروج (نفس الزر الموجود في هيدر كل صفحة بالموقع).
class MoreMenuScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onLogout;
  final VoidCallback onSessionExpired;

  const MoreMenuScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onLogout,
    required this.onSessionExpired,
  });

  @override
  State<MoreMenuScreen> createState() => _MoreMenuScreenState();
}

class _MoreMenuScreenState extends State<MoreMenuScreen> {
  String _tier = 'standard';

  @override
  void initState() {
    super.initState();
    _loadTier();
  }

  Future<void> _loadTier() async {
    final tier = await widget.authStorage.getTier();
    if (!mounted || tier == null || tier.isEmpty) return;
    setState(() => _tier = tier);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 20, 20, 30),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      TierBadge(tier: _tier),
                      const Spacer(),
                      const Text(
                        'المزيد',
                        style: TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'التقارير المالية، المخزن، الحساب، والدعم الفني',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MenuTile(
                    icon: Icons.bar_chart_rounded,
                    color: AppColors.indigo600,
                    title: 'التقارير المالية',
                    subtitle: 'الدخل والمصروفات وصافي الأرباح',
                    onTap: () => _push(FinanceScreen(
                      apiService: widget.apiService,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  _MenuTile(
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.violet600,
                    title: 'مخزن المواد',
                    subtitle: 'متابعة كميات المستلزمات (Premium)',
                    onTap: () => _push(InventoryScreen(
                      apiService: widget.apiService,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  _MenuTile(
                    icon: Icons.person_outline,
                    color: AppColors.cyan400,
                    title: 'حسابي',
                    subtitle: 'بيانات الطبيب والعيادة وكلمة السر',
                    onTap: () => _push(ProfileScreen(
                      apiService: widget.apiService,
                      authStorage: widget.authStorage,
                      onSessionExpired: widget.onSessionExpired,
                    )),
                  ),
                  const SizedBox(height: 10),
                  _MenuTile(
                    icon: Icons.support_agent_outlined,
                    color: AppColors.emerald500,
                    title: 'تواصل مع المطور',
                    subtitle: 'الدعم الفني والترقية والتواصل المباشر',
                    onTap: () => _push(const ContactDeveloperScreen()),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: widget.onLogout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.rose50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.rose200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text('تسجيل الخروج',
                                style: TextStyle(
                                    color: AppColors.rose700text, fontWeight: FontWeight.w800)),
                            SizedBox(width: 8),
                            Icon(Icons.logout, color: AppColors.rose700text, size: 18),
                          ],
                        ),
                      ),
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

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.slate200),
            boxShadow: [
              BoxShadow(
                color: AppColors.slate900.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.chevron_left, color: AppColors.slate400),
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
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
