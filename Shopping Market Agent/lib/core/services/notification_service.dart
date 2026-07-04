import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import '../network/dio_client.dart';

/// Single notification entrypoint. Sets up 3 awesome_notifications channels
/// with distinct sounds, registers the FCM token, and emits a stream of
/// incoming-order payloads consumed by the global app router (to push the
/// IncomingOrderOverlay on top of any current screen).
class AgentNotificationService {
  AgentNotificationService._();
  static final AgentNotificationService I = AgentNotificationService._();

  final _newOrderCtrl = StreamController<Map<String, dynamic>>.broadcast();
  /// Fires whenever an FCM message of type=new_order arrives in foreground.
  Stream<Map<String, dynamic>> get newOrderStream => _newOrderCtrl.stream;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _permissionAsked = false;

  /// Automatic self-heal layer. Call on app launch AND every app-resume.
  /// Silently (no visible test push):
  ///   1. re-requests notification permission once per session if revoked,
  ///   2. (re)fetches the FCM token with a retry,
  ///   3. re-syncs the token to the backend so it always has a live token.
  /// This fixes the common "device stops getting notifications" causes —
  /// missing permission, a null/rotated token, or a token the backend cleared
  /// after a delivery failure — without any user action.
  Future<void> ensureHealthy() async {
    try {
      final fcm = FirebaseMessaging.instance;
      final allowed = await AwesomeNotifications().isNotificationAllowed();
      if (!allowed && !_permissionAsked) {
        _permissionAsked = true;
        await AwesomeNotifications().requestPermissionToSendNotifications();
        await fcm.requestPermission(
            alert: true, badge: true, sound: true, criticalAlert: true);
      }
      _fcmToken ??= await fcm.getToken();
      if (_fcmToken == null) {
        await Future.delayed(const Duration(seconds: 2));
        _fcmToken = await fcm.getToken();
      }
      if (_fcmToken != null) await _sendTokenToBackend(_fcmToken!);
    } catch (e) {
      debugPrint('[Agent FCM] ensureHealthy failed: $e');
    }
  }

  Future<void> init() async {
    // ── Awesome Notifications ─────────────────────────────────────────────
    await AwesomeNotifications().initialize(
      null, // small icon — null uses launcher icon
      [
        NotificationChannel(
          channelKey: 'agent_new_order',
          channelName: 'طلبات جديدة',
          channelDescription: 'تنبيه عند ورود طلب جديد للوكيل',
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
          criticalAlerts: true,
          defaultColor: const Color(0xFFFF6B35),
          ledColor: const Color(0xFFFF6B35),
        ),
        NotificationChannel(
          channelKey: 'agent_adjustment',
          channelName: 'تحديثات الطلب',
          channelDescription: 'رد العميل على تعديلات الأسعار/الأوزان/البدائل',
          importance: NotificationImportance.High,
          playSound: true,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'agent_general',
          channelName: 'إشعارات عامة',
          channelDescription: 'إشعارات النظام والمحادثات',
          importance: NotificationImportance.Default,
          playSound: false,
        ),
      ],
      debug: kDebugMode,
    );

    final allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    // ── Firebase Messaging ────────────────────────────────────────────────
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true, criticalAlert: true);
    _fcmToken = await fcm.getToken();
    debugPrint('[Agent FCM] token=$_fcmToken');

    // On first install getToken() can return null while Firebase registers the
    // device. Retry once after a short delay so bootstrap() has a token to sync.
    if (_fcmToken == null) {
      Future.delayed(const Duration(seconds: 5), () async {
        _fcmToken = await fcm.getToken();
        if (_fcmToken != null) {
          debugPrint('[Agent FCM] token (retry)=$_fcmToken');
          _sendTokenToBackend(_fcmToken!);
        }
      });
    }

    fcm.onTokenRefresh.listen((t) {
      _fcmToken = t;
      debugPrint('[Agent FCM] token refreshed=$t');
      _sendTokenToBackend(t);
    });

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);
  }

  /// Called by [AgentAuthController] after a successful login or bootstrap so
  /// the token is synced even if [init()] ran before the user was authenticated.
  Future<void> syncTokenAfterAuth() async {
    if (_fcmToken != null) {
      await _sendTokenToBackend(_fcmToken!);
    }
  }

  /// Second layer: re-sync the token, then ask the server to send a test push to
  /// this device. Returns {has_token, fcm_sent} so the UI can explain the result.
  Future<Map<String, dynamic>> sendTestNotification() async {
    // Make sure the token (possibly fetched after a retry) is on the backend.
    _fcmToken ??= await FirebaseMessaging.instance.getToken();
    if (_fcmToken != null) await _sendTokenToBackend(_fcmToken!);
    final res = await DioClient.I.dio.post('/notifications/test/');
    final body = res.data;
    return (body is Map && body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
  }

  /// Sends the FCM token to the backend. Called on init and on every token refresh.
  /// Uses DioClient which already injects the stored access token via interceptors.
  Future<void> _sendTokenToBackend(String token) async {
    try {
      await DioClient.I.dio.post('/auth/fcm-token/', data: {'fcm_token': token});
      debugPrint('[Agent FCM] token synced to backend');
    } catch (e) {
      debugPrint('[Agent FCM] token sync failed (may not be logged in yet): $e');
    }
  }

  void _onForegroundMessage(RemoteMessage msg) {
    final type = msg.data['type'] ?? '';
    final payload = Map<String, String?>.from(msg.data.map((k, v) => MapEntry(k, v?.toString())));
    if (type == 'new_order') {
      _newOrderCtrl.add(Map<String, dynamic>.from(msg.data));
      _showLocalNotification(
        channelKey: 'agent_new_order',
        title: msg.notification?.title ?? 'طلب جديد',
        body: msg.notification?.body ?? '',
        payload: payload,
      );
    } else if (type == 'order_status') {
      // Status changed on an order the agent is handling
      _showLocalNotification(
        channelKey: 'agent_adjustment',
        title: msg.notification?.title ?? 'تحديث الطلب',
        body: msg.notification?.body ?? msg.data['body_ar'] ?? '',
        payload: payload,
      );
    } else if (type == 'adjustment_response') {
      _showLocalNotification(
        channelKey: 'agent_adjustment',
        title: msg.notification?.title ?? 'تحديث على الطلب',
        body: msg.notification?.body ?? '',
        payload: payload,
      );
    } else {
      _showLocalNotification(
        channelKey: 'agent_general',
        title: msg.notification?.title ?? 'إشعار',
        body: msg.notification?.body ?? '',
        payload: payload,
      );
    }
  }

  void _onMessageTap(RemoteMessage msg) {
    final orderId = msg.data['order_id'];
    if (orderId != null) {
      // Router can read this via a global key — kept simple for the scaffold.
      debugPrint('[Agent FCM] open order $orderId');
    }
  }

  Future<void> _showLocalNotification({
    required String channelKey,
    required String title,
    required String body,
    Map<String, String?>? payload,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: channelKey,
        title: title,
        body: body,
        payload: payload,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }

  void dispose() => _newOrderCtrl.close();
}

/// Required top-level background handler — registered in main.dart.
@pragma('vm:entry-point')
Future<void> agentBackgroundHandler(RemoteMessage message) async {
  // Awesome notifications handles display on Android even when the app is killed,
  // because of the FCM payload's notification + data dual fields. Nothing more
  // to do here beyond ensuring Firebase is initialized.
}
