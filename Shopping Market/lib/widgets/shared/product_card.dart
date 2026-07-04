import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import 'weight_picker.dart';

// ── Const-safe shadows / colours ─────────────────────────────────────────────
// Using explicit hex codes so these can be compile-time constants and are
// never reallocated on build().
const _kCardShadow = BoxShadow(
  color: Color(0x121A1A2E), // AppColors.midnight @ 7 %
  blurRadius: 16,
  offset: Offset(0, 4),
);
const _kAddBtnShadow = BoxShadow(
  color: Color(0x59FF8C00), // AppColors.coral @ 35 %
  blurRadius: 8,
  offset: Offset(0, 3),
);
const _kFavShadow = BoxShadow(
  color: Color(0x14000000), // black @ 8 %
  blurRadius: 6,
);

// ══════════════════════════════════════════════════════════════════════════════
// ProductCard — top-level widget stays completely static.
// Only the two Selector-wrapped sub-widgets rebuild on cart changes,
// and only when the quantity for *this specific product* changes.
// ══════════════════════════════════════════════════════════════════════════════
class ProductCard extends StatelessWidget {
  final ProductModel product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final p           = product;
    // The list-grid serializer does NOT send `is_out_of_stock`, so we MUST
    // also check `quantity_in_stock <= 0` directly — otherwise a product with
    // zero stock looks normal on the home grid and the customer can still
    // add it to the cart, only to fail at checkout.
    final outOfStock  = p.isOutOfStock || !p.isAvailable || p.quantityInStock <= 0;
    final hasImage    = p.mainImageUrl.isNotEmpty;
    final hasDiscount = p.isOnSale && p.discountPercentage > 0;

    // RepaintBoundary isolates this card's repaints from its neighbours.
    return RepaintBoundary(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(20)),
          boxShadow: [_kCardShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image — Selector redraws only when inCart bool flips
            Expanded(
              flex: 55,
              child: _ImageSection(
                product: p,
                hasImage: hasImage,
                hasDiscount: hasDiscount,
                outOfStock: outOfStock,
              ),
            ),

            // Info — price text is fully static; only the qty button uses Selector
            Expanded(
              flex: 45,
              child: _InfoSection(
                product: p,
                hasDiscount: hasDiscount,
                outOfStock: outOfStock,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ImageSection
// Uses Selector<CartProvider, bool> — only rebuilds when inCart flips
// (i.e. qty goes 0 → 1 or 1 → 0 for THIS product).
// ══════════════════════════════════════════════════════════════════════════════
class _ImageSection extends StatelessWidget {
  final ProductModel product;
  final bool hasImage, hasDiscount, outOfStock;

  const _ImageSection({
    required this.product,
    required this.hasImage,
    required this.hasDiscount,
    required this.outOfStock,
  });

  @override
  Widget build(BuildContext context) {
    // Tapping the product image opens the full product screen.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/product/${product.id}'),
      child: Selector<CartProvider, bool>(
        // Only the boolean matters here — no rebuild when qty goes 2→3.
        selector: (_, cart) => cart.getQuantity(product.id) > 0,
        builder: (_, inCart, staticContent) {
          return Stack(children: [
            staticContent!, // static: image + gradient + badges — never rebuilt
            if (inCart) const Positioned(bottom: 8, left: 8, child: _InCartBadge()),
          ]);
        },
        // child is built once and passed as-is to builder — zero cost on rebuilds
        child: _buildStaticContent(),
      ),
    );
  }

  Widget _buildStaticContent() {
    final p = product;
    return Stack(children: [
      // ── Product image ────────────────────────────────────────────────────
      ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SizedBox(
          width: double.infinity,
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: p.mainImageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _ImagePlaceholder(),
                  errorWidget: (_, __, ___) => const _ImagePlaceholder(),
                )
              : const _ImagePlaceholder(),
        ),
      ),

      // ── Bottom gradient overlay ──────────────────────────────────────────
      const Positioned(
        bottom: 0, left: 0, right: 0,
        child: SizedBox(
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x40000000), Colors.transparent],
              ),
            ),
          ),
        ),
      ),

      // ── Discount badge ───────────────────────────────────────────────────
      if (hasDiscount && !outOfStock)
        Positioned(
          top: 8, right: 8,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: AppColors.coralGradient,
              borderRadius: BorderRadius.all(Radius.circular(100)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                '-${p.discountPercentage.toInt()}%',
                style: const TextStyle(
                  color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w800, fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ),

      // ── Out-of-stock overlay ─────────────────────────────────────────────
      if (outOfStock)
        Positioned.fill(
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: const ColoredBox(
              color: Color(0x73000000), // black 45 %
              child: Center(child: _OutOfStockLabel()),
            ),
          ),
        ),

      // ── Favourite button ─────────────────────────────────────────────────
      const Positioned(
        top: 8, left: 8,
        child: _FavButton(),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _InfoSection
// Price text is static. Only the quantity button uses Selector so it rebuilds
// only when the quantity for this product changes.
// ══════════════════════════════════════════════════════════════════════════════
class _InfoSection extends StatelessWidget {
  final ProductModel product;
  final bool hasDiscount, outOfStock;

  const _InfoSection({
    required this.product,
    required this.hasDiscount,
    required this.outOfStock,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name — static
          Text(
            p.nameAr,
            style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              fontFamily: 'Cairo', color: AppColors.textMain, height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),

          // Unit — static
          Text(
            _unitLabel(p.sellUnit),
            style: const TextStyle(
                fontSize: 9, color: AppColors.textMuted, fontFamily: 'Cairo'),
          ),

          const Spacer(),

          // Price + qty row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Price column — fully static, never rebuilt from cart
              Expanded(child: _PriceColumn(product: p, hasDiscount: hasDiscount)),

              // Qty control — Selector keyed to THIS product's quantity
              if (!outOfStock)
                Selector<CartProvider, double>(
                  selector: (_, cart) => cart.getQuantity(p.id),
                  builder: (ctx, qty, __) {
                    // Weight-based: tapping opens a grams picker instead of a
                    // piece counter. The stored quantity is in kilograms.
                    if (p.isWeighed) {
                      return qty == 0
                          ? _AddButton(onTap: () => _pickWeight(ctx, qty))
                          : _WeightChip(
                              kg: qty,
                              onTap: () => _pickWeight(ctx, qty),
                            );
                    }
                    return qty == 0
                        ? _AddButton(
                            onTap: () => ctx.read<CartProvider>().addItem(p))
                        : _QtyControl(
                            qty: qty,
                            onAdd: () => ctx.read<CartProvider>().addItem(p),
                            onRemove: () =>
                                ctx.read<CartProvider>().decrementItem(p.id),
                          );
                  },
                )
              else
                // Out-of-stock: gray disabled button + small notify bell
                _OutOfStockButton(product: p),
            ],
          ),
        ],
      ),
    );
  }

  // Opens the grams picker; writes the chosen weight (kg) into the cart.
  Future<void> _pickWeight(BuildContext ctx, double currentKg) async {
    final cart = ctx.read<CartProvider>();
    final kg = await showWeightPicker(
      ctx, product,
      initialKg: currentKg > 0 ? currentKg : 0.5,
    );
    if (kg == null) return;
    if (currentKg > 0) {
      cart.updateQuantity(product.id, kg);
    } else {
      cart.addItem(product, qty: kg);
    }
  }

  static String _unitLabel(String unit) {
    switch (unit) {
      case 'kg':     return 'كيلوجرام';
      case 'gram':   return 'جرام';
      case 'liter':  return 'لتر';
      case 'piece':  return 'قطعة';
      case 'pack':   return 'عبوة';
      case 'box':    return 'علبة';
      case 'carton': return 'كرتون';
      default:       return unit;
    }
  }
}

