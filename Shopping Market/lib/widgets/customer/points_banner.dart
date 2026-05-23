import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

class PointsBanner extends StatelessWidget {
  final UserModel user;
  const PointsBanner({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.sapphire, AppColors.midnight.withBlue(80)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.sapphire.withOpacity(0.3), blurRadius: 12, offset: const Offset(0,4))],
      ),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: const Center(child: Text('⭐', style: TextStyle(fontSize: 18)))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${user.loyaltyPoints} نقطة', style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
          const Text('رصيد نقاط الولاء', style: TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Cairo')),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.gold.withOpacity(0.5))),
          child: const Text('استخدم الآن', style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
        ),
      ]),
    );
  }
}
