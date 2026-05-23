import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_constants.dart';
import '../orders/data/orders_api.dart';
import '../scanner/barcode_scanner_screen.dart';
import 'product_detail_screen.dart';

// ─── Data / API ───────────────────────────────────────────────────────────────

class _InventoryPage {
  final List<Map<String, dynamic>> items;
  final int total;
  final int totalPages;
  final bool hasMore;
  const _InventoryPage({
    required this.items,
    required this.total,
    required this.totalPages,
    required this.hasMore,
  });
}

Future<_InventoryPage> _fetchPage(String query, int page) async {
  final dio = DioClient.I.dio;
  final res = await dio.get(
    ApiConstants.inventoryProducts,
    queryParameters: {
      if (query.isNotEmpty) 'q': query,
      'page': page,
      'limit': 40,
    },
  );
  final body = res.data as Map<String, dynamic>;
  final List<dynamic> raw = body['data'] ?? [];
  final pag = (body['pagination'] as Map?) ?? {};
  return _InventoryPage(
    items: raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    total: (pag['total'] as int?) ?? raw.length,
    totalPages: (pag['totalPages'] as int?) ?? 1,
    hasMore: (pag['hasMore'] as bool?) ?? false,
  );
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class ScannerInventoryScreen extends ConsumerStatefulWidget {
  const ScannerInventoryScreen({super.key});

  @override
  ConsumerState<ScannerInventoryScreen> createState() =>
      _ScannerInventoryScreenState();
}

class _ScannerInventoryScreenState
    extends ConsumerState<ScannerInventoryScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String _query = '';
  final List<Map<String, dynamic>> _products = [];
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loadingFirst = true;
        _error = null;
        _page = 1;
        _products.clear();
        _hasMore = true;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final result = await _fetchPage(_query, _page);
      if (!mounted) return;
      setState(() {
        _products.addAll(result.items);
        _total = result.total;
        _hasMore = result.hasMore;
        _page++;
        _loadingFirst = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingFirst = false;
        _loadingMore = false;
      });
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String v) {
    final q = v.trim();
    if (q == _query) return;
    _query = q;
    _loadPage(reset: true);
  }

  // ── Open product detail ───────────────────────────────────────────────────

  Future<void> _openDetail(int index) async {
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: _products[index]),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _products[index] = {..._products[index], ...updated});
    }
  }

  // ── Barcode scanner ───────────────────────────────────────────────────────

  Future<void> _openScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode == null || barcode.isEmpty || !mounted) return;
    _showScannedProduct(barcode);
  }

  void _showScannedProduct(String barcode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScannedProductSheet(
        barcode: barcode,
        onToggled: (pid, newVal) {
          final idx = _products.indexWhere((p) => p['id'].toString() == pid);
          if (idx != -1) {
            setState(() =>
                _products[idx] = {..._products[idx], 'is_available': newVal});
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final availableCount = _products.where((p) => p['is_available'] == true).length;
    final activeCount = _products.where((p) => p['is_active'] != false).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        title: const Text('مخزون المنتجات',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'بحث باسم المنتج أو الباركود...',
                hintStyle:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                filled: true,
                fillColor: AppColors.backgroundSecondary,
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: AppColors.accentOrange,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('مسح باركود'),
      ),
      body: _loadingFirst
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.accentOrange))
          : _error != null && _products.isEmpty
              ? _ErrorView(
                  message: _error!,
                  onRetry: () => _loadPage(reset: true),
                )
              : Column(children: [
                  // Stats bar
                  _StatsBar(
                    available: availableCount,
                    active: activeCount,
                    total: _total,
                    loaded: _products.length,
                  ),

                  // Product grid
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.accentOrange,
                      onRefresh: () => _loadPage(reset: true),
                      child: _products.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 120),
                              const Icon(Icons.inventory_2_outlined,
                                  color: AppColors.textSecondary, size: 64),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  _query.isEmpty
                                      ? 'لا توجد منتجات'
                                      : 'لا نتائج لـ "$_query"',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                              ),
                            ])
                          : GridView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.70,
                              ),
                              itemCount:
                                  _products.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _products.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(
                                          color: AppColors.accentOrange,
                                          strokeWidth: 2),
                                    ),
                                  );
                                }
                                return _ProductGridCard(
                                  key: ValueKey(_products[i]['id']),
                                  product: _products[i],
                                  onTap: () => _openDetail(i),
                                );
                              },
                            ),
                    ),
                  ),
                ]),
    );
  }
}

// ─── Stats bar ────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int available, active, total, loaded;
  const _StatsBar({
    required this.available,
    required this.active,
    required this.total,
    required this.loaded,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _Chip(label: 'متاح', value: '$available', color: AppColors.successGreen),
          Container(width: 1, height: 28, color: AppColors.divider),
          _Chip(label: 'نشط', value: '$active', color: AppColors.infoBlue),
          Container(width: 1, height: 28, color: AppColors.divider),
          _Chip(label: 'محمّل', value: '$loaded', color: AppColors.accentOrange),
          Container(width: 1, height: 28, color: AppColors.divider),
          _Chip(label: 'الكل', value: '$total', color: AppColors.textSecondary),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 10)),
      ]);
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off, color: AppColors.errorRed, size: 56),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
      );
}

// ─── Product grid card ────────────────────────────────────────────────────────