// ── Price column (static — never rebuilt by cart) ─────────────────────────────
class _PriceColumn extends StatelessWidget {
  final ProductModel product;
  final bool hasDiscount;
  const _PriceColumn({required this.product, required this.hasDiscount});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDiscount)
          Text(
            '${p.originalPrice.toStringAsFixed(1)} ج',
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textMuted,
              decoration: TextDecoration.lineThrough,
              fontFamily: 'Cairo',
            ),
          ),
        Text(
          p.currentPrice > 0
              ? '${p.currentPrice.toStringAsFixed(2)} ج'
              : 'السعر عند الطلب',
          style: TextStyle(
            fontSize: p.currentPrice > 0 ? 14 : 10,
            fontWeight: FontWeight.w800,
            color: p.currentPrice > 0 ? AppColors.midnight : AppColors.textMuted,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}

// ── Static small widgets (const constructors = zero allocation) ───────────────

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.ice,
        child: Center(
          child: Icon(Icons.shopping_basket_outlined,
              color: Color(0x7F7BA4D0), size: 32), // sky @ 50%
        ),
      );
}

class _InCartBadge extends StatelessWidget {
  const _InCartBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: const BoxDecoration(
          color: Color(0xBF1A1A2E), // midnight @ 75 %
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        child: const Text(
          'في السلة',
          style: TextStyle(
            color: Colors.white, fontSize: 8,
            fontWeight: FontWeight.w700, fontFamily: 'Cairo',
          ),
        ),
      );
}

class _OutOfStockLabel extends StatelessWidget {
  const _OutOfStockLabel();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: const BoxDecoration(
          color: Color(0xA6000000), // black 65 %
          borderRadius: BorderRadius.all(Radius.circular(100)),
        ),
        child: const Text(
          'نفذت الكمية',
          style: TextStyle(
            color: Colors.white, fontSize: 10,
            fontWeight: FontWeight.w700, fontFamily: 'Cairo',
          ),
        ),
      );
}

class _FavButton extends StatelessWidget {
  const _FavButton();
  @override
  Widget build(BuildContext context) => Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(
          color: Color(0xE6FFFFFF), // white 90 %
          shape: BoxShape.circle,
          boxShadow: [_kFavShadow],
        ),
        child: const Icon(Icons.favorite_border_rounded,
            size: 14, color: AppColors.textSub),
      );
}

