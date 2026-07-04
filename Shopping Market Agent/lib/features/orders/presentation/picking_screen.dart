import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_typography.dart';
import '../data/order_models.dart';
import '../data/orders_providers.dart';

class PickingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PickingScreen({super.key, required this.orderId});

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends ConsumerState<PickingScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  final Set<String> _togglingIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isPicked(OrderItemModel i) =>
      i.status == 'picked' ||
      i.status == 'substituted' ||
      i.status == 'price_adjusted' ||
      i.status == 'weight_adjusted' ||
      i.status == 'unavailable' ||
      (i.actualQty != null && i.actualQty! > 0);

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('تجميع الطلب')),
      body: Builder(builder: (context) {
        // Prefer the last-good order so a transient refresh failure (e.g. a
        // dropped connection after a rapid tap) doesn't blow away the screen.
        final order = orderAsync.valueOrNull;
        if (order == null) {
          return orderAsync.hasError
              ? Center(child: Text(orderAsync.error.toString()))
              : const Center(
                  child: CircularProgressIndicator(color: AppColors.accentOrange));
        }
        {
          final picked = order.items.where(_isPicked).length;
          final total = order.items.length;
          final pct = total > 0 ? picked / total : 0.0;

          final filtered = order.items
              .where((i) =>
                  _search.isEmpty ||
                  i.nameAr.contains(_search) ||
                  (i.barcode != null && i.barcode!.contains(_search)))
              .toList();

          final pickedItems = filtered.where(_isPicked).toList();
          final unpickedItems = filtered.where((i) => !_isPicked(i)).toList();

          return CustomScrollView(
            slivers: [
              // ── Stats + Search header ──────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingH),
                  color: AppColors.backgroundSecondary,
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          'تم تجميع $picked من $total أصناف',
                          style: AppTypography.body
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: Text(
                          '${(pct * 100).toStringAsFixed(0)}%',
                          key: ValueKey(picked),
                          style: const TextStyle(
                            color: AppColors.accentOrange,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      builder: (_, v, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 8,
                          backgroundColor: AppColors.backgroundPrimary,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.accentOrange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'بحث باسم الصنف أو الباركود',
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textSecondary),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: AppColors.textSecondary),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _search = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Section: تم تحضيره ─────────────────────────────────────
              if (pickedItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    label: 'تم تحضيره',
                    count: pickedItems.length,
                    color: AppColors.successGreen,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final item = pickedItems[i];
                        return Padding(
                          key: ValueKey('picked_${item.id}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AnimatedItemEntry(
                            child: _ItemRow(
                              item: item,
                              orderId: widget.orderId,
                              onToggle: () => _handleToggle(item),
                              toggling: _togglingIds.contains(item.id.toString()),
                            ),
                          ),
                        );
                      },
                      childCount: pickedItems.length,
                    ),
                  ),
                ),
              ],

              // ── Section: لم يتم تحضيره بعد ────────────────────────────
              if (unpickedItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    label: 'لم يتم تحضيره بعد',
                    count: unpickedItems.length,
                    color: AppColors.textSecondary,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final item = unpickedItems[i];
                        return Padding(
                          key: ValueKey('unpicked_${item.id}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _AnimatedItemEntry(
                            child: _ItemRow(
                              item: item,
                              orderId: widget.orderId,
                              onToggle: () => _handleToggle(item),
                              toggling: _togglingIds.contains(item.id.toString()),
                            ),
                          ),
                        );
                      },
                      childCount: unpickedItems.length,
                    ),
                  ),
                ),
              ],

              if (filtered.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('لا توجد أصناف',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
            ],
          );
        }
      }),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accentOrange,
        onPressed: () async {
          final barcode = await context.push<String>('/scanner');
          if (barcode == null || barcode.isEmpty || !mounted) return;
          await _handleScannedBarcode(barcode);
        },
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }

  Future<void> _handleToggle(OrderItemModel item) async {
    final id = item.id.toString();
    if (_togglingIds.contains(id)) return;
    setState(() => _togglingIds.add(id));
    try {
      if (_isPicked(item)) {
        // Deselect: reset the item (clears status→pending and actual_qty→null).
        // Falls back to qty=0 on servers without the reset route.
        try {
          await ref.read(ordersApiProvider).resetItem(widget.orderId, item.id);
        } catch (_) {
          await ref.read(ordersApiProvider)
              .setActualQty(widget.orderId, item.id, 0);
        }
      } else {
        await ref.read(ordersApiProvider)
            .setActualQty(widget.orderId, item.id, item.requestedQty);
      }
      ref.refresh(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()),
                backgroundColor: AppColors.errorRed));
      }
    } finally {
      if (mounted) setState(() => _togglingIds.remove(id));
    }
  }

  Future<void> _handleScannedBarcode(String code) async {
    final order = ref.read(orderDetailProvider(widget.orderId)).valueOrNull;
    if (order == null) return;

    final normalized = code.trim();
    OrderItemModel? match;
    for (final it in order.items) {
      if (it.barcode != null && it.barcode!.trim() == normalized) {
        match = it;
        break;
      }
    }

    if (match == null) {
      _searchCtrl.text = normalized;
      setState(() => _search = normalized);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('الباركود "$normalized" غير موجود في الطلب'),
          backgroundColor: AppColors.warning,
        ));
      }
      return;
    }

    try {
      await ref.read(ordersApiProvider).setActualQty(
            widget.orderId, match.id, match.requestedQty);
      // ignore: unused_result
      ref.refresh(orderDetailProvider(widget.orderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تجميع: ${match.nameAr}'),
        backgroundColor: AppColors.successGreen,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.errorRed,
      ));
    }
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label,
            style: AppTypography.sectionHeader.copyWith(color: color)),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(count),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter')),
          ),
        ),
      ]),
    );
  }
}

