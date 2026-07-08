import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/auth_provider.dart';
import '../../../utils/constants.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (!auth.isAuthenticated || user == null) return _buildGuest(context);

    final initial = user.fullName.isNotEmpty
        ? user.fullName[0].toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [

        // ── Header ──────────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          backgroundColor: AppColors.midnight,
          elevation: 0,
          actions: [
            // Edit profile button
            IconButton(
              icon: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_rounded,
                    color: Colors.white, size: 18),
              ),
              onPressed: () => _showEditSheet(context, auth),
              tooltip: 'تعديل الملف الشخصي',
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.midnight, Color(0xFF2D2D4E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Avatar with edit indicator
                    Stack(
                      children: [
                        Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.coral, Color(0xFFFF6B00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.coral.withOpacity(0.45),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(initial,
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  fontFamily: 'Cairo',
                                )),
                          ),
                        ),
                        // Small edit badge
                        Positioned(
                          bottom: 0, right: 0,
                          child: GestureDetector(
                            onTap: () => _showEditSheet(context, auth),
                            child: Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.midnight, width: 2),
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text(user.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                        )),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.phone_rounded,
                          color: Colors.white38, size: 13),
                      const SizedBox(width: 4),
                      Text(user.phone,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          )),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Stats row
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

              // Edit profile card (quick access)
              GestureDetector(
                onTap: () => _showEditSheet(context, auth),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.coral.withOpacity(0.08),
                        AppColors.gold.withOpacity(0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.coral.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.coral, Color(0xFFFF6B00)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تعديل الملف الشخصي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textMain,
                              )),
                          SizedBox(height: 2),
                          Text('تغيير الاسم ورقم الهاتف',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textMuted,
                              )),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left_rounded,
                        color: AppColors.coral, size: 22),
                  ]),
                ),
              ),

              const SizedBox(height: 16),

              // Menu card
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
                    badge: '${user.loyaltyPoints} نقطة',
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
                    onTap: () => _showSupportSheet(context),
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              Center(
                child: Text('Shopping Market v1.0',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                    )),
              ),

              const SizedBox(height: 16),

              // Logout button
              SizedBox(
                width: double.infinity,
                height: 52,
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
                        color: AppColors.error,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                  onPressed: () => _confirmLogout(context, auth),
                ),
              ),
              const SizedBox(height: 12),

              // Delete account button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_forever_rounded,
                      color: AppColors.textMuted, size: 20),
                  label: const Text('حذف الحساب نهائياً',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      )),
                  onPressed: () => _confirmDeleteAccount(context, auth),
                ),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Edit profile bottom sheet ──────────────────────────────────────────────
  void _showEditSheet(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(auth: auth),
    );
  }

  // ── Contact support bottom sheet ───────────────────────────────────────────
  static const List<String> _supportNumbers = ['01126555088', '01126544999'];

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.seafoam,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.headset_mic_rounded,
                  color: AppColors.mint, size: 20),
            ),
            const SizedBox(width: 14),
            const Text('خدمة العملاء',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  color: AppColors.textMain,
                )),
          ]),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('تواصل معنا عبر الاتصال أو واتساب',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Cairo',
                  color: AppColors.textMuted,
                )),
          ),
          const SizedBox(height: 16),
          for (final number in _supportNumbers) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(number,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.textMain,
                      )),
                ),
                _supportAction(
                  context,
                  icon: Icons.call_rounded,
                  color: AppColors.mint,
                  onTap: () => _launch(context, Uri(scheme: 'tel', path: number)),
                ),
                const SizedBox(width: 10),
                _supportAction(
                  context,
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF25D366),
                  onTap: () => _launch(
                      context, Uri.parse('https://wa.me/2$number')),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _supportAction(BuildContext context,
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح التطبيق',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _divider() => const Divider(
      height: 1, indent: 60, endIndent: 16, color: AppColors.border);

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      // dialogCtx is the BuildContext INSIDE the dialog overlay (root nav).
      // We must use it (not the outer `context`) — the outer one points at
      // the ShellRoute's inner Navigator, and popping that pops the profile
      // page itself, which crashes with "popped the last page off the stack".
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('تسجيل الخروج',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
            )),
        content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
            style: TextStyle(
                fontFamily: 'Cairo', color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              // Close the dialog using the dialog's own (root) navigator.
              Navigator.pop(dialogCtx);
              // auth.logout() flips status synchronously; GoRouter's
              // refreshListenable then redirects /profile → /login.
              // No manual context.go() — it would race the redirect.
              auth.logout();
            },
            child: const Text('خروج',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('حذف الحساب نهائياً',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
            )),
        content: const Text(
          'سيتم حذف بياناتك الشخصية (الاسم، البريد الإلكتروني، العناوين) نهائياً ولن '
          'تتمكن من تسجيل الدخول بهذا الحساب مرة أخرى. سجل طلباتك السابقة يُحتفظ به '
          'بشكل مجهول لأغراض محاسبية فقط. هل تريد المتابعة؟',
          style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء',
                style:
                    TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final ok = await auth.deleteAccount();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(auth.error ?? 'تعذّر حذف الحساب'),
                  backgroundColor: AppColors.error,
                ));
              }
              // On success auth.deleteAccount() flips status to
              // unauthenticated synchronously — GoRouter's refreshListenable
              // redirects away, same as logout().
            },
            child: const Text('حذف نهائياً',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildGuest(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.midnight,
          elevation: 0,
          title: const Text('حسابي',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
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
                      shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline_rounded,
                      size: 52, color: AppColors.coral),
                ),
                const SizedBox(height: 24),
                const Text('مرحباً بك',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                      color: AppColors.textMain,
                    )),
                const SizedBox(height: 10),
                const Text(
                  'سجل الدخول للوصول إلى حسابك\nونقاط الولاء وعناوين التوصيل',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontFamily: 'Cairo',
                      fontSize: 14),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                          color: Colors.white,
                        )),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('إنشاء حساب جديد',
                      style: TextStyle(
                          color: AppColors.sapphire,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Edit Profile Bottom Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _EditProfileSheet extends StatefulWidget {
  final AuthProvider auth;
  const _EditProfileSheet({required this.auth});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.auth.user?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: widget.auth.user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });

    final ok = await widget.auth.updateProfile(
      fullName: _nameCtrl.text.trim(),
      phone:    _phoneCtrl.text.trim(),
    );

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم تحديث الملف الشخصي بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.mint,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      setState(() {
        _error = widget.auth.error ?? 'حدث خطأ، حاول مجدداً';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 44, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.coral, Color(0xFFFF6B00)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Text('تعديل الملف الشخصي',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  color: AppColors.textMain,
                )),
          ]),
          const SizedBox(height: 24),

          // Name field
          _buildField(
            controller: _nameCtrl,
            label: 'الاسم الكامل',
            icon: Icons.person_rounded,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'يرجى إدخال الاسم';
              if (v.trim().length < 2) return 'الاسم قصير جداً';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Phone field
          _buildField(
            controller: _phoneCtrl,
            label: 'رقم الهاتف',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'يرجى إدخال رقم الهاتف';
              if (v.trim().length < 7) return 'رقم الهاتف غير صحيح';
              return null;
            },
          ),

          // Error message
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        fontFamily: 'Cairo',
                      )),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 24),

          // Buttons row
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    )),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5,
                        ))
                    : const Text('حفظ التغييرات',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white,
                        )),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 14,
        color: AppColors.textMain,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: AppColors.textMuted,
        ),
        prefixIcon: Icon(icon, color: AppColors.coral, size: 20),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.coral, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value, label, icon;
  final Color color, bg;
  const _StatCard({
    required this.value, required this.label,
    required this.icon,  required this.color, required this.bg,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
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
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color,
                  fontFamily: 'Cairo',
                )),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.7),
                  fontFamily: 'Cairo',
                )),
          ]),
        ),
      );
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
    required this.icon,       required this.iconColor,
    required this.iconBg,     required this.label,
    required this.onTap,      this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textMain,
                  )),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppColors.coral).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(badge!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: badgeColor ?? AppColors.coral,
                      fontFamily: 'Cairo',
                    )),
              )
            else
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.textMuted, size: 22),
          ]),
        ),
      );
}
