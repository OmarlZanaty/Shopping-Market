import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_typography.dart';
import '../data/order_models.dart';
import '../data/orders_providers.dart';

/// Preparer-only picking flow. Each row has: checkbox, image, name, stepper,
/// status icon, three-dot menu (price/unavailable/scan).
class PickingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PickingScreen({super.key, required this.orderId});

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends ConsumerState<PickingScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('تجميع الطلب')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentOrange)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (order) {
          final picked = order.items.where((i) =>
              i.status == 'picked' || i.status == 'substituted' ||
              i.status == 'price_adjusted' || i.status == 'weight_adjusted'
          ).length;
          final total = order.items.length;
          final pct = total > 0 ? picked / total : 0.0;

          final filtered = order.items.where((i) =>
            _search.isEmpty || i.nameAr.contains(_search)
          ).toList();

          return Column(children: [
            Container(
              padding: const EdgeInsets.all(AppDimensions.paddingH),
              color: AppColors.backgroundSecondary,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text('تم تجميع $picked من $total أصناف',
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Text('${(pct * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: AppColors.accentOrange,
                          fontWeight: FontWeight.bold, fontFamily: 'Inter')),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: AppColors.backgroundPrimary,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accentOrange),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'بحث في الأصناف',
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ItemRow(item: filtered[i], orderId: widget.orderId),
              ),
            ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accentOrange,
        onPressed: () {
          // Hook to shared scanner — pushes a route that returns barcode string.
          Navigator.pushNamed(context, '/scanner');
        },
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

class _ItemRow extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final String orderId;
  const _ItemRow({required this.item, required this.orderId});
  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  late double _qty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _qty = widget.item.actualQty ?? widget.item.requestedQty;
  }

  Future<void> _setActualQty(double v) async {
    setState(() { _qty = v; _busy = true; });
    try {
      await ref.read(ordersApiProvider).setActualQty(widget.orderId, widget.item.id, v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markUnavailable() async {
    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).markUnavailable(widget.orderId, widget.item.id);
      ref.refresh(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final changed = (_qty - it.requestedQty).abs() > 0.001;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: changed
            ? AppColors.warning.withOpacity(0.1)
            : AppColors.backgroundSecondary,
        border: Border.all(
          color: changed ? AppColors.warning : Colors.transparent,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(children: [
        Row(children: [
          _StatusIcon(status: it.status),
          const SizedBox(width: 8),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(8),
              image: it.imageUrl != null
                  ? DecorationImage(image: NetworkImage(it.imageUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: it.imageUrl == null
                ? const Icon(Icons.image, color: AppColors.textSecondary, size: 20)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.nameAr, style: AppTypography.body),
              if (it.barcode != null)
                Text(it.barcode!,
                    style: AppTypography.smallLabel.copyWith(fontFamily: 'Inter')),
            ]),
          ),
          PopupMenuButton<String>(
            color: AppColors.backgroundSecondary,
            onSelected: (v) async {
              if (v == 'unavailable') await _markUnavailable();
              if (v == 'price') _showPriceSheet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'price', child: Text('تعديل السعر')),
              PopupMenuItem(value: 'unavailable', child: Text('غير متوفر')),
            ],
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('${it.requestedQty.toStringAsFixed(it.isWeightBased ? 2 : 0)} ${it.unitType}',
              style: AppTypography.smallLabel),
          const Spacer(),
          _Stepper(
            value: _qty,
            step: it.isWeightBased ? 0.1 : 1.0,
            onChanged: _busy ? null : _setActualQty,
          ),
        ]),
      ]),
    );
  }

  void _showPriceSheet() {
    final priceCtrl = TextEditingController(text: widget.item.unitPrice.toStringAsFixed(2));
    String reason = 'تغيير سعر المورد';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعديل السعر', style: AppTypography.sectionHeader),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'السعر الجديد'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: reason,
            decoration: const InputDecoration(labelText: 'السبب'),
            items: const [
              DropdownMenuItem(value: 'تغيير سعر المورد', child: Text('تغيير سعر المورد')),
              DropdownMenuItem(value: 'خطأ في النظام', child: Text('خطأ في النظام')),
              DropdownMenuItem(value: 'انتهى العرض', child: Text('انتهى العرض')),
              DropdownMenuItem(value: 'سبب آخر', child: Text('سبب آخر')),
            ],
            onChanged: (v) { if (v != null) reason = v; },
            dropdownColor: AppColors.backgroundSecondary,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final p = double.tryParse(priceCtrl.text);
                if (p == null) return;
                Navigator.pop(sheetCtx);
                try {
                  await ref.read(ordersApiProvider).adjustPrice(
                      widget.orderId, widget.item.id, p, reason);
                  ref.refresh(orderDetailProvider(widget.orderId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم الإرسال للعميل للموافقة'),
                    backgroundColor: AppColors.successGreen,
                  ));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(e.toString()),
                    backgroundColor: AppColors.errorRed,
                  ));
                }
              },
              child: const Text('إرسال للموافقة'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});
  @override
  Widget build(BuildContext context) {
    IconData icon; Color color;
    switch (status) {
      case 'picked':           icon = Icons.check_circle; color = AppColors.successGreen; break;
      case 'unavailable':      icon = Icons.cancel; color = AppColors.errorRed; break;
      case 'substituted':      icon = Icons.swap_horiz; color = AppColors.infoBlue; break;
      case 'price_adjusted':
      case 'weight_adjusted':  icon = Icons.pending; color = AppColors.warning; break;
      default:                 icon = Icons.radio_button_unchecked; color = AppColors.textSecondary;
    }
    return Icon(icon, color: color, size: 20);
  }
}

class _Stepper extends StatelessWidget {
  final double value;
  final double step;
  final ValueChanged<double>? onChanged;
  const _Stepper({required this.value, required this.step, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentGold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 18, color: AppColors.accentGold),
          onPressed: onChanged == null ? null : () => onChanged!((value - step).clamp(0, 9999)),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text(
            value.toStringAsFixed(step >= 1 ? 0 : 1),
            style: const TextStyle(
              color: AppColors.accentGold,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18, color: AppColors.accentGold),
          onPressed: onChanged == null ? null : () => onChanged!(value + step),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }
}