class _ProductGridCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  const _ProductGridCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAvailable = product['is_available'] == true;
    final isActive = product['is_active'] != false; // default true if missing
    final price = (product['current_price'] as num?)?.toDouble() ?? 0.0;
    final name = (product['name_ar'] ?? product['name_en'] ?? '—') as String;
    final imageUrl = (product['image_url'] ?? '') as String;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !isActive
                ? AppColors.errorRed.withOpacity(0.5)
                : isAvailable
                    ? AppColors.successGreen.withOpacity(0.3)
                    : AppColors.divider,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                _PlaceholderImage(name: name),
                            placeholder: (_, __) => Container(
                              color: AppColors.backgroundPrimary,
                              child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        : _PlaceholderImage(name: name),
                    // "مخفي" overlay when not active
                    if (!isActive)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.errorRed,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('مخفي',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Info area
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (price > 0)
                      Text(
                        '${price.toStringAsFixed(1)} ج',
                        style: const TextStyle(
                          color: AppColors.accentOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(children: [
                      _StatusDot(
                        label: isAvailable ? 'متاح' : 'نفذ',
                        color: isAvailable
                            ? AppColors.successGreen
                            : AppColors.errorRed,
                      ),
                      const SizedBox(width: 4),
                      _StatusDot(
                        label: isActive ? 'نشط' : 'مخفي',
                        color: isActive
                            ? AppColors.infoBlue
                            : AppColors.textSecondary,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  final String name;
  const _PlaceholderImage({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.backgroundPrimary,
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.inventory_2_outlined,
              color: AppColors.textSecondary, size: 36),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              name.length > 20 ? name.substring(0, 20) : name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ),
        ]),
      );
}

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      );
}

// ─── Scanned product bottom sheet ────────────────────────────────────────────

class _ScannedProductSheet extends StatefulWidget {
  final String barcode;
  final void Function(String productId, bool newVal) onToggled;
  const _ScannedProductSheet(
      {required this.barcode, required this.onToggled});

  @override
  State<_ScannedProductSheet> createState() => _ScannedProductSheetState();
}

class _ScannedProductSheetState extends State<_ScannedProductSheet> {
  Map<String, dynamic>? _product;
  bool _loading = true;
  String? _error;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await OrdersApi().inventoryScan(widget.barcode);
      if (mounted) setState(() { _product = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle() async {
    if (_product == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      final newVal =
          await OrdersApi().toggleAvailability(_product!['id'].toString());
      if (!mounted) return;
      setState(() { _product!['is_available'] = newVal; _toggling = false; });
      widget.onToggled(_product!['id'].toString(), newVal);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newVal ? 'تم تفعيل المنتج ✓' : 'تم إيقاف المنتج'),
        backgroundColor:
            newVal ? AppColors.successGreen : AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _toggling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ: $e'),
        backgroundColor: AppColors.errorRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: AppColors.accentOrange))
            : _error != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.errorRed, size: 48),
                    const SizedBox(height: 12),
                    const Text('لم يُعثر على منتج بهذا الباركود',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 16),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(widget.barcode,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter')),
                  ])
                : _ProductSheetDetail(
                    product: _product!,
                    onToggle: _toggle,
                    toggling: _toggling,
                  ),
      ),
    );
  }
}

class _ProductSheetDetail extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onToggle;
  final bool toggling;
  const _ProductSheetDetail(
      {required this.product, required this.onToggle, required this.toggling});

  @override
  Widget build(BuildContext context) {
    final isAvailable = product['is_available'] == true;
    final stockQty = (product['quantity_in_stock'] as num?)?.toInt() ?? 0;
    final price = (product['current_price'] as num?)?.toDouble() ?? 0.0;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isAvailable
              ? AppColors.successGreen.withOpacity(0.15)
              : AppColors.errorRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: isAvailable ? AppColors.successGreen : AppColors.errorRed),
        ),
        child: Text(
          isAvailable ? 'متاح للعملاء' : 'موقوف عن العملاء',
          style: TextStyle(
              color: isAvailable ? AppColors.successGreen : AppColors.errorRed,
              fontWeight: FontWeight.bold,
              fontSize: 13),
        ),
      ),
      const SizedBox(height: 16),
      Text(product['name_ar'] ?? product['name_en'] ?? '—',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
      const SizedBox(height: 4),
      if ((product['barcode'] ?? '').toString().isNotEmpty)
        Text(product['barcode'].toString(),
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'Inter')),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _InfoTile(label: 'السعر', value: '${price.toStringAsFixed(1)} ج'),
        _InfoTile(
            label: 'المخزون',
            value: '$stockQty',
            valueColor: stockQty > 0
                ? AppColors.successGreen
                : AppColors.errorRed),
      ]),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton.icon(
          onPressed: toggling ? null : onToggle,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isAvailable ? AppColors.errorRed : AppColors.successGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            disabledBackgroundColor: AppColors.divider,
          ),
          icon: toggling
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(isAvailable ? Icons.visibility_off : Icons.visibility),
          label: Text(
            isAvailable ? 'إيقاف (إخفاء عن العملاء)' : 'تفعيل (إظهار للعملاء)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ]);
  }
}

class _InfoTile extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _InfoTile(
      {required this.label,
      required this.value,
      this.valueColor = AppColors.accentOrange});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Inter')),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ]);
}