// ── Entrance animation wrapper ─────────────────────────────────────────────────

class _AnimatedItemEntry extends StatefulWidget {
  final Widget child;
  const _AnimatedItemEntry({required this.child});

  @override
  State<_AnimatedItemEntry> createState() => _AnimatedItemEntryState();
}

class _AnimatedItemEntryState extends State<_AnimatedItemEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, -0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ── Item row ──────────────────────────────────────────────────────────────────

class _ItemRow extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final String orderId;
  final VoidCallback onToggle;
  final bool toggling;
  const _ItemRow(
      {required this.item, required this.orderId, required this.onToggle,
       this.toggling = false});
  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  late double _qty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _qty = (widget.item.actualQty != null && widget.item.actualQty! > 0)
        ? widget.item.actualQty!
        : widget.item.requestedQty;
  }

  @override
  void didUpdateWidget(_ItemRow old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _qty = (widget.item.actualQty != null && widget.item.actualQty! > 0)
        ? widget.item.actualQty!
        : widget.item.requestedQty;
    }
  }

  Future<void> _setActualQty(double v) async {
    setState(() {
      _qty = v;
      _busy = true;
    });
    try {
      await ref
          .read(ordersApiProvider)
          .setActualQty(widget.orderId, widget.item.id, v);
      ref.refresh(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markUnavailable() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(ordersApiProvider)
          .markUnavailable(widget.orderId, widget.item.id);
      ref.refresh(orderDetailProvider(widget.orderId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetItem() async {
    setState(() => _busy = true);
    try {
      try {
        await ref
            .read(ordersApiProvider)
            .resetItem(widget.orderId, widget.item.id);
      } catch (_) {
        // Fallback for servers that don't expose the reset route yet:
        // clear the picked quantity via the qty endpoint instead.
        await ref
            .read(ordersApiProvider)
            .setActualQty(widget.orderId, widget.item.id, 0);
      }
      ref.refresh(orderDetailProvider(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة الصنف للفحص'),
            backgroundColor: AppColors.infoBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isPicked =>
      widget.item.status == 'picked' ||
      widget.item.status == 'substituted' ||
      widget.item.status == 'price_adjusted' ||
      widget.item.status == 'weight_adjusted' ||
      widget.item.status == 'unavailable' ||
      (widget.item.actualQty != null && widget.item.actualQty! > 0);

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final changed = (_qty - it.requestedQty).abs() > 0.001;
    // Price per unit (adjusted price if the agent changed it, else the base
    // price) and the live line total that tracks the quantity stepper.
    final unitPrice = it.effectivePrice;
    final lineTotal = unitPrice * _qty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isPicked
            ? AppColors.successGreen.withOpacity(0.08)
            : changed
                ? AppColors.warning.withOpacity(0.1)
                : AppColors.backgroundSecondary,
        border: Border.all(
          color: _isPicked
              ? AppColors.successGreen.withOpacity(0.3)
              : changed
                  ? AppColors.warning
                  : Colors.transparent,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(children: [
        Row(children: [
          // Tappable selection circle / check icon
          GestureDetector(
            onTap: (_busy || widget.toggling) ? null : widget.onToggle,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: widget.toggling
                  ? const SizedBox(
                      key: ValueKey('toggling'),
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accentOrange),
                    )
                  : _StatusIcon(
                      key: ValueKey('${it.status}_${it.actualQty}'),
                      status: it.status,
                      actualQty: it.actualQty,
                      interactive: true,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(8),
              image: it.imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(it.imageUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: it.imageUrl == null
                ? const Icon(Icons.image,
                    color: AppColors.textSecondary, size: 20)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.nameAr, style: AppTypography.body),
                  if (it.barcode != null)
                    Text(it.barcode!,
                        style: AppTypography.smallLabel
                            .copyWith(fontFamily: 'Inter')),
                ]),
          ),
          PopupMenuButton<String>(
            color: AppColors.backgroundSecondary,
            onSelected: (v) async {
              if (v == 'unavailable') await _markUnavailable();
              if (v == 'price') _showPriceSheet();
              if (v == 'substitute') _showSubstituteSheet();
              if (v == 'reset') await _resetItem();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'price', child: Text('تعديل السعر')),
              const PopupMenuItem(
                value: 'substitute',
                child: Row(children: [
                  Icon(Icons.swap_horiz, size: 16, color: AppColors.infoBlue),
                  SizedBox(width: 6),
                  Text('إقتراح بديل للعميل'),
                ]),
              ),
              const PopupMenuItem(
                  value: 'unavailable', child: Text('غير متوفر')),
              if (widget.item.status == 'unavailable' ||
                  widget.item.status == 'picked')
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.refresh,
                          size: 16, color: AppColors.infoBlue),
                      SizedBox(width: 6),
                      Text('إعادة الفحص',
                          style: TextStyle(color: AppColors.infoBlue)),
                    ],
                  ),
                ),
            ],
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(
            it.isWeighed
                ? 'المطلوب: ${it.qtyLabel(it.requestedQty)}'
                : '${it.requestedQty.toStringAsFixed(0)} قطعة',
            style: AppTypography.smallLabel,
          ),
          const SizedBox(width: 8),
          // Unit price (per piece / per kg)
          Text(
            it.isWeighed
                ? '× ${unitPrice.toStringAsFixed(2)} ج/كجم'
                : '× ${unitPrice.toStringAsFixed(2)} ج',
            style: AppTypography.smallLabel.copyWith(fontFamily: 'Inter'),
          ),
          const Spacer(),
          _Stepper(
            value: _qty,
            step: it.isWeighed ? 0.1 : 1.0,
            weighed: it.isWeighed,
            onChanged: _busy ? null : _setActualQty,
          ),
        ]),
        const SizedBox(height: 8),
        // Live line total — recomputes whenever the quantity changes.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentGold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الإجمالي', style: AppTypography.smallLabel),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '${lineTotal.toStringAsFixed(2)} ج',
                  key: ValueKey(lineTotal),
                  style: const TextStyle(
                    color: AppColors.accentGold,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  void _showPriceSheet() {
    final priceCtrl =
        TextEditingController(text: widget.item.unitPrice.toStringAsFixed(2));
    String reason = 'تغيير سعر المورد';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعديل السعر', style: AppTypography.sectionHeader),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'السعر الجديد'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: reason,
            decoration: const InputDecoration(labelText: 'السبب'),
            items: const [
              DropdownMenuItem(
                  value: 'تغيير سعر المورد',
                  child: Text('تغيير سعر المورد')),
              DropdownMenuItem(
                  value: 'خطأ في النظام', child: Text('خطأ في النظام')),
              DropdownMenuItem(
                  value: 'انتهى العرض', child: Text('انتهى العرض')),
              DropdownMenuItem(
                  value: 'سبب آخر', child: Text('سبب آخر')),
            ],
            onChanged: (v) {
              if (v != null) reason = v;
            },
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
                  await ref
                      .read(ordersApiProvider)
                      .adjustPrice(widget.orderId, widget.item.id, p, reason);
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

  void _showSubstituteSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      isScrollControlled: true,
      builder: (sheetCtx) => _SubstitutePicker(
        originalName: widget.item.nameAr,
        onSubmit: (picks) async {
          Navigator.pop(sheetCtx);
          if (picks.isEmpty) return;
          int sent = 0;
          final failed = <String>[];
          for (final p in picks) {
            try {
              await ref
                  .read(ordersApiProvider)
                  .substitute(widget.orderId, widget.item.id, p.id);
              sent++;
            } catch (_) {
              failed.add(p.name);
            }
          }
          // ignore: unused_result
          ref.refresh(orderDetailProvider(widget.orderId));
          if (!mounted) return;
          if (failed.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'تم إرسال $sent اقتراح${sent > 1 ? "ات" : ""} للعميل'),
              backgroundColor: AppColors.successGreen,
            ));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('تم إرسال $sent — فشل: ${failed.join("، ")}'),
              backgroundColor: AppColors.warning,
            ));
          }
        },
      ),
    );
  }
}

