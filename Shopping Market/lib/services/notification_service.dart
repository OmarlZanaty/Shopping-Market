import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import '../utils/constants.dart';
import '../router/customer_router.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

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
  static const orderChannel     = 'market_fresh_orders_v2';
  static const promoChannel     = 'market_fresh_promotions_v2';
  static const driverNewOrder   = 'driver_new_orders_v2';
  static const driverUpdates    = 'driver_updates_v2';

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    try {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // Permission prompt can throw on some iOS states — non-fatal.
    }

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: orderChannel,
          channelName: 'Order Updates',
          channelDescription: 'Order status updates and delivery notifications',
          defaultColor: AppColors.sapphire,
          ledColor: AppColors.sapphire,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          soundSource: _soundSource,
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: promoChannel,
          channelName: 'Promotions',
          channelDescription: 'Deals and offers',
          defaultColor: AppColors.coral,
          importance: NotificationImportance.Default,
          channelShowBadge: true,
          playSound: true,
          soundSource: _soundSource,
        ),
      ],
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // App opened by tapping FCM notification while in background.
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _navigateFromData(msg.data);
    });

    // App launched from terminated state via notification tap.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Delay until the router is mounted.
      Future.delayed(const Duration(milliseconds: 800), () {
        _navigateFromData(initial.data);
      });
    }

    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
    );

    // On iOS getToken() can throw (apns-token-not-set) or hang until the APNS
    // token is registered. Guard it so it can never crash notification init.
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        _onTokenRefresh(token);
      } else {
        // Fresh installs can return null while FCM is still registering the
        // device. Retry once shortly — otherwise this device never sends a
        // token to the backend and silently receives no pushes.
        Future.delayed(const Duration(seconds: 5), () async {
          try {
            final t = await _fcm.getToken();
            if (t != null) _onTokenRefresh(t);
          } catch (_) {}
        });
      }
    } catch (_) {
      // Retry later once APNS is ready; never block or crash startup.
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          final t = await _fcm.getToken();
          if (t != null) _onTokenRefresh(t);
        } catch (_) {}
      });
    }
    _fcm.onTokenRefresh.listen(_onTokenRefresh);
  }

  /// Navigate to the correct screen based on notification payload.
  static void _navigateFromData(Map<String, dynamic> data) {
    final orderId = data['order_id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    final ctx = CustomerRouter.navigatorKey.currentContext;
    if (ctx == null) return;
    // Navigate to order detail — GoRouter handles auth guard automatically.
    GoRouter.of(ctx).push('/orders/$orderId');
  }

  Future<void> initDriverNotifications() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: driverNewOrder,
          channelName: 'New Orders Alert',
          channelDescription: 'Loud alert for new delivery orders',
          defaultColor: AppColors.coral,
          ledColor: AppColors.coral,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: _soundSource,
          enableVibration: true,
          vibrationPattern: highVibrationPattern,
          criticalAlerts: true,
        ),
        NotificationChannel(
          channelKey: driverUpdates,
          channelName: 'Order Updates',
          channelDescription: 'Customer approval responses',
          defaultColor: AppColors.sapphire,
          importance: NotificationImportance.High,
          playSound: true,
          soundSource: _soundSource,
        ),
      ],
    );

    FirebaseMessaging.onMessage.listen(_handleDriverForegroundMessage);
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onDriverActionReceived,
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? '';

    if (type == 'order_status') {
      _showOrderNotification(
        title: data['title_ar'] ?? 'Market Fresh',
        body: data['body_ar'] ?? '',
        orderId: data['order_id'],
        channelKey: orderChannel,
      );
    } else if (['price_change', 'substitute', 'item_added', 'quantity_change'].contains(type)) {
      _showAdjustmentNotification(data);
    } else if (type == 'stock_available') {
      _showBasicNotification(
        title: '📦 المنتج متاح الآن!',
        body: data['body_ar'] ?? '',
        channelKey: promoChannel,
      );
    } else if (type == 'promotion') {
      _showBasicNotification(
        title: data['title_ar'] ?? '🎉 عرض جديد!',
        body: data['body_ar'] ?? '',
        channelKey: promoChannel,
      );
    }
  }

  void _handleDriverForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? '';

    if (type == 'new_order') {
      _showDriverNewOrderAlert(data);
    } else if (type == 'adjustment_response') {
      _showBasicNotification(
        title: data['approved'] == 'true' ? '✅ العميل وافق' : '❌ العميل رفض',
        body: 'تم تحديث الفاتورة',
        channelKey: driverUpdates,
      );
    }
  }

  Future<void> _showOrderNotification({
    required String title,
    required String body,
    String? orderId,
    required String channelKey,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: channelKey,
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        payload: orderId != null ? {'order_id': orderId} : null,
        color: AppColors.sapphire,
      ),
    );
  }

  Future<void> _showAdjustmentNotification(Map<String, dynamic> data) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: orderChannel,
        title: data['title_ar'] ?? '⚠️ تعديل على طلبك',
        body: data['body_ar'] ?? '',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'type': data['type'] ?? '',
          'order_id': data['order_id'] ?? '',
          'adjustment_id': data['adjustment_id'] ?? '',
        },
      ),
      actionButtons: [
        NotificationActionButton(key: 'APPROVE', label: '✅ موافق'),
        NotificationActionButton(key: 'REJECT', label: '❌ رفض', actionType: ActionType.SilentAction),
      ],
    );
  }

  Future<void> _showDriverNewOrderAlert(Map<String, dynamic> data) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: driverNewOrder,
        title: '🛒 طلب جديد!',
        body: data['customer_name'] ?? 'طلب جديد يحتاج إلى استلام',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'type': 'new_order',
          'order_id': data['order_id'] ?? '',
        },
        color: AppColors.coral,
        category: NotificationCategory.Call,
        wakeUpScreen: true,
        fullScreenIntent: true,
      ),
      actionButtons: [
        NotificationActionButton(key: 'ACCEPT', label: '✅ قبول الطلب', color: AppColors.mint),
        NotificationActionButton(key: 'DECLINE', label: '❌ رفض', actionType: ActionType.SilentAction),
      ],
    );
  }

  Future<void> _showBasicNotification({
    required String title,
    required String body,
    required String channelKey,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: channelKey,
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    // User tapped the notification body (not an action button) → open order detail.
    if (action.buttonKeyPressed.isEmpty) {
      final orderId = action.payload?['order_id'] ?? '';
      if (orderId.isNotEmpty) {
        _navigateFromData({'order_id': orderId});
      }
      return;
    }

    // Handle inline action buttons on adjustment notifications.
    final type        = action.payload?['type'] ?? '';
    final orderId     = action.payload?['order_id'] ?? '';
    final adjustmentId = action.payload?['adjustment_id'] ?? '';

    if (['price_change', 'substitute', 'item_added', 'quantity_change'].contains(type)) {
      final adjIdInt = int.tryParse(adjustmentId);
      if (adjIdInt != null) {
        final approved = action.buttonKeyPressed == 'APPROVE';
        ApiService().approveAdjustment(adjIdInt, approved).catchError((_) {});
      }
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _onDriverActionReceived(ReceivedAction action) async {
    // Handle driver app notification actions
    final type = action.payload?['type'];
    if (type == 'new_order' && action.buttonKeyPressed == 'ACCEPT') {
      // Trigger order acceptance
    }
  }

  void _onTokenRefresh(String token) {
    // Send FCM token to backend so the server can push notifications to this device.
    // If the user isn't logged in yet the request will fail silently (no token = 401).
    ApiService().updateFcmToken(token).catchError((_) {});
  }

  bool _permissionAsked = false;

  /// Automatic self-heal layer. Call on app launch AND every app-resume.
  /// Silently (no visible test push):
  ///   1. re-requests notification permission once per session if revoked,
  ///   2. (re)fetches the FCM token with a retry,
  ///   3. re-syncs the token to the backend so it always has a live token.
  /// Fixes the common "device stops getting notifications" causes — missing
  /// permission, a null/rotated token, or a token the backend cleared after a
  /// delivery failure — without any user action.
  Future<void> ensureHealthy() async {
    try {
      final settings = await _fcm.getNotificationSettings();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted && !_permissionAsked) {
        _permissionAsked = true;
        await _fcm.requestPermission(alert: true, badge: true, sound: true);
      }
      var token = await _fcm.getToken();
      if (token == null) {
        await Future.delayed(const Duration(seconds: 2));
        token = await _fcm.getToken();
      }
      if (token != null) {
        await ApiService().updateFcmToken(token).catchError((_) {});
      }
    } catch (_) {}
  }

  Future<String?> get fcmToken => _fcm.getToken();
}
