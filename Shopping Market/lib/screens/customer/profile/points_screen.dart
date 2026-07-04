import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/constants.dart';

class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});
  @override State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final txns = await _api.getMyNotifications(); // reusing for demo
      if (mounted) setState(() { _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final points = context.watch<AuthProvider>().user?.loyaltyPoints ?? 0;
    final value = LoyaltyConfig.valueForPoints(points);
    // "احصل على X نقطة لكل Y جنيه"
    final earnLabel = LoyaltyConfig.earnPerEgp > 0
        ? '${LoyaltyConfig.earnPoints} نقطة'
        : '—';
    // "Z نقطة = W جنيه"
    final redeemLabel =
        '${LoyaltyConfig.redeemPoints} نقطة = ${LoyaltyConfig.redeemEgp.toStringAsFixed(LoyaltyConfig.redeemEgp.truncateToDouble() == LoyaltyConfig.redeemEgp ? 0 : 1)} ج';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('نقاط الولاء ⭐', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.midnight),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
        : Column(children: [
          Container(width: double.infinity, margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.sapphire, AppColors.midnight]), borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              const Text('رصيد نقاطك', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
              const SizedBox(height: 8),
              Text('$points', style: const TextStyle(color: AppColors.gold, fontSize: 48, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              Text('= ${value.toStringAsFixed(2)} جنيه', style: const TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 13)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _miniStat('لكل ${LoyaltyConfig.earnPerEgp.toStringAsFixed(0)} ج', earnLabel),
                _miniStat('الاستبدال', redeemLabel),
                _miniStat('النقطة', '${LoyaltyConfig.egpPerPoint.toStringAsFixed(2)} ج'),
              ]),
            ])),
          Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.timeline_rounded, size: 60, color: AppColors.sky),
            SizedBox(height: 12),
            Text('سجل المعاملات سيظهر هنا', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
          ]))),
        ]),
    );
  }

  Widget _miniStat(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Cairo')),
  ]);
}
