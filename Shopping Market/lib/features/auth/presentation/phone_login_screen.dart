import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/validators.dart';
import '../../../models/models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/firebase_phone_rest.dart';

/// Customer phone login — uses Firebase Phone Auth to send OTP.
/// The phone number is formatted as +20XXXXXXXXXX before being sent.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _phoneError;
  bool _isValid = false;
  Timer? _watchdog;

  @override
  void dispose() {
    _watchdog?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  /// Guarantees this screen's spinner always resolves.
  ///
  /// On iOS, `verifyPhoneNumber` can stall without ever invoking *any* of its
  /// callbacks — the native handler (FLTPhoneNumberVerificationStreamHandler.m)
  /// only emits `phoneCodeSent`/`phoneVerificationFailed` from FIRPhoneAuthProvider's
  /// completion block, so if that block never runs nothing fires at all.
  /// `codeAutoRetrievalTimeout` cannot rescue it: only Android's handler emits
  /// that event, and the `timeout:` argument is ignored on iOS entirely — so
  /// there is no SDK-level guarantee that `_isLoading` ever clears.
  ///
  /// This screen is not the one App Review screenshotted (that was the OTP
  /// screen — see otp_screen.dart's _verifyCredential), but the same class of
  /// stall applies here, so bound it too.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || !_isLoading) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر إرسال الكود، تحقّق من اتصالك وحاول مرة أخرى'),
        backgroundColor: AppColors.errorRed,
      ));
    });
  }

  void _validate(String value) {
    final local = _toLocalNumber(value);
    setState(() {
      _phoneError = Validators.egyptianPhone(local);
      _isValid = _phoneError == null && local.isNotEmpty;
    });
  }

  /// Normalises whatever the user typed into the canonical 11-digit local form
  /// (01XXXXXXXXX). Accepts a bare local number, or the full international form
  /// (+201XXXXXXXXX / 201XXXXXXXXX / 00201XXXXXXXXX) — the latter matters for
  /// App Review, whose sign-in notes hand the reviewer the full +20 number.
  String _toLocalNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), ''); // digits only
    if (d.startsWith('0020')) d = d.substring(4);
    if (d.startsWith('20') && d.length >= 12) d = d.substring(2);
    if (d.isNotEmpty && !d.startsWith('0')) d = '0$d';
    return d;
  }

  Future<void> _submit() async {
    if (!_isValid || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final localNumber = _toLocalNumber(_phoneController.text);
    // Firebase expects E.164 format: +20XXXXXXXXXX
    // Egyptian numbers: 01XXXXXXXXX → +2 + local → +201XXXXXXXXX
    final e164 = '+2$localNumber';

    await _startVerification(e164, localNumber);
  }

  /// [retried] guards against looping forever if the APNs handshake keeps failing.
  Future<void> _startVerification(String e164, String localNumber,
      {bool retried = false}) async {
    _startWatchdog();

    // Firebase test numbers (App Review's demo account) are allowlisted and
    // need no reCAPTCHA/APNs, so send the code over REST and skip the native
    // `verifyPhoneNumber` entirely — that native call is the one that stalls on
    // iOS and produced the "sign-in spinner spins forever" rejections. Real
    // numbers fall through to the SDK below because they still require reCAPTCHA.
    if (FirebasePhoneRest.isTestNumber(e164)) {
      try {
        final sessionInfo = await FirebasePhoneRest.sendVerificationCode(e164)
            .timeout(const Duration(seconds: 20));
        _watchdog?.cancel();
        if (!mounted) return;
        setState(() => _isLoading = false);
        context.push('/otp', extra: {
          'phone': localNumber,
          'verificationId': sessionInfo,
          'resendToken': null,
        });
      } catch (e) {
        _watchdog?.cancel();
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر إرسال الكود، حاول مرة أخرى\n$e'),
          backgroundColor: AppColors.errorRed,
        ));
      }
      return;
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: e164,
        // Android-only: how long to wait for SMS auto-retrieval. Ignored on iOS
        // (see _startWatchdog), which is why the watchdog above — not this — is
        // what guarantees the spinner resolves.
        timeout: const Duration(seconds: 20),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android auto-retrieval — sign in immediately without user input.
          _watchdog?.cancel();
          await _signInWithCredential(credential, localNumber);
        },
        verificationFailed: (FirebaseAuthException e) async {
          _watchdog?.cancel();
          // iOS-only: on a fresh install, Firebase Auth's one-time APNs
          // silent-push handshake can fire before the device's push token has
          // finished registering with Apple, throwing this even though the
          // app/Firebase/APNs config is all correct. Retrying once — by which
          // point the token has almost always arrived — resolves it silently
          // instead of dead-ending the user (this is exactly what blocked App
          // Review's login attempt with the demo account).
          if (!retried && e.code == 'notification-not-forwarded') {
            await Future.delayed(const Duration(seconds: 2));
            if (!mounted) return;
            await _startVerification(e164, localNumber, retried: true);
            return;
          }
          if (!mounted) return;
          setState(() => _isLoading = false);
          // ignore: avoid_print — temporary until the real Play Integrity/billing
          // cause is confirmed; e.code alone ("unknown") hides the actual reason.
          print('verifyPhoneNumber failed — code: ${e.code}, plugin: ${e.plugin}, message: ${e.message}');
          final msg = _friendlyError(e.code);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$msg\n${e.message ?? ""}'),
            backgroundColor: AppColors.errorRed,
          ));
        },
        codeSent: (String verificationId, int? resendToken) {
          _watchdog?.cancel();
          if (!mounted) return;
          setState(() => _isLoading = false);
          context.push('/otp', extra: {
            'phone': localNumber,
            'verificationId': verificationId,
            'resendToken': resendToken,
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Android-only, and NOT an error: it just means the SMS auto-read
          // window closed and the user should type the code themselves. It
          // fires ~20s after codeSent has already pushed the OTP screen, so
          // surfacing a failure here (as build 16 did) shows a bogus "sending
          // timed out" error over a working OTP screen. The watchdog covers
          // the genuine "nothing ever resolved" case on both platforms.
        },
      );
    } catch (e) {
      // verifyPhoneNumber itself threw before any callback fired (e.g. a
      // platform-level config error) — without this, _isLoading would stay
      // true forever and the button would look permanently stuck.
      _watchdog?.cancel();
      if (!mounted) return;
      setState(() => _isLoading = false);
      print('verifyPhoneNumber threw synchronously: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر إرسال الكود، حاول مرة أخرى\n$e'),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }

  /// Android auto-retrieval path: Firebase reads the SMS itself and hands us a
  /// credential without the user typing it. This must complete the SAME full
  /// login as the OTP screen — sign in to Firebase, exchange the ID token for
  /// our backend JWT, and mark the session authenticated — otherwise the router
  /// sees an unauthenticated user on /home and bounces back to /login.
  Future<void> _signInWithCredential(
      PhoneAuthCredential credential, String phone) async {
    try {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) throw Exception('Firebase token missing');

      final res =
          await ApiService().firebaseTokenLogin(idToken: idToken, phone: phone);
      final UserModel user = res['user'] is Map
          ? UserModel.fromJson(Map<String, dynamic>.from(res['user']))
          : await ApiService().getProfile();

      if (!mounted) return;
      await context.read<AuthProvider>().setAuthenticated(user);
      final isNew = res['is_new_user'] == true;
      context.go(isNew ? '/profile-complete' : '/home');
    } catch (_) {
      // Auto-retrieval failed silently — leave the user on the OTP screen so
      // they can enter the code manually instead of getting bounced.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'رقم الهاتف غير صحيح';
      case 'too-many-requests':
        return 'تم تجاوز الحد المسموح — حاول لاحقاً';
      case 'quota-exceeded':
        return 'تم تجاوز حصة الرسائل اليوم';
      default:
        return 'فشل الإرسال ($code)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('تسجيل الدخول'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingH),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Text(
                  'أدخل رقم هاتفك',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 28),
                _buildPhoneField(),
                if (_phoneError != null &&
                    _phoneController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _phoneError!,
                    style:
                        const TextStyle(color: AppColors.errorRed, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: (_isValid && !_isLoading) ? _submit : null,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('متابعة'),
                ),
                const SizedBox(height: 24),
                _socialDivider(),
                const SizedBox(height: 16),
                if (Platform.isIOS) ...[
                  _socialButton(
                    label: 'الدخول بحساب Apple',
                    onTap: _appleSignIn,
                  ),
                  const SizedBox(height: 12),
                ],
                _socialButton(
                  label: 'الدخول بحساب Google',
                  onTap: _googleSignIn,
                ),
                const SizedBox(height: 20),
                // Guest browsing — required by App Store guideline 5.1.1(v):
                // features that aren't account-based (browsing products) must
                // be reachable without registering or logging in.
                TextButton(
                  onPressed: _isLoading ? null : _continueAsGuest,
                  child: const Text(
                    'تصفّح بدون تسجيل الدخول',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Enters the app as a guest so products can be browsed without an account.
  /// Account-based routes (cart checkout, orders, profile) still redirect to
  /// login via the router's guest guard.
  void _continueAsGuest() {
    context.read<AuthProvider>().browseAsGuest();
    context.go('/home');
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        border: Border.all(
          color: _phoneError != null && _phoneController.text.isNotEmpty
              ? AppColors.errorRed
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: const [
                Text('🇪🇬', style: TextStyle(fontSize: 18)),
                SizedBox(width: 6),
                Text('+20',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontFamily: 'Inter',
                    )),
              ],
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.appBarDivider),
          Expanded(
            child: TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 15,
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
                fontSize: 16,
              ),
              decoration: const InputDecoration(
                hintText: '01xxxxxxxxx',
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
              onChanged: _validate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialDivider() => Row(
        children: const [
          Expanded(child: Divider(color: AppColors.appBarDivider)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child:
                Text('أو', style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Divider(color: AppColors.appBarDivider)),
        ],
      );

  Widget _socialButton({required String label, required VoidCallback onTap}) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.appBarDivider),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Future<void> _googleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      // Sign out first so the account picker always appears (avoids silently
      // reusing a previously-selected account).
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User cancelled the picker.
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      await _completeSocialLogin(
        provider: 'google',
        socialId: account.id,
        email: account.email,
        fullName: account.displayName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر تسجيل الدخول عبر Google'),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }

  /// Apple only returns the user's name on the very first authorization —
  /// the backend verifies `identityToken` itself (see apple_auth.py) rather
  /// than trusting a client-supplied id, so `socialId` here is just a
  /// fallback the server ignores once it decodes the token.
  Future<void> _appleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final fullName = [credential.givenName, credential.familyName]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');
      await _completeSocialLogin(
        provider: 'apple',
        socialId: credential.userIdentifier ?? '',
        email: credential.email,
        fullName: fullName.isNotEmpty ? fullName : null,
        token: credential.identityToken,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e.code == AuthorizationErrorCode.canceled) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر تسجيل الدخول عبر Apple'),
        backgroundColor: AppColors.errorRed,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر تسجيل الدخول عبر Apple'),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }

  /// Sends the provider profile to the backend. New social users must supply a
  /// phone number, so on the backend's "phone required" response we prompt for
  /// one and retry. On success we route to the home screen.
  Future<void> _completeSocialLogin({
    required String provider,
    required String socialId,
    String? email,
    String? fullName,
    String? phone,
    String? token,
  }) async {
    final auth = context.read<AuthProvider>();
    final result = await auth.handleSocialLogin(
      provider: provider,
      socialId: socialId,
      email: email,
      fullName: fullName,
      phone: phone,
      token: token,
    );
    if (!mounted) return;

    switch (result) {
      case SocialLoginResult.success:
        context.go('/home');
        return;
      case SocialLoginResult.needsPhone:
        // New user — backend needs a phone number before creating the account.
        final entered = await _askForPhone();
        if (!mounted) return;
        if (entered == null) {
          setState(() => _isLoading = false);
          return;
        }
        await _completeSocialLogin(
          provider: provider,
          socialId: socialId,
          email: email,
          fullName: fullName,
          phone: entered,
          token: token,
        );
        return;
      case SocialLoginResult.failed:
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error ?? 'فشل تسجيل الدخول'),
          backgroundColor: AppColors.errorRed,
        ));
        return;
    }
  }

  /// Bottom-sheet prompting a new social user for their Egyptian phone number.
  /// Returns the local number (e.g. 01xxxxxxxxx) or null if cancelled.
  Future<String?> _askForPhone() {
    final ctrl = TextEditingController();
    String? err;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('أدخل رقم هاتفك لإكمال التسجيل',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              autofocus: true,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                prefixText: '+20  ',
                prefixStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '01xxxxxxxxx',
                counterText: '',
                errorText: err,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final v = ctrl.text.trim();
                  final e = Validators.egyptianPhone(v);
                  if (e != null) {
                    setSheet(() => err = e);
                    return;
                  }
                  Navigator.pop(sheetCtx, v);
                },
                child: const Text('متابعة'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
