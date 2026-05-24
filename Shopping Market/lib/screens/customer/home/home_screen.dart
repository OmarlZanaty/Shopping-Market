import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../services/api_service.dart';
import '../../../models/models.dart';
import '../../../utils/constants.dart';
import '../../../widgets/shared/product_card.dart';
import '../../../widgets/shared/search_bar_widget.dart';
import '../../../widgets/customer/banner_slider.dart';
import '../../../widgets/customer/category_row.dart';
import '../../../widgets/customer/points_banner.dart';
import '../../../widgets/shared/barcode_scanner_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _scrollController = ScrollController();

  String? _currentAddress;
  bool _locationLoading = false;

  List<BannerModel> _banners = [];
  List<CategoryModel> _categories = [];
  List<ProductModel> _products = [];
  List<ProductModel> _featuredProducts = [];
  Map<String, dynamic> _appSettings = {};
  int _selectedCategory = 0;
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _detectLocation();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_loading) _loadMoreProducts();
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _locationLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          setState(() { _currentAddress = 'التوصيل إلى موقعك'; _locationLoading = false; });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      // Reverse geocode via OpenStreetMap (free, no API key)
      final res = await Dio().get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': position.latitude,
          'lon': position.longitude,
          'format': 'json',
          'accept-language': 'ar',
        },
        options: Options(headers: {'User-Agent': 'MarketFresh/1.0'}),
      );

      final addr = res.data['address'] as Map<String, dynamic>?;
      final city = addr?['city'] ?? addr?['town'] ?? addr?['state'] ?? '';
      final district = addr?['suburb'] ?? addr?['district'] ?? addr?['neighbourhood'] ?? '';

      if (mounted) {
        setState(() {
          _currentAddress = (city.isNotEmpty && district.isNotEmpty)
              ? 'التوصيل إلى $city - $district'
              : (city.isNotEmpty ? 'التوصيل إلى $city' : 'التوصيل إلى موقعك');
          _locationLoading = false;
        });
      }
    } catch (e) {
      print('Location error: $e');
      if (mounted) setState(() { _currentAddress = 'التوصيل إلى موقعك'; _locationLoading = false; });
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      print('🚀 Loading data from ${AppConfig.baseUrl}');
      final results = await Future.wait([
        _api.getBanners(position: 'home_main'),
        _api.getCategories(),
        _api.getProducts(page: 1),
        _api.getProducts(featured: true),
        _api.getAppSettings(),
      ]);
      print('✅ Banners: ${(results[0] as List).length}');
      print('✅ Categories: ${(results[1] as List).length}');
      final productsData = results[2] as Map<String, dynamic>;
      print('✅ Products count: ${productsData['count']}');
      print('✅ Products results: ${(productsData['results'] as List?)?.length}');

      if (mounted) {
        setState(() {
          _banners = results[0] as List<BannerModel>;
          _categories = results[1] as List<CategoryModel>;
          _products = (productsData['results'] as List? ?? [])
              .map((p) => ProductModel.fromJson(p)).toList();
          _hasMore = productsData['next'] != null;
          final featuredData = results[3] as Map<String, dynamic>;
          _featuredProducts = (featuredData['results'] as List? ?? [])
              .map((p) => ProductModel.fromJson(p)).toList();
          _appSettings = results[4] as Map<String, dynamic>;
          _loading = false;
        });
        print('📦 Products in state: ${_products.length}');
        print('🌟 Featured products: ${_featuredProducts.length}');
      }
    } catch (e, stack) {
      print('❌ ERROR: $e');
      print('❌ STACK: $stack');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreProducts() async {
    if (!_hasMore || _loading) return;
    setState(() => _loading = true);
    _page++;
    try {
      final data = await _api.getProducts(
        page: _page,
        category: _selectedCategory == 0 ? null : _selectedCategory,
      );
      final newProducts = (data['results'] as List? ?? [])
          .map((p) => ProductModel.fromJson(p)).toList();
      if (mounted) {
        setState(() {
          _products.addAll(newProducts);
          _hasMore = data['next'] != null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _filterByCategory(int categoryId) async {
    setState(() { _selectedCategory = categoryId; _page = 1; _loading = true; });
    try {
      final data = await _api.getProducts(
        category: categoryId == 0 ? null : categoryId, page: 1,
      );
      if (mounted) {
        setState(() {
          _products = (data['results'] as List? ?? [])
              .map((p) => ProductModel.fromJson(p)).toList();
          _hasMore = data['next'] != null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.coral,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: 180,
              backgroundColor: AppColors.midnight,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(gradient: AppColors.headerGradient),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top row
                          Row(children: [
                            // Logo
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                _appSettings['Shopping Market'] ?? 'Shopping Market',
                                style: AppText.h3.copyWith(color: Colors.white, fontSize: 17),
                              ),
                              Text('SHOPPING', style: AppText.caption.copyWith(
                                color: AppColors.sky, letterSpacing: 3, fontSize: 9,
                              )),
                            ]),
                            const Spacer(),
                            // Notifications
                            IconButton(
                              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                              onPressed: () {},
                            ),
                            // Cart
                            Stack(children: [
                              IconButton(
                                icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                                onPressed: () => context.go('/cart'),
                              ),
                              if (cart.itemCount > 0) Positioned(
                                right: 6, top: 6,
                                child: Container(
                                  width: 16, height: 16,
                                  decoration: const BoxDecoration(
                                    color: AppColors.watermelon,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text('${cart.itemCount}',
                                      style: const TextStyle(color: Colors.white,
                                          fontSize: 9, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ),
                            ]),
                          ]),
                          const SizedBox(height: AppSpacing.md),
                          // Location
                          Row(children: [
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: _detectLocation, // tap to refresh
                              child: Row(children: [
                                const Icon(Icons.location_on_rounded, color: AppColors.sky, size: 14),
                                const SizedBox(width: 4),
                                _locationLoading
                                    ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(color: AppColors.sky, strokeWidth: 2),
                                )
                                    : Text(
                                  _currentAddress ?? 'التوصيل إلى موقعك',
                                  style: AppText.caption.copyWith(color: AppColors.sky),
                                ),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: AppSpacing.md),
                          // Search bar
                          GestureDetector(
                            onTap: () => _showSearchBottomSheet(context),
                            child: const SearchBarWidget(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Points banner ────────────────────────────────────────────────
            if (user != null && user.loyaltyPoints > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: PointsBanner(user: user),
                ),
              ),

            // ── Banner Slider ────────────────────────────────────────────────
            if (_banners.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: BannerSlider(banners: _banners),
                ),
              ),

            // ── Promo chips ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(children: [
                  _promoChip('🔥 عروض فلاش', AppColors.coral, AppColors.peach),
                  const SizedBox(width: 8),
                  _promoChip('🌿 عضوي', AppColors.mint, AppColors.seafoam),
                  const SizedBox(width: 8),
                  _promoChip('⭐ الأكثر مبيعاً', AppColors.gold, AppColors.lemon),
                  const SizedBox(width: 8),
                  _promoChip('🎁 جديد', AppColors.watermelon, const Color(0xFFFFF0F3)),
                ]),
              ),
            ),

            // ── Categories ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الأقسام', style: AppText.h3),
                    TextButton(
                      onPressed: () {},
                      child: Text('عرض الكل', style: AppText.caption.copyWith(
                        color: AppColors.coral, fontWeight: FontWeight.w600,
                      )),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CategoryRow(
                categories: _categories,
                selectedId: _selectedCategory,
                onSelect: _filterByCategory,
              ),
            ),

            // ── Flash Deals ──────────────────────────────────────────────────
            if (_featuredProducts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('🔥 عروض اليوم', style: AppText.h3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.peach,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.coral.withOpacity(0.3)),
                        ),
                        child: Text('تنتهي الليلة',
                          style: AppText.caption.copyWith(color: AppColors.coral, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    itemCount: _featuredProducts.length,
                    itemBuilder: (ctx, i) => SizedBox(
                      width: 155,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ProductCard(
                          product: _featuredProducts[i],
                          onAddToCart: (p) => _addToCart(context, p),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // ── Products Grid ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_selectedCategory == 0 ? 'جميع المنتجات' :
                      _categories.where((c) => c.id == _selectedCategory)
                          .firstOrNull?.nameAr ?? 'المنتجات',
                      style: AppText.h3),
                    Text('${_products.length} منتج',
                      style: AppText.caption),
                  ],
                ),
              ),
            ),
            _loading && _products.isEmpty
              ? SliverToBoxAdapter(child: _buildShimmerGrid())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i == _products.length) {
                          return _loading
                            ? const Center(child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: AppColors.sapphire),
                              ))
                            : const SizedBox.shrink();
                        }
                        return ProductCard(
                          product: _products[i],
                          onAddToCart: (p) => _addToCart(context, p),
                        );
                      },
                      childCount: _products.length + (_hasMore ? 1 : 0),
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void _addToCart(BuildContext context, ProductModel product) {
    context.read<CartProvider>().addItem(product);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تمت الإضافة: ${product.nameAr}',
        style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: AppColors.mint,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'السلة',
        textColor: Colors.white,
        onPressed: () => context.go('/cart'),
      ),
    ));
  }

  Widget _promoChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(label, style: AppText.caption.copyWith(
        color: textColor, fontWeight: FontWeight.w600,
      )),
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 0.72,
            crossAxisSpacing: 10, mainAxisSpacing: 10,
          ),
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
          ),
        ),
      ),
    );
  }

  void _showSearchBottomSheet(BuildContext context) {
    final ctrl   = TextEditingController();
    List<ProductModel> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (_, ss) => Container(
          height: MediaQuery.of(ctx).size.height * 0.92,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            // ── Handle ──────────────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 44, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // ── Title ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('البحث',
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo', color: AppColors.textMain,
                    )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: AppColors.textMain),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Search field ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.midnight.withOpacity(0.06),
                          blurRadius: 12, offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 14,
                        color: AppColors.textMain,
                      ),
                      decoration: InputDecoration(
                        hintText: 'اكتب اسم المنتج أو الباركود...',
                        hintStyle: TextStyle(
                          fontFamily: 'Cairo', fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                        prefixIcon: searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.coral,
                                ),
                              ),
                            )
                          : const Icon(Icons.search_rounded,
                              color: AppColors.sky, size: 22),
                        suffixIcon: ctrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                ctrl.clear();
                                ss(() { results = []; searching = false; });
                              },
                              child: const Icon(Icons.close_rounded,
                                  color: AppColors.textMuted, size: 18),
                            )
                          : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      onChanged: (q) async {
                        if (q.length >= 1) {
                          ss(() => searching = true);
                          final res = await _api.searchSuggestions(q);
                          ss(() { results = res; searching = false; });
                        } else {
                          ss(() { results = []; searching = false; });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Barcode scanner button
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    final result = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                    if (result != null && mounted) {
                      context.push('/product/$result');
                    }
                  },
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      gradient: AppColors.coralGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.coral.withOpacity(0.3),
                          blurRadius: 10, offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // ── Results ──────────────────────────────────────────────────────
            Expanded(
              child: results.isEmpty
                ? _buildSearchEmptyState(ctrl.text)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = results[i];
                      return _buildSearchResultCard(ctx, p);
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(BuildContext ctx, ProductModel p) {
    final hasImage   = p.mainImageUrl.isNotEmpty;
    final outOfStock = p.isOutOfStock || !p.isAvailable;
    final cart       = context.read<CartProvider>();

    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        context.push('/product/${p.id}');
      },
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.midnight.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
            child: SizedBox(
              width: 88, height: 88,
              child: hasImage
                ? CachedNetworkImage(
                    imageUrl: p.mainImageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.ice,
                      child: const Center(child: Icon(Icons.shopping_basket_outlined,
                          color: AppColors.sky, size: 24))),
                    errorWidget: (_, __, ___) => Container(color: AppColors.ice,
                      child: const Center(child: Icon(Icons.shopping_basket_outlined,
                          color: AppColors.sky, size: 24))),
                  )
                : Container(color: AppColors.ice,
                    child: const Center(child: Icon(Icons.shopping_basket_outlined,
                        color: AppColors.sky, size: 24))),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.nameAr,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo', color: AppColors.textMain,
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  Row(children: [
                    // Price
                    Text(
                      p.currentPrice > 0
                        ? '${p.currentPrice.toStringAsFixed(2)} ج'
                        : 'السعر عند الطلب',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                        color: p.currentPrice > 0
                          ? AppColors.midnight : AppColors.textMuted,
                      ),
                    ),
                    if (p.isOnSale) ...[
                      const SizedBox(width: 6),
                      Text('${p.originalPrice.toStringAsFixed(1)} ج',
                        style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),

          // Add button
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: outOfStock
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('نفذ',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted,
                        fontFamily: 'Cairo')),
                )
              : GestureDetector(
                  onTap: () {
                    cart.addItem(p);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('تمت الإضافة: ${p.nameAr}',
                          style: const TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: AppColors.mint,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.coralGradient,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.coral.withOpacity(0.3),
                          blurRadius: 8, offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
          ),

          const SizedBox(width: 12),
        ]),
      ),
    );
  }

  Widget _buildSearchEmptyState(String query) {
    if (query.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.ice,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded,
                color: AppColors.sky, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('ابحث عن منتجاتك',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              fontFamily: 'Cairo', color: AppColors.textMain,
            )),
          const SizedBox(height: 6),
          Text('اكتب اسم المنتج أو امسح الباركود',
            style: TextStyle(
              fontSize: 13, fontFamily: 'Cairo',
              color: AppColors.textMuted,
            )),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.peach,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.search_off_rounded,
              color: AppColors.coral, size: 36),
        ),
        const SizedBox(height: 16),
        const Text('لا توجد نتائج',
          style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700,
            fontFamily: 'Cairo', color: AppColors.textMain,
          )),
        const SizedBox(height: 6),
        Text('لم نجد منتجاً يطابق "$query"',
          style: TextStyle(
            fontSize: 13, fontFamily: 'Cairo',
            color: AppColors.textMuted,
          )),
      ]),
    );
  }
}
