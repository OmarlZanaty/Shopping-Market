import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../data/order_time_filter.dart';

/// Horizontal row of preset chips + a custom date-range picker for filtering
/// orders by created time. Reads/writes the global [orderTimeFilterProvider],
/// so it can be dropped onto any screen and stays in sync everywhere.
class OrderTimeFilterBar extends ConsumerWidget {
  const OrderTimeFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(orderTimeFilterProvider);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _chip(ref, filter, OrderTimePreset.all, 'الكل'),
          _chip(ref, filter, OrderTimePreset.today, 'اليوم'),
          _chip(ref, filter, OrderTimePreset.yesterday, 'أمس'),
          _chip(ref, filter, OrderTimePreset.last7, 'آخر ٧ أيام'),
          _chip(ref, filter, OrderTimePreset.thisMonth, 'هذا الشهر'),
          _customChip(context, ref, filter),
        ],
      ),
    );
  }

  Widget _chip(WidgetRef ref, OrderTimeFilter filter, OrderTimePreset preset,
      String label) {
    final selected = filter.preset == preset;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
        backgroundColor: AppColors.backgroundSecondary,
        selectedColor: AppColors.accentOrange,
        side: BorderSide.none,
        onSelected: (_) => ref.read(orderTimeFilterProvider.notifier).state =
            OrderTimeFilter(preset: preset),
      ),
    );
  }

  Widget _customChip(
      BuildContext context, WidgetRef ref, OrderTimeFilter filter) {
    final selected = filter.preset == OrderTimePreset.custom;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        avatar: Icon(Icons.date_range,
            size: 18,
            color: selected ? Colors.white : AppColors.textSecondary),
        label: Text(selected ? filter.label : 'مخصص'),
        selected: selected,
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
        backgroundColor: AppColors.backgroundSecondary,
        selectedColor: AppColors.accentOrange,
        side: BorderSide.none,
        onSelected: (_) => _pickCustomRange(context, ref, filter),
      ),
    );
  }

  Future<void> _pickCustomRange(
      BuildContext context, WidgetRef ref, OrderTimeFilter filter) async {
    final now = DateTime.now();
    final initial = (filter.preset == OrderTimePreset.custom &&
            filter.customFrom != null &&
            filter.customTo != null)
        ? DateTimeRange(
            start: filter.customFrom!,
            end: filter.customTo!.subtract(const Duration(days: 1)),
          )
        : DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day),
          );

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: initial,
      helpText: 'اختر نطاق التاريخ',
      saveText: 'تم',
    );
    if (range == null) return;

    // Normalise to day boundaries: [start of first day, start of day after last).
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));
    ref.read(orderTimeFilterProvider.notifier).state = OrderTimeFilter(
      preset: OrderTimePreset.custom,
      customFrom: from,
      customTo: to,
    );
  }
}
