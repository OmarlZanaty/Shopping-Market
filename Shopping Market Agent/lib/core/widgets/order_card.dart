import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';
import '../utils/formatters.dart';
import 'status_badge.dart';

/// Rich order card for the agent's queues. Shows everything the agent needs
/// to triage an order without opening the detail screen:
///   • Order number + status badge
///   • Customer name + phone
///   • Full delivery address (with optional building/floor/apt)
///   • Up to 3 product names (the items_preview from the list endpoint)
///   • Item count, total, time ago, payment method
class OrderCard extends StatelessWidget {
  final String orderNumber;
  final String status;
  final int itemCount;
  final double total;
  final String customerArea;
  final String customerName;
  final String customerPhone;
  final String addressFull;
  final String paymentMethod;
  final List<Map<String, String>> itemsPreview;
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
    this.customerName = '',
    this.customerPhone = '',
    this.addressFull = '',
    this.paymentMethod = '',
    this.itemsPreview = const [],
  });

  String get _payLabel {
    switch (paymentMethod) {
      case 'cash':    return 'كاش';
      case 'pos':     return 'كارت عند الاستلام';
      case 'online':  return 'دفع أونلاين';
      case 'wallet':  return 'محفظة';
      case 'loyalty_points': return 'نقاط';
      default:        return paymentMethod;
    }
  }

  /// One-line preview of items: "اسم1 • اسم2 • اسم3" (Arabic, falling back
  /// to English when the Arabic name is empty).
  String get _itemsLine {
    if (itemsPreview.isEmpty) return '';
    return itemsPreview
        .map((m) {
          final n = (m['name_ar'] ?? '').trim().isNotEmpty
              ? m['name_ar']!.trim()
              : (m['name_en'] ?? '').trim();
          return n.isEmpty ? null : n;
        })
        .whereType<String>()
        .join(' • ');
  }

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
          // ── Header: order number + status badge ────────────────────────
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
          const SizedBox(height: 10),

          // ── Customer name + phone ──────────────────────────────────────
          if (customerName.isNotEmpty || customerPhone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.person_outline,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  customerName.isNotEmpty ? customerName : 'عميل',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                )),
                if (customerPhone.isNotEmpty)
                  Text(customerPhone,
                      style: AppTypography.smallLabel.copyWith(
                          fontFamily: 'Inter')),
              ]),
            ),

          // ── Address (full, multi-line) ─────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.location_on_outlined,
                  size: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(
              addressFull.isNotEmpty
                  ? addressFull
                  : (customerArea.isNotEmpty ? customerArea : '—'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.smallLabel.copyWith(height: 1.4),
            )),
          ]),

          // ── Items preview ──────────────────────────────────────────────
          if (_itemsLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shopping_basket_outlined,
                      size: 14, color: AppColors.accentGold),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    _itemsLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500),
                  )),
                ],
              ),
            ),
          ],

          // ── Bottom row: count • total • payment • time ─────────────────
          const SizedBox(height: 10),
          Row(children: [
            Text('$itemCount صنف', style: AppTypography.body),
            const SizedBox(width: 10),
            Text('•', style: AppTypography.smallLabel),
            const SizedBox(width: 10),
            Text(Formatters.price(total),
                style: AppTypography.money
                    .copyWith(color: AppColors.accentOrange)),
            if (paymentMethod.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text('•', style: AppTypography.smallLabel),
              const SizedBox(width: 10),
              Flexible(child: Text(_payLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTypography.smallLabel)),
            ],
            const Spacer(),
            Text(Formatters.relativeTime(createdAt),
                style: AppTypography.smallLabel),
          ]),
        ]),
      ),
    );
  }
}
