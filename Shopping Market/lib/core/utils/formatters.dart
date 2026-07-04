import 'package:intl/intl.dart';

/// Display formatters for prices, dates, etc.
class Formatters {
  Formatters._();

  /// "12.50 ج.م" with English digits per spec (Inter font is used for money).
  static String price(num value) {
    final f = NumberFormat('#,##0.00', 'en_US');
    return '${f.format(value)} ج.م';
  }

  /// Just the number without currency.
  static String priceNum(num value) {
    final f = NumberFormat('#,##0.00', 'en_US');
    return f.format(value);
  }

  /// Order date — "DD/MM/YYYY  HH:mm"
  static String orderDate(DateTime dt) {
    return DateFormat('dd/MM/yyyy  HH:mm', 'en_US').format(dt.toLocal());
  }

  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    return DateFormat('dd MMM').format(dt.toLocal());
  }

  /// Returns the spec's Arabic label for a given backend order status.
  static String orderStatusLabel(String status) {
    switch (status) {
      case 'new':              return 'تم الاستلام';
      case 'accepted':         return 'تم الموافقة';
      case 'preparing':        return 'جاري التحضير';
      case 'out_for_delivery': return 'في الطريق';
      case 'delivered':        return 'تم التوصيل';
      case 'cancelled':        return 'ملغي';
      default:                 return status;
    }
  }

  /// Human label for a weight-based quantity stored in kilograms.
  /// < 1 kg → grams ("500 جم"), otherwise kilograms ("1.5 كجم").
  static String weightLabel(double kg) {
    if (kg < 1) return '${(kg * 1000).round()} جم';
    final s = kg == kg.roundToDouble()
        ? kg.toStringAsFixed(0)
        : kg.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s كجم';
  }

  /// Unit suffix shown after price, e.g. "/ كجم", "/ قطعة".
  static String unitSuffix(String sellUnit) {
    switch (sellUnit) {
      case 'kg':     return '/ كجم';
      case 'gram':   return '/ جرام';
      case 'box':    return '/ صندوق';
      case 'carton': return '/ كرتونة';
      case 'liter':  return '/ لتر';
      case 'pack':   return '/ علبة';
      case 'piece':
      default:       return '/ قطعة';
    }
  }
}
