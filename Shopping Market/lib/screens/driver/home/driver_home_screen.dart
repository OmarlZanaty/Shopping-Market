import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/location_service.dart';
import '../../../models/models.dart';
import '../../../utils/constants.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _api = ApiService();
  List<OrderModel> _activeOrders = [];
  bool _loading = true;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Start location tracking
    final loc = context.read<LocationService>();
    loc.startTracking();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orders = await _api.getDriverOrders();
      final active = orders.where((o) => !['delivered','cancelled'].contains(o.status)).toList();
      if (mounted) setState(() { _activeOrders = active; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _toggleOnline() async {
    try {
      await _api.toggleOnlineStatus();
      setState(() => _isOnline = !_isOnline);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(onRefresh: _load, color: AppColors.coral,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: AppColors.midnight,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.headerGradient),
                child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(radius: 22, backgroundColor: AppColors.sapphire,
                        child: Text(user?.fullName[0] ?? 'D', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('مرحباً، ${user?.fullName ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                        Row(children: [
                          const Icon(Icons.star_rounded, color: AppColors.gold, size: 14),
                          Text(' ${user?.rating?.toStringAsFixed(1) ?? '5.0'}', style: const TextStyle(color: AppColors.sky, fontSize: 12, fontFamily: 'Cairo')),
                        ]),
                      ]),
                      const Spacer(),
                      // Online/Offline toggle
                      GestureDetector(
                        onTap: _toggleOnline,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isOnline ? AppColors.mint : Colors.grey,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(_isOnline ? 'متاح' : 'غير متاح', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, fontFamily: 'Cairo')),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _statPill('0', 'توصيلة', AppColors.gold),
                      const SizedBox(width: 8),
                      _statPill('${user?.cash_on_hand ?? 0} ج', 'الكاش', AppColors.coral),
                      const SizedBox(width: 8),
                      _statPill('${_activeOrders.length}', 'طلبات نشطة', AppColors.mint),
                    ]),
                  ],
                ))),
              ),
            ),
          ),

          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Text('الطلبات النشطة', style: AppText.h3),
          )),

          _loading
            ? const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.coral))))
            : _activeOrders.isEmpty
              ? SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.all(60),
                  child: Column(children: [
                    const Icon(Icons.delivery_dining_rounded, size: 70, color: AppColors.sky),
                    const SizedBox(height: 16),
                    const Text('لا توجد طلبات نشطة حالياً', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 15)),
                    const SizedBox(height: 8),
                    if (!_isOnline) const Text('فعّل حالة الاستعداد لاستقبال الطلبات', style: TextStyle(fontFamily: 'Cairo', color: AppColors.coral, fontSize: 12)),
                  ]))))
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final o = _activeOrders[i];
                      return GestureDetector(
                        onTap: () => context.push('/driver-order/${o.orderId}'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: o.status == 'new' ? AppColors.coral : AppColors.border, width: o.status == 'new' ? 1.5 : 1),
                            boxShadow: [BoxShadow(color: AppColors.midnight.withOpacity(0.05), blurRadius: 10)]),
                          child: Column(children: [
                            Row(children: [
                              Container(width: 40, height: 40, decoration: BoxDecoration(color: OrderStatus.color(o.status).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Icon(OrderStatus.icon(o.status), color: OrderStatus.color(o.status), size: 22)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('#${o.orderId}', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                                Text(o.customerName ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo')),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${o.totalAmount.toStringAsFixed(1)} ج', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.sapphire, fontFamily: 'Cairo')),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: OrderStatus.color(o.status).withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
                                  child: Text(OrderStatus.labelAr(o.status), style: TextStyle(color: OrderStatus.color(o.status), fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'Cairo'))),
                              ]),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.sky),
                              const SizedBox(width: 4),
                              Expanded(child: Text('${o.deliveryAddress} - ${o.buildingNumber.isNotEmpty ? "عمارة ${o.buildingNumber}" : ""}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${o.items.length} صنف', style: const TextStyle(color: AppColors.sky, fontSize: 11, fontFamily: 'Cairo')),
                            ]),
                          ]),
                        ),
                      );
                    },
                    childCount: _activeOrders.length,
                  )),
                ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ]),
      ),
    );
  }

  Widget _statPill(String value, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
    child: Column(children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14, fontFamily: 'Cairo')),
      Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 9, fontFamily: 'Cairo')),
    ]),
  );
}

// Extension for cash on hand display
extension UserExt on dynamic {
  double get cash_on_hand => 0;
}
