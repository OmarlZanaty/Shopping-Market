import 'package:flutter/material.dart';

import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';
import '../../../widgets/shared/product_card.dart';

/// Shows the products for a single category (or a promo filter).
///
/// Opened from the home screen when a category card is tapped. Fetches its own
/// products with pagination so the home screen no longer needs a product grid.
class CategoryProductsScreen extends StatefulWidget {
  /// Title shown in the app bar (e.g. the category name).
  final String title;

  /// Category id to filter by. `null`/0 means "all products".
  final int? categoryId;

  // Optional promo filters (used when opened from a promo chip).
  final bool? featured;
  final bool? hasDiscount;
  final String? search;

  const CategoryProductsScreen({
    super.key,
    required this.title,
    this.categoryId,
    this.featured,
    this.hasDiscount,
    this.search,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final _api = ApiService();
  final _scrollCtrl = ScrollController();

  final List<ProductModel> _products = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (_hasMore && !_loading && !_loadingMore) _loadMore();
    }
  }

  Future<Map<String, dynamic>> _fetch(int page) => _api.getProducts(
        page: page,
        category: (widget.categoryId == null || widget.categoryId == 0)
            ? null
            : widget.categoryId,
        featured: widget.featured,
        hasDiscount: widget.hasDiscount,
        search: widget.search,
      );

  Future<void> _load({bool reset = false}) async {
    setState(() => _loading = true);
    try {
      _page = 1;
      final data = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll((data['results'] as List? ?? [])
              .map((p) => ProductModel.fromJson(p)));
        _hasMore = data['next'] != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final data = await _fetch(_page);
      if (!mounted) return;
      setState(() {
        _products.addAll((data['results'] as List? ?? [])
            .map((p) => ProductModel.fromJson(p)));
        _hasMore = data['next'] != null;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        color: AppColors.coral,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.midnight,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.coral, strokeWidth: 2.5),
                ),
              )
            else if (_products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                            color: AppColors.ice, shape: BoxShape.circle),
                        child: const Icon(Icons.inventory_2_outlined,
                            color: AppColors.coral, size: 36),
                      ),
                      const SizedBox(height: 16),
                      const Text('لا توجد منتجات',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo',
                            color: AppColors.textMain,
                          )),
                      const SizedBox(height: 6),
                      const Text('لا توجد منتجات في هذا القسم حالياً',
                          style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              color: AppColors.textMuted)),
                    ],
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => ProductCard(product: _products[i]),
                    childCount: _products.length,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _loadingMore
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.coral, strokeWidth: 2.5),
                        ),
                      )
                    : const SizedBox(height: 32),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
