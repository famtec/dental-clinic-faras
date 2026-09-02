import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';

/// بطاقة رمز QR لصفحة الحجز العامة -- طبق الأصل عن #bookingQrPrintCard في
/// profile.html بالموقع (نفس الشعار/اسم الطبيب/الجملة التعريفية/الرمز/
/// الرابط)، مع فرقين عن نسخة الموقع: الرمز يُولَّد محلياً هنا (qr_flutter)
/// بلا اعتماد على خدمة خارجية (بخلاف api.qrserver.com المستخدَمة سابقاً في
/// هذه الشاشة بالتطبيق)، و"تحميل الصورة" يصدّر البطاقة **بالكامل** كما
/// تظهر (شعار + اسم + رمز + رابط + اسم الموقع بالأسفل) بدل الرمز وحده --
/// نفس الشيء بالضبط لزر "طباعة البطاقة" (PDF عبر حزمتي pdf/printing
/// الموجودتين أصلاً بالمشروع لطباعة الوصفات). كلا الزرين يلتقطان نفس
/// البطاقة المعروضة على الشاشة حرفياً عبر RepaintBoundary، فلا داعٍ لرسم
/// التصميم مرتين بطريقتين مختلفتين قد تختلفان لاحقاً عن بعضهما. أُضيفت
/// 2026-08-31.
class BookingQrCard extends StatefulWidget {
  final String? doctorName;
  final String bookingUrl;

  const BookingQrCard({
    super.key,
    required this.doctorName,
    required this.bookingUrl,
  });

  @override
  State<BookingQrCard> createState() => _BookingQrCardState();
}

class _BookingQrCardState extends State<BookingQrCard> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isSaving = false;
  bool _isPrinting = false;

  String get _doctorLabel {
    final name = widget.doctorName?.trim();
    return (name != null && name.isNotEmpty) ? 'د. $name' : 'عيادتك الرقمية';
  }

  /// "اسم الموقع" الظاهر بأسفل البطاقة -- نفس منطق clinicTitle المستخدَم في
  /// رأس كل صفحات الموقع (qr.html وغيرها): "عيادة {اسم الطبيب}" أو
  /// "عيادتي الرقمية" كاسم افتراضي قبل إدخال الطبيب اسمه.
  String get _siteName {
    final name = widget.doctorName?.trim();
    return (name != null && name.isNotEmpty) ? 'عيادة $name' : 'عيادتي الرقمية';
  }

  String get _suggestedFileName {
    final segments = widget.bookingUrl.split('/').where((s) => s.isNotEmpty);
    final slug = segments.isNotEmpty ? segments.last : 'clinic';
    return 'qr-booking-$slug.png';
  }

  /// يلتقط البطاقة المعروضة على الشاشة كما هي بالضبط (PNG) -- المصدر
  /// المشترك لكل من "تحميل الصورة" و"طباعة البطاقة" أدناه.
  Future<Uint8List?> _captureCardPng() async {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // pixelRatio أعلى من دقة الشاشة الفعلية حتى تخرج الصورة/PDF المُصدَّرة
    // بجودة مناسبة للطباعة الحقيقية، لا مجرد حجم عرضها الصغير على الجوال.
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _downloadImage() async {
    if (_isSaving || _isPrinting) return;
    setState(() => _isSaving = true);
    try {
      final bytes = await _captureCardPng();
      if (bytes == null) {
        _showMessage('تعذر إنشاء الصورة. حاول مرة أخرى.');
        return;
      }
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ رمز QR',
        fileName: _suggestedFileName,
        type: FileType.image,
        bytes: bytes,
      );
      if (savedPath != null) _showMessage('تم حفظ الصورة بنجاح');
    } catch (_) {
      _showMessage('تعذر حفظ الصورة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _printCard() async {
    if (_isSaving || _isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final bytes = await _captureCardPng();
      if (bytes == null) {
        _showMessage('تعذر إنشاء البطاقة. حاول مرة أخرى.');
        return;
      }
      final pdf = pw.Document();
      final image = pw.MemoryImage(bytes);
      // pw.Image بلا width/height صريحين يرسم بأبعاد الصورة الفعلية بالبكسل
      // كنقاط PDF مباشرة -- عند pixelRatio: 3.0 هذا يعني بطاقة أكبر بكثير من
      // صفحة A5 فتُقصّ. نحسب العرض/الارتفاع المناسبين يدوياً من أبعاد
      // الصورة الحقيقية (MemoryImage تعرفهما فور فك تشفير البايتات) حتى
      // تظهر البطاقة كاملة ومتناسبة داخل الصفحة.
      const targetWidth = 300.0;
      // image.width/height من نوع int? (قد تكون غير معروفة قبل فك التشفير)،
      // لكن MemoryImage تفك تشفير البايتات فوراً وبشكل متزامن في constructor
      // أعلاه، فهما مضمونتان فعلياً هنا -- ! لإخبار المترجم بذلك.
      final targetHeight = targetWidth * image.height! / image.width!;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => pw.Center(
            child: pw.Image(image, width: targetWidth, height: targetHeight),
          ),
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (_) {
      _showMessage('تعذر تجهيز البطاقة للطباعة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.indigo50.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.indigo200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // شارة الشعار -- نفس الشارة المستخدَمة برأس شاشات تسجيل
                  // الدخول/التفعيل/شاشة البدء (AppColors.authCardHeaderGradient)
                  // حتى يبقى "شعار العيادة" موحّداً بكل أنحاء التطبيق.
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.authCardHeaderGradient,
                    ),
                    child: const Icon(Icons.medical_services_rounded,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _doctorLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.indigo800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'امسح الرمز لحجز موعدك مباشرة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.indigo700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.slate200),
                    ),
                    child: QrImageView(
                      data: widget.bookingUrl,
                      version: QrVersions.auto,
                      size: 160,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.indigo800,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.indigo800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.bookingUrl,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: AppColors.slate500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: AppColors.slate200, height: 1),
                  const SizedBox(height: 10),
                  // "اسم الموقع" -- يظهر هنا على الشاشة، وبالتالي في أي نسخة
                  // مُصدَّرة أيضاً (RepaintBoundary يلتقط البطاقة بالكامل).
                  Text(
                    _siteName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isSaving || _isPrinting) ? null : _downloadImage,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 16),
                label: const Text('تحميل الصورة'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isSaving || _isPrinting) ? null : _printCard,
                icon: _isPrinting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined, size: 16),
                label: const Text('طباعة البطاقة'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
