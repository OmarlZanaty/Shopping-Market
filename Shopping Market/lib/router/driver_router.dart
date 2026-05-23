import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/driver/home/driver_home_screen.dart';
import '../screens/driver/orders/driver_order_detail_screen.dart';

class DriverRouter {
  static GoRouter router(AuthProvider auth) => GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final isAuth = auth.status == AuthStatus.authenticated;
      final isUnauth = auth.status == AuthStatus.unauthenticated;
      final goingToAuth = state.matchedLocation.startsWith('/login') || state.matchedLocation == '/splash';
      if (isUnauth && !goingToAuth) return '/login';
      if (isAuth && goingToAuth && state.matchedLocation != '/splash') return '/driver-home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/driver-home', builder: (_, __) => const DriverHomeScreen()),
      GoRoute(path: '/driver-order/:orderId', builder: (_, s) => DriverOrderDetailScreen(orderId: s.pathParameters['orderId']!)),
    ],
  );
}
