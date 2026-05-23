import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [AppColors.midnight, Color(0xFF1a3a6e)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        )),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const SizedBox(height: 24),
                        Container(width: 60, height: 60,
                            decoration: BoxDecoration(color: AppColors.sapphire, borderRadius: BorderRadius.circular(18)),
                            child: const Icon(Icons.shopping_basket_rounded, color: Colors.white, size: 30)),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                          child: Column(children: [
                            const Align(alignment: Alignment.centerRight,
                                child: Text('إنشاء حساب جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.midnight, fontFamily: 'Cairo'))),
                            const SizedBox(height: 20),
                            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل', prefixIcon: Icon(Icons.person_outline))),
                            const SizedBox(height: 14),
                            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined))),
                            const SizedBox(height: 14),
                            TextField(controller: _passCtrl, obscureText: _obscure,
                                decoration: InputDecoration(labelText: 'كلمة المرور (6+ أحرف)', prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                        onPressed: () => setState(() => _obscure = !_obscure)))),
                            if (auth.error != null) ...[
                              const SizedBox(height: 10),
                              Text(auth.error!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontFamily: 'Cairo')),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(width: double.infinity, height: 52,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                  onPressed: auth.isLoading ? null : () async {
                                    if (_nameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty || _passCtrl.text.length < 6) return;
                                    final ok = await auth.register(phone: _phoneCtrl.text.trim(), fullName: _nameCtrl.text.trim(), password: _passCtrl.text);
                                    if (ok && mounted) context.go('/biometric-setup');
                                  },
                                  child: auth.isLoading
                                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                      : const Text('إنشاء الحساب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                                )),
                            const SizedBox(height: 16),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('لديك حساب؟', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                              TextButton(onPressed: () => context.go('/login'),
                                  child: const Text('سجل الدخول', style: TextStyle(color: AppColors.sapphire, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                            ]),
                          ]),
                        ),
                        const Expanded(child: SizedBox()), // fills remaining space with gradient
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}