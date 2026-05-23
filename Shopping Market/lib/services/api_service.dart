import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../models/models.dart';
import '../core/network/api_envelope.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: StorageKeys.accessToken);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        // Don't try to refresh token on auth endpoints
        final path = e.requestOptions.path;
        final isAuthEndpoint = path.contains('/auth/login/') ||
            path.contains('/auth/register/') ||
            path.contains('/auth/social-login/') ||
            path.contains('/auth/biometric/');

        if (e.response?.statusCode == 401 && !isAuthEndpoint) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: StorageKeys.accessToken);
            e.requestOptions.headers['Authorization'] = 'Bearer $token';
            final retry = await _dio.request(
              e.requestOptions.path,
              options: Options(method: e.requestOptions.method, headers: e.requestOptions.headers),
              data: e.requestOptions.data,
              queryParameters: e.requestOptions.queryParameters,
            );
            return handler.resolve(retry);
          }
        }
        return handler.next(e);
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[API] $obj'),
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refresh = await _storage.read(key: StorageKeys.refreshToken);
      if (refresh == null) return false;
      // Try /auth/refresh/ (new) then /auth/token/refresh/ (legacy)
      Response res;
      try {
        res = await Dio().post('${AppConfig.baseUrl}/auth/refresh/', data: {'refresh': refresh});
      } catch (_) {
        res = await Dio().post('${AppConfig.baseUrl}/auth/token/refresh/', data: {'refresh': refresh});
      }
      final access = res.data['access'] ?? res.data['data']?['access'];
      final newRefresh = res.data['refresh'] ?? res.data['data']?['refresh'];
      if (access != null) {
        await _storage.write(key: StorageKeys.accessToken, value: access);
      }
      if (newRefresh != null) {
        await _storage.write(key: StorageKeys.refreshToken, value: newRefresh);
      }
      return access != null;
    } catch (_) {
      await _storage.deleteAll();
      return false;
    }
  }

  /// Smart-unwrap any response: handles both the new envelope
  /// `{success, data, ...}` and legacy raw shapes.
  static dynamic _unwrap(dynamic body) => ApiEnvelope.unwrap(body);

  // ─── Auth ──────────────────────────────────────────────────────────────────

  // OTP — new customer auth flow (spec).
  /// Send a 6-digit OTP to an Egyptian phone. Rate-limited 3/min server-side.
  /// Returns the response data (incl. `debug_code` in dev mode).
  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final res = await _dio.post('/auth/send-otp/', data: {'phone': phone});
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Verify the OTP code. On success, persists tokens and returns the user payload.
  Future<Map<String, dynamic>> verifyOtp(
    String phone,
    String code, {
    String? fullName,
    String? fcmToken,
  }) async {
    final res = await _dio.post('/auth/verify-otp/', data: {
      'phone': phone,
      'code': code,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
    });
    final data = _unwrap(res.data);
    final m = Map<String, dynamic>.from(data is Map ? data : {});
    if (m['access'] != null && m['refresh'] != null) {
      await _saveTokens(m['access'], m['refresh']);
    }
    return m;
  }

  Future<Map<String, dynamic>> login(String phone, String password) async {
    final res = await _dio.post('/auth/login/', data: {'phone': phone, 'password': password});
    final data = _unwrap(res.data);
    final m = Map<String, dynamic>.from(data is Map ? data : res.data);
    await _saveTokens(m['access'], m['refresh']);
    return m;
  }

  /// Multi-store config — returns `{multistore_enabled, default_store_id}`.
  Future<Map<String, dynamic>> getStoresConfig() async {
    final res = await _dio.get('/stores/config/');
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Active stores list (only when multistore_enabled=1).
  Future<List<Map<String, dynamic>>> getStores() async {
    final res = await _dio.get('/stores/');
    return ApiEnvelope.unwrapList<Map<String, dynamic>>(
      res.data,
      (e) => Map<String, dynamic>.from(e as Map),
    );
  }

  /// Single store detail. Pass GPS for nearest-branch resolution.
  Future<Map<String, dynamic>> getStore(int storeId, {double? lat, double? lng}) async {
    final res = await _dio.get('/stores/$storeId/', queryParameters: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Wallet balance (+ loyalty points).
  Future<Map<String, dynamic>> getWalletBalance() async {
    final res = await _dio.get('/wallet/balance/');
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  Future<List<Map<String, dynamic>>> getWalletTransactions() async {
    final res = await _dio.get('/wallet/transactions/');
    return ApiEnvelope.unwrapList<Map<String, dynamic>>(
      res.data,
      (e) => Map<String, dynamic>.from(e as Map),
    );
  }

  /// Validate a promo code at checkout. Returns `{ valid, discount_amount?, reason? }`.
  Future<Map<String, dynamic>> validatePromoCode({
    required String code,
    required int storeId,
    required double subtotal,
    List<int> categoryIds = const [],
  }) async {
    final res = await _dio.post('/promotions/promotions/validate/', data: {
      'code': code,
      'store_id': storeId,
      'subtotal': subtotal,
      'category_ids': categoryIds,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Mark all notifications as read.
  Future<void> markAllNotificationsRead() async {
    await _dio.patch('/notifications/read-all/');
  }

  /// Submit a rating using the spec field names. Optional photo_url.
  Future<Map<String, dynamic>> submitRating({
    required String orderId,
    required int productQualityRating,
    required int deliverySpeedRating,
    String comment = '',
    String? photoUrl,
  }) async {
    final res = await _dio.post('/ratings/', data: {
      'order_id': orderId,
      'product_quality_rating': productQualityRating,
      'delivery_speed_rating': deliverySpeedRating,
      if (comment.isNotEmpty) 'comment': comment,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photo_url': photoUrl,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Cancel an order with a reason.
  Future<Map<String, dynamic>> cancelOrder(String orderId, {String reason = ''}) async {
    final res = await _dio.patch('/orders/$orderId/cancel/', data: {'reason': reason});
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Customer adds an item to a preparing order.
  Future<Map<String, dynamic>> customerAddItemToOrder(
    String orderId,
    String productId,
    double qty,
  ) async {
    final res = await _dio.post('/orders/$orderId/items/', data: {
      'product_id': productId,
      'qty': qty,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Customer removes an item from a preparing order.
  Future<void> customerRemoveItemFromOrder(String orderId, int itemId) async {
    await _dio.delete('/orders/$orderId/items/$itemId/');
  }

  /// Approve / reject an adjustment with the NEW path.
  Future<Map<String, dynamic>> approveAdjustmentV2(
    String orderId,
    int adjustmentId,
    bool approved,
  ) async {
    final res = await _dio.patch('/orders/$orderId/approve-adjustment/', data: {
      'adjustment_id': adjustmentId,
      'approved': approved,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  /// Request a presigned S3 upload URL (image uploads).
  Future<Map<String, dynamic>> presignUpload({
    required String filename,
    required String contentType,
    String folder = 'misc',
  }) async {
    final res = await _dio.post('/uploads/presign/', data: {
      'filename': filename,
      'content_type': contentType,
      'folder': folder,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final res = await _dio.post('/auth/register/', data: data);
    final m = Map<String, dynamic>.from(_unwrap(res.data) ?? res.data);
    await _saveTokens(m['access'], m['refresh']);
    return m;
  }

  Future<Map<String, dynamic>> socialLogin(String provider, String socialId,
      {String? phone, String? fullName, String? email}) async {
    final res = await _dio.post('/auth/social/', data: {
      'provider': provider, 'social_id': socialId,
      if (phone != null) 'phone': phone,
      if (fullName != null) 'full_name': fullName,
      if (email != null) 'email': email,
    });
    final m = Map<String, dynamic>.from(_unwrap(res.data) ?? res.data);
    await _saveTokens(m['access'], m['refresh']);
    return m;
  }

  Future<Map<String, dynamic>> biometricLogin(String biometricToken) async {
    final res = await _dio.post('/auth/biometric/login/', data: {'biometric_token': biometricToken});
    final m = Map<String, dynamic>.from(_unwrap(res.data) ?? res.data);
    await _saveTokens(m['access'], m['refresh']);
    return m;
  }

  Future<void> registerBiometric(String biometricToken) async {
    await _dio.post('/auth/biometric/register/', data: {'biometric_token': biometricToken});
  }

  Future<void> logout() async {
    try {
      final refresh = await _storage.read(key: StorageKeys.refreshToken);
      await _dio.post('/auth/logout/', data: {'refresh': refresh});
    } catch (_) {}
    await _storage.deleteAll();
  }

  Future<void> updateFcmToken(String fcmToken) async {
    await _dio.post('/auth/fcm-token/', data: {'fcm_token': fcmToken});
  }

  Future<void> _saveTokens(String access, String refresh) async {
    await _storage.write(key: StorageKeys.accessToken, value: access);
    await _storage.write(key: StorageKeys.refreshToken, value: refresh);
  }

  Future<UserModel> getProfile() async {
    // Prefer /auth/me/ (new), fall back to /auth/profile/ (legacy alias).
    Response res;
    try {
      res = await _dio.get('/auth/me/');
    } catch (_) {
      res = await _dio.get('/auth/profile/');
    }
    final data = _unwrap(res.data);
    return UserModel.fromJson(Map<String, dynamic>.from(data is Map ? data : res.data));
  }

  // ─── Products ─────────────────────────────────────────────────────────────

  /// Paginated product list. Returns the full response payload so callers
  /// can read pagination metadata. Use [getProductsList] for just the items.
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    int limit = 20,
    String? search,
    int? category,
    int? storeId,
    bool? hasDiscount,
    bool? onSale,  // alias of hasDiscount for back-compat
    bool? featured,
    String? branchId,
  }) async {
    final res = await _dio.get('/products/', queryParameters: {
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null) 'category_id': category,
      if (storeId != null) 'store_id': storeId,
      if (hasDiscount == true || onSale == true) 'has_discount': true,
      if (featured == true) 'featured': true,
      if (branchId != null) 'branch_id': branchId,
    });
    final body = res.data;
    if (body is Map<String, dynamic>) return body;
    return {'data': body};
  }

  /// Convenience — just the product list.
  Future<List<ProductModel>> getProductsList({
    int page = 1,
    int limit = 20,
    String? search,
    int? category,
    int? storeId,
    bool? hasDiscount,
  }) async {
    final res = await getProducts(
      page: page, limit: limit, search: search,
      category: category, storeId: storeId, hasDiscount: hasDiscount,
    );
    return ApiEnvelope.unwrapList<ProductModel>(
      res, (e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<ProductModel> getProduct(String id) async {
    final res = await _dio.get('/products/$id/');
    final data = _unwrap(res.data);
    return ProductModel.fromJson(Map<String, dynamic>.from(data is Map ? data : res.data));
  }

  Future<ProductModel?> getProductByBarcode(String barcode) async {
    try {
      final res = await _dio.get('/products/barcode/$barcode/');
      final data = _unwrap(res.data);
      return ProductModel.fromJson(Map<String, dynamic>.from(data is Map ? data : res.data));
    } catch (_) {
      return null;
    }
  }

  Future<List<ProductModel>> searchSuggestions(String query) async {
    final res = await _dio.get('/products/search/suggestions/', queryParameters: {'q': query});
    return ApiEnvelope.unwrapList<ProductModel>(
      res.data, (p) => ProductModel.fromJson(Map<String, dynamic>.from(p as Map)),
    );
  }

  Future<List<CategoryModel>> getCategories() async {
    final res = await _dio.get('/products/categories/');
    final data = res.data;
    final List list = data is List ? data : (data['results'] ?? []);
    return list.map((c) => CategoryModel.fromJson(c)).toList().cast<CategoryModel>();
  }

  Future<List<BannerModel>> getBanners({String? position}) async {
    final res = await _dio.get('/products/banners/', queryParameters: {
      if (position != null) 'position': position,
    });
    final data = res.data;
    final List list = data is List ? data : (data['results'] ?? []);
    return list.map((b) => BannerModel.fromJson(b)).toList().cast<BannerModel>();
  }

  Future<void> toggleWaitlist(String productId) async {
    await _dio.post('/products/$productId/waitlist/');
  }

  // ─── Orders ───────────────────────────────────────────────────────────────

  Future<OrderModel> createOrder(Map<String, dynamic> data) async {
    final res = await _dio.post('/orders/create/', data: data);
    final body = _unwrap(res.data);
    return OrderModel.fromJson(Map<String, dynamic>.from(body is Map ? body : res.data));
  }

  Future<List<OrderModel>> getMyOrders() async {
    final res = await _dio.get('/orders/');
    return ApiEnvelope.unwrapList<OrderModel>(
      res.data,
      (o) => OrderModel.fromJson(Map<String, dynamic>.from(o as Map)),
    );
  }

  Future<OrderModel> getOrder(String orderId) async {
    final res = await _dio.get('/orders/$orderId/');
    final body = _unwrap(res.data);
    return OrderModel.fromJson(Map<String, dynamic>.from(body is Map ? body : res.data));
  }

  Future<Map<String, dynamic>> confirmReceipt(String orderId) async {
    final res = await _dio.post('/orders/$orderId/confirm-receipt/');
    return res.data;
  }

  Future<void> approveAdjustment(int adjustmentId, bool approved) async {
    await _dio.post('/orders/adjustments/$adjustmentId/respond/', data: {'approved': approved});
  }

  Future<void> rateOrder(String orderId, {
    required int productRating,
    required int deliveryRating,
    String comment = '',
  }) async {
    await _dio.post('/orders/$orderId/rate/', data: {
      'product_rating': productRating,
      'delivery_rating': deliveryRating,
      'comment': comment,
    });
  }

  // ─── Driver ───────────────────────────────────────────────────────────────

  Future<List<OrderModel>> getDriverOrders({String? status}) async {
    final res = await _dio.get('/orders/driver/list/', queryParameters: {
      if (status != null) 'status': status,
    });
    final list = res.data['results'] ?? res.data as List;
    return list.map<OrderModel>((o) => OrderModel.fromJson(o)).toList();
  }

  Future<OrderModel> acceptOrder(String orderId) async {
    final res = await _dio.post('/orders/$orderId/accept/');
    return OrderModel.fromJson(res.data);
  }

  Future<void> startDelivery(String orderId) async {
    await _dio.post('/orders/$orderId/start-delivery/');
  }

  Future<void> markDelivered(String orderId) async {
    await _dio.post('/orders/$orderId/mark-delivered/');
  }

  Future<void> autoCloseOrder(String orderId) async {
    await _dio.post('/orders/$orderId/auto-close/');
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _dio.post('/auth/location/', data: {'latitude': lat, 'longitude': lng});
  }

  Future<void> toggleOnlineStatus() async {
    await _dio.post('/auth/online-toggle/');
  }

  Future<void> adjustItemPrice(String orderId, int itemId, double newPrice, String reason) async {
    await _dio.post('/orders/$orderId/items/$itemId/adjust-price/', data: {
      'new_price': newPrice, 'reason': reason,
    });
  }

  Future<void> substituteItem(String orderId, int itemId, String substituteProductId) async {
    await _dio.post('/orders/$orderId/items/$itemId/substitute/', data: {
      'substitute_product_id': substituteProductId,
    });
  }

  Future<void> addItemToOrder(String orderId, String productId, double quantity) async {
    await _dio.post('/orders/$orderId/add-item/', data: {
      'product_id': productId, 'quantity': quantity,
    });
  }

  // ─── Addresses ────────────────────────────────────────────────────────────

  Future<List<AddressModel>> getAddresses() async {
    final res = await _dio.get('/auth/addresses/');
    final list = res.data['results'] ?? res.data as List;
    return list.map<AddressModel>((a) => AddressModel.fromJson(a)).toList();
  }

  Future<AddressModel> createAddress(Map<String, dynamic> data) async {
    final res = await _dio.post('/auth/addresses/', data: data);
    return AddressModel.fromJson(res.data);
  }

  Future<void> deleteAddress(int id) async {
    await _dio.delete('/auth/addresses/$id/');
  }

  // ─── Settings & Notifications ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getAppSettings() async {
    final res = await _dio.get('/notifications/settings/');
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final res = await _dio.get('/notifications/my/');
    return List<Map<String, dynamic>>.from(res.data['results'] ?? res.data);
  }
}
