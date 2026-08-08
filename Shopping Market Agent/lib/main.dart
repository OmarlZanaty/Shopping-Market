import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_router.dart';
import 'core/constants/app_colors.dart';
import 'core/network/dio_client.dart';
import 'core/services/notification_service.dart';
import 'core/storage/offline_queue.dart';
import 'core/theme/app_theme.dart';
import 'features/orders/data/orders_providers.dart';
import 'features/orders/presentation/incoming_order_overlay.dart';

/// Runs in a separate isolate when the app is in the background or terminated.
/// Must re-initialise every plugin it uses from scratch.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // Re-register channels so AwesomeNotifications can create the local
  // notification in this isolate (channels are per-process, not persisted).
  // Shares AgentNotificationService.channels so the custom tone can't drift
  // between the foreground and background definitions.
  await AwesomeNotifications().initialize(
    null,
    AgentNotificationService.channels,
  );

  final type = message.data['type'] ?? '';
  final channelKey = AgentNotificationService.channelForType(type);

  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelKey: channelKey,
      title: message.notification?.title ??
          message.data['title_ar'] ??
          'إشعار جديد',
      body: message.notification?.body ?? message.data['body_ar'] ?? '',
      payload: Map<String, String?>.from(
        message.data.map((k, v) => MapEntry(k, v?.toString())),
      ),
      notificationLayout: NotificationLayout.Default,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);

  DioClient.I.init();
  await OfflineQueue.init();
  await AgentNotificationService.I.init();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.backgroundPrimary,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.backgroundPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: AgentApp()));
}

/// Root widget. Wires Router + RTL + listens for foreground new-order FCMs to
/// surface the IncomingOrderOverlay over whatever screen is currently visible.
class AgentApp extends ConsumerStatefulWidget {
  const AgentApp({super.key});
  @override
  ConsumerState<AgentApp> createState() => _AgentAppState();
}

class _AgentAppState extends ConsumerState<AgentApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AgentNotificationService.I.newOrderStream.listen(_onIncomingOrder);
    // Automatic notification self-heal on launch.
    AgentNotificationService.I.ensureHealthy();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-verify + re-sync the push token every time the app comes back to the
    // foreground, so a device can't silently fall out of notifications.
    if (state == AppLifecycleState.resumed) {
      AgentNotificationService.I.ensureHealthy();
    }
  }

  Future<void> _onIncomingOrder(Map<String, dynamic> data) async {
    final orderId = data['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    final router = ref.read(agentRouterProvider);
    final nav = router.routerDelegate.navigatorKey.currentState;
    if (nav == null) return;

    // Push the full-screen overlay on GoRouter's own navigator so it covers
    // the current screen and the GoRouter back button / context are intact.
    final result = await nav.push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingOrderOverlay(
          orderId: orderId,
          orderNumber: data['order_number']?.toString() ?? '#$orderId',
          itemCount: int.tryParse(data['item_count']?.toString() ?? '0') ?? 0,
          customerArea: data['customer_area']?.toString() ?? 'العميل',
          total: double.tryParse(data['total']?.toString() ?? '0') ?? 0,
        ),
      ),
    );

    if (result == 'accepted') {
      router.push('/order/$orderId');
    }
    // Refresh queues.
    // ignore: unused_result
    ref.refresh(ordersListProvider('new'));
  }

  @override
  Widget build(BuildContext context) {
    // Read (not watch) — router is stable, created once.
    final router = ref.watch(agentRouterProvider);
    return MaterialApp.router(
      title: 'Shopping Market Agent',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
  }
}
