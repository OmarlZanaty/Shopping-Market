import 'package:flutter/foundation.dart';

/// Endpoint paths + base URL for the agent app. All agent-side calls live under
/// `/api/v1/agent/...`; auth lives under `/api/v1/auth/...`.
class ApiConstants {
  ApiConstants._();

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return kReleaseMode
        ? 'https://api.shopping-market.com/api/v1'
        : 'http://34.124.228.3:8000/api/v1';
  }

  static String get wsBaseUrl {
    const fromEnv = String.fromEnvironment('WS_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return kReleaseMode
        ? 'wss://api.shopping-market.com'
        : 'ws://34.124.228.3:8000';
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
  static String agentDelivered(String orderId)       => '/agent/orders/$orderId/delivered/';
  static String agentForceClose(String orderId)      => '/agent/orders/$orderId/force-close/';
  static String agentShare(String orderId)           => '/agent/orders/$orderId/share/';
  static String agentLog(String orderId)             => '/agent/orders/$orderId/log/';

  // Agent — items
  static String itemQty(String oid, int iid)         => '/agent/orders/$oid/items/$iid/qty/';
  static String itemUnavailable(String oid, int iid) => '/agent/orders/$oid/items/$iid/unavailable/';
  static String itemPrice(String oid, int iid)       => '/agent/orders/$oid/items/$iid/price/';
  static String itemWeight(String oid, int iid)      => '/agent/orders/$oid/items/$iid/weight/';
  static String itemSubstitute(String oid, int iid)  => '/agent/orders/$oid/items/$iid/substitute/';
  static String itemAdd(String oid)                  => '/agent/orders/$oid/items/add/';
  static String itemRemove(String oid, int iid)      => '/agent/orders/$oid/items/$iid/';

  // Inventory
  static String inventoryScan(String barcode)        => '/agent/inventory/scan/$barcode/';
  static String inventoryMarkAvailable(String pid)   => '/agent/inventory/mark-available/$pid/';

  // Uploads
  static const String uploadsPresign = '/uploads/presign/';
}
