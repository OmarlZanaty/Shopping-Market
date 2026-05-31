import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../models/models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';
import '../../../widgets/customer/banner_slider.dart';
import '../../../widgets/customer/points_banner.dart';
import '../../../widgets/shared/barcode_scanner_screen.dart';
import '../../../widgets/shared/product_card.dart';
import '../categories/all_categories_screen.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final _api = ApiService();
  final _scrollCtrl = ScrollController();

  // ── Animation controller ──────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;

  // Pre-computed animation intervals — created once, reused every build.
  // Creating CurvedAnimation / Tween.animate() inside build() allocates new
  // objects on every setState and keeps them alive until the next GC cycle.
  late final Animation<double> _aniPoints;     // points banner
  late final Animation<double> _aniBanner;     // banner slider
  late final Animation<double> _aniPromo;      // promo chips
  late final Animation<double> _aniCats;       // categories
  late final Animation<double> _aniFlash;      // flash deals
  late final Animation<double> _aniProdHdr;    // products section header
  // Slide counterparts (Offset animations)
  late final Animation<Offset> _slidePoints;
  late final Animation<Offset> _slideBanner;
  late final Animation<Offset> _slidePromo;
  late final Animation<Offset> _slideCats;
  late final Animation<Offset> _slideFlash;
  late final Animation<Offset> _slideProdHdr;

  // ── Data ──────────────────────────────────────────────────────────────────
  List<BannerModel>    _banners              = [];
  List<CategoryModel>  _categories           = [];
  List<ProductModel>   _products             = [];
  List<ProductModel>   _featuredProducts     = [];
  List<ProductModel>   _recommendations      = [];
  List<ProductModel>   _smartCartItems       = [];
  Map<String, dynamic> _appSettings         = {};

  // Key used to scroll the CustomScrollView to the products section
  final _productsKey = GlobalKey();

  int  _selectedCategory = 0;
  bool _loading          = true;
  int  _page             = 1;
  bool _hasMore          = true;

  // ── Notifications ─────────────────────────────────────────────────────────
  int _unreadCount = 0;

  // ── Location ──────────────────────────────────────────────────────────────
  String? _currentAddress;
  bool    _locationLoading = false;

  // ── Search state ──────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  List<ProductModel> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Pre-compute all animation objects once — avoids repeated allocation
    // inside build() which runs on every setState().
    _aniPoints  = _makeInterval(0.0,  0.4);
    _aniBanner  = _makeInterval(0.0,  0.5);
    _aniPromo   = _makeInterval(0.1,  0.5);
    _aniCats    = _makeInterval(0.2,  0.65);
    _aniFlash   = _makeInterval(0.35, 0.75);
    _aniProdHdr = _makeInterval(0.5,  0.9);
    // Slide animations (same tween, different parent)
    final _t = _SlideOffsetTween();
    _slidePoints  = _t.animate(_aniPoints);
    _slideBanner  = _t.animate(_aniBanner);
    _slidePromo   = _t.animate(_aniPromo);
    _slideCats    = _t.animate(_aniCats);
    _slideFlash   = _t.animate(_aniFlash);
    _slideProdHdr = _t.animate(_aniProdHdr);

    _loadData();
    _detectLocation();
    _loadUnreadCount();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (_hasMore && !_loading) _loadMoreProducts();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getBanners(position: 'home_main'),
        _api.getCategories(),
        _api.getProducts(page: 1),
        _api.getProducts(featured: true),
        _api.getAppSettings(),
      ]);
      if (!mounted) return;
      final productsData  = results[2] as Map<String, dynamic>;
      final featuredData  = results[3] as Map<String, dynamic>;
      setState(() {
        _banners          = results[0] as List<BannerModel>;
        _categories       = results[1] as List<CategoryModel>;
        _products         = (productsData['results'] as List? ?? [])
            .map((p) => ProductModel.fromJson(p)).toList();
        _hasMore          = productsData['next'] != null;
        _featuredProducts = (featuredData['results'] as List? ?? [])
            .map((p) => ProductModel.fromJson(p)).toList();
        _appSettings      = results[4] as Map<String, dynamic>;
        _loading          = false;
      });
      _fadeCtrl.forward(from: 0);

      // Load AI sections in background — non-blocking, failures silently ignored
      _loadAiSections();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAiSections() async {
    try {
      final recs = await _api.getRecommendations(limit: 10);
      if (mounted && recs.isNotEmpty) setState(() => _recommendations = recs);
    } catch (_) {}
    try {
      final smart = await _api.getSmartCart();
      if (mounted && smart.isNotEmpty) setState(() => _smartCartItems = smart);
    } catch (_) {}
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
      final more = (data['results'] as List? ?? [])
          .map((p) => ProductModel.fromJson(p)).toList();
      if (mounted) {
        setState(() {
          _products.addAll(more);
          _hasMore = data['next'] != null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _filterByCategory(int id) async {
    setState(() { _selectedCategory = id; _page = 1; _loading = true; });
    try {
      final data = await _api.getProducts(
        category: id == 0 ? null : id, page: 1,
      );
      if (mounted) {
        setState(() {
          _products = (data['results'] as List? ?? [])
              .map((p) => ProductModel.fromJson(p)).toList();
          _hasMore  = data['next'] != null;
          _loading  = false;
        });
        // Scroll to products section after the frame is rendered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _productsKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
              alignment: 0.0,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    // Set flag directly — no setState here so we don't trigger a full rebuild
    // just to show a spinner; the flag is picked up on the next natural rebuild.
    _locationLoading = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _currentAddress  = 'التوصيل إلى موقعك';
          _locationLoading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);
      final res = await Dio().get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': pos.latitude, 'lon': pos.longitude,
          'format': 'json', 'accept-language': 'ar',
        },
        options: Options(headers: {'User-Agent': 'ShoppingMarket/1.0'}),
      );
      final addr     = res.data['address'] as Map<String, dynamic>?;
      final city     = addr?['city'] ?? addr?['town'] ?? addr?['state'] ?? '';
      final district = addr?['suburb'] ?? addr?['district'] ?? '';
      if (mounted) setState(() {
        _currentAddress = (city.isNotEmpty && district.isNotEmpty)
            ? '$city - $district'
            : (city.isNotEmpty ? city : 'موقعك الحالي');
        _locationLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _currentAddress  = 'التوصيل إلى موقعك';
        _locationLoading = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  // Only called from initState() — produces a CurvedAnimation once.
  Animation<double> _makeInterval(double start, double end) =>
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      );

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Use select so only the exact value change triggers a rebuild here.
    // ProductCard/SearchResultCard use their own Consumer<CartProvider>.
    final user      = context.select<AuthProvider, UserModel?>((a) => a.user);
    final cartCount = context.select<CartProvider, int>((c) => c.itemCount);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.coral,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header (SliverAppBar) ────────────────────────────────────
            _buildHeader(cartCount),

            // ── Shimmer while first load ─────────────────────────────────
            if (_loading && _products.isEmpty)
              SliverToBoxAdapter(child: _buildShimmer())
            else
              ..._buildSlivers(user),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // HEADER (SliverAppBar)
  // ═══════════════════════════════════════════════
  Widget _buildHeader(int cartCount) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      expandedHeight: 170,
      backgroundColor: AppColors.midnight,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.headerGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Top row: logo + name + icons ───────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Row(children: [
                    // Logo
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: AppColors.coral.withOpacity(0.3),
                              blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.asset('assets/images/logo.png',
                          fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 10),

                    // Store name
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _appSettings['Shopping Market'] ?? 'Shopping Market',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w800, fontFamily: 'Cairo',
                        ),
                      ),
                      Text('MARKET',
                          style: TextStyle(
                            color: AppColors.coral,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            fontFamily: 'Cairo',
                          )),
                    ]),
                    const Spacer(),

                    // Notification bell with unread badge
                    Stack(children: [
                      _headerIcon(Icons.notifications_outlined,
                          _openNotifications),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 4, top: 4,
                          child: Container(
                            width: 16, height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.gold,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _unreadCount > 9 ? '9+' : '$_unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 4),

                    // Cart
                    Stack(children: [
                      _headerIcon(Icons.shopping_cart_outlined,
                          () => context.go('/cart')),
                      if (cartCount > 0)
                        Positioned(
                          right: 4, top: 4,
                          child: Container(
                            width: 16, height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.coral, shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('$cartCount',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 9, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                    ]),
                  ]),
                ),

                // ── Location row ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: GestureDetector(
                    onTap: _detectLocation,
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.coral, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _locationLoading
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    color: AppColors.coral, strokeWidth: 2),
                              )
                            : Text(
                                _currentAddress ?? 'التوصيل إلى موقعك',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12, fontFamily: 'Cairo',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white54, size: 16),
                    ]),
                  ),
                ),

                // ── Search bar ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GestureDetector(
                    onTap: () => _showSearch(context),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 14),
                        const Icon(Icons.search_rounded,
                            color: Colors.white54, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('ابحث عن منتجاتك...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13, fontFamily: 'Cairo',
                              )),
                        ),
                        Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.coral, Color(0xFFFF6B00)]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(children: [
                            Icon(Icons.qr_code_scanner_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('مسح', style: TextStyle(
                              color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                            )),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white, size: 22),
        onPressed: onTap,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      );

  // ═══════════════════════════════════════════════
  // SLIVERS — replaces the old single-Column body.
  // Using SliverGrid for the products makes Flutter
  // virtualise the grid (only paints visible items).
  // ═══════════════════════════════════════════════
  List<Widget> _buildSlivers(UserModel? user) {
    return [
      // ── Points banner ──────────────────────────────────────────────
      if (user != null && user.loyaltyPoints > 0)
        SliverToBoxAdapter(
          child: _animated(
            _aniPoints, _slidePoints,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: PointsBanner(user: user),
            ),
          ),
        ),

      // ── Banner Slider ──────────────────────────────────────────────
      // RepaintBoundary: the slider's internal Timer triggers repaints
      // every 4 s — isolate them so they don't cascade to the rest of
      // the CustomScrollView.
      SliverToBoxAdapter(
        child: _animated(
          _aniBanner, _slideBanner,
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
              child: BannerSlider(banners: _banners),
            ),
          ),
        ),
      ),

      // ── Promo chips ────────────────────────────────────────────────
      SliverToBoxAdapter(
        child: _animated(
          _aniPromo, _slidePromo,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              _promoChip('🔥 عروض فلاش', AppColors.coral, AppColors.peach),
              const SizedBox(width: 8),
              _promoChip('🌿 عضوي', AppColors.mint, AppColors.seafoam),
              const SizedBox(width: 8),
              _promoChip('⭐ الأكثر مبيعاً', AppColors.gold, AppColors.lemon),
              const SizedBox(width: 8),
              _promoChip('🎁 وصل حديثاً', AppColors.watermelon,
                  AppColors.watermelon.withOpacity(0.1)),
            ]),
          ),
        ),
      ),

      // ── Categories (max 6 shown) ───────────────────────────────────
      if (_categories.isNotEmpty)
        SliverToBoxAdapter(
          child: _animated(
            _aniCats, _slideCats,
            _CategoriesSection(
              categories: _categories,
              selectedId: _selectedCategory,
              onSelect: _filterByCategory,
              onViewAll: _showAllCategories,
            ),
          ),
        ),

      // ── Flash deals ────────────────────────────────────────────────
      if (_featuredProducts.isNotEmpty)
        SliverToBoxAdapter(
          child: _animated(
            _aniFlash, _slideFlash,
            _FlashDealsSection(products: _featuredProducts),
          ),
        ),

      // ── AI: Smart cart nudge ───────────────────────────────────────
      if (_smartCartItems.isNotEmpty)
        SliverToBoxAdapter(
          child: _AiHorizontalSection(
            title: 'عادةً ما تطلب 🛒',
            subtitle: 'المنتجات التي تطلبها باستمرار',
            color: AppColors.sky,
            products: _smartCartItems,
          ),
        ),

      // ── AI: Personalised recommendations ──────────────────────────
      if (_recommendations.isNotEmpty)
        SliverToBoxAdapter(
          child: _AiHorizontalSection(
            title: 'مقترح لك ✨',
            subtitle: 'بناءً على سجل مشترياتك',
            color: AppColors.gold,
            products: _recommendations,
          ),
        ),

      // ── Products grid header ───────────────────────────────────────
      SliverToBoxAdapter(
        key: _productsKey,
        child: _animated(
          _aniProdHdr, _slideProdHdr,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  _selectedCategory == 0
                      ? 'جميع المنتجات'
                      : _categories
                              .where((c) => c.id == _selectedCategory)
                              .firstOrNull
                              ?.nameAr ??
                          'المنتجات',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                    color: AppColors.textMain,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),

      // ── Products grid (virtualised SliverGrid) ─────────────────────
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) => ProductCard(product: _products[i]),
            childCount: _products.length,
            // Recycle cells that leave the viewport
            addRepaintBoundaries: true,
            addAutomaticKeepAlives: false,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
        ),
      ),

      // ── Pagination indicator / bottom padding ──────────────────────
      SliverToBoxAdapter(
        child: _hasMore
            ? _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.coral, strokeWidth: 2.5),
                    ),
                  )
                : const SizedBox(height: 16)
            : const SizedBox(height: 32),
      ),
    ];
  }

  // ── Animated wrapper (pre-computed fade + slide passed in) ───────────────
  // No allocations happen here — both animations were created in initState().
  Widget _animated(
    Animation<double> fade,
    Animation<Offset> slide,
    Widget child,
  ) =>
      FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );

  // ── Promo chip ────────────────────────────────────────────────────────────
  Widget _promoChip(String label, Color textColor, Color bgColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: textColor.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: textColor, fontFamily: 'Cairo',
            )),
      );

  // ═══════════════════════════════════════════════
  // SHIMMER LOADING
  // ═══════════════════════════════════════════════
  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: Column(children: [
        // Banner placeholder
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          height: 190, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22),
          ),
        ),
        const SizedBox(height: 20),
        // Category grid placeholder
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, childAspectRatio: 0.85,
              crossAxisSpacing: 10, mainAxisSpacing: 10,
            ),
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Product grid placeholder
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 0.72,
              crossAxisSpacing: 10, mainAxisSpacing: 10,
            ),
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════
  Future<void> _loadUnreadCount() async {
    try {
      final list = await _api.getMyNotifications();
      if (mounted) {
        setState(() {
          _unreadCount = list.where((n) => n['is_read'] != true).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // Refresh count after returning (user may have read some)
    _loadUnreadCount();
  }

  // ═══════════════════════════════════════════════
  // ALL CATEGORIES SCREEN
  // ═══════════════════════════════════════════════
  Future<void> _showAllCategories() async {
    final selectedId = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => AllCategoriesScreen(
          categories: _categories,
          selectedId: _selectedCategory,
        ),
      ),
    );
    if (selectedId != null && mounted) {
      _filterByCategory(selectedId);
    }
  }

  // ═══════════════════════════════════════════════
  // SEARCH BOTTOM SHEET
  // ═══════════════════════════════════════════════
  void _showSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchSheet(api: _api, parentContext: context),
    );
  }
}

