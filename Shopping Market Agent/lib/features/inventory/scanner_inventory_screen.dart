import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/api_envelope.dart';
import '../orders/data/orders_api.dart';
import '../scanner/barcode_scanner_screen.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final _searchProvider = StateProvider<String>((ref) => '');

final _inventoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, query) async {
  return OrdersApi().listInventory(q: query.isEmpty ? null : query);
});

// ─── Screen ──────────────────────────────────────────────────────────────────

/// Shows all products with their availability status.
/// FAB opens the barcode scanner; scanned products are highlighted in a bottom sheet.
class ScannerInventoryScreen extends ConsumerStatefulWidget {
  const ScannerInventoryScreen({super.key});

  @override
  ConsumerState<ScannerInventoryScreen> createState() =>
      _ScannerInventoryScreenState();
}

class _ScannerInventoryScreenState
    extends ConsumerState<ScannerInventoryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Barcode scan ──────────────────────────────────────────────────────────

  Future<void> _openScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode == null || barcode.isEmpty || !mounted) return;
    _showScannedProduct(barcode);
  }

  Future<void> _showScannedProduct(String barcode) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScannedProductSheet(barcode: barcode),
    );
  }

  // ── Toggle ────────────────────────────────────────────────────────────────

  Future<void> _toggle(String productId, bool currentValue) async {
    try {
      final newValue = await OrdersApi().toggleAvailability(productId);
      if (!mounted) return;
      final q = ref.read(_searchProvider);
      ref.invalidate(_inventoryProvider(q));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newValue ? 'تم تفعيل المنتج ✓' : 'تم إيقاف المنتج'),
        backgroundColor:
            newValue ? AppColors.successGreen : AppColors.textSecondary,
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

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(_searchProvider);
    final inventoryAsync = ref.watch(_inventoryProvider(query));

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
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(_searchProvider.notifier).state = '';
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
              onChanged: (v) =>
                  ref.read(_searchProvider.notifier).state = v.trim(),
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
      body: inventoryAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off, color: AppColors.errorRed, size: 56),
            const SizedBox(height: 12),
            Text(e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.refresh(_inventoryProvider(query)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange),
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: AppColors.textSecondary, size: 64),
                    const SizedBox(height: 12),
                    Text(
                      query.isEmpty ? 'لا توجد منتجات' : 'لا نتائج لـ "$query"',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ]),
            );
          }

          // Stats bar
          final activeCount =
              products.where((p) => p['is_available'] == true).length;
          final inactiveCount = products.length - activeCount;

          return Column(children: [
            // Summary bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatChip(
                        label: 'نشط',
                        count: activeCount,
                        color: AppColors.successGreen),
                    Container(width: 1, height: 28, color: AppColors.divider),
                    _StatChip(
                        label: 'موقوف',
                        count: inactiveCount,
                        color: AppColors.errorRed),
                    Container(width: 1, height: 28, color: AppColors.divider),
                    _StatChip(
                        label: 'الإجمالي',
                        count: products.length,
                        color: AppColors.textSecondary),
                  ]),
            ),

            // Product list
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accentOrange,
                onRefresh: () async => ref.invalidate(_inventoryProvider(query)),
                child: ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 96), // 96 for FAB
                  itemCount: products.length,
                  itemBuilder: (_, i) {
                    final p = products[i];
                    return _ProductRow(
                      product: p,
                      onToggle: () =>
                          _toggle(p['id'].toString(), p['is_available'] == true),
                    );
                  },
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ─── Stat chip ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$count',
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      );
}

// ─── Product row ─────────────────────────────────────────────────────────────

class _ProductRow extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onToggle;
  const _ProductRow({required this.product, required this.onToggle});

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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAvailable
              ? AppColors.successGreen.withOpacity(0.3)
              : AppColors.divider,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isAvailable
                ? AppColors.successGreen.withOpacity(0.15)
                : AppColors.backgroundPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isAvailable ? Icons.check_circle : Icons.cancel_outlined,
            color: isAvailable ? AppColors.successGreen : AppColors.textSecondary,
            size: 24,
          ),
        ),
        title: Text(
          p['name_ar'] ?? p['name_en'] ?? '—',
          style: TextStyle(
            color: isAvailable ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(children: [
          Text(
            '${price.toStringAsFixed(1)} ج',
            style: const TextStyle(
                color: AppColors.accentOrange,
                fontSize: 12,
                fontFamily: 'Inter'),
          ),
          const SizedBox(width: 10),
          if (stockQty > 0)
            Text('مخزون: $stockQty',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11))
          else
            const Text('نفذ المخزون',
                style: TextStyle(color: AppColors.errorRed, fontSize: 11)),
        ]),
        trailing: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accentOrange))
            : Switch(
                value: isAvailable,
                activeColor: AppColors.successGreen,
                inactiveThumbColor: AppColors.textSecondary,
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

// ─── Scanned product bottom sheet ─────────────────────────────────────────────

class _ScannedProductSheet extends StatefulWidget {
  final String barcode;
  const _ScannedProductSheet({required this.barcode});

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
      final newValue =
          await OrdersApi().toggleAvailability(_product!['id'].toString());
      if (!mounted) return;
      setState(() {
        _product!['is_available'] = newValue;
        _toggling = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newValue ? 'تم تفعيل المنتج ✓' : 'تم إيقاف المنتج'),
        backgroundColor:
            newValue ? AppColors.successGreen : AppColors.textSecondary,
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
                child: CircularProgressIndicator(color: AppColors.accentOrange))
            : _error != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.errorRed, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'لم يُعثر على منتج بهذا الباركود',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
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
    final stockQty =
        (product['quantity_in_stock'] as num?)?.toInt() ?? 0;
    final price =
        (product['current_price'] as num?)?.toDouble() ?? 0.0;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),

      // Status badge
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isAvailable
              ? AppColors.successGreen.withOpacity(0.15)
              : AppColors.errorRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isAvailable ? AppColors.successGreen : AppColors.errorRed,
          ),
        ),
        child: Text(
          isAvailable ? 'متاح للعملاء' : 'موقوف عن العملاء',
          style: TextStyle(
            color: isAvailable ? AppColors.successGreen : AppColors.errorRed,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Name
      Text(
        product['name_ar'] ?? product['name_en'] ?? '—',
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      if ((product['barcode'] ?? '').isNotEmpty)
        Text(product['barcode'],
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'Inter')),

      const SizedBox(height: 20),

      // Info row
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _InfoTile(label: 'السعر', value: '${price.toStringAsFixed(1)} ج'),
        _InfoTile(
            label: 'المخزون',
            value: '$stockQty',
            valueColor:
                stockQty > 0 ? AppColors.successGreen : AppColors.errorRed),
      ]),

      const SizedBox(height: 24),

      // Toggle button
      SizedBox(
        width: double.infinity,
        height: 52,
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
                  width: 18,
                  height: 18,
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
  final String label;
  final String value;
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