// ── Add button ────────────────────────────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(
            gradient: AppColors.coralGradient,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            boxShadow: [_kAddBtnShadow],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
        ),
      );
}

// ── Quantity stepper (−  N  +) ────────────────────────────────────────────────
class _QtyControl extends StatelessWidget {
  final double qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _QtyControl({
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove_rounded, onRemove),
          SizedBox(
            width: 26,
            child: Text(
              qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800,
                fontFamily: 'Cairo', color: AppColors.midnight,
              ),
            ),
          ),
          _btn(Icons.add_rounded, onAdd),
        ],
      );

  Widget _btn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            gradient: AppColors.coralGradient,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );
}

// ── Weight chip (weight-based product already in cart) ────────────────────────
// Shows the chosen weight (e.g. "500 جم"); tapping reopens the grams picker.
class _WeightChip extends StatelessWidget {
  final double kg;
  final VoidCallback onTap;
  const _WeightChip({required this.kg, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            gradient: AppColors.coralGradient,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            boxShadow: [_kAddBtnShadow],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.scale_rounded, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              Formatters.weightLabel(kg),
              style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w800, fontFamily: 'Cairo',
              ),
            ),
          ]),
        ),
      );
}

// ── Out-of-stock pill (replaces the "+" button when stock = 0) ────────────────
// A clearly disabled gray button that says "غير متوفر". It does NOT add to
// cart on tap — instead it pops a sheet offering to subscribe to a notify-
// when-back-in-stock waitlist. This means the user can never accidentally
// add a 0-stock item to their cart (the backend would reject it with
// "Insufficient stock" anyway, but we want to block it at the UI level).
class _OutOfStockButton extends StatelessWidget {
  final ProductModel product;
  const _OutOfStockButton({required this.product});

  void _openWaitlistSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined,
              size: 44, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(product.nameAr,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.midnight,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                  fontSize: 15)),
          const SizedBox(height: 8),
          const Text('هذا المنتج غير متوفر حالياً',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontFamily: 'Cairo',
                  fontSize: 13)),
          const SizedBox(height: 18),
          // Keep the existing waitlist subscribe widget — full width.
          SizedBox(width: double.infinity,
              child: _WaitlistButton(product: product, full: true)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openWaitlistSheet(context),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),  // neutral gray
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD0D8)),
        ),
        child: const Center(
          child: Text('غير متوفر',
              style: TextStyle(
                color: Color(0xFF6B7280),   // medium gray text
                fontWeight: FontWeight.w800,
                fontSize: 11,
                fontFamily: 'Cairo',
              )),
        ),
      ),
    );
  }
}

// ── Waitlist bell button (shown on out-of-stock card) ─────────────────────────
// StatefulWidget so it can toggle subscribed/unsubscribed optimistically
// without forcing a full product-list reload.
class _WaitlistButton extends StatefulWidget {
  final ProductModel product;
  /// When true, renders a tall pill suitable for the bottom-sheet (full width
  /// with bigger text). When false (default), the compact 30-px chip used on
  /// the product card.
  final bool full;
  const _WaitlistButton({required this.product, this.full = false});
  @override
  State<_WaitlistButton> createState() => _WaitlistButtonState();
}

class _WaitlistButtonState extends State<_WaitlistButton> {
  late bool _subscribed;
  bool _loading = false;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _subscribed = widget.product.isOnWaitlist;
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    final wasSubscribed = _subscribed;
    try {
      if (wasSubscribed) {
        await _api.removeFromWaitlist(widget.product.id);
      } else {
        await _api.addToWaitlist(widget.product.id);
      }
      if (!mounted) return;
      setState(() {
        _subscribed = !wasSubscribed;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _subscribed
              ? 'سيتم إشعارك عند توفر المنتج ✅'
              : 'تم إلغاء الاشتراك من قائمة الانتظار',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        ),
        backgroundColor:
            _subscribed ? AppColors.mint : AppColors.textMuted,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.full;
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: full ? 48 : 30,
        padding: EdgeInsets.symmetric(horizontal: full ? 16 : 8),
        decoration: BoxDecoration(
          color: _subscribed
              ? const Color(0x26FFB800) // gold @ 15 %
              : AppColors.ice,
          borderRadius: BorderRadius.all(Radius.circular(full ? 14 : 10)),
          border: Border.all(
            color: _subscribed
                ? AppColors.gold
                : AppColors.border,
            width: full ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: _loading
              ? SizedBox(
                  width: full ? 18 : 12,
                  height: full ? 18 : 12,
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.gold),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _subscribed
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_outlined,
                    size: full ? 18 : 12,
                    color: _subscribed
                        ? AppColors.gold
                        : AppColors.textMuted,
                  ),
                  SizedBox(width: full ? 8 : 3),
                  Text(
                    _subscribed
                        ? (full ? 'مشترك — سيتم إشعارك عند التوفر' : 'مشترك')
                        : (full ? 'أبلغني عند توفر المنتج' : 'أبلغني'),
                    style: TextStyle(
                      fontSize: full ? 13 : 9,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      color: _subscribed
                          ? AppColors.gold
                          : AppColors.textMuted,
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}
