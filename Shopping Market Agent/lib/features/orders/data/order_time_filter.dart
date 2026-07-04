import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preset time windows for filtering orders by their created date.
enum OrderTimePreset { all, today, yesterday, last7, thisMonth, custom }

/// Resolved concrete range. Nulls mean "unbounded" on that side.
/// [from] is inclusive, [to] is exclusive.
class ResolvedRange {
  final DateTime? from;
  final DateTime? to;
  const ResolvedRange(this.from, this.to);
}

/// Global order time filter shared by every order list in the app. Held in
/// [orderTimeFilterProvider]; changing it re-fetches all watching lists.
class OrderTimeFilter {
  final OrderTimePreset preset;

  /// Only used when [preset] == custom. [customFrom] is the inclusive start of
  /// the first day; [customTo] is the exclusive start of the day after the last.
  final DateTime? customFrom;
  final DateTime? customTo;

  const OrderTimeFilter({
    this.preset = OrderTimePreset.all,
    this.customFrom,
    this.customTo,
  });

  bool get isActive => preset != OrderTimePreset.all;

  /// Resolves the preset to concrete local datetimes.
  ResolvedRange resolve([DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    const day = Duration(days: 1);
    switch (preset) {
      case OrderTimePreset.all:
        return const ResolvedRange(null, null);
      case OrderTimePreset.today:
        return ResolvedRange(startOfToday, startOfToday.add(day));
      case OrderTimePreset.yesterday:
        return ResolvedRange(startOfToday.subtract(day), startOfToday);
      case OrderTimePreset.last7:
        // Last 7 days including today.
        return ResolvedRange(
            startOfToday.subtract(const Duration(days: 6)), startOfToday.add(day));
      case OrderTimePreset.thisMonth:
        return ResolvedRange(
            DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
      case OrderTimePreset.custom:
        return ResolvedRange(customFrom, customTo);
    }
  }

  /// Short Arabic label for the active chip / summary.
  String get label {
    switch (preset) {
      case OrderTimePreset.all:
        return 'كل الأوقات';
      case OrderTimePreset.today:
        return 'اليوم';
      case OrderTimePreset.yesterday:
        return 'أمس';
      case OrderTimePreset.last7:
        return 'آخر ٧ أيام';
      case OrderTimePreset.thisMonth:
        return 'هذا الشهر';
      case OrderTimePreset.custom:
        if (customFrom == null || customTo == null) return 'مخصص';
        final f = customFrom!;
        // customTo is exclusive (day after) → show the actual last day.
        final lastDay = customTo!.subtract(const Duration(days: 1));
        String d(DateTime x) => '${x.day}/${x.month}';
        return d(f) == d(lastDay) ? d(f) : '${d(f)} - ${d(lastDay)}';
    }
  }
}

/// The one filter every order list watches. Setting it invalidates all lists.
final orderTimeFilterProvider =
    StateProvider<OrderTimeFilter>((_) => const OrderTimeFilter());
