import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/storage/secure_storage_keys.dart';
import '../../../services/api_service.dart';
import '../../../models/models.dart';

/// 6-box OTP entry. Auto-submits on the 6th digit. 60-second resend lockout.
/// Shake + red border on wrong code.
class OtpScreen extends StatefulWidget {
  final String phone;
  final String? debugCode;

  const OtpScreen({super.key, required this.phone, this.debugCode});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shake);
    _startResendCountdown();

    // Auto-fill the debug code from the response, if running in dev.
    final dbg = widget.debugCode;
    if (dbg != null && dbg.length == _otpLength) {
      for (var i = 0; i < _otpLength; i++) {
        _ctrls[i].text = dbg[i];
      }
      // Slight delay so the UI renders before auto-submit.
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    } else {
      _focus[0].requestFocus();
    }
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

  Future<void> _resend() async {
    if (_resendIn > 0) return;
    try {
      await ApiService().sendOtp(widget.phone);
      _startResendCountdown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم إرسال الكود مجدداً'),
        backgroundColor: AppColors.successGreen,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل الإرسال: $e'),
        backgroundColor: AppColors.errorRed,
      ));
    }
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

    try {
      final res = await ApiService().verifyOtp(widget.phone, code);
      // Tokens were saved by ApiService. Persist user data.
      if (res['user'] is Map) {
        const storage = FlutterSecureStorage();
        final user = UserModel.fromJson(Map<String, dynamic>.from(res['user']));
        await storage.write(key: SecureStorageKeys.userData, value: user.toJson().toString());
      }
      if (!mounted) return;
      final isNew = res['is_new_user'] == true;
      context.go(isNew ? '/profile-complete' : '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _hasError = true);
      _shake.forward(from: 0).whenComplete(() => _shake.reverse());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('ApiException: ', '')),
        backgroundColor: AppColors.errorRed,
      ));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
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
              Text(
                'أرسلنا كود التحقق إلى',
                style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
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
                          style: const TextStyle(color: AppColors.textSecondary),
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
        textInputAction: i < _otpLength - 1 ? TextInputAction.next : TextInputAction.done,
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
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: BorderSide(
              color: _hasError
                  ? AppColors.errorRed
                  : (isFilled ? AppColors.accentOrange : Colors.transparent),
              width: _hasError || isFilled ? 2 : 0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            borderSide: const BorderSide(color: AppColors.accentOrange, width: 2),
          ),
        ),
        onChanged: (v) => _onChanged(i, v),
      ),
    );
  }
}
