import 'package:flutter/foundation.dart';

/// Endpoint paths + base URL for the agent app. All agent-side calls live under
/// `/api/v1/agent/...`; auth lives under `/api/v1/auth/...`.
class ApiConstants {
  ApiConstants._();

  // NB: there is no `api.shopping-market.com` DNS record yet, so release
  // builds must point at the server's IP directly — otherwise the APK fails
  // on every device with "Failed host lookup". Override with
  // --dart-define=API_BASE_URL=... once a real domain + TLS cert exist.
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'http://63.186.157.245/api/v1';
  }

  static String get wsBaseUrl {
    const fromEnv = String.fromEnvironment('WS_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'ws://63.186.157.245';
  }

  // Auth
  static const String login        = '/auth/login/';
  static const String refresh      = '/auth/refresh/';
  static const String logout       = '/auth/logout/';
  static const String me           = '/auth/me/';
  static const String fcmToken     = '/auth/fcm-token/';
  static const String location     = '/auth/location/';

  // Agent — orders
  static const String agentOrders         = '/agent/orders/';
  static String agentOrderDetail(String orderId)     => '/agent/orders/$orderId/';
  static String agentAccept(String orderId)          => '/agent/orders/$orderId/accept/';
  static String agentReject(String orderId)          => '/agent/orders/$orderId/reject/';
  static String agentStartPreparing(String orderId)  => '/agent/orders/$orderId/start-preparing/';
  static String agentReady(String orderId)           => '/agent/orders/$orderId/ready/';
  static String agentPickedUp(String orderId)        => '/agent/orders/$orderId/picked-up/';
  static String agentDelivered(String orderId)         => '/agent/orders/$orderId/delivered/';
  static String agentFailedDelivery(String orderId)   => '/agent/orders/$orderId/failed-delivery/';
  static String agentForceClose(String orderId)        => '/agent/orders/$orderId/force-close/';
  static String agentShare(String orderId)           => '/agent/orders/$orderId/share/';
  static String agentLog(String orderId)             => '/agent/orders/$orderId/log/';

  // Agent — items
  static String itemQty(String oid, int iid)         => '/agent/orders/$oid/items/$iid/qty/';
  static String itemUnavailable(String oid, int iid) => '/agent/orders/$oid/items/$iid/unavailable/';
  static String itemReset(String oid, int iid)       => '/agent/orders/$oid/items/$iid/reset/';
  static String itemPrice(String oid, int iid)       => '/agent/orders/$oid/items/$iid/price/';
  static String itemWeight(String oid, int iid)      => '/agent/orders/$oid/items/$iid/weight/';
  static String itemSubstitute(String oid, int iid)  => '/agent/orders/$oid/items/$iid/substitute/';
  static String itemAdd(String oid)                  => '/agent/orders/$oid/items/add/';
  static String itemRemove(String oid, int iid)      => '/agent/orders/$oid/items/$iid/';

  // Inventory
  static const String inventoryCategories            =  '/agent/inventory/categories/';
  static const String inventoryProducts              =  '/agent/inventory/products/';
  static String inventoryProductDetail(String pid)   => '/agent/inventory/products/$pid/';
  static String inventoryProductImages(String pid)   => '/agent/inventory/products/$pid/images/';
  static String inventoryProductImage(String pid, int imageId) => '/agent/inventory/products/$pid/images/$imageId/';
  static String inventoryScan(String barcode)        => '/agent/inventory/scan/$barcode/';
  static String inventoryMarkAvailable(String pid)   => '/agent/inventory/mark-available/$pid/';
  static String inventoryToggle(String pid)          => '/agent/inventory/toggle/$pid/';

  // Uploads
  static const String uploadsPresign = '/uploads/presign/';
}
