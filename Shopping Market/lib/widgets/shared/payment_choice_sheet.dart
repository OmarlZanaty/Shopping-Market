import 'package:flutter/material.dart';
import '../../utils/constants.dart';

enum PaymentChoice { card, cash }

/// Bottom sheet shown when the customer approves a price-increase adjustment
/// on an online-payment order. Lets them pick card (Paymob) or cash.
Future<PaymentChoice?> showPaymentChoiceSheet(
  BuildContext context, {
  required String amountEgp,
}) {
  return showModalBottomSheet<PaymentChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentChoiceSheet(amountEgp: amountEgp),
  );
}

class _PaymentChoiceSheet extends StatelessWidget {
  final String amountEgp;
  const _PaymentChoiceSheet({required this.amountEgp});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.midnight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          const Text('اختر طريقة الدفع',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 18,
                  fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text('المبلغ الإضافي المطلوب: $amountEgp جنيه',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                  color: AppColors.gold, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),

          // Card option
          _OptionTile(
            icon: Icons.credit_card_rounded,
            color: AppColors.sky,
            title: 'دفع بالبطاقة البنكية',
            subtitle: 'Visa / Mastercard — آمن ومشفر',
            onTap: () => Navigator.pop(context, PaymentChoice.card),
          ),
          const SizedBox(height: 12),

          // Cash option
          _OptionTile(
            icon: Icons.money_rounded,
            color: AppColors.mint,
            title: 'دفع نقدي عند التسليم',
            subtitle: 'ادفع الفرق للسائق عند استلام الطلب',
            onTap: () => Navigator.pop(context, PaymentChoice.cash),
          ),
          const SizedBox(height: 12),

          // Cancel
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700,
                          color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
