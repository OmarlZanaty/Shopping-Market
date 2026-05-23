import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class BiometricSetupScreen extends StatelessWidget {
  const BiometricSetupScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 100, height: 100,
            decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.fingerprint, color: AppColors.sapphire, size: 56)),
          const SizedBox(height: 24),
          const Text('تفعيل بصمة الإصبع', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.midnight, fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          const Text('سجل الدخول بسرعة وأمان باستخدام بصمة إصبعك', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 14)),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            onPressed: () async {
              final ok = await auth.registerBiometric();
              if (context.mounted) context.go('/home');
            },
            child: const Text('تفعيل البصمة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
          )),
          const SizedBox(height: 14),
          TextButton(onPressed: () => context.go('/home'),
            child: const Text('تخطي الآن', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo'))),
        ]),
      )),
    );
  }
}
