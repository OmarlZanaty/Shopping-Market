import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../models/models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _api = ApiService();
  List<OrderModel> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) _load();
    else setState(() => _loading = false);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orders = await _api.getMyOrders();
      if (mounted) setState(() { _orders = orders; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Not logged in — show friendly prompt
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('طلباتي',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.midnight,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.ice,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.receipt_long_outlined,
                      size: 52, color: AppColors.sapphire),
                ),
                const SizedBox(height: 24),
                const Text('تتبع طلباتك',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo', color: AppColors.midnight)),
                const SizedBox(height: 10),
                const Text(
                  'سجل الدخول لمتابعة طلباتك وتاريخ مشترياتك',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted,
                      fontFamily: 'Cairo', fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.coral,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => context.push('/login'),
                    child: const Text('تسجيل الدخول',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('إنشاء حساب جديد',
                      style: TextStyle(color: AppColors.sapphire,
                          fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('طلباتي',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.midnight,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.coral,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
            : _orders.isEmpty
            ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 70, color: AppColors.sky),
              SizedBox(height: 16),
              Text('لا توجد طلبات بعد',
                  style: TextStyle(fontSize: 16, color: AppColors.textMuted,
                      fontFamily: 'Cairo')),
            ]))
            : ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: _orders.length,
          itemBuilder: (_, i) {
            final o = _orders[i];
            return GestureDetector(
              onTap: () => context.push('/orders/${o.orderId}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: OrderStatus.color(o.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(OrderStatus.icon(o.status),
                        color: OrderStatus.color(o.status), size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('#${o.orderId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Cairo', fontSize: 13)),
                        const Spacer(),
                        Text('${o.totalAmount.toStringAsFixed(1)} ج',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.sapphire,
                                fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: OrderStatus.color(o.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(OrderStatus.labelAr(o.status),
                            style: TextStyle(
                                color: OrderStatus.color(o.status),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo')),
                      ),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}