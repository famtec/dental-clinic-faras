import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment.dart';
import '../models/patient.dart';
import '../models/patient_archive_file.dart';
import '../models/prescription.dart';
import '../models/treatment_invoice.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/appointment_status.dart';
import '../utils/dental_chart.dart';
import '../widgets/app_widgets.dart';
import '../widgets/tooth_widget.dart';

const _prescriptionArabicMonthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// مطابق لـ formatPrescriptionCreatedAt() في patient_record.html (يوم +
/// اسم شهر عربي + سنة + الوقت بنظام 24 ساعة).
String _formatPrescriptionDate(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${_prescriptionArabicMonthNames[date.month - 1]} ${date.year}، $hour:$minute';
}

const _appointmentWeekdayNamesAr = [
  'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
];

/// مطابق لـ formatAppointmentDateTime() في patient_record.html (اسم اليوم +
/// تاريخ كامل بالعربية + الوقت بنظام 24 ساعة) -- مدموج في سطر واحد بدل عمودين
/// منفصلين (اليوم والتاريخ / الوقت) لأن بطاقة الموعد هنا عمودية لا جدول.
String _formatAppointmentDateTime(DateTime date) {
  final weekday = _appointmentWeekdayNamesAr[date.weekday - 1];
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$weekday، ${date.day} ${_prescriptionArabicMonthNames[date.month - 1]} ${date.year} - $hour:$minute';
}

/// مطابق لـ formatAppointmentDescription() في patient_record.html: notes ثم
/// procedure_type كبديل احتياطي، وشرطة عند غيابهما معاً (نادر، لأن الحقل
/// مطلوب عند الإنشاء من كلا الواجهتين).
String _appointmentDescriptionLabel(Appointment appointment) {
  final notes = appointment.notes?.trim();
  if (notes != null && notes.isNotEmpty) return notes;
  if (appointment.procedureType.isNotEmpty) return appointment.procedureType;
  return '—';
}

/// مطابق تماماً لـ normalizeWhatsappPhone() في patient_record.html: يحوّل أي
/// صيغة هاتف سورية محلية (05xxxxxxxx أو 9xxxxxxxx بلا صفر) إلى الصيغة
/// الدولية بلا "+" (963xxxxxxxxx) التي يتطلبها رابط wa.me مباشرة.
String _normalizeWhatsappPhone(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) {
    digits = '963${digits.substring(1)}';
  } else if (!digits.startsWith('963') && digits.length == 9) {
    digits = '963$digits';
  }
  return digits;
}

