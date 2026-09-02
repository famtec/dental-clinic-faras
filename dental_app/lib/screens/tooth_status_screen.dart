import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/dental_chart.dart';
import '../widgets/tooth_widget.dart';

/// شاشة السن الكاملة -- الخيار (ب) الذي اختاره المستخدم للموقع ثم للتطبيق:
/// بدل نافذة منبثقة أطول من الشاشة، صفحة كاملة فيها معاينة كبيرة للسن،
/// وسهمان للتنقّل بين الأسنان دون إغلاقها، وقائمة الحالات في عمودين.
///
/// طبق الأصل عن ‎#toothFullScreen في patient_record.html بالموقع: نفس ترتيب
/// العناصر، نفس ألوان الحالات (من toothStatusOptions المشتركة)، ونفس القاعدة
/// المهمة: الضغط على حالة يحفظ فوراً **واللوحة تبقى مفتوحة** ليتمكّن الطبيب
/// من تسجيل عدة أسنان متتالية.
class ToothStatusScreen extends StatefulWidget {
  /// رقم السن (FDI) الذي فُتحت الشاشة عليه.
  final int initialFdi;

  /// قراءة حيّة لحالة المخطط من الشاشة الأم بعد كل حفظ ناجح -- لا نحتفظ
  /// بنسخة هنا حتى لا تتباعد النسختان.
  final Map<String, String> Function() chartStateReader;

  /// الحفظ الفعلي. تُعيد true عند النجاح. تمرير null يمسح حالة السن (تحذف
  /// مفتاحه من المخطط -- انظر _updateTooth في patient_detail_screen.dart).
  final Future<bool> Function(int fdiNumber, String? statusKey) onSave;

  const ToothStatusScreen({
    super.key,
    required this.initialFdi,
    required this.chartStateReader,
    required this.onSave,
  });

  @override
  State<ToothStatusScreen> createState() => _ToothStatusScreenState();
}

class _ToothStatusScreenState extends State<ToothStatusScreen> {
  /// ترتيب المرور بالأسهم -- نفس ترتيب صفّي المخطط، فالانتقال يتبع القوس
  /// كما يراه الطبيب على الشاشة.
  static final List<int> _walkOrder = [...upperArchFdi, ...lowerArchFdi];

  static const Map<int, String> _quadrantLabels = {
    1: 'الفك العلوي الأيمن',
    2: 'الفك العلوي الأيسر',
    3: 'الفك السفلي الأيسر',
    4: 'الفك السفلي الأيمن',
  };

  late int _fdi = widget.initialFdi;
  final TextEditingController _customLabel = TextEditingController();
  ToothStatusOption? _customColor;
  bool _customOpen = false;
  bool _isSaving = false;
  String _hint = 'تُحفظ فورًا على الملف السحابي';

  @override
  void dispose() {
    _customLabel.dispose();
    super.dispose();
  }

  bool get _isUpper => _fdi ~/ 10 == 1 || _fdi ~/ 10 == 2;

  String? get _rawStatus {
    final palmer = fdiToPalmer[_fdi];
    if (palmer == null) return null;
    return widget.chartStateReader()[palmer];
  }

  void _goToAdjacent(int step) {
    final index = _walkOrder.indexOf(_fdi);
    if (index == -1) return;
    final next = _walkOrder[(index + step + _walkOrder.length) % _walkOrder.length];
    setState(() {
      _fdi = next;
      _customOpen = false;
      _customColor = null;
      _customLabel.clear();
      _hint = 'تُحفظ فورًا على الملف السحابي';
    });
  }

