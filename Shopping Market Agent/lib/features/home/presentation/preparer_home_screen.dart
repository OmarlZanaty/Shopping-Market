import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/order_card.dart';
import '../../auth/auth_controller.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/orders_providers.dart';

class PreparerHomeScreen extends ConsumerStatefulWidget {
  const PreparerHomeScreen({super.key});
  @override
  ConsumerState<PreparerHomeScreen> createState() => _PreparerHomeScreenState();
}

class _PreparerHomeScreenState extends ConsumerState<PreparerHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
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
        title: Text('أهلاً ${session?.name ?? "محضّر"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
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
            Tab(text: 'جديد'),
            Tab(text: 'جاري'),
            Tab(text: 'منتهي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _OrderList(statusGroup: 'new'),
          _OrderList(statusGroup: 'preparing'),
          _OrderList(statusGroup: 'delivered'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scanner-inventory'),
        backgroundColor: AppColors.accentOrange,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('مسح متوفّر'),
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
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.cloud_off, color: AppColors.errorRed, size: 56),
              const SizedBox(height: 12),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.refresh(ordersListProvider(statusGroup)),
                child: const Text('إعادة المحاولة'),
              ),
            ]),
          ),
        ),
        data: (list) {
          if (list.isEmpty) return const _EmptyState();
          // FIFO — oldest first.
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
                customerArea: _districtOf(o),
                createdAt: o.createdAt,
                onTap: () => GoRouter.of(context).push('/order/${o.id}'),
              );
            },
          );
        },
      ),
    );
  }

  /// Show only the district (first comma-separated segment) on list view.
  static String _districtOf(OrderModel o) {
    if (o.addressFull.isEmpty) return '—';
    return o.addressFull.split(RegExp(r'[,،]')).last.trim();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.inbox_outlined, size: 72, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Center(child: Text('لا توجد طلبات', style: TextStyle(color: AppColors.textSecondary))),
        ],
      );
}
