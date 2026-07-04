import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/order_card.dart';
import '../../auth/auth_controller.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/presentation/order_time_filter_bar.dart';

class PreparerHomeScreen extends ConsumerStatefulWidget {
  const PreparerHomeScreen({super.key});
  @override
  ConsumerState<PreparerHomeScreen> createState() => _PreparerHomeScreenState();
}

class _PreparerHomeScreenState extends ConsumerState<PreparerHomeScreen>
    with SingleTickerProviderStateMixin {
  // Tab 0 = all orders (search), 1 = new, 2 = in-progress, 3 = completed
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging && mounted) ref.invalidate(ordersListProvider);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Second layer: verify push delivery on THIS device.
  Future<void> _runNotificationTest() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('جاري إرسال إشعار تجريبي...'),
      duration: Duration(seconds: 2),
    ));
    try {
      final res = await AgentNotificationService.I.sendTestNotification();
      final hasToken = res['has_token'] == true;
      final sent = res['fcm_sent'] == true;
      final msg = !hasToken
          ? 'لا يوجد رمز إشعارات لهذا الجهاز. فعّل الإشعارات ثم أعد المحاولة.'
          : sent
              ? 'تم الإرسال ✓ سيظهر إشعار خلال ثوانٍ. إن لم يظهر فعّل الإشعارات من إعدادات الهاتف.'
              : 'فشل الإرسال عبر FCM. تحقق من الإنترنت وإعدادات الإشعارات.';
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: sent ? AppColors.successGreen : AppColors.errorRed,
        duration: const Duration(seconds: 5),
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('تعذّر إرسال الإشعار التجريبي.'),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(agentAuthControllerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text('أهلاً ${session?.name ?? "محضّر"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'اختبار الإشعارات',
            onPressed: _runNotificationTest,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.backgroundSecondary,
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل تريد تسجيل الخروج من التطبيق؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.errorRed),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('خروج'),
                    ),
                  ],
                ),
              );
              if (confirm != true || !mounted) return;
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
            Tab(text: 'الكل'),
            Tab(text: 'جديد'),
            Tab(text: 'جاري'),
            Tab(text: 'منتهي'),
          ],
        ),
      ),
      body: Column(
        children: [
          const OrderTimeFilterBar(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _AllOrdersTab(),                                     // search + all
                _OrderList(statusGroup: 'new'),
                _OrderList(statusGroup: 'accepted,preparing,out_for_delivery'),
                _OrderList(statusGroup: 'delivered'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scanner-inventory'),
        backgroundColor: AppColors.accentOrange,
        icon: const Icon(Icons.warehouse_outlined),
        label: const Text('المخزن'),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// All-orders tab with live search by order number
// ═══════════════════════════════════════════════════════════════════════════

class _AllOrdersTab extends ConsumerStatefulWidget {
  const _AllOrdersTab();
  @override
  ConsumerState<_AllOrdersTab> createState() => _AllOrdersTabState();
}

class _AllOrdersTabState extends ConsumerState<_AllOrdersTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = ''; // debounced query that actually drives the request

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Debounce so we don't hit the server on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value.trim());
    });
    // Update the clear-button visibility immediately.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;
    // Searching → server-side search across the full dataset.
    // Idle      → most recent orders (page 1, newest first).
    final orders = isSearching
        ? ref.watch(orderSearchProvider(_query))
        : ref.watch(ordersListProvider(null));

    return Column(children: [
      // ── Search bar ────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'ابحث برقم الطلب…',
            hintStyle: const TextStyle(
                color: AppColors.textSecondary, fontFamily: 'Cairo'),
            prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                    onPressed: () {
                      _debounce?.cancel();
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.backgroundSecondary,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: _onSearchChanged,
        ),
      ),

      // ── Order list ────────────────────────────────────────────────────────
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => isSearching
              ? ref.refresh(orderSearchProvider(_query).future)
              : ref.refresh(ordersListProvider(null).future),
          color: AppColors.accentOrange,
          child: orders.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.accentOrange)),
            error: (e, _) => ListView(children: [
              const SizedBox(height: 80),
              const Icon(Icons.cloud_off,
                  color: AppColors.errorRed, size: 56),
              const SizedBox(height: 12),
              Center(child: Text(e.toString(), textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('إعادة المحاولة'),
                ),
              ),
            ]),
            data: (list) {
              if (list.isEmpty) {
                return ListView(children: [
                  const SizedBox(height: 80),
                  Icon(isSearching ? Icons.search_off : Icons.inbox_outlined,
                      size: 72, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      isSearching
                          ? 'لا يوجد طلب برقم "$_query"'
                          : 'لا توجد طلبات',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontFamily: 'Cairo'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]);
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final o = list[i];
                  return OrderCard(
                    orderNumber: o.orderNumber,
                    status: o.status,
                    itemCount: o.itemCount,
                    total: o.total,
                    customerArea: _districtOf(o),
                    customerName: o.customerName,
                    customerPhone: o.customerPhone,
                    addressFull: o.addressFull,
                    paymentMethod: o.paymentMethod,
                    itemsPreview: o.itemsPreview,
                    createdAt: o.createdAt,
                    onTap: () => GoRouter.of(context).push('/order/${o.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    ]);
  }

  static String _districtOf(OrderModel o) {
    if (o.addressFull.isEmpty) return '—';
    return o.addressFull.split(RegExp(r'[,،]')).last.trim();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Status-filtered order list (tabs: new / in-progress / completed)
// ═══════════════════════════════════════════════════════════════════════════

class _OrderList extends ConsumerWidget {
  final String statusGroup;
  const _OrderList({required this.statusGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersListProvider(statusGroup));
    return RefreshIndicator(
      onRefresh: () async =>
          ref.refresh(ordersListProvider(statusGroup).future),
      color: AppColors.accentOrange,
      child: orders.when(
        loading: () => const Center(
            child:
                CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.cloud_off,
                  color: AppColors.errorRed, size: 56),
              const SizedBox(height: 12),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.refresh(ordersListProvider(statusGroup)),
                child: const Text('إعادة المحاولة'),
              ),
            ]),
          ),
        ),
        data: (list) {
          if (list.isEmpty) return const _EmptyState();
          // Finished orders → newest first. Active queues (new / in-progress)
          // stay oldest-first (FIFO — handle the longest-waiting order first).
          final newestFirst = statusGroup.contains('delivered');
          final sorted = [...list]
            ..sort((a, b) => newestFirst
                ? b.createdAt.compareTo(a.createdAt)
                : a.createdAt.compareTo(b.createdAt));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final o = sorted[i];
              return OrderCard(
                orderNumber: o.orderNumber,
                status: o.status,
                itemCount: o.itemCount,
                total: o.total,
                customerArea: _districtOf(o),
                customerName: o.customerName,
                customerPhone: o.customerPhone,
                addressFull: o.addressFull,
                paymentMethod: o.paymentMethod,
                itemsPreview: o.itemsPreview,
                createdAt: o.createdAt,
                onTap: () => GoRouter.of(context).push('/order/${o.id}'),
              );
            },
          );
        },
      ),
    );
  }

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
          Icon(Icons.inbox_outlined,
              size: 72, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Center(
              child: Text('لا توجد طلبات',
                  style: TextStyle(color: AppColors.textSecondary))),
        ],
      );
}