// ── Substitute picker ─────────────────────────────────────────────────────────

class _SubPick {
  final String id;
  final String name;
  const _SubPick(this.id, this.name);
}

class _SubstitutePicker extends ConsumerStatefulWidget {
  final String originalName;
  final void Function(List<_SubPick> picks) onSubmit;
  const _SubstitutePicker(
      {required this.originalName, required this.onSubmit});

  @override
  ConsumerState<_SubstitutePicker> createState() => _SubstitutePickerState();
}

class _SubstitutePickerState extends ConsumerState<_SubstitutePicker> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  final Map<String, String> _selected = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(ordersApiProvider)
          .listInventory(q: q, available: true);
      if (!mounted) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static const int _maxPicks = 3;

  // Opens the camera scanner; on a successful scan, fills the search box with
  // the barcode and runs the search so the agent can pick a substitute by scan.
  Future<void> _scanBarcode() async {
    final code = await context.push<String>('/scanner');
    if (code == null || code.trim().isEmpty || !mounted) return;
    final normalized = code.trim();
    _ctrl.text = normalized;
    _search(normalized);
  }

  void _toggle(String id, String name) {
    if (_selected.containsKey(id)) {
      setState(() => _selected.remove(id));
      return;
    }
    if (_selected.length >= _maxPicks) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يمكنك اقتراح حتى 3 بدائل فقط'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    setState(() => _selected[id] = name);
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          const Text('اختر منتجات بديلة', style: AppTypography.sectionHeader),
          const SizedBox(height: 4),
          Text('بديل لـ: ${widget.originalName}',
              style: AppTypography.smallLabel),
          const SizedBox(height: 4),
          const Text(
            'اختر حتى 3 بدائل — العميل سيختار واحد منها',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            onChanged: _search,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'بحث باسم المنتج أو الباركود',
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: AppColors.accentOrange),
                tooltip: 'مسح الباركود',
                onPressed: _scanBarcode,
              ),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _selected.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Chip(
                            backgroundColor: AppColors.accentOrange,
                            label: Text(e.value,
                                style:
                                    const TextStyle(color: Colors.white)),
                            deleteIconColor: Colors.white,
                            onDeleted: () => _toggle(e.key, e.value),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accentOrange))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.errorRed)))
                    : _results.isEmpty
                        ? const Center(
                            child: Text('لا توجد منتجات',
                                style: TextStyle(
                                    color: AppColors.textSecondary)))
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: AppColors.divider),
                            itemBuilder: (_, i) {
                              final p = _results[i];
                              final id = (p['id'] ?? '').toString();
                              final nameAr = (p['name_ar'] ??
                                      p['name'] ??
                                      '')
                                  .toString();
                              final price = (p['current_price'] ??
                                      p['price'] ??
                                      '')
                                  .toString();
                              final img = (p['image_url'] ??
                                      p['image'] ??
                                      '')
                                  .toString();
                              // Weight-based substitutes are priced per kg.
                              final unit = (p['unit_type'] ?? p['sell_unit'] ?? '')
                                  .toString();
                              final subWeighed = p['is_weight_based'] == true ||
                                  unit == 'kg' || unit == 'gram' || unit == 'liter';
                              final checked = _selected.containsKey(id);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundPrimary,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    image: img.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(img),
                                            fit: BoxFit.cover)
                                        : null,
                                  ),
                                  child: img.isEmpty
                                      ? const Icon(Icons.image,
                                          color: AppColors.textSecondary,
                                          size: 20)
                                      : null,
                                ),
                                title: Text(nameAr,
                                    style: AppTypography.body),
                                subtitle: price.isNotEmpty
                                    ? Text(subWeighed ? '$price ج/كجم' : '$price ج',
                                        style: AppTypography.smallLabel)
                                    : null,
                                trailing: Checkbox(
                                  value: checked,
                                  activeColor: AppColors.accentOrange,
                                  onChanged: id.isEmpty
                                      ? null
                                      : (_) => _toggle(id, nameAr),
                                ),
                                onTap: id.isEmpty
                                    ? null
                                    : () => _toggle(id, nameAr),
                              );
                            },
                          ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentOrange,
                disabledBackgroundColor:
                    AppColors.accentOrange.withOpacity(0.4),
              ),
              onPressed: count == 0
                  ? null
                  : () => widget.onSubmit(_selected.entries
                      .map((e) => _SubPick(e.key, e.value))
                      .toList()),
              child: Text(
                count == 0
                    ? 'اختر منتج بديل واحد على الأقل'
                    : 'إرسال $count اقتراح${count > 1 ? "ات" : ""} للعميل',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Status icon ───────────────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final String status;
  final double? actualQty;
  final bool interactive;
  const _StatusIcon(
      {super.key, required this.status, this.actualQty, this.interactive = false});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    // Treat as picked if actualQty is set (backend keeps status="pending")
    final effectivelPicked = status == 'picked' ||
        (actualQty != null && actualQty! > 0);
    switch (status) {
      case 'unavailable':
        icon = Icons.cancel;
        color = AppColors.errorRed;
        break;
      case 'substituted':
        icon = Icons.swap_horiz;
        color = AppColors.infoBlue;
        break;
      case 'price_adjusted':
      case 'weight_adjusted':
        icon = Icons.pending;
        color = AppColors.warning;
        break;
      default:
        if (effectivelPicked) {
          icon = Icons.check_circle;
          color = AppColors.successGreen;
        } else {
          icon = Icons.radio_button_unchecked;
          color = interactive
              ? AppColors.accentOrange.withOpacity(0.6)
              : AppColors.textSecondary;
        }
    }
    return Icon(icon, color: color, size: 28);
  }
}

// ── Stepper ───────────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final double value;
  final double step;
  final bool weighed;
  final ValueChanged<double>? onChanged;
  const _Stepper(
      {required this.value, required this.step, required this.onChanged,
       this.weighed = false});

  // Weighed values render as grams (< 1 kg) or kg; piece values as a count.
  String get _label {
    if (!weighed) return value.toStringAsFixed(0);
    if (value < 1) return '${(value * 1000).round()} جم';
    final s = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s كجم';
  }
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
          onPressed: onChanged == null
              ? null
              : () => onChanged!((value - step).clamp(0, 9999)),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        Container(
          width: weighed ? 64 : 44,
          alignment: Alignment.center,
          child: Text(
            _label,
            style: const TextStyle(
              color: AppColors.accentGold,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18, color: AppColors.accentGold),
          onPressed:
              onChanged == null ? null : () => onChanged!(value + step),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ]),
    );
  }
}
