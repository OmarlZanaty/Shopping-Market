import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'utils/constants.dart' hide AppTheme;
import 'router/customer_router.dart';
import 'core/constants/app_colors.dart' as design;
import 'core/theme/app_theme.dart';

/// Must be annotated so the Dart AOT compiler keeps it reachable from native.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase. Guarded so a Firebase/config failure can never stop
  // the app from launching (would otherwise leave a blank screen).
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {
    // App still runs without push; features degrade gracefully.
  }

  // Initialize API service
  ApiService().init();

  // Load global app settings (delivery zone + loyalty economics). Non-blocking:
  // configs keep their defaults if the request fails.
  ApiService().getAppSettings().then((s) {
    DeliveryConfig.applySettings(s);
    LoyaltyConfig.applySettings(s);
  }).catchError((_) {});

  // Initialize notifications — fire-and-forget. On iOS, FirebaseMessaging
  // .getToken() can hang or throw until an APNS token is available; awaiting it
  // here previously blocked runApp() and produced a blank launch screen on some
  // devices (App Store review rejection 2.1). Never block startup on it.
  NotificationService().init().catchError((_) {});

  // Lock orientation. Guarded — must never prevent runApp().
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  // Status bar style — matches spec backgroundPrimary.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: design.AppColors.backgroundPrimary,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: design.AppColors.backgroundPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const MarketFreshCustomerApp());
}

// ── App root ──────────────────────────────────────────────────────────────────
// StatefulWidget so we create AuthProvider + GoRouter exactly ONCE.
// A Consumer<AuthProvider> around MaterialApp.router would recreate the
// entire router on every notifyListeners() call, resetting the nav stack and
// causing the splash screen to loop forever.
// GoRouter's own refreshListenable already handles auth-driven redirects.
class MarketFreshCustomerApp extends StatefulWidget {
  const MarketFreshCustomerApp({super.key});

  @override
  State<MarketFreshCustomerApp> createState() => _MarketFreshCustomerAppState();
}

class _MarketFreshCustomerAppState extends State<MarketFreshCustomerApp>
    with WidgetsBindingObserver {
  late final AuthProvider _auth;
  late final GoRouter     _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth   = AuthProvider()..init();
    _router = CustomerRouter.router(_auth);
    // Automatic notification self-heal on launch.
    NotificationService().ensureHealthy();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-verify + re-sync the push token every time the app returns to the
    // foreground, so a device can't silently fall out of notifications.
    if (state == AppLifecycleState.resumed) {
      NotificationService().ensureHealthy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Use .value so Provider hands out the already-created instance.
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider(create: (_) => CartProvider()..load()),
      ],
      child: MaterialApp.router(
        title: 'Shopping Market',
        theme: AppTheme.buildTheme(fontFamily: 'Cairo'),
        routerConfig: _router,          // stable — never recreated
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
            child: child!,
          );
        },
      ),
    );
  }
}
