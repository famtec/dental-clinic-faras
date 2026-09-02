import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'register_screen.dart';

/// شاشة تسجيل الدخول -- 2026-08-31: أُعيدت تصميمها بالكامل لتطابق
/// frontend_web/login.html بالموقع بالحرف: خلفية شبكية فاتحة بدوائر
/// زخرفية باهتة، بطاقة بيضاء برأس متدرّج (indigo-900 -> indigo-800 ->
/// violet-700)، صندوق "حالة الجاهزية"، حقول داخل إطار field-focus فاتح،
/// صف "تذكرني"، زر دخول بتدرّج indigo-600/violet-600، ثم صف رابط
/// "فعّل عيادتك الآن" الذي يفتح شاشة التفعيل الجديدة (RegisterScreen) --
/// لم تكن موجودة بالتطبيق قبل هذا التحديث. التصميم السابق (خلفية بنفسجية
/// داكنة كاملة الشاشة) كان لا يشبه الموقع إطلاقاً وأُزيل بالكامل.
class LoginScreen extends StatefulWidget {
  final ApiService apiService;
  final AuthStorage authStorage;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.apiService,
    required this.authStorage,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // -- منطق تسجيل الدخول (login -> saveSession -> onLoginSuccess) محفوظ
  // بالضبط كما كان قبل إعادة التصميم -- لم يتغيّر إلا الشكل والتنقّل الجديد
  // لشاشة التفعيل.
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // مطابق لِـ loginUser() في login.html بالموقع: تحقّق أوّلي بسيط من
    // امتلاء الحقلين قبل أي نداء شبكة، برسالة توست فورية عند النقص.
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      showAuthToast(context, 'يرجى ملء جميع الحقول المطلوبة أولاً!');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await widget.apiService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      await widget.authStorage.saveSession(
        token: (result['token'] as String?) ?? '',
        email: (result['email'] as String?) ?? _emailController.text.trim(),
        doctorName: result['doctor_name'] as String?,
        tier: result['tier'] as String?,
      );
      if (!mounted) return;
      widget.onLoginSuccess();
    } on ApiException catch (e) {
      // الموقع يعرض خطأ الدخول عبر توست عائم (showPremiumToast) لا صندوق
      // رسالة ثابت -- نفس السلوك هنا.
      if (mounted) showAuthToast(context, e.message);
    } catch (_) {
      if (mounted) {
        showAuthToast(context, 'فشل الاتصال بالسيرفر السحابي. يرجى مراجعة استقرار خادم Render.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          apiService: widget.apiService,
          authStorage: widget.authStorage,
          onRegisterSuccess: widget.onLoginSuccess,
        ),
      ),
    );
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
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
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
            child: const Icon(Icons.medical_services_rounded, size: 30, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'عيادتي الرقمية - تسجيل الدخول',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'مرحبًا بك في لوحة الإدارة الطبية',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthStatusBanner(
            title: 'حالة الجاهزية',
            badgeText: 'بانتظار البيانات',
            hint: 'ابدأ بكتابة البريد الإلكتروني وكلمة المرور لتفعيل زر الدخول بشكل تفاعلي.',
          ),
          const SizedBox(height: 18),
          AuthFieldWrapper(
            label: 'البريد الإلكتروني',
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
              decoration: authInputDecoration(hint: 'doctor@clinic.com'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'البريد الإلكتروني مطلوب' : null,
            ),
          ),
          const SizedBox(height: 14),
          AuthFieldWrapper(
            label: 'كلمة المرور',
            trailing: InkWell(
              onTap: () => setState(() => _obscurePassword = !_obscurePassword),
              child: Text(
                _obscurePassword ? 'إظهار' : 'إخفاء',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.indigoAccent),
              ),
            ),
            footer: const Text(
              'يُفضّل استخدام كلمة مرور العيادة المعتمدة.',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: AppColors.slate500),
            ),
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
              decoration: authInputDecoration(hint: '••••••••'),
              validator: (value) => (value == null || value.isEmpty) ? 'كلمة المرور مطلوبة' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? true),
                          activeColor: AppColors.indigo600,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('تذكرني على هذا الجهاز',
                          style: TextStyle(fontSize: 12.5, color: AppColors.slate700)),
                    ],
                  ),
                ),
                const Text('جلسة أسهل للطبيب', style: TextStyle(fontSize: 11, color: AppColors.slate500)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          GradientButton(
            label: 'تسجيل الدخول الرقمي',
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _submit,
          ),
          const SizedBox(height: 18),
          AuthBottomLinkRow(
            text: 'لا تملك حسابًا بعد؟',
            linkText: 'فعّل عيادتك الآن',
            onTap: _goToRegister,
          ),
          const SizedBox(height: 18),
          const Text(
            'إذا انتهت صلاحية الاشتراك، ستظهر لك رسالة واضحة لتجديد الوصول.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.slate500, height: 1.6),
          ),
          const SizedBox(height: 20),
          Text(
            'تطوير وإدارة: المهندس فارس حلاوي © 2026',
            textAlign: TextAlign.center,
            // مطابق لِـ text-indigo-500/90 في الموقع بالحرف (وليس indigo-600).
            style: TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: AppColors.indigo500.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}
