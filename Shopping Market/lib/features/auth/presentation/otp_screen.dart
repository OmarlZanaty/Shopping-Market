import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../providers/auth_provider.dart' as app_auth;
import '../../../services/api_service.dart';
import '../../../models/models.dart';

/// 6-box OTP entry — verifies via Firebase, then exchanges Firebase ID token
/// for our Django JWT at POST /auth/firebase-token/.
class OtpScreen extends StatefulWidget {
  final String phone;
  final String verificationId;
  final int? resendToken;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.verificationId,
    this.resendToken,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  static const int _otpLength = 6;
  static const int _resendCooldownSec = 60;

  final List<TextEditingController> _ctrls =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focus =
      List.generate(_otpLength, (_) => FocusNode());

  late AnimationController _shake;
  late Animation<double> _shakeAnim;

  Timer? _resendTimer;
  int _resendIn = _resendCooldownSec;
  bool _isVerifying = false;
  bool _hasError = false;

  // Mutable verificationId — updated after resend.
  late String _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shake);
    _startResendCountdown();
    _focus[0].requestFocus();
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final f in _focus) f.dispose();
    _resendTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendIn = _resendCooldownSec;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _resend({bool retried = false}) async {
    if (!retried && _resendIn > 0) return;
    final e164 = '+2${widget.phone}';
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        await _verifyCredential(credential);
      },
      verificationFailed: (e) async {
        // Same transient iOS APNs-handshake race as the initial send — see
        // phone_login_screen.dart's _startVerification for details.
        if (!retried && e.code == 'notification-not-forwarded') {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          await _resend(retried: true);
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل إعادة الإرسال: ${e.code}'),
          backgroundColor: AppColors.errorRed,
        ));
      },
      codeSent: (newVerificationId, newResendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = newVerificationId;
          _resendToken = newResendToken;
        });
        _startResendCountdown();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إرسال الكود مجدداً'),
          backgroundColor: AppColors.successGreen,
        ));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  String get _code => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_isVerifying) return;
    final code = _code;
    if (code.length != _otpLength) return;

    setState(() {
      _isVerifying = true;
      _hasError = false;
    });
    FocusScope.of(context).unfocus();

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: code,
    );
    await _verifyCredential(credential);
  }

  Future<void> _verifyCredential(PhoneAuthCredential credential) async {
    try {
      // 1. Verify with Firebase
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) throw Exception('Firebase token missing');

      // 2. Exchange Firebase ID token for our Django JWT
      final res = await ApiService().firebaseTokenLogin(
        idToken: idToken,
        phone: widget.phone,
      );

      // 3. Persist user data + update AuthProvider so router unlocks.
      // The /auth/firebase-token/ response only returns {access, refresh,
      // is_new_user} — there is NO `user` object. The tokens are already
      // saved inside firebaseTokenLogin(), so fetch the profile to populate
      // AuthProvider. (Previously we threw 'Invalid user data' here, which
      // blocked login from completing even though the tokens had persisted —
      // the user kept landing back on the OTP screen.)
      final UserModel user = res['user'] is Map
          ? UserModel.fromJson(Map<String, dynamic>.from(res['user']))
          : await ApiService().getProfile();

      if (!mounted) return;
      // setAuthenticated is now async (persists to storage) — await it so
      // the user data is saved before we navigate.
      await context.read<app_auth.AuthProvider>().setAuthenticated(user);

      final isNew = res['is_new_user'] == true;
      context.go(isNew ? '/profile-complete' : '/home');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isVerifying = false;
      });
      _shake.forward(from: 0).whenComplete(() => _shake.reverse());
      final msg = e.code == 'invalid-verification-code'
          ? 'الكود غير صحيح'
          : 'خطأ في التحقق (${e.code})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.errorRed,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isVerifying = false;
      });
      _shake.forward(from: 0).whenComplete(() => _shake.reverse());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_friendlyApiError(e)),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }

  /// Turns a raw API/Dio error into a readable Arabic message. Surfaces the
  /// server's reason for 403s (blocked / inactive account) instead of dumping
  /// the raw DioException text.
  String _friendlyApiError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final serverMsg =
          (data is Map ? data['message'] : null)?.toString() ?? '';
      if (code == 403) {
        if (serverMsg.toLowerCase().contains('block')) {
          return 'تم حظر هذا الحساب. برجاء التواصل مع الدعم.';
        }
        return 'هذا الحساب غير مُفعّل. برجاء التواصل مع الدعم.';
      }
      if (serverMsg.isNotEmpty) return serverMsg;
      return 'تعذّر تسجيل الدخول. حاول مرة أخرى.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  void _onChanged(int i, String value) {
    if (value.length == 1 && i < _otpLength - 1) {
      _focus[i + 1].requestFocus();
    }
    if (value.isEmpty && i > 0) {
      _focus[i - 1].requestFocus();
    }
    if (i == _otpLength - 1 && value.length == 1) {
      _verify();
    }
    setState(() => _hasError = false);
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
        title: const Text('تأكيد الكود'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'أرسلنا كود التحقق إلى',
                style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              Text(
                '+20${widget.phone}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentOrange,
                  fontFamily: 'Inter',
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final dx = _shake.isAnimating ? _shakeAnim.value : 0.0;
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_otpLength, _otpBox),
                ),
              ),
              const SizedBox(height: 24),
              if (_isVerifying)
                const Center(child: CircularProgressIndicator())
              else
                Center(
                  child: _resendIn > 0
                      ? Text(
                          'إعادة الإرسال خلال $_resendIn ثانية',
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        )
                      : TextButton(
                          onPressed: _resend,
                          child: const Text('إعادة إرسال'),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int i) {
    final isFilled = _ctrls[i].text.isNotEmpty;
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _ctrls[i],
        focusNode: _focus[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        textInputAction:
            i < _otpLength - 1 ? TextInputAction.next : TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          fontFamily: 'Inter',
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.backgroundSecondary,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: BorderSide(
              color: _hasError
                  ? AppColors.errorRed
                  : (isFilled ? AppColors.accentOrange : Colors.transparent),
              width: _hasError || isFilled ? 2 : 0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide:
                const BorderSide(color: AppColors.accentOrange, width: 2),
          ),
        ),
        onChanged: (v) => _onChanged(i, v),
      ),
    );
  }
}
