import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// نماذج التطبيق المنبثقة: ورقة سفلية على الجوال، ونافذة حوار في الوسط على
/// سطح المكتب (2026-09-24).
/// ═══════════════════════════════════════════════════════════════════════════
///
/// الورقة السفلية على نافذة ويندوز كانت تلتصق بأسفل الشاشة بمقبض سحب لا
/// يُسحب بالفأرة -- شكل هاتف واضح. هنا نفس محتوى الورقة حرفياً (نفس الحقول
/// ونفس الحفظ ونفس `Navigator.pop(result)`) داخل حوار بإطار وظلّ وزرّ
/// إغلاق، ومقبض السحب يختفي عبر [BottomSheetOnly]. الجوال بلا أي تغيير: هو
/// نفس نداء [showModalBottomSheet] بنفس المعاملات.
///
/// [desktopWidth] عرض الحوار الأقصى؛ الارتفاع محدود بالنافذة، والمحتوى
/// الطويل يتمرّر داخله كما كان يتمرّر داخل الورقة.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  double desktopWidth = 560,
}) {
  if (!context.isDesktopShell) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      shape: shape,
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (dialogContext) => _DesktopSheetDialog(
      width: desktopWidth,
      child: Builder(builder: builder),
    ),
  );
}

/// هل هذا المحتوى معروض حواراً على سطح المكتب لا ورقة سفلية؟
class AppSheetScope extends InheritedWidget {
  const AppSheetScope({super.key, required super.child});

  static bool isDialog(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSheetScope>() != null;

  @override
  bool updateShouldNotify(AppSheetScope oldWidget) => false;
}

/// يُعرَض في الورقة السفلية وحدها ويختفي في حوار سطح المكتب -- لمقبض السحب.
class BottomSheetOnly extends StatelessWidget {
  final Widget child;

  const BottomSheetOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      AppSheetScope.isDialog(context) ? const SizedBox.shrink() : child;
}

class _DesktopSheetDialog extends StatelessWidget {
  final double width;
  final Widget child;

  const _DesktopSheetDialog({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    final size = MediaQuery.sizeOf(context);
    const radius = BorderRadius.all(Radius.circular(24));
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: math.min(size.height - 56, 880),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: d.cardBorder),
            boxShadow: d.panelShadow,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: context.surface.sheetBg,
              child: AppSheetScope(
                child: Stack(
                  children: [
                    // عرض الحوار كاملاً كما كانت الورقة بعرض الشاشة كاملاً:
                    // محتوى بلا stretch كان سينكمش إلى عرضه الطبيعي.
                    SizedBox(width: double.infinity, child: child),
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: _CloseButton(onTap: () => Navigator.of(context).maybePop()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = context.desktop;
    return Semantics(
      label: 'إغلاق',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? d.iconBtnHover : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.close_rounded, size: 18, color: _hovered ? d.textPrimary : d.iconBtnFg),
          ),
        ),
      ),
    );
  }
}