  Future<void> _save(String? statusKey, {String? successHint}) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _hint = 'جاري حفظ التحديث...';
    });
    final ok = await widget.onSave(_fdi, statusKey);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hint = ok
          ? (successHint ?? 'تم حفظ الحالة')
          : 'تعذر الحفظ الآن. أعد المحاولة بعد قليل.';
      if (ok) {
        _customOpen = false;
        _customColor = null;
        _customLabel.clear();
      }
    });
  }

  Future<void> _saveCustom() async {
    final label = _customLabel.text.trim();
    if (label.isEmpty) {
      setState(() => _hint = 'يرجى إدخال اسم الحالة أولاً.');
      return;
    }
    final color = _customColor;
    if (color == null) {
      setState(() => _hint = 'يرجى اختيار لون للحالة المخصصة.');
      return;
    }
    await _save(encodeCustomToothStatus(label, color.hex), successHint: 'تم حفظ الحالة');
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawStatus;
    final resolved = resolveToothStatus(raw);
    final activeKey = toothStatusByKey(raw?.trim().toLowerCase())?.key;
    final nextIndex = (_walkOrder.indexOf(_fdi) + 1) % _walkOrder.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(resolved),
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.fromLTRB(
                    16, 26, 16, MediaQuery.of(context).padding.bottom + 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'الحالة العلاجية',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF334155)),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _hint,
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate400),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildOptionsGrid(activeKey),
                    const SizedBox(height: 10),
                    _buildCustomSection(),
                    const SizedBox(height: 10),
                    _GhostButton(
                      label: 'مسح حالة هذا السن',
                      onPressed: _isSaving || raw == null
                          ? null
                          : () => _save(null, successHint: 'تم مسح الحالة'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'التالي: السن ${_walkOrder[nextIndex]}',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.slate400),
                        ),
                        const Spacer(),
                        _PrimaryButton(
                          label: 'السن التالي',
                          onPressed: () => _goToAdjacent(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ResolvedToothStatus? resolved) {
    final fill = resolved?.color.withValues(alpha: 0.28) ?? toothDefaultFill;
    final stroke = resolved?.color ?? toothDefaultStroke;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 14, 16, 34),
      decoration: BoxDecoration(
        gradient: AppColors.smartStatGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.indigoAccent.withValues(alpha: .24),
            blurRadius: 60,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeroPill(
                label: 'عودة للمخطط',
                icon: Icons.chevron_right,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  border: Border.all(color: Colors.white.withValues(alpha: .15)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'FDI',
                  style: TextStyle(
                      color: Color(0xFFA5B4FC),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // السهم المتّجه يميناً يتقدّم مع اتجاه القوس على المخطط
              // (18←11 ثم 21←28 تُقرأ من اليسار لليمين)، لا مع اتجاه القراءة.
              _ArrowButton(
                icon: Icons.chevron_right,
                tooltip: 'السن التالي',
                onPressed: () => _goToAdjacent(1),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 104,
                    height: 172,
                    child: CustomPaint(
                      painter: ToothShapePainter(
                        fill: fill,
                        stroke: stroke,
                        isUpper: _isUpper,
                      ),
                    ),
                  ),
                ),
              ),
              _ArrowButton(
                icon: Icons.chevron_left,
                tooltip: 'السن السابق',
                onPressed: () => _goToAdjacent(-1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'السن $_fdi',
            style: const TextStyle(
                color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            _quadrantLabels[_fdi ~/ 10] ?? '',
            style: const TextStyle(
                color: Color(0xFFC7D2FE), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: resolved?.color ?? Colors.white.withValues(alpha: .45),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  resolved?.label ?? 'بدون حالة مسجّلة',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid(String? activeKey) {
    final rows = <Widget>[];
    for (var i = 0; i < toothStatusOptions.length; i += 2) {
      final left = toothStatusOptions[i];
      final right =
          i + 1 < toothStatusOptions.length ? toothStatusOptions[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
          child: Row(
            children: [
              Expanded(
                child: _StatusOptionTile(
                  option: left,
                  isActive: activeKey == left.key,
                  onPressed: _isSaving ? null : () => _save(left.key),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _StatusOptionTile(
                        option: right,
                        isActive: activeKey == right.key,
                        onPressed: _isSaving ? null : () => _save(right.key),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildCustomSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GhostButton(
          label: 'حالة مخصصة باسم ولون',
          icon: Icons.add,
          dashedIndigo: true,
          onPressed: () => setState(() => _customOpen = !_customOpen),
        ),
        if (_customOpen) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _customLabel,
            textAlign: TextAlign.right,
            maxLength: 40,
            decoration: InputDecoration(
              hintText: 'مثال: كسر، تنظيف، تلميع...',
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.slate300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.slate300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.indigo600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: toothStatusOptions.map((option) {
              final selected = _customColor?.key == option.key;
              return GestureDetector(
                onTap: () => setState(() => _customColor = option),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.indigo800 : Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (selected ? AppColors.indigo800 : AppColors.slate900)
                            .withValues(alpha: selected ? .35 : .18),
                        blurRadius: selected ? 6 : 3,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _PrimaryButton(
            label: 'حفظ الحالة المخصصة',
            wide: true,
            onPressed: _isSaving ? null : _saveCustom,
          ),
        ],
      ],
    );
  }
}

class _StatusOptionTile extends StatelessWidget {
  final ToothStatusOption option;
  final bool isActive;
  final VoidCallback? onPressed;

  const _StatusOptionTile({
    required this.option,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // تدرّج شفاف من لون الحالة نفسها بدل جدول ألوان ثانٍ يحتاج
            // مزامنة مع toothStatusOptions كلما تغيّرت الألوان.
            color: option.color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? option.color : option.color.withValues(alpha: .33),
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: option.color.withValues(alpha: .13),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: option.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  option.label,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155)),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Icon(Icons.check, size: 16, color: option.color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool dashedIndigo;
  final VoidCallback? onPressed;

  const _GhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.dashedIndigo = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dashedIndigo ? const Color(0xFFF8FAFF) : AppColors.pageBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: dashedIndigo ? const Color(0xFFC7D2FE) : AppColors.slate200,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 17,
                      color: dashedIndigo
                          ? AppColors.indigoAccent
                          : AppColors.slate500),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color:
                        dashedIndigo ? AppColors.indigoAccent : AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool wide;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? .6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            height: 48,
            width: wide ? double.infinity : null,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryButtonGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigoAccent.withValues(alpha: .32),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800),
                ),
                if (!wide) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _HeroPill({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .10),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: const Color(0xFFE0E7FF)),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                    color: Color(0xFFE0E7FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: const Color(0xFFC7D2FE)),
          ),
        ),
      ),
    );
  }
}
