import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

/// شريط عنوان النافذة على ويندوز (2026-09-24)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// شريط ويندوز الأصلي يُرسم بلون «التمييز» من إعدادات النظام (وردي عند
/// المستخدم)، لا بلون التطبيق، ولا يتبع الوضع الليلي. أُخفي في
/// platform_support.dart (TitleBarStyle.hidden) ويُرسم هذا مكانه بتوكنات
/// سطح المكتب: سطح الصفحة نفسه، وأزرار تصغير/تكبير/إغلاق بمقاسات ويندوز
/// المعتادة (46×32)، والإغلاق أحمر عند المرور كما يتوقّعه كل مستخدم ويندوز.
///
/// الترتيب فيزيائي ثابت (LTR) لا يتبع اتجاه التطبيق: أزرار النافذة في
/// ويندوز على اليمين دائماً، وقلبها لأن التطبيق عربي يربك اليد المعتادة.
class DesktopTitleBar extends StatefulWidget {
  final String title;

  const DesktopTitleBar({super.key, required this.title});

  static const double height = 32;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowFocus() => setState(() => _focused = true);

  @override
  void onWindowBlur() => setState(() => _focused = false);

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final fg = _focused ? d.textPrimary : d.textMuted;
    // Material شفّافة: الشريط يُرسم في builder الجذر فوق Navigator، أي بلا
    // Material سلف، والنصّ هناك يرث نمط الخطأ الافتراضي (خطّ أصفر مزدوج).
    return Material(
      type: MaterialType.transparency,
      child: Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: DesktopTitleBar.height,
        decoration: BoxDecoration(
          color: d.shellBg,
          border: Border(bottom: BorderSide(color: d.topBarBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: d.logoGradient,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(Icons.medical_services_rounded, size: 11, color: d.onLogo),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: AppType.sans(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ],
                ),
              ),
            ),
            _CaptionButton(
              icon: Icons.remove,
              tooltip: 'تصغير',
              onTap: windowManager.minimize,
            ),
            _CaptionButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              iconSize: _maximized ? 12 : 14,
              tooltip: _maximized ? 'استعادة' : 'تكبير',
              onTap: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
            ),
            _CaptionButton(
              icon: Icons.close,
              tooltip: 'إغلاق',
              danger: true,
              onTap: windowManager.close,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.iconSize = 15,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    // أحمر ويندوز القياسي لزرّ الإغلاق -- لون وظيفة لا لون هوية.
    const closeRed = Color(0xFFE81123);
    final bg = !_hovered
        ? Colors.transparent
        : (widget.danger ? closeRed : d.iconBtnHover);
    final fg = _hovered && widget.danger ? Colors.white : d.iconBtnFg;
    return Semantics(
      label: widget.tooltip,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: DesktopTitleBar.height,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
