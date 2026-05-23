import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static String price(num value) {
    final f = NumberFormat('#,##0.00', 'en_US');
    return '${f.format(value)} ج.م';
  }

  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return DateFormat('dd/MM HH:mm').format(dt.toLocal());
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'new':              return 'جديد';
      case 'accepted':         return 'مقبول';
      case 'preparing':        return 'جاري التحضير';
      case 'ready':            return 'جاهز للتوصيل';
      case 'out_for_delivery': return 'في الطريق';
      case 'delivered':        return 'تم التوصيل';
      case 'cancelled':        return 'ملغي';
      default:                 return status;
    }
  }
}
