import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'core/constants/app_colors.dart';
import 'core/network/dio_client.dart';
import 'core/services/notification_service.dart';
import 'core/storage/offline_queue.dart';
import 'core/theme/app_theme.dart';
import 'features/orders/data/orders_providers.dart';
import 'features/orders/presentation/incoming_order_overlay.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Awesome Notifications shows the system notification automatically based on
  // the FCM payload + the channel config we register in NotificationService.
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

class _AgentAppState extends ConsumerState<AgentApp> {
  final GlobalKey<NavigatorState> _rootKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    AgentNotificationService.I.newOrderStream.listen(_onIncomingOrder);
  }

  Future<void> _onIncomingOrder(Map<String, dynamic> data) async {
    final nav = _rootKey.currentState;
    if (nav == null) return;
    final orderId = data['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

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
      // Open order detail.
      final ctx = _rootKey.currentContext;
      if (ctx != null) GoRouter.of(ctx).push('/order/$orderId');
    }
    // Refresh queues.
    // ignore: unused_result
    ref.refresh(ordersListProvider('new'));
  }

  @override
  Widget build(BuildContext context) {
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
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          // Wrap with a Navigator we control so we can push the overlay over
          // anything — even modals — without a BuildContext fight.
          child: Navigator(
            key: _rootKey,
            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child!),
          ),
        );
      },
    );
  }
}
