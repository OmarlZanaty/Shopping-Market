import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/constants.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    // Not logged in — show friendly prompt
    if (!auth.isAuthenticated || user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('حسابي',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.midnight,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.ice,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      size: 52, color: AppColors.sapphire),
                ),
                const SizedBox(height: 24),
                const Text('مرحباً بك',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo', color: AppColors.midnight)),
                const SizedBox(height: 10),
                const Text(
                  'سجل الدخول للوصول إلى حسابك ونقاط الولاء وعناوين التوصيل',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted,
                      fontFamily: 'Cairo', fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.coral,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => context.push('/login'),
                    child: const Text('تسجيل الدخول',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('إنشاء حساب جديد',
                      style: TextStyle(color: AppColors.sapphire,
                          fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: AppColors.midnight,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                  gradient: AppColors.headerGradient),
              child: SafeArea(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.sapphire,
                    child: Text(
                      user.fullName.isNotEmpty ? user.fullName[0] : 'U',
                      style: const TextStyle(fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.white, fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(user.fullName,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 18, fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo')),
                  Text(user.phone,
                      style: const TextStyle(color: AppColors.sky,
                          fontSize: 13, fontFamily: 'Cairo')),
                ],
              )),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _statCard('${user.loyaltyPoints}', 'نقطة',
                  AppColors.gold, AppColors.lemon),
              const SizedBox(width: 10),
              _statCard('${user.walletBalance.toStringAsFixed(0)} ج',
                  'المحفظة', AppColors.mint, AppColors.seafoam),
              const SizedBox(width: 10),
              _statCard('🔥 ${user.orderStreak}', 'يوم متواصل',
                  AppColors.coral, AppColors.peach),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border)),
              child: Column(children: [
                _menuItem(Icons.location_on_outlined, 'عناوين التوصيل',
                        () => context.push('/profile/addresses')),
                _divider(),
                _menuItem(Icons.star_rounded, 'نقاط الولاء',
                        () => context.push('/profile/points'),
                    trailing: Text('+${user.loyaltyPoints}',
                        style: const TextStyle(color: AppColors.gold,
                            fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                _divider(),
                _menuItem(Icons.fingerprint, 'إعداد البصمة',
                        () => context.push('/biometric-setup')),
                _divider(),
                _menuItem(Icons.headset_mic_outlined, 'خدمة العملاء', () {}),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                label: const Text('تسجيل الخروج',
                    style: TextStyle(color: AppColors.error,
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                onPressed: () {
                  auth.logout();
                },
              ),
            ),
          ),
          const SizedBox(height: 30),
        ])),
      ]),
    );
  }

  Widget _statCard(String value, String label, Color textColor, Color bgColor) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: textColor.withOpacity(0.2))),
        child: Column(children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w700,
              fontSize: 18, color: textColor, fontFamily: 'Cairo')),
          Text(label, style: TextStyle(fontSize: 10,
              color: textColor.withOpacity(0.7), fontFamily: 'Cairo')),
        ]),
      ));

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
      {Widget? trailing}) =>
      ListTile(
        leading: Icon(icon, color: AppColors.sapphire),
        title: Text(label, style: const TextStyle(
            fontFamily: 'Cairo', fontWeight: FontWeight.w500)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted),
        onTap: onTap,
      );

  Widget _divider() => const Divider(height: 1, indent: 56, endIndent: 16);
}

// Add missing color constants reference
extension ColorExt on Color {
  static const seafoam = Color(0xFFECFDF5);
  static const peach = Color(0xFFFFF7ED);
  static const lemon = Color(0xFFFFFBEB);
}