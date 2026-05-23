import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
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
              const Text('1,240', style: TextStyle(color: AppColors.gold, fontSize: 48, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              const Text('نقطة = 62 جنيه', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 13)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _miniStat('كل طلب', '× النقاط'),
                _miniStat('100 نقطة', '= 5 ج'),
                _miniStat('تقييم', '+5 نقاط'),
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
