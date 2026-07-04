import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'order_models.dart';
import 'orders_api.dart';

final ordersApiProvider = Provider<OrdersApi>((_) => OrdersApi());

/// How often watched order data re-fetches on its own. Any screen that watches
/// these providers (home lists, order detail, picking) auto-refreshes without
/// needing its own timer.
const _autoRefreshInterval = Duration(seconds: 15);

/// Schedules a one-shot self-invalidation. Combined with the provider re-running
/// on every fetch, this produces a steady poll while the provider is alive
/// (i.e. while at least one screen is watching it). The timer is cancelled when
/// the provider is disposed, so polling stops once nothing is on screen.
void _scheduleAutoRefresh(Ref ref) {
  final timer = Timer(_autoRefreshInterval, () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
}

/// Family provider — list orders by status group.
/// autoDispose so the auto-refresh timer is torn down when no screen watches it.
final ordersListProvider =
    FutureProvider.autoDispose.family<List<OrderModel>, String?>((ref, status) async {
  _scheduleAutoRefresh(ref);
  return ref.read(ordersApiProvider).list(status: status);
});

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderModel, String>((ref, orderId) async {
  _scheduleAutoRefresh(ref);
  return ref.read(ordersApiProvider).get(orderId);
});

/// Server-side search by order number across the FULL dataset (not just the
/// current page). Returns [] for an empty query so the UI can fall back to the
/// normal "all orders" list. No auto-refresh — searches are on-demand.
final orderSearchProvider =
    FutureProvider.autoDispose.family<List<OrderModel>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return ref.read(ordersApiProvider).list(search: q);
});