// ── Const tween used to pre-compute slide animations in initState() ───────────
class _SlideOffsetTween extends Tween<Offset> {
  _SlideOffsetTween()
      : super(begin: const Offset(0, 0.06), end: Offset.zero);
}

// ══════════════════════════════════════════════════════════════════════════════
// CATEGORIES SECTION — shows at most 6 cards; "عرض الكل" opens full screen
// ══════════════════════════════════════════════════════════════════════════════
class _CategoriesSection extends StatelessWidget {
  final List<CategoryModel> categories;
  final int selectedId;
  final void Function(int) onSelect;
  final VoidCallback onViewAll;

  static const _maxVisible = 6; // "الكل" counts as one of the 6

  const _CategoriesSection({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final all = [
      const CategoryModel(id: 0, nameAr: 'الكل', nameEn: 'All', icon: '🛒'),
      ...categories,
    ];
    // Show at most _maxVisible items; rest are in the full-screen
    final visible = all.length > _maxVisible
        ? all.sublist(0, _maxVisible)
        : all;
    final hasMore = all.length > _maxVisible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Row(children: [
          Container(
            width: 4, height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.coral, AppColors.gold],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Text('الأقسام',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                fontFamily: 'Cairo', color: AppColors.textMain,
              )),
          const Spacer(),
          GestureDetector(
            onTap: onViewAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.coral, Color(0xFFFF6B00)]),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  hasMore
                      ? 'عرض الكل (${all.length})'
                      : 'عرض الكل',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: Colors.white, fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white, size: 10),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // 3-column grid (max 6 items — bounded, so shrinkWrap is safe here)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (_, i) {
            final cat = visible[i];
            return _CategoryCard(
              category: cat,
              selected: cat.id == selectedId,
              onTap: () => onSelect(cat.id),
              index: i,
            );

          },
        ),
      ]),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final CategoryModel category;
  final bool selected;
  final VoidCallback onTap;
  final int index;
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.index,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0, upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final hasImage = (cat.imageUrl ?? '').isNotEmpty;

    return GestureDetector(
      onTap: () {
        _press.forward().then((_) => _press.reverse());
        widget.onTap();
      },
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.midnight : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.selected
                  ? AppColors.coral
                  : AppColors.border,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.selected
                    ? AppColors.coral.withOpacity(0.25)
                    : Colors.black.withOpacity(0.06),
                blurRadius: widget.selected ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Image / icon area
              Expanded(
                flex: 60,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(17)),
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: cat.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => _iconFallback(cat, widget.selected),
                          errorWidget: (_, __, ___) => _iconFallback(cat, widget.selected),
                        )
                      : _iconFallback(cat, widget.selected),
                ),
              ),

              // Name label
              Expanded(
                flex: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cat.nameAr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                          color: widget.selected
                              ? Colors.white
                              : AppColors.textMain,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (cat.productCount > 0) ...[
                        const SizedBox(height: 2),
                        Text('${cat.productCount} منتج',
                            style: TextStyle(
                              fontSize: 9,
                              fontFamily: 'Cairo',
                              color: widget.selected
                                  ? Colors.white54
                                  : AppColors.textMuted,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconFallback(CategoryModel cat, bool selected) => Container(
        color: selected
            ? AppColors.coral.withOpacity(0.15)
            : AppColors.coral.withOpacity(0.06),
        child: Center(
          child: Text(cat.icon, style: const TextStyle(fontSize: 34)),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// FLASH DEALS SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _FlashDealsSection extends StatelessWidget {
  final List<ProductModel> products;
  const _FlashDealsSection({required this.products});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Container(
              width: 4, height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.coral, AppColors.gold],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Text('🔥 عروض اليوم',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo', color: AppColors.textMain,
                )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.coral, Color(0xFFFF6B00)]),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Row(children: [
                Icon(Icons.access_time_rounded,
                    color: Colors.white, size: 10),
                SizedBox(width: 4),
                Text('تنتهي الليلة',
                    style: TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                    )),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Horizontal scroll
        SizedBox(
          height: 215,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(width: 148, child: ProductCard(product: products[i])),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _SearchSheet extends StatefulWidget {
  final ApiService api;
  final BuildContext parentContext;
  const _SearchSheet({required this.api, required this.parentContext});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  List<ProductModel> _results = [];
  bool _searching = false;
  bool _visualSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.isEmpty) { setState(() { _results = []; _searching = false; }); return; }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await widget.api.searchSuggestions(q);
      if (mounted) setState(() { _results = res; _searching = false; });
    });
  }

  Future<void> _visualSearch() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
      if (file == null) return;
      if (mounted) setState(() => _visualSearching = true);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final result = await widget.api.visualSearch(b64);
      final products = (result['results'] as List? ?? [])
          .map((p) => ProductModel.fromJson(p))
          .toList();
      final query = result['query'] as String? ?? '';
      if (mounted) {
        setState(() {
          _results = products;
          _visualSearching = false;
          if (query.isNotEmpty) _ctrl.text = query;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _visualSearching = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        // Handle
        const SizedBox(height: 12),
        Container(width: 44, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),

        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('البحث',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo', color: AppColors.textMain)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey[200], shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.textMain)),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Search field + barcode button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.midnight.withOpacity(0.06),
                      blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontFamily: 'Cairo',
                      fontSize: 14, color: AppColors.textMain),
                  cursorColor: AppColors.coral,
                  decoration: InputDecoration(
                    // The global (dark) theme fills inputs with a dark color,
                    // which hid the dark text. Force a white fill so typed text
                    // (textMain) is visible inside the white search field.
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'اكتب اسم المنتج أو الباركود...',
                    hintStyle: const TextStyle(fontFamily: 'Cairo',
                        fontSize: 13, color: AppColors.textMuted),
                    prefixIcon: _searching
                        ? const Padding(padding: EdgeInsets.all(14),
                            child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.coral)))
                        : const Icon(Icons.search_rounded,
                            color: AppColors.coral, size: 22),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () { _ctrl.clear();
                              setState(() { _results = []; _searching = false; }); },
                            child: const Icon(Icons.close_rounded,
                                color: AppColors.textMuted, size: 18))
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                  onChanged: _onChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Visual search (camera)
            GestureDetector(
              onTap: _visualSearch,
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.midnight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: _visualSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.gold))
                    : const Icon(Icons.camera_alt_rounded,
                        color: AppColors.gold, size: 24),
              ),
            ),
            const SizedBox(width: 8),
            // Barcode scanner
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                final barcode = await Navigator.push<String>(
                    widget.parentContext,
                    MaterialPageRoute(
                        builder: (_) => const BarcodeScannerScreen()));
                if (barcode == null || !widget.parentContext.mounted) return;
                try {
                  final found = await widget.api.searchSuggestions(barcode);
                  if (!widget.parentContext.mounted) return;
                  if (found.isNotEmpty) {
                    widget.parentContext.read<CartProvider>().addItem(found.first);
                    ScaffoldMessenger.of(widget.parentContext).showSnackBar(SnackBar(
                      content: Text('تمت الإضافة: ${found.first.nameAr}',
                          style: const TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: AppColors.mint,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  } else {
                    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                      const SnackBar(
                        content: Text('لم يتم العثور على المنتج',
                            style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (_) {}
              },
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.coral, Color(0xFFFF6B00)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.coral.withOpacity(0.3),
                      blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Results
        Expanded(
          child: _results.isEmpty
              ? _emptyState(_ctrl.text)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _SearchResultCard(
                    product: _results[i],
                    onClose: () => Navigator.pop(context),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _emptyState(String q) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: q.isEmpty ? AppColors.ice : AppColors.peach,
              shape: BoxShape.circle,
            ),
            child: Icon(
              q.isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
              color: AppColors.coral, size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(q.isEmpty ? 'ابحث عن منتجاتك' : 'لا توجد نتائج',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo', color: AppColors.textMain)),
          const SizedBox(height: 6),
          Text(q.isEmpty ? 'اكتب اسم المنتج أو امسح الباركود'
              : 'لم نجد منتجاً يطابق "$q"',
              style: const TextStyle(fontSize: 13, fontFamily: 'Cairo',
                  color: AppColors.textMuted)),
        ]),
      );
}

// Search result card (with −/qty/+ stepper)
class _SearchResultCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onClose;
  const _SearchResultCard({required this.product, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final outOfStock = p.isOutOfStock || !p.isAvailable;

    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        final qty = cart.getQuantity(p.id);
        return Container(
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
              color: AppColors.midnight.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 3),
            )],
          ),
          child: Row(children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(18)),
              child: SizedBox(
                width: 88, height: 88,
                child: p.mainImageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: p.mainImageUrl, fit: BoxFit.cover,
                        placeholder: (_, __) => _imgFallback(),
                        errorWidget: (_, __, ___) => _imgFallback())
                    : _imgFallback(),
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
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo', color: AppColors.textMain),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    Row(children: [
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
                            )),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
            // Qty control
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: outOfStock
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('نفذ', style: TextStyle(
                          fontSize: 10, color: AppColors.textMuted,
                          fontFamily: 'Cairo')))
                  : qty == 0
                      ? GestureDetector(
                          onTap: () => cart.addItem(p),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [AppColors.coral, Color(0xFFFF6B00)]),
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: [BoxShadow(
                                  color: AppColors.coral.withOpacity(0.3),
                                  blurRadius: 8, offset: const Offset(0, 3))],
                            ),
                            child: const Icon(Icons.add_rounded,
                                color: Colors.white, size: 22),
                          ))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          _qtyBtn(Icons.remove_rounded,
                              () => cart.decrementItem(p.id)),
                          SizedBox(width: 26,
                              child: Text(
                                qty % 1 == 0
                                    ? qty.toInt().toString()
                                    : qty.toStringAsFixed(1),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800,
                                  fontFamily: 'Cairo', color: AppColors.midnight,
                                ),
                              )),
                          _qtyBtn(Icons.add_rounded, () => cart.addItem(p)),
                        ]),
            ),
            const SizedBox(width: 12),
          ]),
        );
      },
    );
  }

  Widget _imgFallback() => Container(color: AppColors.ice,
      child: const Center(child: Icon(Icons.shopping_basket_outlined,
          color: AppColors.coral, size: 24)));

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.coral, Color(0xFFFF6B00)]),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// AI HORIZONTAL SECTION
// Used for both "مقترح لك" (recommendations) and "عادةً ما تطلب" (smart cart).
// Horizontal scrolling row of compact product cards.
// ══════════════════════════════════════════════════════════════════════════════
class _AiHorizontalSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<ProductModel> products;

  const _AiHorizontalSection({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo', color: AppColors.textMain)),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 11, fontFamily: 'Cairo',
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            ]),
          ),

          // Horizontal product list
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: products.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _AiProductCard(product: products[i], accentColor: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiProductCard extends StatelessWidget {
  final ProductModel product;
  final Color accentColor;

  const _AiProductCard({required this.product, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final outOfStock = p.isOutOfStock || !p.isAvailable;

    return GestureDetector(
      onTap: () => context.push('/product/${p.id}'),
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: SizedBox(
                height: 100, width: double.infinity,
                child: p.mainImageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: p.mainImageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.ice),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.ice,
                          child: const Icon(Icons.image_not_supported_rounded,
                              color: AppColors.textMuted, size: 28),
                        ),
                      )
                    : Container(color: AppColors.ice,
                        child: const Icon(Icons.shopping_bag_outlined,
                            color: AppColors.textMuted, size: 30)),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nameAr,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                          color: AppColors.textMain),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  outOfStock
                      ? Text('غير متوفر',
                          style: TextStyle(fontSize: 11, fontFamily: 'Cairo',
                              color: AppColors.error, fontWeight: FontWeight.w600))
                      : Text(
                          p.currentPrice > 0
                              ? '${p.currentPrice.toStringAsFixed(2)} ج'
                              : '',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo', color: accentColor),
                        ),
                ],
              ),
            ),
            // Add button
            if (!outOfStock)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Consumer<CartProvider>(
                  builder: (ctx, cart, _) {
                    final qty = cart.getQuantity(p.id);
                    return qty > 0
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _SmallBtn(
                                icon: Icons.remove_rounded,
                                color: AppColors.coral,
                                onTap: () => cart.decrementItem(p.id),
                              ),
                              Text('$qty',
                                  style: const TextStyle(fontWeight: FontWeight.w800,
                                      fontFamily: 'Cairo', fontSize: 13)),
                              _SmallBtn(
                                icon: Icons.add_rounded,
                                color: AppColors.coral,
                                onTap: () => cart.addItem(p),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 28,
                            child: ElevatedButton(
                              onPressed: () => cart.addItem(p),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('+ أضف',
                                  style: TextStyle(fontSize: 11,
                                      fontFamily: 'Cairo', fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );
}
