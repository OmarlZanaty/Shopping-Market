import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/api_envelope.dart';
import '../../core/constants/api_constants.dart';
import '../orders/data/orders_api.dart';
import '../scanner/barcode_scanner_screen.dart';

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

  // ── Toggle ────────────────────────────────────────────────────────────────

  Future<void> _toggle(int index) async {
    final p = _products[index];
    final pid = p['id'].toString();
    try {
      final newVal = await OrdersApi().toggleAvailability(pid);
      if (!mounted) return;
      setState(() => _products[index] = {...p, 'is_available': newVal});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newVal ? 'تم تفعيل المنتج ✓' : 'تم إيقاف المنتج'),
        backgroundColor:
            newVal ? AppColors.successGreen : AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ: $e'),
        backgroundColor: AppColors.errorRed,
        behavior: SnackBarBehavior.floating,
      ));
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
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScannedProductSheet(
        barcode: barcode,
        onToggled: (pid, newVal) {
          // Update the product in the loaded list if it's visible
          final idx = _products.indexWhere((p) => p['id'].toString() == pid);
          if (idx != -1) {
            setState(() => _products[idx] = {..._products[idx], 'is_available': newVal});
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeCount = _products.where((p) => p['is_available'] == true).length;

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
                hintStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
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
              child: CircularProgressIndicator(color: AppColors.accentOrange))
          : _error != null && _products.isEmpty
              ? _ErrorView(
                  message: _error!,
                  onRetry: () => _loadPage(reset: true),
                )
              : Column(children: [
                  // Stats bar
                  _StatsBar(
                    active: activeCount,
                    inactive: _products.length - activeCount,
                    total: _total,
                    loaded: _products.length,
                  ),

                  // Product list
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
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              itemCount:
                                  _products.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _products.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.accentOrange,
                                          strokeWidth: 2),
                                    ),
                                  );
                                }
                                return _ProductRow(
                                  key: ValueKey(_products[i]['id']),
                                  product: _products[i],
                                  onToggle: () => _toggle(i),
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
  final int active, inactive, total, loaded;
  const _StatsBar(
      {required this.active,
      required this.inactive,
      required this.total,
      required this.loaded});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _Chip(label: 'نشط', value: '$active', color: AppColors.successGreen),
          Container(width: 1, height: 28, color: AppColors.divider),
          _Chip(label: 'موقوف', value: '$inactive', color: AppColors.errorRed),
          Container(width: 1, height: 28, color: AppColors.divider),
          _Chip(
              label: 'الإجمالي',
              value: '$total',
              color: AppColors.textSecondary),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Chip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 17, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
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
                style:
                    const TextStyle(color: AppColors.textSecondary)),
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

// ─── Product row ──────────────────────────────────────────────────────────────

class _ProductRow extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onToggle;
  const _ProductRow({super.key, required this.product, required this.onToggle});

  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isAvailable = p['is_available'] == true;
    final stockQty = (p['quantity_in_stock'] as num?)?.toInt() ?? 0;
    final price = (p['current_price'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAvailable
              ? AppColors.successGreen.withOpacity(0.25)
              : AppColors.divider,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          isAvailable ? Icons.check_circle : Icons.cancel_outlined,
          color: isAvailable
              ? AppColors.successGreen
              : AppColors.textSecondary,
          size: 22,
        ),
        title: Text(
          p['name_ar'] ?? p['name_en'] ?? '—',
          style: TextStyle(
            color:
                isAvailable ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(children: [
          if (price > 0)
            Text('${price.toStringAsFixed(1)} ج',
                style: const TextStyle(
                    color: AppColors.accentOrange,
                    fontSize: 11,
                    fontFamily: 'Inter')),
          if (price > 0) const SizedBox(width: 8),
          Text(
            stockQty > 0 ? 'مخزون: $stockQty' : 'نفذ',
            style: TextStyle(
                color: stockQty > 0
                    ? AppColors.textSecondary
                    : AppColors.errorRed,
                fontSize: 11),
          ),
        ]),
        trailing: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accentOrange))
            : Switch(
                value: isAvailable,
                activeColor: AppColors.successGreen,
                inactiveThumbColor: AppColors.textSecondary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) async {
                  setState(() => _loading = true);
                  try {
                    widget.onToggle();
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
              ),
      ),
    );
  }
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
      if (mounted)
        setState(() { _error = e.toString(); _loading = false; });
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
                : _ProductDetail(
                    product: _product!,
                    onToggle: _toggle,
                    toggling: _toggling,
                  ),
      ),
    );
  }
}

class _ProductDetail extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onToggle;
  final bool toggling;
  const _ProductDetail(
      {required this.product,
      required this.onToggle,
      required this.toggling});

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
              color:
                  isAvailable ? AppColors.successGreen : AppColors.errorRed),
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
      if ((product['barcode'] ?? '').isNotEmpty)
        Text(product['barcode'],
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
