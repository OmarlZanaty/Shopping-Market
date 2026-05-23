import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/validators.dart';
import '../auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _serverError;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _loading) return;
    setState(() { _loading = true; _serverError = null; });
    try {
      await ref.read(agentAuthControllerProvider.notifier).login(
        _phone.text.trim(), _password.text,
      );
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      setState(() => _serverError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingH * 1.5),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Container(
                  width: 80, height: 80,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.accentOrange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront, color: Colors.white, size: 48),
                ),
                const Center(
                  child: Text('Shopping Market — Agent',
                    style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 22,
                      fontWeight: FontWeight.bold,
                    )),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text('تسجيل دخول طاقم العمل',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ),
                const SizedBox(height: 36),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter'),
                  decoration: const InputDecoration(
                    hintText: '01xxxxxxxxx',
                    prefixIcon: Icon(Icons.phone, color: AppColors.textSecondary),
                  ),
                  validator: Validators.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  validator: Validators.password,
                ),
                if (_serverError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withOpacity(0.1),
                      border: Border.all(color: AppColors.errorRed),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.errorRed),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_serverError!, style: const TextStyle(color: AppColors.errorRed))),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('تسجيل الدخول'),
                ),
                const Spacer(),
                const Center(
                  child: Text('للحصول على حساب، تواصل مع الإدارة',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