/// صفحة "حالة المريض" الكاملة -- بديل الـ bottom sheet المختصر القديم.
/// تعرض: الملف الشخصي + الرصيد، المخطط السنّي الحقيقي (قابل للتعديل بالنقر
/// على أي سن)، وفواتير العلاج مع سجل الدفعات التفصيلي لكل فاتورة -- مطابقة
/// لِما يراه الطبيب في patient_record.html على الموقع.
class PatientDetailScreen extends StatefulWidget {
  final Patient patient;
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const PatientDetailScreen({
    super.key,
    required this.patient,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late Patient _patient;
  List<TreatmentInvoice>? _invoices;
  String? _invoicesError;
  bool _isLoadingInvoices = true;
  String? _savingToothKey;

  // 2026-08-30: أرشيف ملفات المريض (صور/أشعة أو مستندات PDF) -- بطلب
  // المستخدم "اضف امكانية أرشيف ملفات المريض مثل التي في الموقع تماما"،
  // مطابق لقسم "أرشيف ملفات المريض" في patient_record.html.
  List<PatientArchiveFile>? _archiveFiles;
  String? _archiveError;
  bool _isLoadingArchive = true;
  bool _isUploadingArchive = false;
  final _archiveDescriptionController = TextEditingController();
  final ImagePicker _archiveImagePicker = ImagePicker();

  // 2026-08-30: الوصفات الطبية القابلة للطباعة الفورية -- بطلب المستخدم
  // "اضف خاصية الوصفات الطبية مثل التي في الموقع الاساسي تماما بنفس
  // التصميم"، مطابق لقسم "الوصفات الطبية" في patient_record.html.
  List<Prescription>? _prescriptions;
  String? _prescriptionsError;
  bool _isLoadingPrescriptions = true;
  bool _isSavingPrescription = false;
  int? _printingPrescriptionId;
  final _prescriptionMedicationsController = TextEditingController();
  final _prescriptionInstructionsController = TextEditingController();

  // 2026-08-30: إدارة مواعيد هذا المريض (عرض/إضافة/تعديل/حذف + تذكير واتساب)
  // -- بطلب المستخدم "اضف ايضا امكانية إدارة مواعيد هذا المريض مثل الذي في
  // الموقع الاساسي تماما"، مطابق لقسم "إدارة مواعيد هذا المريض" في
  // patient_record.html. لا يوجد endpoint مخصص لمواعيد مريض واحد فقط، فالموقع
  // يجلب كل مواعيد الطبيب عبر GET /api/appointments ثم يُصفّي محلياً حسب
  // patient_id (أو تطابق الاسم كبديل احتياطي) -- نفس الأسلوب هنا بالضبط.
  List<Appointment>? _appointments;
  String? _appointmentsError;
  bool _isLoadingAppointments = true;
  int? _deletingAppointmentId;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _loadInvoices();
    _loadArchive();
    _loadPrescriptions();
    _loadAppointments();
  }

  @override
  void dispose() {
    _archiveDescriptionController.dispose();
    _prescriptionMedicationsController.dispose();
    _prescriptionInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoadingInvoices = true;
      _invoicesError = null;
    });
    try {
      final invoices = await widget.apiService.fetchPatientInvoices(_patient.id);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoadingInvoices = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _invoicesError = e.message;
        _isLoadingInvoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _invoicesError = 'تعذر تحميل فواتير العلاج. حاول مرة أخرى.';
        _isLoadingInvoices = false;
      });
    }
  }

  Future<void> _loadArchive() async {
    setState(() {
      _isLoadingArchive = true;
      _archiveError = null;
    });
    try {
      final files = await widget.apiService.fetchPatientArchive(_patient.id);
      if (!mounted) return;
      setState(() {
        _archiveFiles = files;
        _isLoadingArchive = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _archiveError = e.message;
        _isLoadingArchive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _archiveError = 'تعذر تحميل أرشيف الملفات الطبية. حاول مرة أخرى.';
        _isLoadingArchive = false;
      });
    }
  }

  /// يفتح قائمة اختيار مصدر الملف (تصوير بالكاميرا/صورة من المعرض/مستند PDF)
  /// ثم يرفعه فوراً -- مطابق لسلوك archiveDropzone/xrayFileInput في
  /// patient_record.html بالموقع (accept="image/png,image/jpeg,image/jpg,
  /// application/pdf"). الموقع يسمح باختيار عدة ملفات دفعة واحدة عبر
  /// السحب-والإفلات؛ في التطبيق كل ضغطة ترفع ملفاً واحداً (أنسب للمس على
  /// الجوال)، ويمكن تكرار الضغط لرفع أكثر من ملف بنفس الوصف المكتوب حالياً.
  Future<void> _pickAndUploadArchiveFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.slate200,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Text(
              'رفع ملف طبي',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            ListTile(
              onTap: () => Navigator.of(sheetContext).pop('camera'),
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.indigo700),
              title: const Text('تصوير بالكاميرا', textAlign: TextAlign.right),
            ),
            ListTile(
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.indigo700),
              title: const Text('اختيار صورة من المعرض', textAlign: TextAlign.right),
            ),
            ListTile(
              onTap: () => Navigator.of(sheetContext).pop('pdf'),
              leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.indigo700),
              title: const Text('اختيار مستند PDF', textAlign: TextAlign.right),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    List<int>? bytes;
    String? filename;

    try {
      if (choice == 'pdf') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        bytes = result.files.single.bytes;
        filename = result.files.single.name;
      } else {
        final picked = await _archiveImagePicker.pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 85,
        );
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        filename = picked.name;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر فتح الكاميرا/المعرض/متصفح الملفات.')));
      return;
    }

    if (bytes == null || filename == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر قراءة الملف المحدد.')));
      return;
    }

    setState(() => _isUploadingArchive = true);
    try {
      final uploaded = await widget.apiService.uploadPatientArchiveFile(
        _patient.id,
        bytes: bytes,
        filename: filename,
        description: _archiveDescriptionController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _archiveFiles = [uploaded, ...(_archiveFiles ?? [])];
        _isUploadingArchive = false;
        _archiveDescriptionController.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم رفع الملف الطبي بنجاح!')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() => _isUploadingArchive = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploadingArchive = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر رفع الملف الطبي الآن. يرجى المحاولة لاحقاً.')));
    }
  }

  /// معاينة صورة بملء الشاشة -- مطابق لـ archiveImageModal في
  /// patient_record.html (يُفتح عند الضغط على أي بطاقة صورة في المعرض).
  void _openArchiveImagePreview(PatientArchiveFile file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    file.fileName,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(file.resolvedImageUrl, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// فتح مستند PDF في تطبيق خارجي/المتصفح -- مطابق لسلوك رابط "فتح المستند"
  /// (target="_blank") في بطاقة ملف PDF على patient_record.html.
  Future<void> _openArchiveDocument(PatientArchiveFile file) async {
    final uri = Uri.tryParse(file.resolvedFileUrl);
    if (uri == null) return;
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح المستند.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح المستند.')));
      }
    }
  }

  String _formatArchiveDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  Future<void> _loadPrescriptions() async {
    setState(() {
      _isLoadingPrescriptions = true;
      _prescriptionsError = null;
    });
    try {
      final prescriptions = await widget.apiService.fetchPatientPrescriptions(_patient.id);
      if (!mounted) return;
      setState(() {
        _prescriptions = prescriptions;
        _isLoadingPrescriptions = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _prescriptionsError = e.message;
        _isLoadingPrescriptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prescriptionsError = 'تعذر تحميل الوصفات الطبية. حاول مرة أخرى.';
        _isLoadingPrescriptions = false;
      });
    }
  }

  Future<void> _submitPrescription() async {
    final medications = _prescriptionMedicationsController.text.trim();
    final instructions = _prescriptionInstructionsController.text.trim();
    if (medications.isEmpty || instructions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال الأدوية والتعليمات قبل حفظ الوصفة.')));
      return;
    }

    setState(() => _isSavingPrescription = true);
    try {
      final created = await widget.apiService.createPrescription(
        _patient.id,
        medications: medications,
        instructions: instructions,
      );
      if (!mounted) return;
      setState(() {
        _prescriptions = [created, ...(_prescriptions ?? [])];
        _isSavingPrescription = false;
        _prescriptionMedicationsController.clear();
        _prescriptionInstructionsController.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم إصدار وحفظ الوصفة الطبية بنجاح 📝')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() => _isSavingPrescription = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSavingPrescription = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر حفظ الوصفة الطبية حالياً.')));
    }
  }

  /// طباعة/مشاركة وصفة كملف PDF -- بديل الجوال لنافذة طباعة المتصفح
  /// (window.print على #prescriptionPrintTemplate) في patient_record.html.
  /// يبني نفس محتوى القالب: اسم العيادة (من doctor_name المحفوظ محلياً، نفس
  /// منطق populatePrescriptionPrintTemplate)، اسم المريض، التاريخ، صندوقا
  /// الأدوية والتعليمات، وسطر الحقوق السفلي -- بخط Noto Naskh Arabic (خط
  /// عربي كامل الدعم عبر PdfGoogleFonts، وهو الخيار الموثّق من حزمة pdf/
  /// printing نفسها لعرض نص عربي صحيح؛ لم يُستخدم خط Tajawal المستخدم في
  /// واجهة التطبيق هنا تحديداً لعدم التأكد من توفره عبر PdfGoogleFonts بلا
  /// أداة Flutter فعلية للتحقق -- إن رغب المستخدم مطابقة الخط بدقة لاحقاً
  /// يمكن تجربة PdfGoogleFonts.tajawalRegular()/tajawalBold() بدلاً منه).
  Future<void> _printPrescription(Prescription prescription) async {
    setState(() => _printingPrescriptionId = prescription.id);
    try {
      final doctorName = await widget.apiService.authStorage.getDoctorName();
      final clinicName = (doctorName != null && doctorName.trim().isNotEmpty)
          ? 'عيادة ${doctorName.trim()}'
          : 'عيادة الطبيب';

      final regularFont = await PdfGoogleFonts.notoNaskhArabicRegular();
      final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PRESCRIPTION LETTER',
                            style: pw.TextStyle(fontSize: 9, color: PdfColors.indigo700, letterSpacing: 2),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            clinicName,
                            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('اسم المريض: ${_patient.fullName}', style: const pw.TextStyle(fontSize: 11)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'التاريخ: ${_formatPrescriptionDate(prescription.createdAt)}',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  pw.Divider(color: PdfColors.indigo100),
                  pw.SizedBox(height: 18),
                  _pdfInfoBox(
                    title: 'الأدوية والمستحضرات',
                    content: prescription.medications,
                    background: PdfColors.indigo50,
                    border: PdfColors.indigo100,
                    titleColor: PdfColors.indigo900,
                  ),
                  pw.SizedBox(height: 14),
                  _pdfInfoBox(
                    title: 'التعليمات والجرعات',
                    content: prescription.instructions,
                    background: PdfColors.purple50,
                    border: PdfColors.purple100,
                    titleColor: PdfColors.purple900,
                  ),
                  pw.SizedBox(height: 30),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Text(
                      'تطوير وإدارة: المهندس فارس حلاوي © 2026',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.indigo700),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => doc.save());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر تجهيز الوصفة للطباعة. حاول مرة أخرى.')));
    } finally {
      if (mounted) setState(() => _printingPrescriptionId = null);
    }
  }

  pw.Widget _pdfInfoBox({
    required String title,
    required String content,
    required PdfColor background,
    required PdfColor border,
    required PdfColor titleColor,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(color: border),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: titleColor)),
          pw.SizedBox(height: 8),
          pw.Text(content, style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
        ],
      ),
    );
  }

  /// تعديل بيانات المريض الأساسية -- يفتح ورقة سفلية بنفس الحقول التي يعدّلها
  /// زر "تعديل" (editProfileBtn) في patient_record.html: الاسم/الهاتف/العمر/
  /// ملاحظات التاريخ الطبي. طلب المستخدم استبدال زر الاتصال القديم بهذا الزر
  /// 2026-08-29 (لم يكن له مقابل تعديل على الإطلاق في التطبيق من قبل).
  Future<void> _openEditPatientSheet() async {
    final nameController = TextEditingController(text: _patient.fullName);
    final phoneController = TextEditingController(text: _patient.phone);
    final ageController =
        TextEditingController(text: _patient.age?.toString() ?? '');
    final historyController =
        TextEditingController(text: _patient.medicalHistory ?? '');
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isSaving = false;
        String? error;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setSheetState(() {
                isSaving = true;
                error = null;
              });
              DateTime? birthDate;
              final ageText = ageController.text.trim();
              if (ageText.isNotEmpty) {
                // مطابق تماماً لحساب birthDateToSend في savePatientProfile()
                // بالموقع: 1 يناير من سنة الميلاد الموافقة للعمر المُدخَل.
                final parsedAge = int.parse(ageText);
                birthDate = DateTime(DateTime.now().year - parsedAge, 1, 1);
              }
              try {
                final updated = await widget.apiService.updatePatient(
                  _patient.id,
                  fullName: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  medicalHistory: historyController.text.trim(),
                  birthDate: birthDate,
                );
                if (!mounted) return;
                setState(() => _patient = updated);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حفظ التحديثات بنجاح')));
                }
              } on ApiException catch (e) {
                if (e.isSessionExpired) {
                  widget.onSessionExpired();
                  return;
                }
                setSheetState(() {
                  isSaving = false;
                  error = e.message;
                });
              } catch (_) {
                setSheetState(() {
                  isSaving = false;
                  error = 'حدث خطأ أثناء حفظ التعديلات.';
                });
              }
            }

            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.slate200,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const Text(
                        'تعديل بيانات المريض',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(labelText: 'الاسم'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'اسم المريض مطلوب'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'الهاتف'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'رقم الهاتف مطلوب'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ageController,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'العمر'),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty) return null;
                          final parsed = int.tryParse(trimmed);
                          if (parsed == null || parsed < 0) return 'يرجى إدخال عمر صحيح';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: historyController,
                        textAlign: TextAlign.right,
                        maxLines: 4,
                        decoration:
                            const InputDecoration(labelText: 'ملاحظات التاريخ الطبي'),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.rose700text)),
                      ],
                      const SizedBox(height: 18),
                      GradientButton(
                        label: 'حفظ',
                        isLoading: isSaving,
                        onPressed: isSaving ? null : submit,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    phoneController.dispose();
    ageController.dispose();
    historyController.dispose();
  }

  /// تحديث حالة سن واحد -- يبني خريطة chart_state الكاملة (الحالية + التعديل)
  /// لأن الـ backend يستبدل القيمة المخزَّنة بالكامل بما يُرسل، لا يدمجها.
  Future<void> _updateTooth(int fdiNumber, String? statusKey) async {
    final palmerKey = fdiToPalmer[fdiNumber];
    if (palmerKey == null) return;
    final updatedMap = Map<String, String>.from(_patient.chartState);
    if (statusKey == null) {
      updatedMap.remove(palmerKey);
    } else {
      updatedMap[palmerKey] = statusKey;
    }
    setState(() => _savingToothKey = palmerKey);
    try {
      final updatedPatient = await widget.apiService.updatePatientChart(_patient.id, updatedMap);
      if (!mounted) return;
      setState(() => _patient = updatedPatient);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر حفظ حالة السن. حاول مرة أخرى.')));
      }
    } finally {
      if (mounted) setState(() => _savingToothKey = null);
    }
  }

  void _openToothPicker(int fdiNumber) {
    final palmerKey = fdiToPalmer[fdiNumber];
    final currentKey = palmerKey == null ? null : _patient.chartState[palmerKey];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'حالة السن رقم $fdiNumber',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 14),
                ...toothStatusOptions.map((option) {
                  final selected = option.key == currentKey;
                  return ListTile(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _updateTooth(fdiNumber, option.key);
                    },
                    leading: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: option.color, shape: BoxShape.circle),
                    ),
                    title: Text(option.label),
                    trailing: selected ? const Icon(Icons.check, color: AppColors.indigo600) : null,
                  );
                }),
                if (currentKey != null)
                  ListTile(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _updateTooth(fdiNumber, null);
                    },
                    leading: const Icon(Icons.close, color: AppColors.slate500),
                    title: const Text('إزالة الحالة'),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreateInvoiceDialog() async {
    final titleController = TextEditingController();
    final costController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('فاتورة علاج جديدة'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: titleController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'عنوان الفاتورة (نوع العلاج)'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'العنوان مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: costController,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'التكلفة الإجمالية'),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || parsed <= 0) return 'أدخل مبلغاً صحيحاً';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final invoice = await widget.apiService.createInvoice(
                              _patient.id,
                              title: titleController.text.trim(),
                              totalCost: double.parse(costController.text.trim()),
                            );
                            if (!mounted) return;
                            setState(() {
                              _invoices = [invoice, ...(_invoices ?? [])];
                            });
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          } on ApiException catch (e) {
                            if (e.isSessionExpired) {
                              widget.onSessionExpired();
                              return;
                            }
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(e.message)));
                            }
                          } catch (_) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('تعذر إنشاء الفاتورة. حاول مرة أخرى.')));
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('إنشاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openInvoiceDetail(TreatmentInvoice invoice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (sheetContext, scrollController) {
            return _InvoiceDetailSheet(
              invoice: invoice,
              apiService: widget.apiService,
              onSessionExpired: widget.onSessionExpired,
              scrollController: scrollController,
              onInvoiceUpdated: (updated) {
                setState(() {
                  _invoices = (_invoices ?? [])
                      .map((item) => item.id == updated.id ? updated : item)
                      .toList();
                });
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context),
          Transform.translate(
            offset: const Offset(0, -30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 16),
                  _buildChartCard(),
                  const SizedBox(height: 16),
                  _buildArchiveSection(),
                  const SizedBox(height: 16),
                  _buildInvoicesSection(),
                  const SizedBox(height: 16),
                  _buildPrescriptionsSection(),
                  const SizedBox(height: 16),
                  _buildAppointmentsSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 6, 12, 56),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
          ),
          const Expanded(
            child: Text(
              'حالة المريض',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final age = _patient.age;
    // 2026-08-29: بطلب المستخدم -- لا نريد عرض جنس المريض إطلاقاً بجانب
    // الاسم (كانت تظهر كلمة "Male" لأن index.html بالموقع يزرعها تلقائياً
    // عند إنشاء أي مريض جديد، بلا حقل حقيقي لاختيارها). العمود gender نفسه
    // يبقى كما هو بالـ backend والموديل بلا أي حذف -- هذا تعديل عرض فقط.
    final subtitleParts = <String>[
      if (age != null) '$age سنة',
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _openEditPatientSheet,
                icon: const Icon(Icons.edit_outlined, color: AppColors.indigo600),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _patient.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (_patient.phone.isNotEmpty) _patient.phone,
                        if (subtitleParts.isNotEmpty) subtitleParts.join(' · '),
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.slate500, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InitialsAvatar(name: _patient.fullName, size: 52),
            ],
          ),
          if (_patient.medicalHistory != null && _patient.medicalHistory!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.amber50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber200),
              ),
              child: Text(
                _patient.medicalHistory!,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, color: AppColors.amber900text),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.slate200),
          const SizedBox(height: 12),
          Row(
            children: [
              _balanceTile('${_patient.totalTreatmentCost.toStringAsFixed(0)}', 'إجمالي التكلفة',
                  AppColors.slate900),
              _balanceDivider(),
              _balanceTile('${_patient.paidAmount.toStringAsFixed(0)}', 'المدفوع', AppColors.emerald600),
              _balanceDivider(),
              _balanceTile(
                  '${_patientRemainingBalance.toStringAsFixed(0)}', 'المتبقي', AppColors.rose700text),
            ],
          ),
        ],
      ),
    );
  }

  /// 2026-08-30: بطلب المستخدم -- "المتبقي" هنا يجب أن يُحسب بنفس تقنية
  /// الموقع الأساسي تماماً: مجموع (تكلفة كل فاتورة ناقص ما دُفع عليها هي
  /// فقط) لكل فاتورة على حدة، ثم جمع الفواتير التي لها متبقٍ فعلي فقط --
  /// تماماً مثل renderRemainingBalanceBadge() في patient_record.html ومنطق
  /// pending_balances في get_patient_stats() بـ main.py (وهو الإصلاح
  /// الجذري لمشكلة "تداخل الحسابات": فاتورة قديمة مسددة بالكامل -أو حتى
  /// مدفوعة بأكثر من قيمتها بالخطأ- لا يجوز أن "تُخفي" جزءاً مما تبقى على
  /// فاتورة أخرى مفتوحة). أسلوب Patient.remainingBalance القديم (طرح واحد
  /// على مستوى المريض كله: total_treatment_cost - paid_amount) عرضة لهذا
  /// الخطأ بالضبط، فلم يعد يُستخدم هنا -- يبقى فقط كقيمة مؤقتة قبل وصول
  /// الفواتير من السيرفر.
  double get _patientRemainingBalance {
    final invoices = _invoices;
    if (invoices == null) return _patient.remainingBalance;
    double total = 0;
    for (final invoice in invoices) {
      if (invoice.remainingAmount > 0) total += invoice.remainingAmount;
    }
    return total;
  }

  Widget _balanceTile(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text('$value ل.س',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: color)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.slate500)),
        ],
      ),
    );
  }

  Widget _balanceDivider() => Container(width: 1, height: 32, color: AppColors.slate200);

  Widget _buildChartCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Spacer(),
              Text('مخطط الأسنان', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  children: upperArchFdi
                      .map((n) => ToothCell(
                            fdiNumber: n,
                            statusKey: _patient.chartState[fdiToPalmer[n]],
                            isUpper: true,
                            onTap: () => _openToothPicker(n),
                          ))
                      .toList(),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  height: 1,
                  color: AppColors.slate200,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: lowerArchFdi
                      .map((n) => ToothCell(
                            fdiNumber: n,
                            statusKey: _patient.chartState[fdiToPalmer[n]],
                            isUpper: false,
                            onTap: () => _openToothPicker(n),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          if (_savingToothKey != null) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: toothStatusOptions
                .map((option) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration:
                              BoxDecoration(color: option.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text(option.label, style: const TextStyle(fontSize: 10.5, color: AppColors.slate500)),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  /// أرشيف ملفات المريض -- مطابق لقسم "أرشيف ملفات المريض" في
  /// patient_record.html: مربع رفع (تصوير/معرض/PDF بدل السحب-والإفلات غير
  /// المتاح على الجوال) + حقل وصف اختياري + شبكة بطاقات (صور بمعاينة بملء
  /// الشاشة، ومستندات PDF ببطاقة "فتح المستند").
  Widget _buildArchiveSection() {
    final files = _archiveFiles ?? [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: _isUploadingArchive ? null : _pickAndUploadArchiveFile,
                icon: _isUploadingArchive
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(_isUploadingArchive ? 'جاري الرفع...' : 'رفع ملف'),
              ),
              const Spacer(),
              const Text('أرشيف ملفات المريض', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _archiveDescriptionController,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              hintText: 'وصف الملف (اختياري) — مثال: أشعة بانوراما قبل العلاج',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              Text(
                '${files.length} ملف',
                style: const TextStyle(fontSize: 11.5, color: AppColors.slate500, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingArchive)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_archiveError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(_archiveError!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _loadArchive, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          else if (files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'لا توجد ملفات طبية مرفوعة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate500, fontSize: 12.5),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.8,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) => _buildArchiveCard(files[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildArchiveCard(PatientArchiveFile file) {
    final uploadedAt = _formatArchiveDate(file.uploadedAt);

    if (file.isPdf) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openArchiveDocument(file),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.rose700text,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  file.description ?? 'بدون وصف',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.slate500),
                ),
                const Spacer(),
                Text(uploadedAt, style: const TextStyle(fontSize: 9.5, color: AppColors.slate400)),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openArchiveImagePreview(file),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                file.resolvedImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  color: AppColors.slate100,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.slate400),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppColors.slate100,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    uploadedAt,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.slate400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _openCreateInvoiceDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('فاتورة جديدة'),
            ),
            const Spacer(),
            const Text('فواتير العلاج', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingInvoices)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_invoicesError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(_invoicesError!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _loadInvoices, child: const Text('إعادة المحاولة')),
              ],
            ),
          )
        else if ((_invoices ?? []).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('لا توجد فواتير علاج مسجّلة بعد')),
          )
        else
          ...(_invoices ?? []).map((invoice) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openInvoiceDetail(invoice),
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              StatusBadge(
                                label: invoice.isOpen ? 'مفتوحة' : 'مسدَّدة',
                                background: invoice.isOpen ? AppColors.amber100 : AppColors.emerald100,
                                foreground:
                                    invoice.isOpen ? AppColors.amber800text : AppColors.emerald700text,
                              ),
                              const Spacer(),
                              Text(invoice.title,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: invoice.progress,
                              minHeight: 6,
                              backgroundColor: AppColors.slate100,
                              valueColor: const AlwaysStoppedAnimation(AppColors.emerald500),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('الإجمالي ${invoice.totalCost.toStringAsFixed(0)} ل.س',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500)),
                              Text('المتبقي ${invoice.remainingAmount.toStringAsFixed(0)} ل.س',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.rose700text)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
      ],
    );
  }

  /// الوصفات الطبية -- مطابق لقسم "الوصفات الطبية" في patient_record.html:
  /// نموذج إصدار وصفة جديدة (الأدوية + التعليمات، مطلوبان)، شارة عدد
  /// الوصفات، وقائمة الوصفات السابقة مع زر "طباعة" لكل واحدة.
  Widget _buildPrescriptionsSection() {
    final prescriptions = _prescriptions ?? [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('الوصفات الطبية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(
                      'أصدر وصفة جديدة للمريض واحتفظ بسجلها مع إمكانية الطباعة الفورية.',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${prescriptions.length} وصفة',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.indigo700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.purple200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('الأدوية والمستحضرات',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.slate600)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _prescriptionMedicationsController,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'مثال: Amoxicillin 500mg, Paracetamol 500mg',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('التعليمات والجرعات',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.slate600)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _prescriptionInstructionsController,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'مثال: حبة كل 8 ساعات بعد الطعام',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  label: 'إصدار وحفظ الوصفة',
                  onPressed: _isSavingPrescription ? null : _submitPrescription,
                  isLoading: _isSavingPrescription,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_isLoadingPrescriptions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_prescriptionsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(_prescriptionsError!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _loadPrescriptions, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          else if (prescriptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد وصفات طبية مسجلة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate500, fontSize: 12.5),
                ),
              ),
            )
          else
            ...prescriptions.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildPrescriptionCard(p),
                )),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard(Prescription prescription) {
    final isPrinting = _printingPrescriptionId == prescription.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: isPrinting ? null : () => _printPrescription(prescription),
                icon: isPrinting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined, size: 16),
                label: const Text('طباعة'),
              ),
              const Spacer(),
              Text(
                _formatPrescriptionDate(prescription.createdAt),
                style: const TextStyle(fontSize: 11, color: AppColors.slate400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text('الأدوية: ${prescription.medications}',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('التعليمات: ${prescription.instructions}',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.slate600)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoadingAppointments = true;
      _appointmentsError = null;
    });
    try {
      final all = await widget.apiService.fetchAppointments();
      final mine = all.where((appointment) {
        if (appointment.patientId != null) {
          return appointment.patientId == _patient.id;
        }
        return appointment.patientName.trim() == _patient.fullName.trim();
      }).toList()
        ..sort((a, b) {
          final left = a.appointmentDate?.millisecondsSinceEpoch ?? 0;
          final right = b.appointmentDate?.millisecondsSinceEpoch ?? 0;
          return right.compareTo(left);
        });
      if (!mounted) return;
      setState(() {
        _appointments = mine;
        _isLoadingAppointments = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _appointmentsError = e.message;
        _isLoadingAppointments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appointmentsError = 'تعذر تحميل مواعيد المريض. حاول مرة أخرى.';
        _isLoadingAppointments = false;
      });
    }
  }

  /// ورقة سفلية واحدة تُستخدم لكل من الإضافة والتعديل معاً (بخلاف الموقع
  /// الذي يستخدم نافذتين منفصلتين appointmentCreateModal/appointmentEditModal
  /// بنفس الحقول بالضبط: تاريخ + وقت + وصف) -- تبسيطاً للكود مع الحفاظ على
  /// نفس الحقول والتحقق والسلوك سواء بسواء.
  Future<void> _openAppointmentFormSheet({Appointment? existing}) async {
    final isEditing = existing != null;
    String initialDescription = '';
    if (existing != null) {
      final notes = existing.notes?.trim();
      initialDescription = (notes != null && notes.isNotEmpty) ? notes : existing.procedureType;
    }
    final descriptionController = TextEditingController(text: initialDescription);
    DateTime selectedDate = existing?.appointmentDate ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    if (existing != null && existing.appointmentTime.length >= 5) {
      selectedTime = TimeOfDay(
        hour: int.tryParse(existing.appointmentTime.substring(0, 2)) ?? TimeOfDay.now().hour,
        minute: int.tryParse(existing.appointmentTime.substring(3, 5)) ?? TimeOfDay.now().minute,
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isSaving = false;
        String? error;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            String formattedDate() =>
                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
            String formattedTime() =>
                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: sheetContext,
                initialDate: selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null) setSheetState(() => selectedDate = picked);
            }

            Future<void> pickTime() async {
              final picked = await showTimePicker(context: sheetContext, initialTime: selectedTime);
              if (picked != null) setSheetState(() => selectedTime = picked);
            }

            Future<void> submit() async {
              final description = descriptionController.text.trim();
              if (description.isEmpty) {
                setSheetState(() => error = 'يرجى تعبئة وصف الموعد قبل الحفظ.');
                return;
              }
              setSheetState(() {
                isSaving = true;
                error = null;
              });
              final combinedDateTime = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );
              try {
                final appointmentBeingEdited = existing;
                if (appointmentBeingEdited != null) {
                  final updated = await widget.apiService.updateAppointment(
                    appointmentBeingEdited.id,
                    appointmentDateTime: combinedDateTime,
                    time: formattedTime(),
                    description: description,
                  );
                  if (!mounted) return;
                  setState(() {
                    _appointments = (_appointments ?? [])
                        .map((a) => a.id == updated.id ? updated : a)
                        .toList();
                  });
                } else {
                  await widget.apiService.createAppointment(
                    patientId: _patient.id,
                    date: formattedDate(),
                    time: formattedTime(),
                    description: description,
                  );
                  await _loadAppointments();
                }
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isEditing ? 'تم تحديث الموعد بنجاح' : 'تمت إضافة الموعد بنجاح ✨')));
                }
              } on ApiException catch (e) {
                if (e.isSessionExpired) {
                  widget.onSessionExpired();
                  return;
                }
                setSheetState(() {
                  isSaving = false;
                  error = e.message;
                });
              } catch (_) {
                setSheetState(() {
                  isSaving = false;
                  error = isEditing
                      ? 'تعذر تحديث الموعد الآن. يرجى المحاولة لاحقاً.'
                      : 'تعذر إضافة الموعد الآن. يرجى المحاولة لاحقاً.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.slate200,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Text(
                        isEditing ? 'تعديل الموعد' : 'إضافة موعد جديد',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pickDate,
                              child: Text(formattedDate()),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pickTime,
                              child: Text(formattedTime()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'الوصف / الملاحظات'),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.rose700text)),
                      ],
                      const SizedBox(height: 18),
                      GradientButton(
                        label: isEditing ? 'حفظ التعديلات' : 'حفظ الموعد',
                        isLoading: isSaving,
                        onPressed: isSaving ? null : submit,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    descriptionController.dispose();
  }

  Future<void> _confirmDeleteAppointment(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الموعد'),
        content: const Text('هل أنت متأكد من حذف هذا الموعد نهائياً؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف', style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingAppointmentId = appointment.id);
    try {
      await widget.apiService.deleteAppointment(appointment.id);
      if (!mounted) return;
      setState(() {
        _appointments = (_appointments ?? []).where((a) => a.id != appointment.id).toList();
        _deletingAppointmentId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حذف الموعد بنجاح')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() => _deletingAppointmentId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingAppointmentId = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الموعد الآن. يرجى المحاولة لاحقاً.')));
    }
  }

  /// إرسال تذكير عبر واتساب لهاتف المريض المسجَّل -- مطابق تماماً لِـ
  /// openWhatsAppReminder() في patient_record.html (نفس نص الرسالة العربي
  /// حرفياً واسم دالة تطبيع الهاتف).
  Future<void> _sendWhatsappReminder(Appointment appointment) async {
    final normalizedPhone = _normalizeWhatsappPhone(_patient.phone);
    if (normalizedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر إرسال التذكير: رقم هاتف المريض غير متوفر أو غير صالح.')));
      return;
    }

    final doctorName = await widget.apiService.authStorage.getDoctorName();
    final doctorLabel =
        (doctorName != null && doctorName.trim().isNotEmpty) ? doctorName.trim() : 'الطبيب المدخل';
    final appointmentDate = appointment.appointmentDate;
    final dateLabel = appointmentDate != null
        ? '${appointmentDate.day} ${_prescriptionArabicMonthNames[appointmentDate.month - 1]} ${appointmentDate.year}'
        : 'غير محدد';
    final timeLabel =
        appointment.appointmentTime.isNotEmpty ? appointment.appointmentTime : 'غير محدد';
    final message =
        'مرحباً سيد/ة ${_patient.fullName}، نذكركم بموعدكم القادم في العيادة $doctorLabel اليوم '
        '$dateLabel عند الساعة $timeLabel. نتمنى لكم دوام الصحة والعافية. 🦷✨';
    final uri = Uri.parse('https://wa.me/$normalizedPhone?text=${Uri.encodeComponent(message)}');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب.')));
      }
    }
  }

  Widget _buildAppointmentsSection() {
    final appointments = _appointments ?? [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('إدارة مواعيد هذا المريض',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    const Text(
                      'عرض مباشر للمواعيد المرتبطة بهذا الملف مع تعديل سريع للموعد والوصف.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: AppColors.slate500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${appointments.length} موعد',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.indigo700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'إضافة موعد جديد',
            icon: Icons.event_available_outlined,
            onPressed: () => _openAppointmentFormSheet(),
          ),
          const SizedBox(height: 14),
          if (_isLoadingAppointments)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_appointmentsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(_appointmentsError!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _loadAppointments, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          else if (appointments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد مواعيد مسجلة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate500, fontSize: 12.5),
                ),
              ),
            )
          else
            ...appointments.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildAppointmentCard(a),
                )),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment appointment) {
    final style = appointmentStatusStyle(appointment.status);
    final isDeleting = _deletingAppointmentId == appointment.id;
    final dateLabel = appointment.appointmentDate != null
        ? _formatAppointmentDateTime(appointment.appointmentDate!)
        : '—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  appointment.statusLabel,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: style.foreground),
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.slate600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _appointmentDescriptionLabel(appointment),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openAppointmentFormSheet(existing: appointment),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('تعديل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.rose700text,
                    side: const BorderSide(color: AppColors.rose200),
                  ),
                  onPressed: isDeleting ? null : () => _confirmDeleteAppointment(appointment),
                  icon: isDeleting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 15),
                  label: const Text('حذف'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.emerald700text,
                    side: const BorderSide(color: AppColors.emerald100),
                  ),
                  onPressed: () => _sendWhatsappReminder(appointment),
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('واتساب'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ورقة سفلية تعرض تفاصيل فاتورة واحدة وسجل الدفعات الكامل عليها، مع نموذج
/// مصغّر لتسجيل دفعة جديدة -- هذا هو "سجل المدفوعات التفصيلي" الذي طلب
/// المستخدم إضافته بعد رؤية صور الموقع.
class _InvoiceDetailSheet extends StatefulWidget {
  final TreatmentInvoice invoice;
  final ApiService apiService;
  final VoidCallback onSessionExpired;
  final ScrollController scrollController;
  final ValueChanged<TreatmentInvoice> onInvoiceUpdated;

  const _InvoiceDetailSheet({
    required this.invoice,
    required this.apiService,
    required this.onSessionExpired,
    required this.scrollController,
    required this.onInvoiceUpdated,
  });

  @override
  State<_InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends State<_InvoiceDetailSheet> {
  late TreatmentInvoice _invoice;
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;
  String? _error;
  // 2026-08-30: بطلب المستخدم -- يطابق checkbox "تسوية رصيد قديم/سابق" في
  // نموذج تسجيل الدفعة الجديدة في patient_record.html (submitInvoicePayment).
  bool _isOpeningBalance = false;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await widget.apiService.addInvoicePayment(
        _invoice.patientId,
        _invoice.id,
        amount: amount,
        description: _descriptionController.text.trim(),
        isOpeningBalance: _isOpeningBalance,
      );
      if (!mounted) return;
      setState(() {
        _invoice = updated;
        _isSaving = false;
        _amountController.clear();
        _descriptionController.clear();
        _isOpeningBalance = false;
      });
      widget.onInvoiceUpdated(updated);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _isSaving = false;
        _error = 'تعذر تسجيل الدفعة. حاول مرة أخرى.';
      });
    }
  }

  /// تعديل دفعة مسجّلة مسبقاً (في حال أُدخلت بالخطأ) -- مطابق حرفياً لنافذة
  /// "تعديل الدفعة المالية" (financeEditModal) في patient_record.html: نفس
  /// الحقول (المبلغ/الوصف/خانة "رصيد قديم/سابق")، ونفس سلوك إعادة تحميل
  /// فواتير المريض بعد الحفظ لأن تعديل المبلغ قد يغيّر المتبقي على الفاتورة
  /// (PUT /api/finance/transaction/{id} يُرجع رسالة نجاح فقط بلا كائن محدَّث).
  Future<void> _openEditPaymentDialog(InvoicePayment payment) async {
    final amountController =
        TextEditingController(text: payment.amount.toStringAsFixed(0));
    final descriptionController = TextEditingController(text: payment.description);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? error;
        bool isOpeningBalance = payment.isOpeningBalance;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() {
                isSaving = true;
                error = null;
              });
              try {
                await widget.apiService.updateFinanceTransaction(
                  payment.id,
                  amount: double.parse(amountController.text.trim()),
                  description: descriptionController.text.trim(),
                  isOpeningBalance: isOpeningBalance,
                );
                final invoices =
                    await widget.apiService.fetchPatientInvoices(_invoice.patientId);
                final updated = invoices.firstWhere(
                  (item) => item.id == _invoice.id,
                  orElse: () => _invoice,
                );
                if (!mounted) return;
                setState(() => _invoice = updated);
                widget.onInvoiceUpdated(updated);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } on ApiException catch (e) {
                if (e.isSessionExpired) {
                  widget.onSessionExpired();
                  return;
                }
                setDialogState(() {
                  isSaving = false;
                  error = e.message;
                });
              } catch (_) {
                setDialogState(() {
                  isSaving = false;
                  error = 'تعذر تحديث الدفعة المالية. حاول مرة أخرى.';
                });
              }
            }

            return AlertDialog(
              title: const Text('تعديل الدفعة'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: amountController,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'المبلغ'),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || parsed <= 0) return 'أدخل مبلغاً صحيحاً أكبر من صفر';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descriptionController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'الوصف'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'الوصف مطلوب' : null,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () =>
                          setDialogState(() => isOpeningBalance = !isOpeningBalance),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '🕰️ هذه تسوية رصيد قديم/سابق (تُستبعد من تقرير أي شهر محدد، وتبقى ضمن الإجمالي الكلي)',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                            ),
                          ),
                          Checkbox(
                            value: isOpeningBalance,
                            activeColor: AppColors.indigo600,
                            onChanged: (value) =>
                                setDialogState(() => isOpeningBalance = value ?? false),
                          ),
                        ],
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.rose700text, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : submit,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    amountController.dispose();
    descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(_invoice.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'الإجمالي ${_invoice.totalCost.toStringAsFixed(0)} ل.س · المدفوع ${_invoice.paidAmount.toStringAsFixed(0)} ل.س · المتبقي ${_invoice.remainingAmount.toStringAsFixed(0)} ل.س',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('سجل الدفعات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _invoice.payments.isEmpty
                  ? const Center(child: Text('لا توجد دفعات مسجّلة بعد'))
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: _invoice.payments.length,
                      itemBuilder: (context, index) {
                        final payment = _invoice.payments[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined, color: AppColors.emerald600),
                          title: Text('${payment.amount.toStringAsFixed(0)} ل.س',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            payment.description.isEmpty
                                ? (payment.isOpeningBalance ? 'رصيد افتتاحي' : '—')
                                : payment.description,
                          ),
                          // 2026-08-30: بطلب المستخدم -- الضغط على أي دفعة يتيح
                          // تعديلها في حال أُدخلت بالخطأ، مطابق لزر "تعديل" في
                          // patient_record.html (نفس financeEditModal المُعاد
                          // استخدامه هناك لكل من السجل المالي العام ودفعات
                          // الفواتير معاً).
                          onTap: () => _openEditPaymentDialog(payment),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit_outlined, size: 14, color: AppColors.indigo600),
                              const SizedBox(width: 4),
                              Text(
                                '${payment.createdAt.year}/${payment.createdAt.month}/${payment.createdAt.day}',
                                style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 20),
            if (_invoice.isOpen) ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _descriptionController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(hintText: 'وصف (اختياري)', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'المبلغ', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    setState(() => _isOpeningBalance = !_isOpeningBalance),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '🕰️ هذه تسوية رصيد قديم/سابق (لن تُحتسب ضمن دخل الشهر الحالي في التقارير)',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                      ),
                    ),
                    Checkbox(
                      value: _isOpeningBalance,
                      activeColor: AppColors.indigo600,
                      onChanged: (value) =>
                          setState(() => _isOpeningBalance = value ?? false),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(color: AppColors.rose700text, fontSize: 12)),
              ],
              const SizedBox(height: 10),
              GradientButton(
                label: 'تسجيل الدفعة',
                onPressed: _isSaving ? null : _addPayment,
                isLoading: _isSaving,
                gradient: AppColors.successButtonGradient,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
