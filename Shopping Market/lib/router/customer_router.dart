import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/biometric_setup_screen.dart';
import '../features/auth/presentation/onboarding_screen.dart';
import '../features/auth/presentation/phone_login_screen.dart';
import '../features/auth/presentation/otp_screen.dart';

import '../screens/customer/home/home_screen.dart';
import '../screens/customer/product/product_detail_screen.dart';
import '../screens/customer/cart/cart_screen.dart';
import '../screens/customer/orders/orders_screen.dart';
import '../screens/customer/orders/order_detail_screen.dart';
import '../screens/customer/orders/order_tracking_screen.dart';
import '../screens/customer/profile/profile_screen.dart';
import '../screens/customer/profile/addresses_screen.dart';
import '../screens/customer/profile/points_screen.dart';
import '../screens/shared/main_scaffold.dart';

class CustomerRouter {
  /// Global key so NotificationService can navigate without a BuildContext.
  static final navigatorKey = GlobalKey<NavigatorState>();

  // Public routes that don't require authentication
  static const _publicPaths = {
    '/splash', '/onboarding', '/login', '/login-password',
    '/register', '/otp', '/biometric-setup', '/profile-complete',
  };

  // Routes a guest (browse-without-login) user may access.
  // Everything else requires a real account.
  static bool _guestAllowed(String path) =>
      path == '/home' || path.startsWith('/product');

  static GoRouter router(AuthProvider auth) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;

      // ① Splash always handles its own navigation — never redirect from here.
      if (path == '/splash') return null;

      // ② If auth is still initialising stay put (avoid premature redirects).
      if (auth.status == AuthStatus.unknown) return null;

      // ③ Authenticated user trying to reach login/register → home.
      if (auth.isAuthenticated && (path == '/login' || path == '/register')) {
        return '/home';
      }

      // ④ Guest user: allow browsing home + product pages; anything else
      //    (cart, orders, profile) requires a real login.
      if (auth.isGuest) {
        if (_publicPaths.contains(path) || _guestAllowed(path)) return null;
        return '/login';
      }

      // ⑤ Unauthenticated user on a protected route → login.
      if (!auth.isAuthenticated && !_publicPaths.contains(path)) {
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash',      builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding',  builder: (_, __) => const OnboardingScreen()),
      // Phone + OTP (spec). The old password login screen is kept as a fallback.
      GoRoute(path: '/login',       builder: (_, __) => const PhoneLoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) {
          final extra = (state.extra ?? const {}) as Map;
          return OtpScreen(
            phone: extra['phone'] as String? ?? '',
            verificationId: extra['verificationId'] as String? ?? '',
            resendToken: extra['resendToken'] as int?,
          );
        },
      ),
      // Legacy password login kept under /login-password for staff or fallback.
      GoRoute(path: '/login-password', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',       builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/biometric-setup',builder: (_, __) => const BiometricSetupScreen()),
      // Stub so the new-user-after-OTP flow doesn't 404 — points back to home for now.
      GoRoute(path: '/profile-complete', builder: (_, __) => const HomeScreen()),

      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/product/:id',
            builder: (_, state) => ProductDetailScreen(
                productId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
          GoRoute(
            path: '/orders',
            builder: (_, __) => const OrdersScreen(),
            routes: [
              GoRoute(
                path: ':orderId',
                builder: (_, state) => OrderDetailScreen(
                    orderId: state.pathParameters['orderId']!),
              ),
              GoRoute(
                path: ':orderId/track',
                builder: (_, state) => OrderTrackingScreen(
                    orderId: state.pathParameters['orderId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
            routes: [
              GoRoute(path: 'addresses', builder: (_, __) => const AddressesScreen()),
              GoRoute(path: 'points',    builder: (_, __) => const PointsScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
