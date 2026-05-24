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

    if (!auth.isAuthenticated || user == null) return _buildGuest(context);

    final initial = user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [

        // ── Header ────────────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          backgroundColor: AppColors.midnight,
          elevation: 0,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.midnight, Color(0xFF1a3a6e)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Avatar
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.coral, Color(0xFFea6009)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.coral.withOpacity(0.4),
                            blurRadius: 20, offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(initial,
                          style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w800,
                            color: Colors.white, fontFamily: 'Cairo',
                          )),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(user.fullName,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.w800, fontFamily: 'Cairo',
                      )),
                    const SizedBox(height: 4),
                    Text(user.phone,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13, fontFamily: 'Cairo',
                      )),
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Stats row ──────────────────────────────────────────────────
            Row(children: [
              _StatCard(
                value: '${user.orderStreak}',
                label: 'يوم متواصل',
                icon: '🔥',
                color: AppColors.coral,
                bg: AppColors.peach,
              ),
              const SizedBox(width: 10),
              _StatCard(
                value: '${user.walletBalance.toStringAsFixed(0)} ج',
                label: 'المحفظة',
                icon: '💰',
                color: AppColors.mint,
                bg: AppColors.seafoam,
              ),
              const SizedBox(width: 10),
              _StatCard(
                value: '${user.loyaltyPoints}',
                label: 'نقطة',
                icon: '⭐',
                color: AppColors.gold,
                bg: AppColors.lemon,
              ),
            ]),

            const SizedBox(height: 20),

            // ── Menu card ──────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: AppColors.midnight.withOpacity(0.06),
                  blurRadius: 16, offset: const Offset(0, 4),
                )],
              ),
              child: Column(children: [
                _MenuItem(
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.coral,
                  iconBg: AppColors.peach,
                  label: 'عناوين التوصيل',
                  onTap: () => context.push('/profile/addresses'),
                ),
                _divider(),
                _MenuItem(
                  icon: Icons.star_rounded,
                  iconColor: AppColors.gold,
                  iconBg: AppColors.lemon,
                  label: 'نقاط الولاء',
                  badge: '+${user.loyaltyPoints}',
                  badgeColor: AppColors.gold,
                  onTap: () => context.push('/profile/points'),
                ),
                _divider(),
                _MenuItem(
                  icon: Icons.fingerprint_rounded,
                  iconColor: AppColors.sapphire,
                  iconBg: AppColors.ice,
                  label: 'إعداد البصمة',
                  onTap: () => context.push('/biometric-setup'),
                ),
                _divider(),
                _MenuItem(
                  icon: Icons.headset_mic_rounded,
                  iconColor: AppColors.mint,
                  iconBg: AppColors.seafoam,
                  label: 'خدمة العملاء',
                  onTap: () {},
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // ── App version ────────────────────────────────────────────────
            Center(
              child: Text('Shopping Market v1.0',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11, fontFamily: 'Cairo',
                )),
            ),

            const SizedBox(height: 12),

            // ── Logout ─────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  backgroundColor: AppColors.error.withOpacity(0.04),
                ),
                icon: const Icon(Icons.logout_rounded,
                    color: AppColors.error, size: 20),
                label: const Text('تسجيل الخروج',
                  style: TextStyle(
                    color: AppColors.error, fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700, fontSize: 15,
                  )),
                onPressed: () => _confirmLogout(context, auth),
              ),
            ),
            const SizedBox(height: 30),
          ]),
        )),
      ]),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 60, endIndent: 16, color: AppColors.border);

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تسجيل الخروج',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800,
              color: AppColors.textMain)),
        content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
          style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
              style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () { Navigator.pop(context); auth.logout(); },
            child: const Text('خروج',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white,
                  fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildGuest(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.midnight, elevation: 0,
      title: const Text('حسابي',
        style: TextStyle(fontFamily: 'Cairo', color: Colors.white,
            fontWeight: FontWeight.w700)),
    ),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(color: AppColors.ice, shape: BoxShape.circle),
          child: const Icon(Icons.person_outline_rounded,
              size: 52, color: AppColors.sapphire),
        ),
        const SizedBox(height: 24),
        const Text('مرحباً بك',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
              fontFamily: 'Cairo', color: AppColors.textMain)),
        const SizedBox(height: 10),
        const Text(
          'سجل الدخول للوصول إلى حسابك\nونقاط الولاء وعناوين التوصيل',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 14),
        ),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => context.push('/login'),
            child: const Text('تسجيل الدخول',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo', color: Colors.white)),
          )),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.push('/register'),
          child: const Text('إنشاء حساب جديد',
            style: TextStyle(color: AppColors.sapphire, fontFamily: 'Cairo',
                fontWeight: FontWeight.w600)),
        ),
      ]),
    )),
  );
}

// ── Stat card ──────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value, label, icon;
  final Color color, bg;
  const _StatCard({required this.value, required this.label,
      required this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 4),
      Text(value,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
            color: color, fontFamily: 'Cairo')),
      const SizedBox(height: 2),
      Text(label,
        style: TextStyle(fontSize: 10,
            color: color.withOpacity(0.7), fontFamily: 'Cairo')),
    ]),
  ));
}

// ── Menu item ──────────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String label;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon, required this.iconColor, required this.iconBg,
    required this.label, required this.onTap, this.badge, this.badgeColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        // Icon box
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        // Label
        Expanded(
          child: Text(label,
            style: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w600,
              fontSize: 14, color: AppColors.textMain,
            )),
        ),
        // Badge or chevron
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (badgeColor ?? AppColors.coral).withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(badge!,
              style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 11,
                color: badgeColor ?? AppColors.coral, fontFamily: 'Cairo',
              )),
          )
        else
          const Icon(Icons.chevron_left_rounded,
              color: AppColors.textMuted, size: 22),
      ]),
    ),
  );
}
