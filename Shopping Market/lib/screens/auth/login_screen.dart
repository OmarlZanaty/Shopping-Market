import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _hasBiometric = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final auth = context.read<AuthProvider>();
    final storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final token = await storage.read(key: StorageKeys.biometricToken);
    final available = await auth.isBiometricAvailable;
    if (mounted) setState(() => _hasBiometric = available && token != null);
  }

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
                        const SizedBox(height: 40),
                        // Logo
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Shopping Market', style: TextStyle(color: AppColors.sky, fontSize: 24, letterSpacing: 4, fontFamily: 'Cairo')),
                        const SizedBox(height: 48),
                        // Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                          child: Column(children: [
                            const Align(alignment: Alignment.centerRight,
                                child: Text('تسجيل الدخول', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.midnight, fontFamily: 'Cairo'))),
                            const SizedBox(height: 20),
                            TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined),
                                    hintText: '01000000000')),
                            const SizedBox(height: 14),
                            TextField(controller: _passCtrl, obscureText: _obscure,
                                decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                        onPressed: () => setState(() => _obscure = !_obscure)))),
                            if (auth.error != null) ...[
                              const SizedBox(height: 10),
                              Text(auth.error!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontFamily: 'Cairo')),
                            ],
                            const SizedBox(height: 20),
                            // Login button
                            SizedBox(width: double.infinity, height: 52,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.midnight, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                  onPressed: auth.isLoading ? null : () async {
                                    final ok = await auth.login(_phoneCtrl.text.trim(), _passCtrl.text);
                                    if (ok && mounted) context.go('/home');
                                  },
                                  child: auth.isLoading
                                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                      : const Text('دخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                                )),
                            // Biometric
                            if (_hasBiometric) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: const BorderSide(color: AppColors.sky)),
                                icon: const Icon(Icons.fingerprint, color: AppColors.sapphire),
                                label: const Text('دخول ببصمة الإصبع', style: TextStyle(color: AppColors.sapphire, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                                onPressed: () async {
                                  final ok = await auth.loginWithBiometric();
                                  if (ok && mounted) context.go('/home');
                                },
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('ليس لديك حساب؟', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                              TextButton(onPressed: () => context.go('/register'),
                                  child: const Text('سجل الآن', style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                            ]),
                          ]),
                        ),
                        const Expanded(child: SizedBox()), // pushes content up, fills bottom with gradient
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