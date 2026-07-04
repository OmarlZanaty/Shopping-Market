import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/network/dio_client.dart';
import 'order_models.dart';

/// All agent-side order endpoints. Each method handles the envelope shape.
class OrdersApi {
  OrdersApi();
  final _dio = DioClient.I.dio;

  Future<List<OrderModel>> list({
    String? status,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final res = await _dio.get(ApiConstants.agentOrders, queryParameters: {
      if (status != null) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      // Send as UTC ISO so the server compares against the aware created_at
      // regardless of device/server timezone.
      if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
    });
    return ApiEnvelope.unwrapList<OrderModel>(
      res.data, (o) => OrderModel.fromJson(Map<String, dynamic>.from(o)),
    );
  }

  Future<OrderModel> get(String orderId) async {
    final res = await _dio.get(ApiConstants.agentOrderDetail(orderId));
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    return OrderModel.fromJson(Map<String, dynamic>.from(body));
  }

  // ── Status transitions ───────────────────────────────────────────────────
  Future<void> accept(String orderId) async =>
      _dio.patch(ApiConstants.agentAccept(orderId));

  Future<void> reject(String orderId, {String reason = ''}) async =>
      _dio.patch(ApiConstants.agentReject(orderId), data: {'reason': reason});

  Future<void> startPreparing(String orderId) async =>
      _dio.patch(ApiConstants.agentStartPreparing(orderId));

  Future<void> markReady(String orderId) async =>
      _dio.patch(ApiConstants.agentReady(orderId));

  Future<void> pickedUp(String orderId) async =>
      _dio.patch(ApiConstants.agentPickedUp(orderId));

  Future<Map<String, dynamic>> delivered(String orderId, {
    double? amountCollected,
    String? deliveryPhotoUrl,
  }) async {
    final res = await _dio.patch(ApiConstants.agentDelivered(orderId), data: {
      if (amountCollected != null) 'amount_collected': amountCollected,
      if (deliveryPhotoUrl != null) 'delivery_photo_url': deliveryPhotoUrl,
    });
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    return Map<String, dynamic>.from(body is Map ? body : {});
  }

  Future<void> failedDelivery(String orderId, {String reason = 'فشل التوصيل'}) async =>
      _dio.patch(ApiConstants.agentFailedDelivery(orderId), data: {'reason': reason});

  Future<void> forceClose(String orderId, {
    required String deliveryPhotoUrl,
    String reason = 'auto_close_timeout',
  }) async => _dio.patch(ApiConstants.agentForceClose(orderId), data: {
        'delivery_photo_url': deliveryPhotoUrl,
        'reason': reason,
      });

  // ── Items ────────────────────────────────────────────────────────────────
  Future<void> markUnavailable(String orderId, int itemId) async =>
      _dio.patch(ApiConstants.itemUnavailable(orderId, itemId));

  Future<void> resetItem(String orderId, int itemId) async =>
      _dio.patch(ApiConstants.itemReset(orderId, itemId));

  Future<void> setActualQty(String orderId, int itemId, double qty) async =>
      _dio.patch(ApiConstants.itemQty(orderId, itemId), data: {'actual_qty': qty});

  Future<void> adjustPrice(String orderId, int itemId, double newPrice, String reason) async =>
      _dio.patch(ApiConstants.itemPrice(orderId, itemId), data: {
        'new_price': newPrice, 'reason': reason,
      });

  Future<void> setActualWeight(String orderId, int itemId, double weight) async =>
      _dio.patch(ApiConstants.itemWeight(orderId, itemId), data: {'weight_actual': weight});

  Future<void> substitute(String orderId, int itemId, String substituteProductId) async =>
      _dio.post(ApiConstants.itemSubstitute(orderId, itemId), data: {
        'substitute_product_id': substituteProductId,
      });

  Future<void> addItem(String orderId, String productId, double qty) async =>
      _dio.post(ApiConstants.itemAdd(orderId), data: {
        'product_id': productId, 'qty': qty,
      });

  Future<void> removeItem(String orderId, int itemId) async =>
      _dio.delete(ApiConstants.itemRemove(orderId, itemId));

  // ── Audit / share / log ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> shareCustomerData(String orderId) async {
    final res = await _dio.post(ApiConstants.agentShare(orderId));
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    return Map<String, dynamic>.from(body is Map ? body : {});
  }

  Future<void> logAction(String orderId, String actionType, {Map<String, dynamic>? data}) async {
    await _dio.post(ApiConstants.agentLog(orderId), data: {
      'action_type': actionType,
      if (data != null) 'data': data,
    });
  }

  // ── Inventory ────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listInventory({String? q, bool? available}) async {
    final res = await _dio.get(ApiConstants.inventoryProducts, queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (available != null) 'available': available ? '1' : '0',
    });
    return ApiEnvelope.unwrapList<Map<String, dynamic>>(
      res.data, (o) => Map<String, dynamic>.from(o),
    );
  }

  Future<Map<String, dynamic>> inventoryScan(String barcode) async {
    final res = await _dio.get(ApiConstants.inventoryScan(barcode));
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    return Map<String, dynamic>.from(body is Map ? body : {});
  }

  Future<void> markAvailable(String productId) async =>
      _dio.patch(ApiConstants.inventoryMarkAvailable(productId));

  /// Flips is_available for a product. Returns updated is_available value.
  Future<bool> toggleAvailability(String productId) async {
    final res = await _dio.patch(ApiConstants.inventoryToggle(productId));
    final body = ApiEnvelope.unwrap(res.data) ?? res.data;
    final data = Map<String, dynamic>.from(body is Map ? body : {});
    return data['is_available'] == true;
  }
}
