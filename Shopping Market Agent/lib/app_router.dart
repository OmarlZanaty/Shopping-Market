import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/role_gate.dart';
import 'features/inventory/scanner_inventory_screen.dart';
import 'features/orders/presentation/delivery_confirm_screen.dart';
import 'features/orders/presentation/order_detail_screen.dart';
import 'features/orders/presentation/picking_screen.dart';
import 'features/scanner/barcode_scanner_screen.dart';
import 'features/scanner/camera_proof_screen.dart';

final agentRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(agentAuthControllerProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final s = auth.valueOrNull;
      final loggedIn = s?.isAuthenticated ?? false;
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const RoleGateScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/order/:id',
        builder: (_, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/picking/:id',
        builder: (_, state) => PickingScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/delivery/:id',
        builder: (_, state) => DeliveryConfirmScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/scanner',           builder: (_, __) => const BarcodeScannerScreen()),
      GoRoute(path: '/camera-proof',      builder: (_, __) => const CameraProofScreen()),
      GoRoute(path: '/scanner-inventory', builder: (_, __) => const ScannerInventoryScreen()),
    ],
  );
});
