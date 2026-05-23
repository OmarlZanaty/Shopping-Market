import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';  // ← Add this import
import '../../providers/cart_provider.dart';
import '../../utils/constants.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/cart')) return 1;
    if (loc.startsWith('/orders')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return 0; // home
  }

  void _onNavTap(BuildContext context, String path) {
    final auth = context.read<AuthProvider>();
    final isAuth = auth.status == AuthStatus.authenticated;
    final isProtected = path == '/cart' || path == '/orders' || path == '/profile';

    if (!isAuth && isProtected) {
      context.push('/login');  // ← Push login as overlay, don't redirect
      return;
    }

    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final idx = _selectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(
            color: AppColors.midnight.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )],
          border: const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(context, 0, idx, Icons.home_rounded,
                    Icons.home_outlined, 'الرئيسية', '/home'),
                _cartItem(context, idx, cart),
                _navItem(context, 2, idx, Icons.receipt_long_rounded,
                    Icons.receipt_long_outlined, 'طلباتي', '/orders'),
                _navItem(context, 3, idx, Icons.person_rounded,
                    Icons.person_outlined, 'حسابي', '/profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int itemIdx, int currentIdx,
      IconData active, IconData inactive, String label, String path) {
    final selected = currentIdx == itemIdx;
    return GestureDetector(
      onTap: () => _onNavTap(context, path),  // ← Use _onNavTap instead of context.go
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.coral.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(selected ? active : inactive,
              color: selected ? AppColors.coral : AppColors.textMuted,
              size: 24),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.coral : AppColors.textMuted,
                fontWeight:
                selected ? FontWeight.w700 : FontWeight.w400,
                fontFamily: 'Cairo',
              )),
        ]),
      ),
    );
  }

  Widget _cartItem(BuildContext context, int currentIdx, CartProvider cart) {
    final selected = currentIdx == 1;
    return GestureDetector(
      onTap: () => _onNavTap(context, '/cart'),  // ← Use _onNavTap
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
              colors: [AppColors.coral, Color(0xFFea6009)])
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_rounded,
                color: selected ? Colors.white : AppColors.textMuted,
                size: 24),
            const SizedBox(height: 3),
            Text('السلة',
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? Colors.white : AppColors.textMuted,
                  fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: 'Cairo',
                )),
          ]),
          if (cart.itemCount > 0)
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.watermelon,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${cart.itemCount}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}