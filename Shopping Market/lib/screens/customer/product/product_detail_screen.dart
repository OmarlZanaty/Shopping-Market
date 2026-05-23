import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../models/models.dart';
import '../../../providers/cart_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});
  @override State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _api = ApiService();
  ProductModel? _product;
  bool _loading = true;
  double _quantity = 1;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final p = await _api.getProduct(widget.productId);
      if (mounted) setState(() { _product = p; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    if (_product == null) return const Scaffold(body: Center(child: Text('المنتج غير موجود')));
    final p = _product!;
    final outOfStock = p.isOutOfStock || !p.isAvailable;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(expandedHeight: 280, pinned: true, backgroundColor: AppColors.seafoam,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(children: [
              if (p.mainImageUrl.isNotEmpty)
                CachedNetworkImage(imageUrl: p.mainImageUrl, width: double.infinity, height: double.infinity, fit: BoxFit.cover)
              else
                Container(color: AppColors.ice, child: const Center(child: Icon(Icons.shopping_bag_outlined, color: AppColors.sky, size: 80))),
              if (p.isOnSale) Positioned(bottom: 16, left: 16,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.watermelon, borderRadius: BorderRadius.circular(100)),
                  child: Text('-${p.discountPercentage.toInt()}% خصم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
              if (outOfStock) Positioned.fill(child: Container(color: Colors.black38,
                child: const Center(child: Text('نفذت الكمية', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))))),
            ]),
          )),
        SliverToBoxAdapter(child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nameAr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: AppColors.midnight)),
            const SizedBox(height: 6),
            Row(children: [
              if (p.isOnSale) Text('${p.originalPrice} ج  ', style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontFamily: 'Cairo')),
              Text('${p.currentPrice} ج', style: AppText.priceLarge),
              if (p.savings > 0) ...[
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.seafoam, borderRadius: BorderRadius.circular(100)),
                  child: Text('وفر ${p.savings.toStringAsFixed(1)} ج', style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700, fontSize: 11, fontFamily: 'Cairo'))),
              ],
            ]),
            const SizedBox(height: 14),
            // Quantity selector
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('الكمية', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                Row(children: [
                  _qBtn(Icons.remove, () => setState(() => _quantity = (_quantity - 1).clamp(1, 100))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_quantity.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                  _qBtn(Icons.add, () => setState(() => _quantity++)),
                ]),
              ])),
            const SizedBox(height: 16),
            // Description
            if (p.descriptionAr.isNotEmpty) ...[
              const Text('الوصف', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 15)),
              const SizedBox(height: 6),
              Text(p.descriptionAr, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, height: 1.6)),
              const SizedBox(height: 16),
            ],
            // Alternatives
            if (p.alternatives.isNotEmpty) ...[
              const Text('منتجات بديلة', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 15)),
              const SizedBox(height: 8),
              SizedBox(height: 80, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: p.alternatives.length,
                itemBuilder: (_, i) {
                  final alt = p.alternatives[i];
                  return Container(margin: const EdgeInsets.only(right: 8), width: 70,
                    decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(alt.nameAr.length > 8 ? '${alt.nameAr.substring(0,8)}..' : alt.nameAr, style: const TextStyle(fontSize: 10, fontFamily: 'Cairo'), textAlign: TextAlign.center),
                      Text('${alt.currentPrice} ج', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.sapphire, fontFamily: 'Cairo')),
                    ]));
                })),
              const SizedBox(height: 16),
            ],
            // Waitlist button
            if (outOfStock)
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.sapphire, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                label: const Text('أبلغني عند التوفر', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                onPressed: () async { await _api.toggleWaitlist(p.id); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سيتم إخطارك عند التوفر ✅', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.mint)); })),
          ]),
        )),
      ]),
      bottomNavigationBar: !outOfStock ? Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0,-4))]),
        child: SizedBox(height: 52, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: () {
            context.read<CartProvider>().addItem(_product!, qty: _quantity);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('أُضيف ${_product!.nameAr} للسلة ✅', style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.mint, behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
          },
          child: Text('إضافة للسلة · ${(p.currentPrice * _quantity).toStringAsFixed(1)} ج', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
        ))) : null,
    );
  }

  Widget _qBtn(IconData icon, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: Colors.white, size: 18)));
}
