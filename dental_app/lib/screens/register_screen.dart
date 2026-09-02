import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// شاشة تفعيل حساب جديد -- لم تكن موجودة في تطبيق الجوال إطلاقاً قبل
/// 2026-08-31 (كان يمكن للطبيب تسجيل الدخول فقط، ولا وسيلة لتفعيل حساب من
/// داخل التطبيق). تطابق frontend_web/register.html بالموقع بالحرف: نفس
/// البطاقة/الرأس المتدرّج، صندوق "مؤشر التفعيل" الديناميكي (يتغيّر لونه
/// ونصه مع كل حقل يُملأ -- بما في ذلك الحالة الأولى الغريبة في الموقع نفسه:
/// بادج أبيض بنص أخضر رغم أن النموذج غير مكتمل)، حقل الاسم/البريد/كلمة
/// المرور بشريط قوّة حي/كود التفعيل بتلميح يتحقق من بادئة FARAS-، وصندوق
/// رسالة الخطأ الثابت (بخلاف شاشة الدخول التي تستخدم توست عائم).
class RegisterScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onRegisterSuccess;

  const RegisterScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onRegisterSuccess,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _activationCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // كل الحقول الأربعة تُحدّث صندوق "مؤشر التفعيل" وشريط قوة كلمة المرور
    // وتلميح كود التفعيل لحظياً -- تماماً كدالة updateRegisterInsights() في
    // register.html بالموقع.
    for (final controller in [
      _fullNameController,
      _emailController,
      _passwordController,
      _activationCodeController,
    ]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _activationCodeController.dispose();
    super.dispose();
  }

  int get _completedCount => [
        _fullNameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        _activationCodeController.text.trim(),
      ].where((value) => value.isNotEmpty).length;

  int _passwordStrength(String password) {
    var score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Za-z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score;
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final activationCode = _activationCodeController.text.trim();

    if (fullName.isEmpty || email.isEmpty || password.isEmpty || activationCode.isEmpty) {
      setState(() => _errorMessage = 'يرجى تعبئة جميع الحقول قبل المتابعة.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService.register(
        doctorName: fullName,
        email: email,
        password: password,
        activationCode: activationCode,
      );
      await widget.authStorage.saveSession(
        token: (result['token'] as String?) ?? '',
        email: email,
        doctorName: fullName,
        tier: (result['tier'] as String?) ?? 'standard',
      );
      if (!mounted) return;
      // الموقع يُعيد التوجيه إلى login.html بعد نجاح التفعيل رغم حفظ التوكن
      // فعلياً (لا يدخل الطبيب مباشرة إلى اللوحة) -- في التطبيق نُفضّل
      // إدخال الطبيب مباشرة بما أن الجلسة أصبحت جاهزة فعلاً، بدل إعادته
      // لتسجيل الدخول يدوياً بنفس البيانات التي أدخلها للتو.
      widget.onRegisterSuccess();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'تعذر الاتصال بالخادم الآن. يرجى المحاولة لاحقًا.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AuthPageBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.slate200),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.slate900.withValues(alpha: 0.14),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        Padding(padding: const EdgeInsets.all(20), child: _buildBody()),
                      ],
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: const BoxDecoration(gradient: AppColors.authCardHeaderGradient),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Text('🦷', style: TextStyle(fontSize: 30)),
          ),
          const SizedBox(height: 16),
          const Text(
            'عيادتي الرقمية - تفعيل حساب جديد',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'أنشئ حسابك الطبي وابدأ استخدام المنصة بأمان',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final completed = _completedCount;
    final String badgeText;
    final Color badgeBg;
    final Color badgeColor;
    final String summary;
    if (completed == 0) {
      // مطابقة متعمّدة لتفصيل غريب في كود الموقع نفسه: البادج بخلفية بيضاء
      // ونص أخضر رغم أن النموذج غير مكتمل بعد -- راجع updateRegisterInsights().
      badgeText = 'النموذج غير مكتمل';
      badgeBg = Colors.white;
      badgeColor = AppColors.emerald700;
      summary = 'أكمل الحقول الأربعة لنجهّز الحساب للربط مع باقة الاشتراك.';
    } else if (completed < 4) {
      badgeText = 'قيد الاكتمال';
      badgeBg = AppColors.amber100;
      badgeColor = AppColors.amber700;
      summary = 'كل حقل تكمله يقرّبك من تفعيل لوحة الإدارة والوصول لملفات المرضى.';
    } else {
      badgeText = 'جاهز للتفعيل';
      badgeBg = AppColors.emerald100;
      badgeColor = AppColors.emerald700;
      summary = 'راجع الكود والبريد ثم اضغط تفعيل الحساب لإنشاء عيادتك الرقمية.';
    }

    final strength = _passwordStrength(_passwordController.text);
    const strengthWidths = [0.0, 0.25, 0.5, 0.75, 1.0];
    const strengthBarColors = [
      AppColors.rose400,
      AppColors.rose400,
      AppColors.amber400,
      AppColors.cyan500,
      AppColors.emerald500,
    ];
    const strengthLabels = ['كلمة المرور ضعيفة', 'ضعيفة', 'متوسطة', 'جيدة', 'قوية'];
    final strengthTextColor =
        strength >= 3 ? AppColors.emerald700 : (strength == 2 ? AppColors.amber600 : AppColors.rose600);

    final email = _emailController.text.trim();
    final code = _activationCodeController.text.trim();
    final String codeHint;
    final Color codeHintColor;
    if (code.isEmpty) {
      codeHint = 'أدخل الكود كما وصلك من إدارة النظام.';
      codeHintColor = AppColors.slate500;
    } else if (code.toUpperCase().startsWith('FARAS-')) {
      codeHint = 'صيغة الكود تبدو صحيحة مبدئيًا.';
      codeHintColor = AppColors.emerald700;
    } else {
      codeHint = 'يفضّل أن يبدأ الكود بـ FARAS- كما تم إرساله لك.';
      codeHintColor = AppColors.amber600;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthStatusBanner(
          title: 'مؤشر التفعيل',
          badgeText: badgeText,
          badgeBackground: badgeBg,
          badgeColor: badgeColor,
          hint: summary,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          AuthMessageBox(message: _errorMessage!),
        ],
        const SizedBox(height: 16),
        AuthFieldWrapper(
          label: 'الاسم الكامل',
          child: TextFormField(
            controller: _fullNameController,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
            decoration: authInputDecoration(hint: 'مثال: د. أحمد العلي'),
          ),
        ),
        const SizedBox(height: 12),
        AuthFieldWrapper(
          label: 'البريد الإلكتروني',
          footer: email.isEmpty
              ? null
              : Text(
                  'سيتم ربط الحساب بالبريد: $email',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
            decoration: authInputDecoration(hint: 'doctor@clinic.com'),
          ),
        ),
        const SizedBox(height: 12),
        AuthFieldWrapper(
          label: 'كلمة المرور',
          trailing: InkWell(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Text(
              _obscurePassword ? 'إظهار' : 'إخفاء',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.indigoAccent),
            ),
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: strengthWidths[strength],
                  minHeight: 8,
                  backgroundColor: AppColors.slate200,
                  valueColor: AlwaysStoppedAnimation(strengthBarColors[strength]),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strengthLabels[strength],
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: strengthTextColor),
                  ),
                  const Text('8 أحرف أو أكثر يفضّل أن تتضمن أرقامًا',
                      style: TextStyle(fontSize: 10.5, color: AppColors.slate500)),
                ],
              ),
            ],
          ),
          child: TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
            decoration: authInputDecoration(hint: '••••••••'),
          ),
        ),
        const SizedBox(height: 12),
        AuthFieldWrapper(
          label: 'كود التفعيل الرقمي (Activation Code)',
          footer: Text(
            codeHint,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: codeHintColor),
          ),
          child: TextFormField(
            controller: _activationCodeController,
            textAlign: TextAlign.right,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            style: const TextStyle(fontSize: 13.5, color: AppColors.slate700, letterSpacing: 1.4),
            decoration: authInputDecoration(hint: 'FARAS-30DAYS-XYZ'),
          ),
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: 'تفعيل الحساب',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
        const SizedBox(height: 18),
        AuthBottomLinkRow(
          text: 'هل الحساب مفعّل بالفعل؟',
          linkText: 'انتقل إلى تسجيل الدخول',
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 20),
        Text(
          'تطوير وإدارة: المهندس فارس حلاوي © 2026',
          textAlign: TextAlign.center,
          // مطابق لِـ text-indigo-500/90 في الموقع بالحرف (وليس indigo-600).
          style: TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: AppColors.indigo500.withValues(alpha: 0.9)),
        ),
      ],
    );
  }
}
