import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;
  final void Function(ProductModel)? onAddToCart;

  const ProductCard({super.key, required this.product, this.onAddToCart});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final outOfStock = p.isOutOfStock || !p.isAvailable;
    final hasImage   = p.mainImageUrl.isNotEmpty;
    final hasDiscount = p.isOnSale && p.discountPercentage > 0;

    return GestureDetector(
      onTap: () => context.push('/product/${p.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.midnight.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image section ──────────────────────────────────────────────
            Expanded(
              flex: 55,
              child: Stack(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: SizedBox(
                      width: double.infinity,
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: p.mainImageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _imagePlaceholder(),
                              errorWidget: (_, __, ___) => _imagePlaceholder(),
                            )
                          : _imagePlaceholder(),
                    ),
                  ),

                  // Gradient overlay at bottom of image
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 40,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0x40000000), Colors.transparent],
                        ),
                      ),
                    ),
                  ),

                  // Discount badge (top-right)
                  if (hasDiscount && !outOfStock)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppColors.coralGradient,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '-${p.discountPercentage.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),

                  // Out of stock overlay
                  if (outOfStock)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: Container(
                          color: Colors.black.withOpacity(0.45),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                'نفذت الكمية',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Favourite / wishlist placeholder (top-left)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.favorite_border_rounded,
                          size: 14, color: AppColors.textSub),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content section ────────────────────────────────────────────
            Expanded(
              flex: 45,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      p.nameAr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo',
                        color: AppColors.textMain,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 3),

                    // Unit label
                    Text(
                      _unitLabel(p.sellUnit),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                        fontFamily: 'Cairo',
                      ),
                    ),

                    const Spacer(),

                    // Price row + add button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Strikethrough original price
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
                              // Current price
                              Text(
                                p.currentPrice > 0
                                    ? '${p.currentPrice.toStringAsFixed(2)} ج'
                                    : 'السعر عند الطلب',
                                style: TextStyle(
                                  fontSize: p.currentPrice > 0 ? 14 : 10,
                                  fontWeight: FontWeight.w800,
                                  color: p.currentPrice > 0
                                      ? AppColors.midnight
                                      : AppColors.textMuted,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Add to cart button
                        if (!outOfStock)
                          GestureDetector(
                            onTap: () => onAddToCart?.call(p),
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                gradient: AppColors.coralGradient,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.coral.withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.ice,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_basket_outlined,
                color: AppColors.sky.withOpacity(0.5), size: 32),
          ],
        ),
      ),
    );
  }

  String _unitLabel(String unit) {
    switch (unit) {
      case 'kg':      return 'كيلوجرام';
      case 'gram':    return 'جرام';
      case 'liter':   return 'لتر';
      case 'piece':   return 'قطعة';
      case 'pack':    return 'عبوة';
      case 'box':     return 'علبة';
      case 'carton':  return 'كرتون';
      default:        return unit;
    }
  }
}
