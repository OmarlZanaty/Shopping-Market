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

  /// Custom notification tone. Android reads it from res/raw/notification_sound.mp3;
  /// on iOS awesome_notifications resolves this to notification_sound.aiff in the
  /// app bundle (its resource lookup hardcodes the .aiff extension).
  static const _soundSource = 'resource://raw/notification_sound';

  /// Android freezes a channel's sound at creation time — an existing install
  /// keeps the old (default) tone no matter what we pass on the next launch, and
  /// deleting + recreating the same id restores the old settings too. So the sound
  /// can only change by publishing NEW channel keys; bump the suffix whenever the
  /// tone or importance changes. Devices on an older build still receive pushes:
  /// an unknown channel_id falls back to the default channel in their manifest.
  ///
  /// These keys must stay in sync with `_android_channel()` in the backend
  /// (Backend/apps/notifications/utils.py) — Android 8+ drops a push whose
  /// channel_id it doesn't recognise and can't fall back from.
  static const newOrderChannel   = 'agent_new_order_v2';
  static const adjustmentChannel = 'agent_adjustment_v2';
  /// Deliberately silent, so it keeps its original key — no sound to change.
  static const generalChannel    = 'agent_general';

  /// The single channel definition, shared by [init] and the background isolate
  /// in main.dart — channels are per-process, so the isolate has to declare the
  /// identical set or a background push would recreate them without the tone.
  static List<NotificationChannel> get channels => [
        NotificationChannel(
          channelKey: newOrderChannel,
          channelName: 'طلبات جديدة',
          channelDescription: 'تنبيه عند ورود طلب جديد للوكيل',
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: _soundSource,
          enableVibration: true,
          criticalAlerts: true,
          defaultColor: const Color(0xFFFF6B35),
          ledColor: const Color(0xFFFF6B35),
        ),
        NotificationChannel(
          channelKey: adjustmentChannel,
          channelName: 'تحديثات الطلب',
          channelDescription: 'رد العميل على تعديلات الأسعار/الأوزان/البدائل',
          importance: NotificationImportance.High,
          playSound: true,
          soundSource: _soundSource,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: generalChannel,
          channelName: 'إشعارات عامة',
          channelDescription: 'إشعارات النظام والمحادثات',
          importance: NotificationImportance.Default,
          playSound: false,
        ),
      ];

  /// Channel for an incoming FCM payload's `type`. Mirrors `_android_channel()`
  /// in Backend/apps/notifications/utils.py.
  static String channelForType(String type) => type == 'new_order'
      ? newOrderChannel
      : (type == 'order_status' ||
              type == 'adjustment_response' ||
              type == 'price_change' ||
              type == 'substitute' ||
              type == 'item_added' ||
              type == 'quantity_change')
          ? adjustmentChannel
          : generalChannel;

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
      channels,
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
        channelKey: newOrderChannel,
        title: msg.notification?.title ?? 'طلب جديد',
        body: msg.notification?.body ?? '',
        payload: payload,
      );
    } else if (type == 'order_status') {
      // Status changed on an order the agent is handling
      _showLocalNotification(
        channelKey: adjustmentChannel,
        title: msg.notification?.title ?? 'تحديث الطلب',
        body: msg.notification?.body ?? msg.data['body_ar'] ?? '',
        payload: payload,
      );
    } else if (type == 'adjustment_response') {
      _showLocalNotification(
        channelKey: adjustmentChannel,
        title: msg.notification?.title ?? 'تحديث على الطلب',
        body: msg.notification?.body ?? '',
        payload: payload,
      );
    } else {
      _showLocalNotification(
        channelKey: generalChannel,
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
