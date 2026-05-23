import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../auth/auth_controller.dart';
import 'preparer_home_screen.dart';
import 'driver_home_screen.dart';

/// Dispatches to the right home based on the agent's role.
class RoleGateScreen extends ConsumerWidget {
  const RoleGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(agentAuthControllerProvider);
    return session.when(
      loading: () => const _LoadingScaffold(),
      error: (e, _) => _ErrorScaffold(message: e.toString()),
      data: (s) {
        if (!s.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (s.isBlocked) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم إيقاف حسابك. تواصل مع الأدمن.'),
                backgroundColor: AppColors.errorRed,
              ));
            }
            context.go('/login');
          });
          return const _LoadingScaffold();
        }
        switch (s.role) {
          case AgentRole.preparer: return const PreparerHomeScreen();
          case AgentRole.driver:   return const DriverHomeScreen();
          case AgentRole.unknown:
            return _ErrorScaffold(message: 'دور غير معروف لهذا الحساب');
        }
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
      );
}

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, color: AppColors.errorRed, size: 64),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );
}
