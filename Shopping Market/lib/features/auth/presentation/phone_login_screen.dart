import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/validators.dart';
import '../../../services/api_service.dart';

/// Customer phone login. Egyptian phone with +20 prefix. Validates the spec
/// regex inline. Submits OTP request and navigates to the OTP screen.
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

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _validate(String value) {
    setState(() {
      _phoneError = Validators.egyptianPhone(value);
      _isValid = _phoneError == null && value.isNotEmpty;
    });
  }

  Future<void> _submit() async {
    if (!_isValid || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final phone = _phoneController.text.trim();
    try {
      final res = await ApiService().sendOtp(phone);
      if (!mounted) return;
      // Pass debug_code (DEBUG mode only) so the dev can complete the flow.
      context.push('/otp', extra: {
        'phone': phone,
        'debug_code': res['debug_code'],
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل الإرسال: ${e.toString()}'),
        backgroundColor: AppColors.errorRed,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                const SizedBox(height: 8),
                const Text(
                  'سنرسل لك رمز تحقق برسالة نصية',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 28),
                _buildPhoneField(),
                if (_phoneError != null && _phoneController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _phoneError!,
                    style: const TextStyle(color: AppColors.errorRed, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: (_isValid && !_isLoading) ? _submit : null,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(
                            color: AppColors.textPrimary, strokeWidth: 2,
                          ),
                        )
                      : const Text('متابعة'),
                ),
                const SizedBox(height: 24),
                _socialDivider(),
                const SizedBox(height: 16),
                _socialButton(
                  label: 'الدخول بحساب Google',
                  iconAsset: 'assets/images/google.png',
                  onTap: _googleSignIn,
                ),
                const SizedBox(height: 12),
                _socialButton(
                  label: 'الدخول بحساب Facebook',
                  iconAsset: 'assets/images/facebook.png',
                  onTap: _facebookSignIn,
                ),
                const Spacer(),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('تصفح بدون تسجيل'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: const [
                Text('🇪🇬', style: TextStyle(fontSize: 18)),
                SizedBox(width: 6),
                Text('+20', style: TextStyle(
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
              maxLength: 11,
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
                fontSize: 16,
              ),
              decoration: const InputDecoration(
                hintText: '1xxxxxxxxx',
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
            child: Text('أو', style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Divider(color: AppColors.appBarDivider)),
        ],
      );

  Widget _socialButton({
    required String label,
    required String iconAsset,
    required VoidCallback onTap,
  }) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.appBarDivider),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _googleSignIn() async {
    // Wired in feature/auth — uses google_sign_in package. Stubbed here so
    // the screen is fully functional even if the package isn't configured.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Google Sign-In — قيد التطوير'),
    ));
  }

  Future<void> _facebookSignIn() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Facebook Sign-In — قيد التطوير'),
    ));
  }
}
