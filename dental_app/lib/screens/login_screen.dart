import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../theme/app_theme.dart';

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
  // -- كل المنطق أدناه محفوظ بالضبط كما كان قبل إعادة التصميم البصري: نفس
  // الحقول ونفس تسلسل النداءات (login -> saveSession -> onLoginSuccess) ونفس
  // معالجة الأخطاء -- لم يتغيّر إلا الشكل. --
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'حدث خطأ غير متوقع. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final borderRadius = BorderRadius.circular(14);
    final border = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
      prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.85)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: Colors.white, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: AppColors.rose200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // خلفية بتدرج لوني كامل مطابق لصفحة تسجيل الدخول في الموقع، مع
          // دوائر زخرفية باهتة (نفس أسلوب login.html).
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppColors.loginBackgroundGradient),
              child: Stack(
                children: [
                  Positioned(
                    top: -70,
                    right: -60,
                    child: _decorativeCircle(220, Colors.white.withValues(alpha: 0.06)),
                  ),
                  Positioned(
                    bottom: -90,
                    left: -70,
                    child: _decorativeCircle(260, Colors.white.withValues(alpha: 0.05)),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // شارة زجاجية دائرية بأيقونة العيادة (glass-morphism logo badge).
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.medical_services_rounded,
                            size: 40, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'عيادتي الرقمية',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تطبيق الطبيب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(
                              label: 'البريد الإلكتروني',
                              icon: Icons.email_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'البريد الإلكتروني مطلوب';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(
                              label: 'كلمة المرور',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'كلمة المرور مطلوبة';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.rose200.withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          // زر بيضاوي أبيض مصمت -- نفس زر الدخول في الموقع.
                          Opacity(
                            opacity: _isLoading ? 0.75 : 1,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isLoading ? null : _submit,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: _isLoading
                                      ? const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation(
                                                  AppColors.indigo700),
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'دخول',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: AppColors.indigo700,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15.5,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'استخدم نفس بيانات الدخول التي تستخدمها في موقع العيادة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decorativeCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
