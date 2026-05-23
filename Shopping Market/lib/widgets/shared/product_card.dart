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
    return GestureDetector(
      onTap: () => context.push('/product/${p.id}'),
      child: Opacity(
        opacity: outOfStock ? 0.6 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: AppColors.midnight.withOpacity(0.05), blurRadius: 12, offset: const Offset(0,4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Container(width: double.infinity, color: AppColors.ice,
                  child: p.mainImageUrl.isNotEmpty
                    ? Image.network(
                    p.mainImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.shopping_bag_outlined,
                            color: AppColors.sky, size: 36)),
                  )
                    : const Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.sky, size: 36)),
                ),
              ),
              if (p.isOnSale && !outOfStock) Positioned(top: 8, left: 8,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.watermelon, borderRadius: BorderRadius.circular(100)),
                  child: Text('-${p.discountPercentage.toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
              if (outOfStock) Positioned.fill(child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Container(color: Colors.black38, child: Center(
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(100)),
                    child: const Text('نفذت الكمية', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))))),
              ),
              )])),
            Expanded(flex: 4, child: Padding(padding: const EdgeInsets.all(10), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nameAr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Cairo', color: AppColors.textMain), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(p.sellUnit, style: const TextStyle(fontSize: 10, color: AppColors.sky, fontFamily: 'Cairo')),
                const Spacer(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (p.isOnSale) Text('${p.originalPrice.toStringAsFixed(1)}', style: const TextStyle(fontSize: 9, color: Colors.grey, decoration: TextDecoration.lineThrough, fontFamily: 'Cairo')),
                    Text('${p.currentPrice.toStringAsFixed(1)} ج', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.sapphire, fontFamily: 'Cairo')),
                  ]),
                  if (!outOfStock)
                    GestureDetector(
                      onTap: () => onAddToCart?.call(p),
                      child: Container(width: 28, height: 28,
                        decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.add, color: Colors.white, size: 18)),
                    ),
                ]),
              ],
            ))),
          ]),
        ),
      ),
    );
  }
}
