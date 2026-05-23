import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';
import '../utils/formatters.dart';
import 'status_badge.dart';

class OrderCard extends StatelessWidget {
  final String orderNumber;
  final String status;
  final int itemCount;
  final double total;
  final String customerArea;
  final DateTime createdAt;
  final VoidCallback onTap;

  const OrderCard({
    super.key,
    required this.orderNumber,
    required this.status,
    required this.itemCount,
    required this.total,
    required this.customerArea,
    required this.createdAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppDimensions.cardInner),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          boxShadow: const [AppDimensions.cardGlow],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(orderNumber,
                  style: const TextStyle(
                    color: AppColors.accentGold, fontWeight: FontWeight.bold,
                    fontSize: 15, fontFamily: 'Inter',
                  )),
            ),
            StatusBadge(status),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(child: Text(customerArea,
                style: AppTypography.smallLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Text('$itemCount صنف', style: AppTypography.body),
            const SizedBox(width: 12),
            Text('•', style: AppTypography.smallLabel),
            const SizedBox(width: 12),
            Text(Formatters.price(total),
                style: AppTypography.money.copyWith(color: AppColors.accentOrange)),
            const Spacer(),
            Text(Formatters.relativeTime(createdAt), style: AppTypography.smallLabel),
          ]),
        ]),
      ),
    );
  }
}
