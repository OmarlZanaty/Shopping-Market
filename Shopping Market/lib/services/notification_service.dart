import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'market_fresh_orders',
          channelName: 'Order Updates',
          channelDescription: 'Order status updates and delivery notifications',
          defaultColor: AppColors.sapphire,
          ledColor: AppColors.sapphire,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          // REMOVED: soundSource - uses default system sound
          enableVibration: true,
        ),
        NotificationChannel(
          channelKey: 'market_fresh_promotions',
          channelName: 'Promotions',
          channelDescription: 'Deals and offers',
          defaultColor: AppColors.coral,
          importance: NotificationImportance.Default,
          channelShowBadge: true,
        ),
      ],
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
    );

    final token = await _fcm.getToken();
    if (token != null) _onTokenRefresh(token);
    _fcm.onTokenRefresh.listen(_onTokenRefresh);
  }

  Future<void> initDriverNotifications() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'driver_new_orders',
          channelName: 'New Orders Alert',
          channelDescription: 'Loud alert for new delivery orders',
          defaultColor: AppColors.coral,
          ledColor: AppColors.coral,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          // REMOVED: soundSource - uses default system sound
          enableVibration: true,
          vibrationPattern: highVibrationPattern,
          criticalAlerts: true,
        ),
        NotificationChannel(
          channelKey: 'driver_updates',
          channelName: 'Order Updates',
          channelDescription: 'Customer approval responses',
          defaultColor: AppColors.sapphire,
          importance: NotificationImportance.High,
          playSound: true,
          // REMOVED: soundSource
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
        channelKey: 'market_fresh_orders',
      );
    } else if (['price_change', 'substitute', 'item_added', 'quantity_change'].contains(type)) {
      _showAdjustmentNotification(data);
    } else if (type == 'stock_available') {
      _showBasicNotification(
        title: '📦 المنتج متاح الآن!',
        body: data['body_ar'] ?? '',
        channelKey: 'market_fresh_promotions',
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
        channelKey: 'driver_updates',
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
        channelKey: 'market_fresh_orders',
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
        channelKey: 'driver_new_orders',
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
    // Handle notification action taps in customer app
    if (action.payload?['order_id'] != null) {
      // Navigate to order detail - handled via global navigator key
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
    // Store token and send to backend when user is logged in
    // Handled in AuthProvider.updateFcmToken
  }

  Future<String?> get fcmToken => _fcm.getToken();
}
