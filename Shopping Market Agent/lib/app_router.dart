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

/// A [ChangeNotifier] that bridges Riverpod auth state → GoRouter's
/// [refreshListenable]. GoRouter calls [refresh] and re-runs the redirect
/// whenever this notifier fires — without recreating the router.
class _AuthListenable extends ChangeNotifier {
  AgentSession? _session;

  bool get loggedIn => _session?.isAuthenticated ?? false;

  void update(AsyncValue<AgentSession> auth) {
    final next = auth.valueOrNull;
    if (next != _session) {
      _session = next;
      notifyListeners();
    }
  }
}

/// The router is created ONCE and lives for the duration of the provider.
/// Auth changes are fed through [_AuthListenable] so GoRouter re-evaluates
/// the redirect without rebuilding the entire router tree.
final agentRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthListenable();

  // Mirror auth state into the notifier.
  ref.listen<AsyncValue<AgentSession>>(
    agentAuthControllerProvider,
    (_, next) => notifier.update(next),
  );
  // Seed initial state.
  notifier.update(ref.read(agentAuthControllerProvider));

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = notifier.loggedIn;
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/',      builder: (_, __) => const RoleGateScreen()),
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

  ref.onDispose(() {
    router.dispose();
    notifier.dispose();
  });

  return router;
});
