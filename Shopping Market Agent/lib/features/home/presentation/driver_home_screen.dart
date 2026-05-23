import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../core/widgets/order_card.dart';
import '../../auth/auth_controller.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/orders_providers.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _trackingPrompted = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptForLocationOnce());
  }

  Future<void> _promptForLocationOnce() async {
    if (_trackingPrompted) return;
    _trackingPrompted = true;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text('السماح بتتبع الموقع'),
        content: const Text(
          'نحتاج للوصول لموقعك أثناء التوصيل ليتمكن العميل من رؤيتك على الخريطة. '
          'يتم تحديث الموقع كل 5 ثوانٍ ويتوقف عند تسليم الطلب.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await AgentLocationService.I.start();
            },
            child: const Text('السماح'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(agentAuthControllerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text('أهلاً ${session?.name ?? "كابتن"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AgentLocationService.I.stop();
              await ref.read(agentAuthControllerProvider.notifier).logout();
              if (mounted) context.go('/login');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accentOrange,
          indicatorWeight: 3,
          labelColor: AppColors.accentOrange,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'في الانتظار'),
            Tab(text: 'جاري التوصيل'),
            Tab(text: 'مُسلَّم'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _OrderList(statusGroup: 'ready'),
          _OrderList(statusGroup: 'out_for_delivery'),
          _OrderList(statusGroup: 'delivered'),
        ],
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  final String statusGroup;
  const _OrderList({required this.statusGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersListProvider(statusGroup));
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(ordersListProvider(statusGroup).future),
      color: AppColors.accentOrange,
      child: orders.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (list) {
          if (list.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Icon(Icons.local_shipping_outlined,
                  size: 72, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Center(child: Text('لا توجد طلبات حالياً',
                  style: TextStyle(color: AppColors.textSecondary))),
            ]);
          }
          final sorted = [...list]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final o = sorted[i];
              return OrderCard(
                orderNumber: o.orderNumber,
                status: o.status,
                itemCount: o.items.length,
                total: o.total,
                customerArea: _district(o),
                createdAt: o.createdAt,
                onTap: () => GoRouter.of(context).push('/order/${o.id}'),
              );
            },
          );
        },
      ),
    );
  }

  static String _district(OrderModel o) {
    if (o.addressFull.isEmpty) return '—';
    return o.addressFull.split(RegExp(r'[,،]')).last.trim();
  }
}
