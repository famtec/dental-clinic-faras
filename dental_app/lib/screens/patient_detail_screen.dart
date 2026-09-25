import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment.dart';
import '../models/inventory_item.dart';
import '../models/patient.dart';
import '../models/patient_archive_file.dart';
import '../models/pending_payment.dart';
import '../models/prescription.dart';
import '../models/treatment_catalog_item.dart';
import '../models/treatment_invoice.dart';
import '../services/api_service.dart';
import '../services/app_session.dart';
import '../services/media_picker.dart';
import '../theme/app_theme.dart';
import '../utils/appointment_status.dart';
import '../utils/dental_chart.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_widgets.dart';
import '../widgets/clinic_doctor_field.dart';
import '../widgets/desktop_widgets.dart';
import '../widgets/finance_review_panel.dart';
import '../widgets/tooth_widget.dart';
import 'tooth_status_screen.dart';

part 'patient_detail_desktop.dart';

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

  /// أطباء العيادة لحقل «الطبيب المعالج» في ورقة التعديل -- تُحمَّل عند أول
  /// فتح للورقة وتُحفَظ لبقية عمر الشاشة.
  ClinicDoctorChoices? _doctorChoices;
  List<TreatmentInvoice>? _invoices;
  String? _invoicesError;
  bool _isLoadingInvoices = true;
  String? _savingToothKey;
  /// الربع المعروض في المخطط (1..4 بترميز FDI). المخطط الكامل (32 سناً في
  /// صفّين) كان يفرض خلايا صغيرة جداً على شاشة الهاتف؛ عرض الأرباع يكبّر
  /// ثمانية أسنان فقط في كل مرة -- نفس ما فُعل في patient_record.html.
  int _activeQuadrant = 1;

  /// «تحديد عدة أسنان» (2026-09-25): الضغط على السن يحدّده بدل فتح لوحته،
  /// ثم تُطبَّق حالة واحدة على كل المحدَّد بطلب حفظ واحد (chart_state كاملاً).
  /// التحديد يبقى عند التنقّل بين الأرباع -- الجسر قد يعبر خط المنتصف.
  bool _multiSelect = false;
  final Set<int> _selectedTeeth = <int>{};
  bool _bulkSaving = false;

  // 2026-08-30: أرشيف ملفات المريض (صور/أشعة أو مستندات PDF) -- بطلب
  // المستخدم "اضف امكانية أرشيف ملفات المريض مثل التي في الموقع تماما"،
  // مطابق لقسم "أرشيف ملفات المريض" في patient_record.html.
  List<PatientArchiveFile>? _archiveFiles;
  String? _archiveError;
  bool _isLoadingArchive = true;
  bool _isUploadingArchive = false;
  int? _deletingArchiveId;
  final _archiveDescriptionController = TextEditingController();
  // 2026-09-10: أُزيل حقل ImagePicker من هنا؛ الاختيار يمرّ عبر
  // services/media_picker.dart ليعمل على ويندوز أيضاً.

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
    final surf = context.surface;
    final choice = await showAppSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BottomSheetOnly(
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: surf.cardBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const Text(
              'رفع ملف طبي',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            // 2026-09-10: خيار الكاميرا يظهر على الجوال فقط -- ويندوز لا يملك
            // ImageSource.camera، وعرض خيار يفشل عند الضغط عليه أسوأ من
            // إخفائه.
            if (supportsCameraCapture)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  onTap: () => Navigator.of(sheetContext).pop('camera'),
                  leading: const Icon(Icons.photo_camera_outlined, color: AppColors.indigo700),
                  title: const Text('تصوير بالكاميرا', textAlign: TextAlign.right),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                onTap: () => Navigator.of(sheetContext).pop('gallery'),
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.indigo700),
                title: Text(
                  supportsCameraCapture
                      ? 'اختيار صورة من المعرض'
                      : 'اختيار صورة من الجهاز',
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                onTap: () => Navigator.of(sheetContext).pop('pdf'),
                leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.indigo700),
                title: const Text('اختيار مستند PDF', textAlign: TextAlign.right),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    List<int>? bytes;
    String? filename;

    try {
      // 2026-09-10: مرّ الاختيار كله عبر services/media_picker.dart بدل
      // استدعاء FilePicker/ImagePicker هنا مباشرة -- هو من يقرر أي آلية
      // تناسب المنصّة (كاميرا/معرض على الجوال، حوار ملفات ويندوز على سطح
      // المكتب) ويرجع بايتات + اسم ملف موحّدَين.
      final PickedMedia? picked = choice == 'pdf'
          ? await pickPdfFromDevice()
          : await pickImageFromDevice(
              source: choice == 'camera'
                  ? ImageSource.camera
                  : ImageSource.gallery,
            );
      if (picked == null) return;
      bytes = picked.bytes;
      filename = picked.name;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supportsCameraCapture
                ? 'تعذر فتح الكاميرا/المعرض/متصفح الملفات.'
                : 'تعذر فتح نافذة اختيار الملفات.',
          ),
        ),
      );
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

  /// حذف ملف من أرشيف المريض بعد تأكيد -- يُستدعى بالضغط المطوّل على بطاقة
  /// الملف (صورة/أشعة أو PDF)، بنفس أسلوب مربع تأكيد الحذف المستخدم مسبقاً
  /// في التطبيق (انظر _confirmDeleteAppointment أعلاه) للحفاظ على تناسق
  /// التصميم. يستدعي DELETE /api/patients/{id}/archive/{archive_id} في
  /// main.py (delete_patient_archive) الموجود مسبقاً في الـ backend.
  Future<void> _confirmDeleteArchiveFile(PatientArchiveFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الملف الطبي'),
        content: Text(
          'هل أنت متأكد من حذف "${file.fileName}" نهائياً؟ لا يمكن التراجع عن هذا الإجراء.',
          textAlign: TextAlign.right,
        ),
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

    setState(() => _deletingArchiveId = file.id);
    try {
      await widget.apiService.deletePatientArchiveFile(_patient.id, file.id);
      if (!mounted) return;
      setState(() {
        _archiveFiles = (_archiveFiles ?? []).where((f) => f.id != file.id).toList();
        _deletingArchiveId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حذف الملف الطبي بنجاح')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() => _deletingArchiveId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingArchiveId = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الملف الطبي الآن. يرجى المحاولة لاحقاً.')));
    }
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

  /// خط الوصفة يُقرأ من ملفات مرفقة داخل التطبيق بدل تنزيله وقت الطباعة.
  ///
  /// **هذا إصلاح حقيقي لا مجرد تهيئة لويندوز:** كان الكود يستدعي
  /// `PdfGoogleFonts.notoNaskhArabic*()`، وهي تُنزّل الخط من الإنترنت عند أول
  /// طباعة. أي أن طباعة وصفة على جهاز بلا اتصال كانت تفشل -- وهو أسوأ توقيت
  /// ممكن للفشل في تطبيق يُفترض أنه يعمل أوفلاين، والمريض واقف أمام الطبيب.
  /// الملفات الآن ضمن مجلد `google_fonts/` المرفق (انظر pubspec.yaml).
  Future<pw.Font> _loadPrescriptionFont(String fileName) async {
    final data = await rootBundle.load('google_fonts/$fileName.ttf');
    return pw.Font.ttf(data);
  }

  /// طباعة/مشاركة وصفة كملف PDF -- بديل الجوال لنافذة طباعة المتصفح
  /// (window.print على #prescriptionPrintTemplate) في patient_record.html.
  /// يبني نفس محتوى القالب: اسم العيادة (من doctor_name المحفوظ محلياً، نفس
  /// منطق populatePrescriptionPrintTemplate)، اسم المريض، التاريخ، صندوقا
  /// الأدوية والتعليمات، وسطر الحقوق السفلي -- بخط Noto Naskh Arabic، وهو خط
  /// عربي كامل الدعم مناسب للنص المطبوع (خطّا الواجهة Noto Kufi/Noto Sans
  /// مصمَّمان للشاشة). 2026-09-10: صار يُقرأ من ملف مرفق داخل التطبيق عبر
  /// [_loadPrescriptionFont] بدل تنزيله من الإنترنت -- انظر شرح السبب هناك.
  Future<void> _printPrescription(Prescription prescription) async {
    setState(() => _printingPrescriptionId = prescription.id);
    try {
      final doctorName = await widget.apiService.authStorage.getDoctorName();
      final clinicName = (doctorName != null && doctorName.trim().isNotEmpty)
          ? 'عيادة ${doctorName.trim()}'
          : 'عيادة الطبيب';

      final regularFont = await _loadPrescriptionFont('NotoNaskhArabic-Regular');
      final boldFont = await _loadPrescriptionFont('NotoNaskhArabic-Bold');

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
    // أطباء العيادة لحقل «الطبيب المعالج» -- يُطلَبون عند أول فتح للورقة لا
    // مع فتح ملف المريض، فتصفّح الملفات لا يطلق طلباً لا يُستعمل.
    final doctorChoices =
        _doctorChoices ??= await ClinicDoctorChoices.load(widget.apiService);
    if (!mounted) return;
    final surf = context.surface;
    int? selectedDoctorId = _patient.clinicDoctorId;
    final nameController = TextEditingController(text: _patient.fullName);
    final phoneController = TextEditingController(text: _patient.phone);
    final ageController =
        TextEditingController(text: _patient.age?.toString() ?? '');
    final historyController =
        TextEditingController(text: _patient.medicalHistory ?? '');
    final formKey = GlobalKey<FormState>();

    await showAppSheet<void>(
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
                  // يُرسَل الطبيب فقط حين يظهر حقله -- عيادة بطبيب واحد لا
                  // تمسّ ما على الخادم (انظر ApiService.updatePatient).
                  clinicDoctorId: selectedDoctorId,
                  sendClinicDoctor: !doctorChoices.isEmpty,
                  clinicDoctorNameHint: doctorChoices.nameFor(selectedDoctorId),
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
                decoration: BoxDecoration(
                  color: surf.sheetBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BottomSheetOnly(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: surf.cardBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
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
                      if (!doctorChoices.isEmpty) ...[
                        const SizedBox(height: 12),
                        ClinicDoctorDropdown(
                          choices: doctorChoices,
                          value: selectedDoctorId,
                          currentDoctorName: _patient.clinicDoctorName,
                          onChanged: (id) =>
                              setSheetState(() => selectedDoctorId = id),
                        ),
                      ],
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
  ///
  /// 2026-08-30: يعيد الآن true عند نجاح الحفظ الفعلي وfalse عند أي فشل --
  /// القيمة المُعادة تُستخدم من قسم "الحالة المخصصة" الجديد في
  /// _openToothPicker لتقرير ما إذا كانت الورقة السفلية تُغلَق تلقائياً
  /// (نجاح) أو تبقى مفتوحة مع رسالة خطأ (فشل)، تماماً كسلوك toothStatusModal
  /// في الموقع. استدعاءات اختيار حالة جاهزة/إزالة الحالة تتجاهل القيمة
  /// المُعادة كما كانت (سلوكهما لم يتغيّر).
  Future<bool> _updateTooth(int fdiNumber, String? statusKey) async {
    final palmerKey = fdiToPalmer[fdiNumber];
    if (palmerKey == null) return false;
    final updatedMap = Map<String, String>.from(_patient.chartState);
    if (statusKey == null) {
      updatedMap.remove(palmerKey);
    } else {
      updatedMap[palmerKey] = statusKey;
    }
    setState(() => _savingToothKey = palmerKey);
    var success = false;
    try {
      final updatedPatient = await widget.apiService.updatePatientChart(_patient.id, updatedMap);
      if (!mounted) return false;
      setState(() => _patient = updatedPatient);
      success = true;
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return false;
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
    return success;
  }

  /// نافذة "تحديث حالة السن" -- أُعيد تصميمها بالكامل 2026-08-30 لتطابق
  /// toothStatusModal في patient_record.html بالموقع بالضبط: شبكة من 8
  /// بطاقات ملوّنة (نفس ألوان/ترتيب/تسميات TOOTH_STATUS_OPTIONS)، ثم قسم
  /// "حالة مخصصة" باسم حر ولون من نفس اللوحة، محفوظ بنفس صيغة الموقع
  /// (custom:<اسم>|<لون>) حتى تتوافق الحالة أياً كانت الجهة التي أنشأتها.
  /// "إزالة الحالة الحالية" ليست موجودة في نافذة الموقع أصلاً، لكن أُبقيت
  /// هنا (بشكل ثانوي أسفل النافذة) لأنها ميزة مفيدة قائمة سلفاً في التطبيق
  /// ولا تعارض التصميم المطلوب مطابقته.
  /// شاشة السن الكاملة (الخيار ب) -- بديل الورقة السفلية على الجوال.
  /// تبقى مفتوحة بعد كل حفظ ليتمكّن الطبيب من تسجيل عدة أسنان متتالية،
  /// وتقرأ حالة المخطط حيّةً من هذه الشاشة بعد كل حفظ ناجح.
  Future<void> _openToothScreen(int fdiNumber) async {
    // سطح المكتب: نافذة حوار في الوسط لا صفحة بملء النافذة -- الشاشة نفسها
    // تبني تخطيطها المزدوج فوق العتبة (ToothStatusScreen._buildDesktop).
    if (context.isDesktopShell) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940, maxHeight: 640),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ToothStatusScreen(
                initialFdi: fdiNumber,
                chartStateReader: () => _patient.chartState,
                onSave: _updateTooth,
              ),
            ),
          ),
        ),
      );
      if (mounted) setState(() {});
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ToothStatusScreen(
          initialFdi: fdiNumber,
          chartStateReader: () => _patient.chartState,
          onSave: _updateTooth,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ignore: unused_element
  void _openToothPicker(int fdiNumber) {
    final surf = context.surface;
    final palmerKey = fdiToPalmer[fdiNumber];
    final currentKey = palmerKey == null ? null : _patient.chartState[palmerKey];
    final customEntry = decodeCustomToothStatus(currentKey);
    final customLabelController = TextEditingController(text: customEntry?.label ?? '');
    ToothStatusOption? selectedCustomColorOption =
        customEntry != null ? toothStatusByHex(customEntry.hex) : null;
    var isSavingCustom = false;
    var hintText = 'اختر الحالة السنية المناسبة وسيتم حفظها فورًا على الملف السحابي.';

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> handlePresetTap(String key) async {
              Navigator.of(sheetContext).pop();
              await _updateTooth(fdiNumber, key);
            }

            Future<void> handleRemove() async {
              Navigator.of(sheetContext).pop();
              await _updateTooth(fdiNumber, null);
            }

            Future<void> handleSaveCustom() async {
              final label = customLabelController.text.trim();
              if (label.isEmpty) {
                setSheetState(() => hintText = 'يرجى إدخال اسم الحالة أولاً.');
                return;
              }
              final colorOption = selectedCustomColorOption;
              if (colorOption == null) {
                setSheetState(() => hintText = 'يرجى اختيار لون للحالة المخصصة.');
                return;
              }
              setSheetState(() {
                isSavingCustom = true;
                hintText = 'جاري حفظ التحديث...';
              });
              final ok = await _updateTooth(
                  fdiNumber, encodeCustomToothStatus(label, colorOption.hex));
              if (ok) {
                Navigator.of(sheetContext).pop();
              } else {
                setSheetState(() {
                  isSavingCustom = false;
                  hintText = 'تعذر الحفظ الآن. أعد المحاولة بعد قليل.';
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    18, 16, 18, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
                child: SingleChildScrollView(
                  // 2026-08-30 (تصغير/ترتيب): يُحدَّد أقصى عرض للمحتوى ويُوضع
                  // في المنتصف -- على شاشة هاتف حقيقية هذا لا يُغيّر شيئاً
                  // (العرض المتاح أصلاً أضيق من الحد الأقصى)، لكنه يمنع
                  // الورقة من التمدد لتملأ نافذة متصفح سطح مكتب عريضة أثناء
                  // اختبار `flutter run -d chrome` فتبدو البطاقات ضخمة --
                  // بهذا تبقى نسب التصميم كما لو كانت على هاتف دائماً.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'تحديث حالة السن',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.indigoAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'السن $fdiNumber',
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        color: surf.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Material(
                                color: surf.chipBg,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => Navigator.of(sheetContext).pop(),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    child: Text(
                                      'إغلاق',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: surf.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'اختر الحالة السنية المناسبة وسيتم حفظها فورًا على الملف السحابي.',
                            style: TextStyle(fontSize: 12, height: 1.5, color: surf.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.5,
                            children: toothStatusOptions
                                .map((option) => _ToothStatusCard(
                                      option: option,
                                      onTap: () => handlePresetTap(option.key),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 14),
                          Container(height: 1, color: surf.chipBg),
                          const SizedBox(height: 10),
                          Text(
                            'أو أضف حالة مخصصة باسم ولون من اختيارك',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: surf.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: customLabelController,
                            maxLength: 40,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              hintText: 'مثال: كسر، تنظيف، تلميع...',
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: toothStatusOptions
                                .map((option) => _CustomColorSwatch(
                                      color: option.color,
                                      selected: selectedCustomColorOption?.key == option.key,
                                      onTap: () => setSheetState(
                                          () => selectedCustomColorOption = option),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: 'حفظ الحالة المخصصة',
                            isLoading: isSavingCustom,
                            onPressed: isSavingCustom ? null : handleSaveCustom,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hintText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: surf.textSecondary,
                            ),
                          ),
                          if (currentKey != null) ...[
                            const SizedBox(height: 2),
                            Center(
                              child: TextButton.icon(
                                onPressed: handleRemove,
                                icon: Icon(Icons.close,
                                    size: 15, color: surf.textSecondary),
                                label: Text(
                                  'إزالة الحالة الحالية',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: surf.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(customLabelController.dispose);
  }

  /// منتقي الحالة من لائحة الأسعار. الحالات المعطَّلة لا تُعرَض: تعطيلها
  /// يعني تحديداً "أخرِجها من قوائم الاختيار واحفظ تاريخها".
  ///
  /// فشل التحميل يُعرَض ولا يُبطِل النافذة: كتابة الفاتورة يدوياً تبقى
  /// الطريق الأصلي وتعمل بلا اللائحة إطلاقاً.
  Future<TreatmentCatalogItem?> _pickCatalogItem() async {
    List<TreatmentCatalogItem> items;
    try {
      items = await widget.apiService.fetchTreatmentCatalog(includeInactive: false);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return null;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر تحميل لائحة الأسعار. اكتب الفاتورة يدوياً.')));
      }
      return null;
    }
    if (!mounted) return null;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'لا حالات مفعَّلة في اللائحة. أضِفها من «لائحة أسعار العلاجات».')));
      return null;
    }
    return showAppSheet<TreatmentCatalogItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final surf = sheetContext.surface;
        return Container(
          decoration: BoxDecoration(
            color: surf.sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BottomSheetOnly(
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: surf.divider,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('اختر الحالة العلاجية',
                    textAlign: TextAlign.center,
                    style: AppType.kufi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: surf.textPrimary)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: surf.divider, height: 12),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => Navigator.of(sheetContext).pop(item),
                          title: Text(item.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: surf.textPrimary)),
                          subtitle: Text(
                            item.hasMaterials
                                ? '${item.materials.length} مادة · تكلفة ${item.materialsCost.toStringAsFixed(0)} ل.س'
                                : 'بلا مواد مرتبطة',
                            style: TextStyle(fontSize: 11.5, color: surf.textMuted),
                          ),
                          trailing: Text('${item.price.toStringAsFixed(0)} ل.س',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.indigo700)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreateInvoiceDialog() async {
    // 2026-09-25: الطبيب المنفّذ يُختار هنا ويبدأ بطبيب المريض المعالج --
    // كانت فواتير التطبيق كلها تُنسب للمدير فيخسر المساعد نسبته بصمت.
    final doctorChoices =
        _doctorChoices ??= await ClinicDoctorChoices.load(widget.apiService);
    if (!mounted) return;
    int? invoiceDoctorId = doctorChoices.nameFor(_patient.clinicDoctorId) != null
        ? _patient.clinicDoctorId
        : null;
    final titleController = TextEditingController();
    final costController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    // 2026-09-18: الحالة المختارة من لائحة الأسعار. مرجع للقراءة فقط --
    // العنوان والتكلفة يُرسَلان كأي فاتورة ويُجمَّدان عليها، فتعديل سعر
    // الحالة في اللائحة لاحقاً لا يمسّ هذه الفاتورة.
    int? catalogItemId;
    var materials = <InvoiceMaterialInput>[];
    String? materialsLabel;

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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final picked = await _pickCatalogItem();
                                if (picked == null) return;
                                setDialogState(() {
                                  catalogItemId = picked.id;
                                  titleController.text = picked.name;
                                  costController.text =
                                      picked.price.toStringAsFixed(0);
                                  // وصفة الحالة تُنسَخ كمُدخَل قابل للتعديل،
                                  // لا كمرجع حيّ إليها: ما يُخصَم هو ما يراه
                                  // الطبيب في هذه النافذة الآن.
                                  materials = [
                                    for (final material in picked.materials)
                                      InvoiceMaterialInput(
                                        inventoryItemId: material.inventoryItemId,
                                        itemName: material.itemName,
                                        quantity: material.quantity,
                                      ),
                                  ];
                                  materialsLabel = picked.materials.isEmpty
                                      ? null
                                      : picked.materials
                                          .map((m) => '${m.itemName} × ${m.quantity}')
                                          .join(' · ');
                                });
                              },
                        icon: const Icon(Icons.price_change_outlined, size: 18),
                        label: const Text('اختر من لائحة الأسعار'),
                      ),
                    ),
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
                    if (!doctorChoices.isEmpty) ...[
                      const SizedBox(height: 12),
                      ClinicDoctorDropdown(
                        choices: doctorChoices,
                        value: invoiceDoctorId,
                        label: 'الطبيب المنفّذ (تُحسب نسبته من دفعاتها)',
                        onChanged: (value) => setDialogState(() => invoiceDoctorId = value),
                      ),
                    ],
                    if (materialsLabel != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: context.surface.warnBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.surface.warnBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('ستُخصَم من المخزن مع إنشاء الفاتورة:',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: context.surface.warnFg)),
                            const SizedBox(height: 3),
                            Text(materialsLabel!,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.surface.warnFg,
                                    height: 1.6)),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: isSaving
                                    ? null
                                    : () => setDialogState(() {
                                          materials = <InvoiceMaterialInput>[];
                                          materialsLabel = null;
                                        }),
                                child: const Text('افتح الفاتورة بلا خصم مواد'),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                              catalogItemId: catalogItemId,
                              clinicDoctorId: invoiceDoctorId,
                              sendClinicDoctor: !doctorChoices.isEmpty,
                              materials: materials.isEmpty ? null : materials,
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
    showAppSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // في حوار سطح المكتب لا سحب بالفأرة: الورقة بارتفاع الحوار كاملاً.
        final desktop = AppSheetScope.isDialog(sheetContext);
        return DraggableScrollableSheet(
          initialChildSize: desktop ? 1 : 0.7,
          minChildSize: desktop ? 1 : 0.4,
          maxChildSize: desktop ? 1 : 0.92,
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
    if (context.isDesktopShell) return _buildDesktop(context);
    final surf = context.surface;
    return Scaffold(
      backgroundColor: surf.pageBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context),
          const OfflineSyncBanner(),
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
    return AnimatedHeroHeader(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 6, 12, 56),
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
    final surf = context.surface;
    final age = _patient.age;
    // 2026-08-29: بطلب المستخدم -- لا نريد عرض جنس المريض إطلاقاً بجانب
    // الاسم (كانت تظهر كلمة "Male" لأن index.html بالموقع يزرعها تلقائياً
    // عند إنشاء أي مريض جديد، بلا حقل حقيقي لاختيارها). العمود gender نفسه
    // يبقى كما هو بالـ backend والموديل بلا أي حذف -- هذا تعديل عرض فقط.
    final subtitleParts = <String>[
      if (age != null) '$age سنة',
    ];
    // opaque: البطاقة مسحوبة 30px فوق الترويسة المتدرّجة (Transform.translate
    // في build)، والزجاج الشفّاف كان يُظهر البنفسجي من خلال نصفها العلوي
    // ويتوقّف فجأة عند حدّ الترويسة فتبدو مقطوعة أفقياً.
    return SectionCard(
      opaque: true,
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
                // CrossAxisAlignment.start -- تحت اتجاه RTL العام للتطبيق
                // (main.dart) "start" = يمين، وليس .end كما كان سابقاً (.end
                // = يسار فعلياً) -- كان هذا سبب ظهور اسم المريض وهاتفه
                // ملتصقين بالحافة اليسرى لعمود Expanded الواسع بدل حافته
                // اليمنى الملاصقة لأيقونة التعديل، فيبدوان "مكتوبين من
                // اليسار لليمين". أُصلح 2026-08-31.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _patient.fullName,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                          ),
                        ),
                        // مريض أُنشئ/عُدِّلت بياناته أو مخطط أسنانه أوفلاين
                        // وما زال بانتظار الاتصال بالإنترنت -- انظر
                        // OfflineAwareApiService. أُضيف 2026-09-02.
                        if (_patient.isPendingSync) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.cloud_off_outlined,
                              size: 15, color: AppColors.amber900),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (_patient.phone.isNotEmpty) _patient.phone,
                        if (subtitleParts.isNotEmpty) subtitleParts.join(' · '),
                      ].join(' · '),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: surf.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // بلا تدرّج كان يستعمل الخلفية الافتراضية indigo50 -- قرص
              // أبيض ساطع على سطح داكن. نفس تدرّج بطاقة المريض في القائمة.
              InitialsAvatar(
                name: _patient.fullName,
                size: 52,
                borderRadius: 18,
                spacedInitials: true,
                gradient: AppColors.primaryButtonGradient,
                foreground: Colors.white,
              ),
            ],
          ),
          if (_patient.medicalHistory != null && _patient.medicalHistory!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: surf.warnBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: surf.warnBorder),
              ),
              child: Text(
                _patient.medicalHistory!,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: surf.warnFg),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: surf.cardBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              _balanceTile('${_patient.totalTreatmentCost.toStringAsFixed(0)}', 'إجمالي التكلفة',
                  surf.textPrimary),
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
    final surf = context.surface;
    return Expanded(
      child: Column(
        children: [
          Text('$value ل.س',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: color)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, color: surf.textSecondary)),
        ],
      ),
    );
  }

  Widget _balanceDivider() {
    final surf = context.surface;
    return Container(width: 1, height: 32, color: surf.cardBorder);
  }

  /// أرقام أسنان ربع واحد بترتيب عرضه على الشاشة -- الربعان الأيمنان
  /// يُقرآن تنازلياً (18←11 و48←41) تماماً كصفّي المخطط الكامل.
  List<int> _quadrantFdiList(int quadrant) {
    final list = List<int>.generate(8, (i) => quadrant * 10 + i + 1);
    return (quadrant == 1 || quadrant == 4) ? list.reversed.toList() : list;
  }

  /// خريطة الفم كاملاً بأسنان مصغّرة ملوّنة حسب الحالة، والربع المحدَّد
  /// مؤطَّر -- تعطي الطبيب الصورة الكلية دون أن يفقدها عند تكبير ربع واحد.
  /// (2026-09-25) أسنان بنفس الرسم التشريحي بدل مستطيلات، تيجان الفكّين
  /// متقابلة عند خط الإطباق كما في الفم؛ والضغط على أي ربع يفتحه في الأسفل.
  Widget _buildMouthOverview() {
    final surf = context.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget chipsRow(List<int> quadrants) {
      return Row(
        children: [
          for (var i = 0; i < quadrants.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _activeQuadrant = quadrants[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                    decoration: BoxDecoration(
                      color: _activeQuadrant == quadrants[i]
                          ? (dark
                              ? AppColors.indigoAccent.withValues(alpha: .16)
                              : const Color(0xFFE0E7FF))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _activeQuadrant == quadrants[i]
                            ? (dark
                                ? AppColors.indigoAccent.withValues(alpha: .55)
                                : const Color(0xFFA5B4FC))
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final fdi in _quadrantFdiList(quadrants[i]))
                          Expanded(child: _overviewChip(fdi)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 9),
      decoration: BoxDecoration(
        color: surf.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: surf.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            'الفم كاملاً — الربع المحدَّد مؤطَّر',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: surf.textMuted),
          ),
          const SizedBox(height: 8),
          // dir=ltr حتى يقع الربع الأول يساراً والثاني يميناً كما في المخطط
          // الكامل وكما في الموقع -- داخل RTL ينعكس الترتيب ويظهر مقلوباً.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                chipsRow(const [1, 2]),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  height: 1,
                  color: AppColors.rose200,
                ),
                chipsRow(const [4, 3]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewChip(int fdi) {
    final raw = _patient.chartState[fdiToPalmer[fdi]];
    // الارتفاع من عرض الخانة (نسبة السن 44:78): ~30px في الجوال، وأكبر قليلاً
    // على سطح المكتب حيث الخانة أعرض -- بسقف حتى لا تطول الخريطة.
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: (constraints.maxWidth * 1.75).clamp(26.0, 46.0),
        child: CustomPaint(
          painter: ToothShapePainter(
            fdi: fdi,
            statusColor: resolveToothStatus(raw)?.color,
            statusKey: resolveToothStatusKey(raw),
            outline: _selectedTeeth.contains(fdi) ? AppColors.indigoAccent : null,
            glow: _selectedTeeth.contains(fdi) ? .5 : 0,
            glowColor: AppColors.indigoAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildQuadrantTabs() {
    final surf = context.surface;
    const labels = {
      1: 'علوي يمين',
      2: 'علوي يسار',
      3: 'سفلي يسار',
      4: 'سفلي يمين',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: surf.chipBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final quadrant in const [1, 2, 3, 4])
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _activeQuadrant = quadrant),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _activeQuadrant == quadrant
                          ? AppColors.primaryButtonGradient
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _activeQuadrant == quadrant
                          ? [
                              BoxShadow(
                                color: AppColors.indigoAccent.withValues(alpha: .32),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[quadrant]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _activeQuadrant == quadrant
                            ? Colors.white
                            : surf.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuadrantTeeth() {
    final surf = context.surface;
    final isUpper = _activeQuadrant == 1 || _activeQuadrant == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      decoration: BoxDecoration(
        color: surf.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: surf.cardBorder),
      ),
      child: Column(
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                for (final fdi in _quadrantFdiList(_activeQuadrant))
                  Expanded(
                    child: ToothCell(
                      fdiNumber: fdi,
                      statusKey: _patient.chartState[fdiToPalmer[fdi]],
                      isUpper: isUpper,
                      // أكبر من السابق (30×48) ليظهر تشريح السن الجديد؛ على
                      // سطح المكتب بمقاس لوحة الرسم الكامل.
                      shapeWidth: context.isDesktopShell ? 44 : 34,
                      shapeHeight: context.isDesktopShell ? 78 : 60,
                      numberFontSize: 10.5,
                      selected: _selectedTeeth.contains(fdi),
                      onTap: () => _multiSelect
                          ? _toggleToothSelection(fdi)
                          : _openToothScreen(fdi),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _multiSelect
                ? 'اضغط الأسنان لتحديدها — ويمكنك التنقّل بين الأرباع'
                : 'اضغط أي سن لفتح لوحة الحالة',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: surf.textMuted),
          ),
        ],
      ),
    );
  }

  void _toggleMultiSelect() {
    setState(() {
      _multiSelect = !_multiSelect;
      _selectedTeeth.clear();
    });
  }

  void _toggleToothSelection(int fdi) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedTeeth.remove(fdi)) _selectedTeeth.add(fdi);
    });
  }

  /// الربع المفتوح كاملاً: يحدّد أسنانه الثمانية، أو يلغيها إن كانت كلها محدَّدة.
  void _toggleQuadrantSelection() {
    final teeth = _quadrantFdiList(_activeQuadrant);
    HapticFeedback.selectionClick();
    setState(() {
      if (teeth.every(_selectedTeeth.contains)) {
        _selectedTeeth.removeAll(teeth);
      } else {
        _selectedTeeth.addAll(teeth);
      }
    });
  }

  static String _selectedTeethLabel(int n) {
    if (n == 1) return 'سن واحد محدَّد';
    if (n == 2) return 'سنّان محدَّدان';
    if (n <= 10) return '$n أسنان محدَّدة';
    return '$n سنّاً محدَّداً';
  }

  static String _updatedTeethLabel(int n) {
    if (n == 1) return 'تم تحديث حالة سن واحد';
    if (n == 2) return 'تم تحديث حالة سنّين';
    if (n <= 10) return 'تم تحديث حالة $n أسنان';
    return 'تم تحديث حالة $n سنّاً';
  }

  Widget _buildBulkBar() {
    final surf = context.surface;
    final count = _selectedTeeth.length;
    final quadrantFull = _quadrantFdiList(_activeQuadrant).every(_selectedTeeth.contains);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.indigoAccent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.indigoAccent.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == 0 ? 'لم تحدِّد أسناناً بعد' : _selectedTeethLabel(count),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: surf.textPrimary),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _toggleQuadrantSelection,
                  child: Text(
                    quadrantFull ? 'إلغاء تحديد هذا الربع' : 'تحديد الربع كاملاً',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.indigoAccent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_bulkSaving)
            const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          else
            Opacity(
              opacity: count == 0 ? .45 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: count == 0 ? null : _applyBulkStatus,
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryButtonGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.format_paint_outlined, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text('تطبيق حالة',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
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

  Future<void> _applyBulkStatus() async {
    final count = _selectedTeeth.length;
    final choice = await showAppSheet<_BulkToothChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      desktopWidth: 520,
      builder: (_) => _BulkToothStatusSheet(count: count),
    );
    if (choice == null || !mounted) return;
    final updated = Map<String, String>.from(_patient.chartState);
    for (final fdi in _selectedTeeth) {
      final key = fdiToPalmer[fdi];
      if (key == null) continue;
      if (choice.statusKey == null) {
        updated.remove(key);
      } else {
        updated[key] = choice.statusKey!;
      }
    }
    setState(() => _bulkSaving = true);
    try {
      final patient = await widget.apiService.updatePatientChart(_patient.id, updated);
      if (!mounted) return;
      setState(() {
        _patient = patient;
        _selectedTeeth.clear();
        _multiSelect = false;
      });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_updatedTeethLabel(count))));
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
            const SnackBar(content: Text('تعذر حفظ حالة الأسنان. حاول مرة أخرى.')));
      }
    } finally {
      if (mounted) setState(() => _bulkSaving = false);
    }
  }

  Widget _buildChartCard() {
    final surf = context.surface;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: _bulkSaving ? null : _toggleMultiSelect,
                icon: Icon(_multiSelect ? Icons.close_rounded : Icons.checklist_rounded, size: 18),
                label: Text(_multiSelect ? 'إنهاء التحديد' : 'تحديد عدة أسنان'),
              ),
              const Spacer(),
              const Text('مخطط الأسنان', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          _buildMouthOverview(),
          const SizedBox(height: 12),
          _buildQuadrantTabs(),
          const SizedBox(height: 12),
          _buildQuadrantTeeth(),
          if (_multiSelect) ...[
            const SizedBox(height: 10),
            _buildBulkBar(),
          ],
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
                        Text(option.label, style: TextStyle(fontSize: 10.5, color: surf.textSecondary)),
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
    final surf = context.surface;
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
              if (files.isNotEmpty)
                Expanded(
                  child: Text(
                    'اضغط على أيقونة الحذف الظاهرة على كل بطاقة لحذفها',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10.5, color: surf.textMuted),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              Text(
                '${files.length} ملف',
                style: TextStyle(fontSize: 11.5, color: surf.textSecondary, fontWeight: FontWeight.w700),
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'لا توجد ملفات طبية مرفوعة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: surf.textSecondary, fontSize: 12.5),
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

  /// أيقونة حذف صريحة دائمة الظهور في زاوية بطاقة الأرشيف -- أُضيفت 2026-09-07
  /// بعد أن أبلغ المستخدم أن الضغط المطوّل (الطريقة الوحيدة سابقاً) لا يفتح
  /// مربع التأكيد إطلاقاً على جهاز حقيقي. راجعت onLongPress نفسها ولم أجد
  /// خللاً بها (مربوطة بشكل صحيح لـ _confirmDeleteArchiveFile)، لكن هذه
  /// البطاقات تقع داخل GridView متداخل بلا تمرير خاص به (physics:
  /// NeverScrollableScrollPhysics) ضمن ListView رأسي هو المتحكم الفعلي
  /// بالتمرير (_buildArchiveSection يُستدعى كعنصر من ListView الشاشة كاملة) --
  /// الضغط المطوّل الذي يتضمن أي انزلاق طفيف بالإصبع (متوقع تماماً على شاشة
  /// حقيقية، بخلاف نقرة فأرة ثابتة تماماً بالمحاكي) قد يجعل محرّك التمرير
  /// الرأسي "يفوز" بحلبة الإيماءات قبل انتهاء مهلة الضغط المطوّل، فتُلغى
  /// onLongPress بصمت بلا أي خطأ. بدل محاولة إصلاح غير مضمونة على مستوى
  /// الإيماءات، أُضيفت أيقونة حذف صريحة (نفس مبدأ زر "حذف" الصريح المستخدم
  /// أصلاً لحذف المواعيد بهذه الشاشة، انظر Icons.delete_outline أعلاه) --
  /// نقرة عادية بسيطة لا تعاني من نفس تعارض الإيماءات. الضغط المطوّل تُرك
  /// يعمل كطريقة بديلة إضافية لمن ينجح معه.
  Widget _buildArchiveDeleteBadge(PatientArchiveFile file, bool isDeleting) {
    return Positioned(
      top: 6,
      left: 6,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 1.5,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isDeleting ? null : () => _confirmDeleteArchiveFile(file),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.delete_outline, size: 16, color: AppColors.rose700text),
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveCard(PatientArchiveFile file) {
    final surf = context.surface;
    final uploadedAt = _formatArchiveDate(file.uploadedAt);
    final isDeleting = _deletingArchiveId == file.id;

    if (file.isPdf) {
      return _wrapArchiveCardWithDeleteOverlay(
        isDeleting: isDeleting,
        child: Stack(
        fit: StackFit.expand,
        children: [
        Material(
          color: surf.cardBg,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: isDeleting ? null : () => _openArchiveDocument(file),
            onLongPress: isDeleting ? null : () => _confirmDeleteArchiveFile(file),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: surf.cardBorder),
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
                    style: TextStyle(fontSize: 10.5, color: surf.textSecondary),
                  ),
                  const Spacer(),
                  Text(uploadedAt, style: TextStyle(fontSize: 9.5, color: surf.textMuted)),
                ],
              ),
            ),
          ),
        ),
        _buildArchiveDeleteBadge(file, isDeleting),
        ],
      ),
      );
    }

    return _wrapArchiveCardWithDeleteOverlay(
      isDeleting: isDeleting,
      child: Stack(
      fit: StackFit.expand,
      children: [
      Material(
        color: surf.cardBg,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isDeleting ? null : () => _openArchiveImagePreview(file),
          onLongPress: isDeleting ? null : () => _confirmDeleteArchiveFile(file),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  file.resolvedImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: surf.chipBg,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image_outlined, color: surf.textMuted),
                  ),
                  loadingBuilder: (context, child, progress) {
    final surf = context.surface;
                    if (progress == null) return child;
                    return Container(
                      color: surf.chipBg,
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
                // .start = يمين تحت RTL العام (انظر تعليق _buildProfileCard
                // أعلاه لنفس الإصلاح) -- كانت .end السابقة تدفع اسم/تاريخ
                // الملف لليسار.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: TextStyle(fontSize: 9.5, color: surf.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      _buildArchiveDeleteBadge(file, isDeleting),
      ],
      ),
    );
  }

  /// طبقة شفافة فوق بطاقة الملف أثناء تنفيذ الحذف (بعد تأكيد المستخدم) --
  /// نفس فكرة تعطيل الزر + إظهار مؤشّر تحميل مكانه المستخدمة في بطاقة
  /// الموعد (انظر _buildAppointmentCard/isDeleting)، هنا كطبقة فوق البطاقة
  /// كاملةً (بما فيها أيقونة الحذف الصريحة _buildArchiveDeleteBadge) أثناء
  /// تنفيذ طلب الحذف الفعلي.
  Widget _wrapArchiveCardWithDeleteOverlay({required bool isDeleting, required Widget child}) {
    if (!isDeleting) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoicesSection() {
    final surf = context.surface;
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
                              // 2026-09-25: مبلغ استلمه طبيب مساعد ينتظر تأكيد المدير.
                              if (invoice.pendingPayments.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                StatusBadge(
                                  label: '⏳ ${invoice.pendingAmount.toStringAsFixed(0)} بانتظار التأكيد',
                                  background: surf.pillDueBg,
                                  foreground: surf.pillDueFg,
                                ),
                              ],
                              const SizedBox(width: 8),
                              // العنوان يُختصر بدل أن يدفع الشارات خارج البطاقة
                              // على شاشة ضيقة (صارت شارتين منذ الدفعات المعلّقة).
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // فاتورة (أو دفعة عليها) أُنشئت أوفلاين وما
                                    // زالت بانتظار الاتصال بالإنترنت -- انظر
                                    // OfflineAwareApiService. أُضيف 2026-09-02.
                                    if (invoice.isPendingSync) ...[
                                      const Icon(Icons.cloud_off_outlined,
                                          size: 14, color: AppColors.amber900),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(invoice.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: invoice.progress,
                              minHeight: 6,
                              backgroundColor: surf.chipBg,
                              valueColor: const AlwaysStoppedAnimation(AppColors.emerald500),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('الإجمالي ${invoice.totalCost.toStringAsFixed(0)} ل.س',
                                  style: TextStyle(fontSize: 11.5, color: surf.textSecondary)),
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
    final surf = context.surface;
    final prescriptions = _prescriptions ?? [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // .start = يمين تحت RTL العام (انظر تعليق _buildProfileCard
                // أعلاه لنفس الإصلاح).
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الوصفات الطبية',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(
                      'أصدر وصفة جديدة للمريض واحتفظ بسجلها مع إمكانية الطباعة الفورية.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: surf.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: surf.iconBoxBg,
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
              color: surf.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: AppColors.purple600.withValues(alpha: .28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('الأدوية والمستحضرات',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: surf.textSecondary)),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('التعليمات والجرعات',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: surf.textSecondary)),
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد وصفات طبية مسجلة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: surf.textSecondary, fontSize: 12.5),
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
    final surf = context.surface;
    final isPrinting = _printingPrescriptionId == prescription.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surf.chipBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surf.cardBorder),
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
                style: TextStyle(fontSize: 11, color: surf.textMuted),
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
                textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, height: 1.5, color: surf.textSecondary)),
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
    final surf = context.surface;
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

    await showAppSheet<void>(
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
                decoration: BoxDecoration(
                  color: surf.sheetBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BottomSheetOnly(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: surf.cardBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
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
    final surf = context.surface;
    final appointments = _appointments ?? [];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // .start = يمين تحت RTL العام (انظر تعليق _buildProfileCard
                // أعلاه لنفس الإصلاح).
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إدارة مواعيد هذا المريض',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(
                      'عرض مباشر للمواعيد المرتبطة بهذا الملف مع تعديل سريع للموعد والوصف.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: surf.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: surf.iconBoxBg,
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'لا توجد مواعيد مسجلة لهذا المريض حتى الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: surf.textSecondary, fontSize: 12.5),
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

  /// نمط موحّد لأزرار إجراءات الموعد الثلاثة: حشوة أفقية ضيّقة (6 بدل 16)
  /// حتى يتّسع النص العربي داخل ثلث عرض الشاشة.
  ButtonStyle _appointmentActionStyle({
    required Color foreground,
    required Color border,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      minimumSize: const Size(0, 44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// نص زر لا ينكسر سطرين: يصغّر نفسه قليلاً عند الضيق بدل الالتفاف.
  Widget _actionLabel(String text) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      );

  Widget _buildAppointmentCard(Appointment appointment) {
    final surf = context.surface;
    final style = appointmentStatusStyle(appointment.status,
        isDark: context.surface.isDark);
    final isDeleting = _deletingAppointmentId == appointment.id;
    final dateLabel = appointment.appointmentDate != null
        ? _formatAppointmentDateTime(appointment.appointmentDate!)
        : '—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surf.chipBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surf.cardBorder),
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
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: surf.textSecondary),
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
          // ثلاثة أزرار في ثلث عرض الشاشة لكلٍّ منها. الحشوة الأفقية
          // الافتراضية لـ OutlinedButton (16 لكل جهة) + الأيقونة + الفجوة لم
          // تكن تترك للنص إلا بضعة بكسلات، وبعد انتقال الخط إلى Noto Sans
          // Arabic -- وهو أعرض من Tajawal عند نفس المقاس -- صارت "تعديل"
          // و"واتساب" تلتفّان سطرين داخل الزر. الحلّ: حشوة ضيّقة + FittedBox
          // يصغّر النص بدل أن يكسره، لا تصغير المقاس لكل الأزرار في التطبيق.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _appointmentActionStyle(
                      foreground: surf.accentSolid, border: surf.cardBorder),
                  onPressed: () => _openAppointmentFormSheet(existing: appointment),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: _actionLabel('تعديل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: _appointmentActionStyle(
                    foreground: surf.isDark
                        ? AppColors.rose400
                        : AppColors.rose700text,
                    border: AppColors.rose500
                        .withValues(alpha: surf.isDark ? .30 : .35),
                  ),
                  onPressed: isDeleting ? null : () => _confirmDeleteAppointment(appointment),
                  icon: isDeleting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 15),
                  label: _actionLabel('حذف'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: _appointmentActionStyle(
                    foreground: surf.pillPaidFg,
                    border: surf.pillPaidFg.withValues(alpha: .40),
                  ),
                  onPressed: () => _sendWhatsappReminder(appointment),
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: _actionLabel('واتساب'),
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

  /// أطباء العيادة -- null حتى التحميل، وفارغة لعيادة الطبيب الواحد (لا صفّ).
  ClinicDoctorChoices? _doctorChoices;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
    ClinicDoctorChoices.load(widget.apiService).then((choices) {
      if (mounted) setState(() => _doctorChoices = choices);
    });
  }

  /// تصحيح الطبيب المنفّذ (2026-09-25). إن كانت على الفاتورة دفعات يسأل:
  /// تصحيح خطأ (تنتقل الدفعات السابقة ونسبها) أم تغيير للأقساط القادمة فقط.
  Future<void> _changeDoctor() async {
    final choices = _doctorChoices;
    if (choices == null) return;
    int? selected = _invoice.clinicDoctorId;
    var moveExisting = true;
    final paymentsCount = _invoice.payments.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('تغيير الطبيب المنفّذ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClinicDoctorDropdown(
                choices: choices,
                value: selected,
                currentDoctorName: _invoice.clinicDoctorName,
                label: 'الطبيب المنفّذ',
                onChanged: (value) => setDialogState(() => selected = value),
              ),
              if (paymentsCount > 0) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: moveExisting,
                  onChanged: (value) => setDialogState(() => moveExisting = value ?? true),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('نقل الدفعات السابقة ($paymentsCount) ونسبها إلى الطبيب الجديد',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                    'اتركه محدّداً إن كان الطبيب السابق اختياراً خاطئاً. أزِله إن كان العلاج انتقل '
                    'لطبيب آخر من الآن فقط.',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || selected == _invoice.clinicDoctorId) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await widget.apiService.updateInvoiceDoctor(
        _invoice.patientId,
        _invoice.id,
        totalCost: _invoice.totalCost,
        clinicDoctorId: selected,
        applyToExistingPayments: paymentsCount > 0 && moveExisting,
      );
      if (!mounted) return;
      setState(() {
        _invoice = updated;
        _isSaving = false;
      });
      widget.onInvoiceUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الطبيب المنفّذ للفاتورة')));
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── الدفعات المعلّقة (2026-09-25) ──

  /// يعيد جلب الفاتورة بعد عملية على دفعة معلّقة (المسارات تُرجع الدفعة
  /// المعلّقة لا الفاتورة).
  Future<void> _reloadInvoice() async {
    final invoices = await widget.apiService.fetchPatientInvoices(_invoice.patientId);
    final updated = invoices.firstWhere((item) => item.id == _invoice.id, orElse: () => _invoice);
    if (!mounted) return;
    setState(() => _invoice = updated);
    widget.onInvoiceUpdated(updated);
  }

  bool get _isOwnStaffInvoice =>
      AppSession.instance.isStaff && _invoice.clinicDoctorId == AppSession.instance.staffDoctorId.value;

  /// الطبيب المساعد يرسل مبلغاً استلمه -- لا يدخل الحسابات قبل تأكيد المدير.
  Future<void> _submitPendingPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً');
      return;
    }
    final available = _invoice.remainingAmount - _invoice.pendingAmount;
    if (amount > available + 0.001) {
      setState(() => _error =
          'المبلغ أكبر من المتبقي على الفاتورة (${available < 0 ? 0 : available.toStringAsFixed(0)} ل.س) '
          'بعد الدفعات التي تنتظر التأكيد.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.createPendingPayment(
        _invoice.patientId,
        _invoice.id,
        amount: amount,
        description: _descriptionController.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _amountController.clear();
      _descriptionController.clear();
      await _reloadInvoice();
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أُرسلت الدفعة للطبيب المدير، وتُحسب بعد تأكيده.')),
      );
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    }
  }

  /// المدير: تأكيد/رفض. المساعد: إلغاء دفعته قبل المراجعة.
  Future<void> _actOnPending(PendingPayment payment, String action) async {
    String? note;
    if (action == 'reject') {
      note = await askRejectReason(context);
      if (note == null) return;
    } else if (action == 'cancel') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إلغاء الدفعة؟'),
          content: const Text('تُحذف الدفعة المرسلة قبل أن يراجعها الطبيب المدير.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('تراجع')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('إلغاء الدفعة')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      switch (action) {
        case 'confirm':
          await widget.apiService.confirmPendingPayment(payment.id);
        case 'reject':
          await widget.apiService.rejectPendingPayment(payment.id, note: note);
        default:
          await widget.apiService.cancelPendingPayment(payment.id);
      }
      await _reloadInvoice();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (action) {
          'confirm' => 'تم تأكيد الدفعة وإضافتها للحسابات',
          'reject' => 'تم رفض الدفعة',
          _ => 'تم إلغاء الدفعة',
        }),
      ));
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildPendingSection() {
    final isStaff = AppSession.instance.isStaff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            isStaff ? 'بانتظار تأكيد الطبيب المدير' : 'دفعات بانتظار تأكيدك',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 8),
        for (final payment in _invoice.pendingPayments)
          PendingPaymentTile(
            payment: payment,
            actions: isStaff
                ? [
                    if (payment.clinicDoctorId == AppSession.instance.staffDoctorId.value)
                      TextButton(
                        onPressed: _isSaving ? null : () => _actOnPending(payment, 'cancel'),
                        child: const Text('إلغاء'),
                      ),
                  ]
                : [
                    TextButton(
                      onPressed: _isSaving ? null : () => _actOnPending(payment, 'reject'),
                      child: const Text('رفض', style: TextStyle(color: AppColors.rose700text)),
                    ),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : () => _actOnPending(payment, 'confirm'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('تأكيد الاستلام'),
                    ),
                  ],
          ),
      ],
    );
  }

  Widget _buildStaffPaymentForm() {
    final surf = context.surface;
    if (!_isOwnStaffInvoice) {
      return Text(
        'هذه فاتورة طبيب آخر — الدفعات عليها عند الطبيب المدير.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: surf.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                decoration: const InputDecoration(hintText: 'المبلغ المستلم', isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'المبلغ يصل للطبيب المدير ليؤكّد استلامه، ولا يدخل الحسابات ولا نسبتك قبل تأكيده.',
          style: TextStyle(fontSize: 11.5, height: 1.5, color: surf.textSecondary),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: AppColors.rose700text, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        GradientButton(
          label: 'إرسال للمدير للتأكيد',
          icon: Icons.send_outlined,
          onPressed: _isSaving ? null : _submitPendingPayment,
          isLoading: _isSaving,
          gradient: AppColors.successButtonGradient,
        ),
      ],
    );
  }

  Future<void> _addPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً');
      return;
    }
    // 2026-09-25: الخادم يرفض الدفعة الزائدة (كانت تُحسب نسبة الطبيب على
    // الزيادة) -- الفحص هنا يعطي الرسالة فوراً، وأوفلاين قبل أن تُؤجَّل.
    if (amount > _invoice.remainingAmount + 0.001) {
      setState(() => _error =
          'المبلغ أكبر من المتبقي على الفاتورة (${_invoice.remainingAmount.toStringAsFixed(0)} ل.س). '
          'إن زادت تكلفة المعالجة فعدّل تكلفة الفاتورة أولاً.');
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
      HapticFeedback.mediumImpact();
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
    final surf = context.surface;
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
                              style: TextStyle(fontSize: 11.5, color: surf.textSecondary),
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

  /// ملخّص المواد المستهلكة على الفاتورة وربحها.
  ///
  /// "ربح الفاتورة" = التكلفة الإجمالية ناقص تكلفة المواد المجمَّدة: ربح
  /// **مفوتَر** لا محصَّل، مستقل تماماً عن كم دُفع منها (ذاك المدفوع أعلاه).
  /// لذلك لا يُسمّى "الربح المحقَّق" ولا يُوضَع بين أرقام الدفعات.
  Widget _buildMaterialsSummary() {
    final surf = context.surface;
    final hasMaterials = _invoice.materials.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: surf.iconBoxBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: surf.iconBoxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: surf.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  hasMaterials
                      ? '${_invoice.materials.length} مادة مستهلكة'
                      : 'بلا مواد مستهلكة',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: surf.textPrimary),
                ),
              ),
              TextButton(
                onPressed: _openMaterialsSheet,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32)),
                child: const Text('إدارة المواد'),
              ),
            ],
          ),
          if (hasMaterials)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'تكلفة المواد ${_invoice.materialsCost.toStringAsFixed(0)} ل.س · '
                'ربح الفاتورة ${_invoice.netProfit.toStringAsFixed(0)} ل.س',
                style: TextStyle(
                    fontSize: 11,
                    color: _invoice.netProfit < 0
                        ? AppColors.rose700text
                        : surf.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openMaterialsSheet() async {
    // نداء مباشر عند كل تغيير، لا نتيجة راجعة من pop: الورقة السفلية تُغلَق
    // أيضاً بالسحب لأسفل وبزر الرجوع، وكلاهما يُرجع null -- فكانت أرقام
    // الفاتورة تبقى قديمة بعد إضافة مادة إن أغلق الطبيب الورقة بالسحب.
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvoiceMaterialsSheet(
        invoice: _invoice,
        apiService: widget.apiService,
        onSessionExpired: widget.onSessionExpired,
        onInvoiceChanged: (updated) {
          if (!mounted) return;
          setState(() => _invoice = updated);
          widget.onInvoiceUpdated(updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
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
            BottomSheetOnly(
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: surf.fieldBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
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
              style: TextStyle(fontSize: 12, color: surf.textSecondary),
            ),
            if (_doctorChoices != null && !_doctorChoices!.isEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medical_services_outlined, size: 15, color: surf.textSecondary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'الطبيب المنفّذ: ${_invoice.clinicDoctorName ?? (_invoice.clinicDoctorId == null ? _doctorChoices!.ownerLabel : 'طبيب غير نشط')}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: surf.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _changeDoctor,
                    child: const Text('تغيير'),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            // المواد المستهلكة -- 2026-09-18. تُعرَض ملخَّصاً وتُدار في ورقة
            // مستقلّة عن قصد: قائمة الدفعات هنا داخل Expanded، فإدراج قائمة
            // مواد قابلة للنموّ فوقها كان سيخنق سجل الدفعات على فاتورة
            // بعشر مواد.
            _buildMaterialsSummary(),
            const SizedBox(height: 12),
            if (_invoice.pendingPayments.isNotEmpty) ...[
              _buildPendingSection(),
              const SizedBox(height: 8),
            ],
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
    final surf = context.surface;
                        final payment = _invoice.payments[index];
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
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
                            onTap: AppSession.instance.isStaff
                                ? null
                                : () => _openEditPaymentDialog(payment),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!AppSession.instance.isStaff) ...[
                                  const Icon(Icons.edit_outlined, size: 14, color: AppColors.indigo600),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  '${payment.createdAt.year}/${payment.createdAt.month}/${payment.createdAt.day}',
                                  style: TextStyle(fontSize: 11, color: surf.textMuted),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 20),
            // الطبيب المساعد (2026-09-25): يرسل المبلغ الذي استلمه، ولا يدخل
            // الحسابات قبل أن يؤكّد الطبيب المدير وصوله للصندوق.
            if (_invoice.isOpen && AppSession.instance.isStaff) _buildStaffPaymentForm(),
            if (_invoice.isOpen && !AppSession.instance.isStaff) ...[
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
                        style: TextStyle(fontSize: 11.5, color: surf.textSecondary),
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

/// بطاقة حالة سن واحدة ضمن شبكة نافذة "تحديث حالة السن" -- مطابقة تماماً
/// لِـ [data-tooth-status] buttons في toothStatusModal بـ patient_record.html
/// بالموقع (bg-*-50 + border-*-200|300 + text-*-700 + rounded-2xl). النص
/// ملفوف بـ FittedBox حتى يتقلّص تلقائياً بدل أن يفيض من البطاقة على
/// الشاشات الأضيق من سطح المكتب (كانت هذه فعلياً نقطة الطفح "BOTTOM
/// OVERFLOWED" في نسخة النافذة السابقة).
/// ورقة إدارة المواد المستهلكة على فاتورة واحدة -- 2026-09-18.
///
/// كل عملية هنا **حركة مخزن حقيقية فورية**: الإضافة تخصم من المخزن، والحذف
/// يُرجِع الكمية إليه. ليست تحريراً محلياً يُحفَظ في النهاية، ولذلك لا يوجد
/// زر "حفظ": كل سطر يُنفَّذ لحظة الضغط، والفاتورة المحدَّثة تعود من الخادم
/// بعد كل عملية فتُعرَض أرقامها الحقيقية لا أرقاماً محسوبة محلياً.
///
/// الشاشة متّصلة فقط عن قصد -- انظر شرح createInvoice في
/// OfflineAwareApiService: تأجيل خصم المخزن يُنشئ سجلاً كاذباً قد تفشل
/// مزامنته بعد يومين دون أن يعرف الطبيب.
class _InvoiceMaterialsSheet extends StatefulWidget {
  final TreatmentInvoice invoice;
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  /// يُنادى بعد كل عملية ناجحة (إضافة أو حذف) بالفاتورة كما أعادها الخادم.
  final ValueChanged<TreatmentInvoice> onInvoiceChanged;

  const _InvoiceMaterialsSheet({
    required this.invoice,
    required this.apiService,
    required this.onSessionExpired,
    required this.onInvoiceChanged,
  });

  @override
  State<_InvoiceMaterialsSheet> createState() => _InvoiceMaterialsSheetState();
}

class _InvoiceMaterialsSheetState extends State<_InvoiceMaterialsSheet> {
  late TreatmentInvoice _invoice;
  List<InventoryItem>? _inventory;
  InventoryItem? _selectedItem;
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  bool _isBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
    _loadInventory();
  }

  /// المخزن محروس بباقة Premium فيعيد 403 لحساب أدنى. ذلك ليس خطأ يُعرَض:
  /// تبقى الإضافة بالاسم متاحة (الخادم يطابق الاسم بالمخزن بنفسه)، وتختفي
  /// قائمة الاختيار وحدها.
  Future<void> _loadInventory() async {
    try {
      final items = await widget.apiService.fetchInventory();
      if (!mounted) return;
      setState(() => _inventory = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _inventory = const []);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _addMaterial() async {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (quantity <= 0) {
      setState(() => _error = 'الكمية يجب أن تكون 1 على الأقل');
      return;
    }
    final selected = _selectedItem;
    if (selected == null && _nameController.text.trim().isEmpty) {
      setState(() => _error = 'اختر مادة من المخزن أو اكتب اسمها');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final updated = await widget.apiService.addInvoiceMaterials(
        _invoice.patientId,
        _invoice.id,
        [
          InvoiceMaterialInput(
            inventoryItemId: selected?.id,
            itemName: selected?.itemName ?? _nameController.text.trim(),
            quantity: quantity,
          ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _invoice = updated;
        _isBusy = false;
        _selectedItem = null;
        _nameController.clear();
        _quantityController.text = '1';
      });
      widget.onInvoiceChanged(updated);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (!mounted) return;
      // نقص المخزن يرجع 400 برسالة الخادم نفسها -- تُعرَض كما هي لأنها
      // تسمّي المادة والكمية المتوفّرة.
      setState(() {
        _error = e.message;
        _isBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تسجيل المادة. حاول مرة أخرى.';
        _isBusy = false;
      });
    }
  }

  Future<void> _deleteMaterial(InvoiceMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surface.sheetBg,
        title: const Text('حذف سطر المادة؟'),
        content: Text(
          'ستُرجَع ${material.quantity} من «${material.itemName}» إلى المخزن، '
          'وتنخفض تكلفة الفاتورة بمقدار ${material.totalCost.toStringAsFixed(0)} ل.س.',
          style: TextStyle(color: context.surface.textSecondary, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('حذف وإرجاع للمخزن',
                style: TextStyle(color: AppColors.rose700text)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final updated = await widget.apiService.deleteInvoiceMaterial(
          _invoice.patientId, _invoice.id, material.id);
      if (!mounted) return;
      setState(() {
        _invoice = updated;
        _isBusy = false;
      });
      widget.onInvoiceChanged(updated);
    } on ApiException catch (e) {
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر حذف السطر. حاول مرة أخرى.';
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    final inventory = _inventory ?? const <InventoryItem>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surf.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSheetOnly(
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: surf.divider,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('المواد المستهلكة',
                    textAlign: TextAlign.center,
                    style: AppType.kufi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: surf.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'الإضافة تخصم من المخزن فوراً، والحذف يُرجِع الكمية إليه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: surf.textMuted, height: 1.7),
                ),
                const SizedBox(height: 14),
                if (_invoice.materials.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('لا مواد مسجَّلة على هذه الفاتورة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: surf.textMuted, fontSize: 12.5)),
                  )
                else
                  for (final material in _invoice.materials)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(11, 7, 4, 7),
                        decoration: BoxDecoration(
                          color: surf.iconBoxBg,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: surf.iconBoxBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(material.itemName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: surf.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${material.quantity} × ${material.unitCost.toStringAsFixed(0)} = '
                                    '${material.totalCost.toStringAsFixed(0)} ل.س',
                                    style: TextStyle(
                                        fontSize: 10.5, color: surf.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            // حذف مادة يعيد المخزن ويغيّر كلفة الفاتورة --
                            // للمدير وحده؛ المساعد يطلب منه تصحيح الخطأ.
                            if (!AppSession.instance.isStaff)
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 19, color: AppColors.rose700text),
                                tooltip: 'حذف وإرجاع للمخزن',
                                onPressed:
                                    _isBusy ? null : () => _deleteMaterial(material),
                              ),
                          ],
                        ),
                      ),
                    ),
                Divider(color: surf.divider, height: 22),
                Text('إضافة مادة',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: surf.heroCaption)),
                const SizedBox(height: 8),
                if (inventory.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: surf.fieldBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: surf.fieldBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<InventoryItem?>(
                        value: _selectedItem,
                        isExpanded: true,
                        hint: Text('اختر مادة من المخزن',
                            style: TextStyle(color: surf.fieldHint)),
                        dropdownColor: surf.sheetBg,
                        borderRadius: BorderRadius.circular(14),
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: surf.textSecondary),
                        items: [
                          const DropdownMenuItem<InventoryItem?>(
                            value: null,
                            child: Text('-- بكتابة الاسم --',
                                textAlign: TextAlign.right),
                          ),
                          for (final item in inventory)
                            DropdownMenuItem<InventoryItem?>(
                              value: item,
                              child: Text(
                                '${item.itemName} (متوفّر ${item.quantity})',
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _isBusy
                            ? null
                            : (value) => setState(() {
                                  _selectedItem = value;
                                  _error = null;
                                }),
                      ),
                    ),
                  ),
                if (_selectedItem == null) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة كما هو في المخزن',
                      helperText: 'يجب أن تكون المادة مسجَّلة في مخزنك مسبقاً',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _quantityController,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TextStyle(
                          color: AppColors.rose700text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),
                GradientButton(
                  label: 'خصم المادة من المخزن',
                  icon: Icons.add,
                  isLoading: _isBusy,
                  onPressed: _isBusy ? null : _addMaterial,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
                  child: const Text('تم'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToothStatusCard extends StatelessWidget {
  final ToothStatusOption option;
  final VoidCallback onTap;

  const _ToothStatusCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: option.cardBackground,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: option.cardBorder),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              option.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: option.cardText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// دائرة لون واحدة ضمن لوحة "أضف حالة مخصصة" -- مطابقة لِـ
/// #customToothColorSwatches في الموقع (دائرة 28px، حدّ أبيض بسماكة 2px
/// بشكل افتراضي يتحوّل إلى إندگو-800 مع توهّج خفيف عند الاختيار).
class _CustomColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CustomColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? surf.accentSolid : surf.cardBg,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.indigo800.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.25),
              blurRadius: selected ? 0 : 3,
              spreadRadius: selected ? 2 : 0,
            ),
          ],
        ),
      ),
    );
  }
}

/// اختيار ورقة «حالة الأسنان المحدَّدة». [statusKey] null = مسح الحالة.
class _BulkToothChoice {
  final String? statusKey;
  const _BulkToothChoice(this.statusKey);
}

class _BulkToothStatusSheet extends StatelessWidget {
  final int count;

  const _BulkToothStatusSheet({required this.count});

  @override
  Widget build(BuildContext context) {
    final surf = context.surface;
    return Container(
      decoration: BoxDecoration(
        color: surf.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BottomSheetOnly(
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: surf.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Text(
                'حالة الأسنان المحدَّدة',
                style: AppType.kufi(
                    fontSize: 16, fontWeight: FontWeight.w700, color: surf.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'تُطبَّق على الأسنان المحدَّدة كلها ($count) بحفظ واحد.',
                style: TextStyle(fontSize: 12, color: surf.textSecondary),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in toothStatusOptions)
                        SizedBox(
                          width: itemWidth,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () =>
                                Navigator.of(context).pop(_BulkToothChoice(option.key)),
                            child: Ink(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: option.color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: option.color.withValues(alpha: .45)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: option.color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: surf.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pop(const _BulkToothChoice(null)),
                child: Ink(
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: surf.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.layers_clear_outlined, size: 17, color: surf.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'مسح حالة الأسنان المحدَّدة',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: surf.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
