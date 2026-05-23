import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'order_models.dart';
import 'orders_api.dart';

final ordersApiProvider = Provider<OrdersApi>((_) => OrdersApi());

/// Family provider — list orders by status group.
final ordersListProvider =
    FutureProvider.family<List<OrderModel>, String?>((ref, status) async {
  return ref.read(ordersApiProvider).list(status: status);
});

final orderDetailProvider =
    FutureProvider.family<OrderModel, String>((ref, orderId) async {
  return ref.read(ordersApiProvider).get(orderId);
});
