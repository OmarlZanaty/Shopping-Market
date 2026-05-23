class Validators {
  Validators._();
  static final _egPhone = RegExp(r'^01[0125]\d{8}$');
  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'رقم الهاتف مطلوب';
    if (!_egPhone.hasMatch(v.replaceAll(RegExp(r'\s'), ''))) return 'رقم هاتف غير صحيح';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'كلمة المرور مطلوبة';
    if (v.length < 6) return 'كلمة المرور قصيرة جداً';
    return null;
  }

  static String? required(String? v, {String label = 'الحقل'}) {
    if (v == null || v.trim().isEmpty) return '$label مطلوب';
    return null;
  }
}
