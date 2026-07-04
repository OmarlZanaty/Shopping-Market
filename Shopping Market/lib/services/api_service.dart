import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../models/models.dart';
import '../core/network/api_envelope.dart';

/// Thrown by [ApiService.socialLogin] when the backend recognises a brand-new
/// social account and needs a phone number to complete the signup. The UI
/// catches this to prompt for the phone, then retries with it supplied.
class SocialNeedsPhoneException implements Exception {}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Called whenever a 401 cannot be recovered (refresh expired / invalid).
  /// Set this from AuthProvider.init() to trigger a UI-level logout.
  static void Function()? onUnauthorized;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
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
        try {
          // Don't attach a stale token to public auth endpoints — a deleted-user
          // token causes the server to return 401 user_not_found before the view runs.
          const _noAuth = ['/auth/login/', '/auth/register/', '/auth/refresh/',
                           '/auth/firebase-token/', '/auth/verify-otp/', '/auth/send-otp/',
                           '/auth/social/', '/auth/biometric/login/'];
          final isPublic = _noAuth.any((p) => options.path.contains(p));
          final token = await _storage.read(key: StorageKeys.accessToken);
          if (token != null && !isPublic) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // Corrupt storage — ignore and proceed unauthenticated.
          await _storage.deleteAll();
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        // Don't try to refresh on auth endpoints (login, register, social…)
        final path = e.requestOptions.path;
        final isAuthEndpoint = path.contains('/auth/login/') ||
            path.contains('/auth/register/') ||
            path.contains('/auth/social-login/') ||
            path.contains('/auth/biometric/') ||
            path.contains('/auth/refresh/') ||
            path.contains('/auth/token/refresh/');

        if (e.response?.statusCode == 401 && !isAuthEndpoint) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Retry with the new access token
            final token = await _storage.read(key: StorageKeys.accessToken);
            e.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final retry = await _dio.fetch(e.requestOptions);
              return handler.resolve(retry);
            } catch (retryErr) {
              return handler.next(e);
            }
          } else {
            // Refresh failed — tokens are gone; notify the app to log out.
            onUnauthorized?.call();
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

  /// In-flight refresh, shared so concurrent 401s perform ONE refresh.
  /// With ROTATE_REFRESH_TOKENS + BLACKLIST_AFTER_ROTATION on the server,
  /// parallel refreshes race: the first rotation blacklists the old token and
  /// the losers get 401 → deleteAll() → user is logged out on every cold start.
  Future<bool>? _refreshInFlight;

  Future<bool> _refreshToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefreshToken().whenComplete(() => _refreshInFlight = null);
    _refreshInFlight = future;
    return future;
  }

  Future<bool> _doRefreshToken() async {
    try {
      final refresh = await _storage.read(key: StorageKeys.refreshToken);
      if (refresh == null) return false;

      // Use a plain Dio (no auth interceptor) to avoid infinite retry loops.
      final plain = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      Response? res;
      for (final url in [
        '${AppConfig.baseUrl}/auth/refresh/',
        '${AppConfig.baseUrl}/auth/token/refresh/',
      ]) {
        try {
          res = await plain.post(url, data: {'refresh': refresh});
          break; // success — stop trying
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403) {
            // Refresh token is genuinely expired / blacklisted — must log out.
            await _storage.deleteAll();
            return false;
          }
          if (e.response != null) {
            // Other 4xx/5xx (e.g. 500 server glitch) — don't wipe tokens,
            // just report the refresh as failed so the caller can fall back.
            return false;
          }
          // Network-level error (timeout, no connection) → try next URL.
        }
      }

      if (res == null) {
        // Both URLs failed at network level — keep tokens, report failure.
        return false;
      }

      final body = res.data is Map ? res.data as Map : {};
      final access = body['access'] ?? body['data']?['access'];
      final newRefresh = body['refresh'] ?? body['data']?['refresh'];

      if (access == null) {
        // Unexpected response shape — don't wipe tokens, just fail silently.
        return false;
      }

      await _storage.write(key: StorageKeys.accessToken, value: access as String);
      if (newRefresh != null) {
        await _storage.write(key: StorageKeys.refreshToken, value: newRefresh as String);
      }
      return true;
    } catch (_) {
      // Unexpected error — don't wipe tokens.
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

  /// Exchange a Firebase Phone Auth ID token for our Django JWT.
  /// Backend: POST /auth/firebase-token/
  Future<Map<String, dynamic>> firebaseTokenLogin({
    required String idToken,
    required String phone,
    String? fullName,
    String? fcmToken,
  }) async {
    final res = await _dio.post('/auth/firebase-token/', data: {
      'id_token': idToken,
      'phone': phone,
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

  /// Global app settings (delivery radius, store location, ...) as a flat
  /// {key: value} map. Public endpoint — returns a raw dict, not enveloped.
  Future<Map<String, dynamic>> getAppSettings() async {
    final res = await _dio.get('/notifications/settings/');
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
  /// Returns full response including `payment_required`, `amount_owed`,
  /// `wallet_refund` fields when applicable.
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

  /// Initiate a Paymob card payment for a price-increase adjustment.
  /// Returns `{ iframe_url, transaction_id, amount_egp }`.
  Future<Map<String, dynamic>> initiateAdjustmentPayment({
    required String orderId,
    required int adjustmentId,
  }) async {
    final res = await _dio.post('/payments/adjustment-topup/', data: {
      'order_id': orderId,
      'adjustment_id': adjustmentId,
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
    try {
      final res = await _dio.post('/auth/social/', data: {
        'provider': provider, 'social_id': socialId,
        if (phone != null) 'phone': phone,
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
      });
      final m = Map<String, dynamic>.from(_unwrap(res.data) ?? res.data);
      await _saveTokens(m['access'], m['refresh']);
      return m;
    } on DioException catch (e) {
      // A brand-new social account returns 400 "Phone required for new social
      // signup". Surface that distinctly so the UI can collect a phone and retry
      // (only when we didn't already send one).
      final body = e.response?.data;
      final msg = (body is Map && body['message'] != null)
          ? body['message'].toString().toLowerCase()
          : '';
      if (phone == null &&
          e.response?.statusCode == 400 &&
          msg.contains('phone')) {
        throw SocialNeedsPhoneException();
      }
      rethrow;
    }
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

  /// Wipes local tokens immediately, then best-effort notifies the server.
  ///
  /// We deliberately do `deleteAll()` BEFORE the network call so that:
  ///   • the auth interceptor can't enter a 401-refresh-onUnauthorized cycle
  ///     while logout is still in flight (was causing blank-screen logout),
  ///   • a slow / failing network never blocks the UI from leaving the
  ///     authenticated screens.
  /// The server-side call is fire-and-forget using a plain Dio (no interceptors)
  /// so a corrupt access token can't bounce through refresh logic.
  Future<void> logout() async {
    String? refresh;
    try {
      refresh = await _storage.read(key: StorageKeys.refreshToken);
    } catch (_) {}
    // 1) Local wipe — synchronous from the caller's perspective.
    try {
      await _storage.deleteAll();
    } catch (_) {}
    // 2) Best-effort server notify. Plain Dio = no auth interceptor, no refresh
    //    loop, no validateStatus throws.
    if (refresh == null || refresh.isEmpty) return;
    try {
      final plain = Dio(BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true, // never throw on status code
      ));
      await plain.post('/auth/logout/', data: {'refresh': refresh});
    } catch (_) {}
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

  Future<UserModel> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    Response res;
    try {
      res = await _dio.patch('/auth/me/', data: {
        'full_name': fullName,
        'phone': phone,
      });
    } catch (_) {
      res = await _dio.patch('/auth/profile/', data: {
        'full_name': fullName,
        'phone': phone,
      });
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

  /// Join the waitlist for an out-of-stock product.
  Future<void> addToWaitlist(String productId) async {
    await _dio.post('/products/waitlist/', data: {'product_id': productId});
  }

  /// Leave the waitlist for a product.
  Future<void> removeFromWaitlist(String productId) async {
    await _dio.delete('/products/waitlist/$productId/');
  }

  // ─── Orders ───────────────────────────────────────────────────────────────

  Future<OrderModel> createOrder(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/orders/create/', data: data);
      final body = _unwrap(res.data);
      return OrderModel.fromJson(Map<String, dynamic>.from(body is Map ? body : res.data));
    } on DioException catch (e) {
      // Translate the backend's English business-rule errors to Arabic so the
      // UI never has to show "DioException [bad response]: …" to the user.
      throw Exception(_translateOrderError(e));
    }
  }

  /// Maps known English error messages from the backend's order-create
  /// service to friendly Arabic. Falls back to the original message if the
  /// backend already replied in Arabic, or a generic Arabic message otherwise.
  String _translateOrderError(DioException e) {
    String raw = '';
    final r = e.response?.data;
    if (r is Map) {
      raw = (r['message'] ?? r['detail'] ?? '').toString();
    }
    raw = raw.trim();

    // Already Arabic? Pass through verbatim.
    if (RegExp(r'[؀-ۿ]').hasMatch(raw)) return raw;

    final low = raw.toLowerCase();
    if (low.contains('insufficient stock')) {
      final m = RegExp(r'insufficient stock for\s+(.+)', caseSensitive: false)
          .firstMatch(raw);
      final name = (m?.group(1) ?? '').trim();
      return name.isEmpty
          ? 'الكمية المطلوبة غير متوفرة في المخزون'
          : 'المنتج "$name" غير متوفر بالكمية المطلوبة في المخزون';
    }
    if (low.contains('address not found')) {
      return 'العنوان غير موجود أو لا يخصك';
    }
    if (low.contains('same store') || low.contains('cross-store')) {
      return 'لا يمكن إضافة منتجات من متاجر مختلفة في نفس الطلب';
    }
    if (low.contains('insufficient wallet')) {
      return 'رصيد المحفظة غير كافٍ لإتمام الطلب';
    }
    if (low.contains('not enough loyalty points')) {
      return 'نقاط الولاء غير كافية';
    }
    if (low.contains('at least one item')) {
      return 'يجب إضافة منتج واحد على الأقل للطلب';
    }
    if (low.contains('not available')) {
      return 'أحد المنتجات غير متاح حالياً';
    }
    if (low.contains('not found')) {
      return 'أحد المنتجات غير موجود في قاعدة البيانات';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'انقطع الاتصال بالخادم، تحقق من الإنترنت وحاول مرة أخرى';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'لا يمكن الاتصال بالخادم، تحقق من الإنترنت';
    }
    return raw.isNotEmpty
        ? 'تعذر إتمام الطلب: $raw'
        : 'تعذر إتمام الطلب الآن، حاول مرة أخرى';
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

  /// Agent-side order detail — uses /agent/orders/{id}/ which is scoped by
  /// store/assignment, not by customer. Falls back to customer endpoint.
  Future<OrderModel> getAgentOrder(String orderId) async {
    try {
      final res = await _dio.get('/agent/orders/$orderId/');
      final body = _unwrap(res.data);
      return OrderModel.fromJson(Map<String, dynamic>.from(body is Map ? body : res.data));
    } catch (_) {
      return getOrder(orderId);
    }
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
    final body = _unwrap(res.data);
    return OrderModel.fromJson(Map<String, dynamic>.from(body is Map ? body : res.data));
  }

  /// Transition: accepted → preparing
  Future<void> startPreparing(String orderId) async {
    await _dio.post('/orders/$orderId/start-preparing/');
  }

  /// Transition: preparing → out_for_delivery (order ready for pickup/delivery)
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

  // ─── AI / Smart Shopping ──────────────────────────────────────────────────

  /// Personalised product recommendations for the logged-in user.
  Future<List<ProductModel>> getRecommendations({
    int limit = 10,
    String? storeId,
  }) async {
    final res = await _dio.get('/ai/recommendations/', queryParameters: {
      'limit': limit,
      if (storeId != null) 'store_id': storeId,
    });
    final data = _unwrap(res.data);
    final list = (data is Map ? data['results'] : data) as List? ?? [];
    return list.map<ProductModel>((p) => ProductModel.fromJson(p)).toList();
  }

  /// "You usually order these" nudge list for the current session.
  Future<List<ProductModel>> getSmartCart({String? storeId}) async {
    final res = await _dio.get('/ai/smart-cart/', queryParameters: {
      if (storeId != null) 'store_id': storeId,
    });
    final data = _unwrap(res.data);
    final list = (data is Map ? data['results'] : data) as List? ?? [];
    return list.map<ProductModel>((p) => ProductModel.fromJson(p)).toList();
  }

  /// Visual search — send base64-encoded image, get matching products.
  Future<Map<String, dynamic>> visualSearch(String imageBase64, {String? storeId}) async {
    final res = await _dio.post('/ai/visual-search/', data: {
      'image_base64': imageBase64,
      if (storeId != null) 'store_id': storeId,
    });
    final data = _unwrap(res.data);
    return Map<String, dynamic>.from(data is Map ? data : {});
  }
}
