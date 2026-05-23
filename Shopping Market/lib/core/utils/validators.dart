/// Form input validators.
class Validators {
  Validators._();

  static final _egyptianPhoneRegex = RegExp(r'^01[0125]\d{8}$');

  /// Validates an Egyptian mobile (11 digits, starts with 010/011/012/015).
  static String? egyptianPhone(String? value, {String fieldName = 'الهاتف'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName مطلوب';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-+]'), '');
    final normalized = cleaned.startsWith('20') ? cleaned.substring(2) : cleaned;
    if (!_egyptianPhoneRegex.hasMatch(normalized)) {
      return 'رقم هاتف غير صحيح';
    }
    return null;
  }

  static String? required(String? value, {String fieldName = 'الحقل'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName مطلوب';
    return null;
  }

  static String? otpCode(String? value) {
    if (value == null || value.isEmpty) return 'الكود مطلوب';
    if (value.length != 6) return 'الكود يجب أن يكون 6 أرقام';
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return 'أرقام فقط';
    return null;
  }
}
