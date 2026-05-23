import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'utils/constants.dart';
import 'router/driver_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  ApiService().init();
  await NotificationService().initDriverNotifications();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.midnight,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MarketFreshDriverApp());
}

class MarketFreshDriverApp extends StatelessWidget {
  const MarketFreshDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) => MaterialApp.router(
          title: 'Market Fresh - Driver',
          theme: AppTheme.theme.copyWith(
            // Driver app uses coral as primary for urgency
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.coral,
              primary: AppColors.coral,
              secondary: AppColors.sapphire,
              background: AppColors.background,
            ),
          ),
          routerConfig: DriverRouter.router(auth),
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
        ),
      ),
    );
  }
}
