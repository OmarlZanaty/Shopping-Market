import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

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
          soundSource: 'resource://raw/new_order',
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
          soundSource: 'resource://raw/adjustment',
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

    fcm.onTokenRefresh.listen((t) {
      _fcmToken = t;
    });

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);
  }

  void _onForegroundMessage(RemoteMessage msg) {
    final type = msg.data['type'] ?? '';
    if (type == 'new_order') {
      _newOrderCtrl.add(Map<String, dynamic>.from(msg.data));
      _showLocalNotification(
        channelKey: 'agent_new_order',
        title: msg.notification?.title ?? 'طلب جديد',
        body: msg.notification?.body ?? '',
        payload: Map<String, String?>.from(msg.data.map((k, v) => MapEntry(k, v?.toString()))),
      );
    } else if (type == 'adjustment_response') {
      _showLocalNotification(
        channelKey: 'agent_adjustment',
        title: msg.notification?.title ?? 'تحديث على الطلب',
        body: msg.notification?.body ?? '',
        payload: Map<String, String?>.from(msg.data.map((k, v) => MapEntry(k, v?.toString()))),
      );
    } else {
      _showLocalNotification(
        channelKey: 'agent_general',
        title: msg.notification?.title ?? 'إشعار',
        body: msg.notification?.body ?? '',
        payload: Map<String, String?>.from(msg.data.map((k, v) => MapEntry(k, v?.toString()))),
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
