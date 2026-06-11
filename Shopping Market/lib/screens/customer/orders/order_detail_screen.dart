import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';
import '../../../widgets/shared/product_card.dart';
import '../../../widgets/shared/payment_choice_sheet.dart';
import '../payment/paymob_webview_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _api = ApiService();
  OrderModel? _order;
  bool _loading = true;
  int _productRating = 5;
  int _deliveryRating = 5;
  final _commentCtrl = TextEditingController();
  bool _showRating = false;
  bool _cancelling = false;

  // The customer can cancel only before the order leaves for delivery.
  static const _cancellableStatuses = {'new', 'accepted', 'preparing'};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _cancelOrder() async {
    final o = _order;
    if (o == null || _cancelling) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('هل أنت متأكد من إلغاء هذا الطلب؟',
              style: TextStyle(fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'سبب الإلغاء (اختياري)',
              hintStyle: const TextStyle(fontFamily: 'Cairo'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      await _api.cancelOrder(o.orderId, reason: reasonCtrl.text.trim());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم إلغاء الطلب', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.mint,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر إلغاء الطلب — قد يكون خرج للتوصيل',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _load() async {
    try {
      final order = await _api.getOrder(widget.orderId);
      if (mounted) setState(() { _order = order; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _approveAdjustment(int adjId, bool approved) async {
    if (_order == null) return;
    try {
      final result = await _api.approveAdjustmentV2(_order!.orderId, adjId, approved);
      _load();

      if (!mounted) return;

      // ── Wallet refund notification ────────────────────────────────────────
      final walletRefund = result['wallet_refund'];
      if (walletRefund != null && (double.tryParse(walletRefund.toString()) ?? 0) > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم إضافة $walletRefund جنيه لمحفظتك 💰',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.mint,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
        return;
      }

      // ── Payment required for price increase ───────────────────────────────
      final paymentRequired = result['payment_required'] == true;
      if (approved && paymentRequired) {
        final amountOwed = result['amount_owed']?.toString() ?? '0';
        final choice = await showPaymentChoiceSheet(
          context,
          amountEgp: amountOwed,
        );
        if (!mounted) return;

        if (choice == PaymentChoice.card) {
          // Launch Paymob WebView
          try {
            final payResult = await _api.initiateAdjustmentPayment(
              orderId: _order!.id,
              adjustmentId: adjId,
            );
            final iframeUrl = payResult['iframe_url'] as String?;
            if (iframeUrl == null || iframeUrl.isEmpty) throw 'No iframe URL';

            final paid = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => PaymobWebviewScreen(
                  iframeUrl: iframeUrl,
                  amountEgp: amountOwed,
                ),
              ),
            );

            if (!mounted) return;
            if (paid == true) {
              _load();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('تم الدفع بنجاح ✅',
                    style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: AppColors.mint,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('لم يكتمل الدفع — يمكنك المحاولة لاحقاً',
                    style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
            }
          } catch (_) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('فشل الاتصال بخدمة الدفع — حاول مرة أخرى',
                  style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
          }
        } else if (choice == PaymentChoice.cash) {
          // Customer chose cash — just acknowledge
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('سيتم تحصيل $amountOwed جنيه نقداً عند التسليم 💵',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.sky,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
        }
        return;
      }

      // ── Simple approve/reject feedback ────────────────────────────────────
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved ? 'تم القبول ✅' : 'تم الرفض ❌',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: approved ? AppColors.mint : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('حدث خطأ — حاول مرة أخرى',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _submitRating() async {
    try {
      await _api.rateOrder(widget.orderId, productRating: _productRating, deliveryRating: _deliveryRating, comment: _commentCtrl.text);
      if (mounted) { setState(() => _showRating = false); _load(); }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    if (_order == null) return const Scaffold(body: Center(child: Text('الطلب غير موجود', style: TextStyle(fontFamily: 'Cairo'))));
    final o = _order!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('طلب #${o.orderId}', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.midnight,
        actions: [
          if (o.status == 'out_for_delivery')
            TextButton(onPressed: () => context.push('/orders/${o.orderId}/track'),
              child: const Text('تتبع 📍', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, color: AppColors.coral,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          // Status card
          _card(child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: OrderStatus.color(o.status).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(OrderStatus.icon(o.status), color: OrderStatus.color(o.status))),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(OrderStatus.labelAr(o.status), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Cairo')),
              Text(o.orderId, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.w500)),
            ]),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: OrderStatus.color(o.status).withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: OrderStatus.color(o.status).withOpacity(0.3))),
              child: Text(OrderStatus.labelAr(o.status), style: TextStyle(color: OrderStatus.color(o.status), fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
          ])),
          const SizedBox(height: 10),

          // ── Pending adjustments ────────────────────────────────────────
          // We group substitute_suggested adjustments by the order_item they
          // belong to and render them as ONE row of up to 3 product cards
          // (the customer picks one — the backend auto-rejects the others).
          // Non-substitute adjustments keep the original old→new card style.
          ..._buildPendingAdjustments(o),

          // ── Items ───────────────────────────────────────────────────────
          // Explicit dark colors EVERYWHERE — the global theme is dark
          // (Brightness.dark), so any Text on a white card without a color
          // renders white-on-white and the name disappears.
          _card(title: 'الأصناف (${o.items.length})', child: Column(children: o.items.map((item) {
            final hasImage = (item.productImageUrl ?? '').isNotEmpty;
            final unitLabel = item.status == 'substituted' ? 'بديل' : null;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Product image (or placeholder bag)
                Container(
                  width: 56, height: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.ice,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: hasImage
                      ? Image.network(item.productImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.shopping_bag_outlined,
                              color: AppColors.sky, size: 26))
                      : const Icon(Icons.shopping_bag_outlined,
                          color: AppColors.sky, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name — explicit midnight color so it shows on white.
                    Row(children: [
                      Expanded(child: Text(
                        item.productNameAr.isNotEmpty
                            ? item.productNameAr
                            : item.productNameEn,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.midnight,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo',
                            fontSize: 14),
                      )),
                      if (unitLabel != null) Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('بديل',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${item.effectiveQty.toStringAsFixed(item.effectiveQty == item.effectiveQty.roundToDouble() ? 0 : 1)} × ${item.effectivePrice.toStringAsFixed(2)} ج',
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontFamily: 'Cairo',
                            fontSize: 12)),
                    if ((item.productBarcode ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.productBarcode!,
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontFamily: 'Cairo',
                                fontSize: 10)),
                      ),
                  ],
                )),
                const SizedBox(width: 8),
                Text('${item.lineTotal.toStringAsFixed(2)} ج',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.sapphire,
                        fontFamily: 'Cairo',
                        fontSize: 14)),
              ]),
            );
          }).toList())),
          const SizedBox(height: 10),

          // Summary
          _card(title: 'ملخص الفاتورة', child: Column(children: [
            _row('المنتجات', '${o.subtotal.toStringAsFixed(2)} ج'),
            _row('التوصيل', '${o.deliveryFee.toStringAsFixed(2)} ج'),
            if (o.totalSavings > 0) _row('الوفر', '-${o.totalSavings.toStringAsFixed(2)} ج', color: AppColors.mint),
            const Divider(),
            _row('الإجمالي', '${o.totalAmount.toStringAsFixed(2)} ج', bold: true),
            _row('طريقة الدفع', _payLabel(o.paymentMethod)),
            if (o.pointsEarned > 0) _row('نقاط مكتسبة', '+${o.pointsEarned} ⭐', color: AppColors.gold),
          ])),
          const SizedBox(height: 10),

          // Delivery address — explicit dark color for the main address line
          // (was invisible: theme is dark, card is white, no color set).
          _card(title: 'عنوان التوصيل', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.deliveryAddress,
                style: const TextStyle(
                    color: AppColors.midnight,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            if (o.buildingNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'عمارة ${o.buildingNumber} - دور ${o.floorNumber} - شقة ${o.apartmentNumber}',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontFamily: 'Cairo'),
                ),
              ),
            if (o.landmark.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('علامة مميزة: ${o.landmark}',
                    style: const TextStyle(
                        color: AppColors.sky,
                        fontSize: 12,
                        fontFamily: 'Cairo')),
              ),
          ])),
          const SizedBox(height: 10),

          // Cancel — available until the order goes out for delivery.
          if (_cancellableStatuses.contains(o.status))
            SizedBox(width: double.infinity, height: 50, child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _cancelling
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                  : const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الطلب',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              onPressed: _cancelling ? null : _cancelOrder,
            )),
          if (_cancellableStatuses.contains(o.status)) const SizedBox(height: 10),

          // Rating
          if (o.status == 'delivered' && o.rating == null && !_showRating)
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.star_rounded, color: Colors.white),
              label: const Text('قيّم طلبك واحصل على 5 نقاط ⭐', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              onPressed: () => setState(() => _showRating = true))),

          if (_showRating) _card(title: 'تقييم الطلب', child: Column(children: [
            _ratingRow('جودة المنتجات', _productRating, (v) => setState(() => _productRating = v)),
            const SizedBox(height: 12),
            _ratingRow('سرعة التوصيل', _deliveryRating, (v) => setState(() => _deliveryRating = v)),
            const SizedBox(height: 12),
            TextField(controller: _commentCtrl, maxLines: 2,
              decoration: InputDecoration(hintText: 'تعليقك...', hintStyle: const TextStyle(fontFamily: 'Cairo'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _submitRating,
              child: const Text('إرسال التقييم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)))),
          ])),

          if (o.rating != null) _card(title: 'تقييمك', child: Row(children: [
            const Icon(Icons.star_rounded, color: AppColors.gold),
            Text(' ${o.rating!.productRating}/5 منتجات  ${o.rating!.deliveryRating}/5 توصيل',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
          ])),

          const SizedBox(height: 20),
        ])),
    );
  }

  Widget _card({String? title, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) ...[Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'Cairo', color: AppColors.midnight)), const SizedBox(height: 12)],
      child,
    ]),
  );

  Widget _row(String label, String value, {Color? color, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 13)),
      Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color ?? AppColors.midnight, fontFamily: 'Cairo', fontSize: 13)),
    ]),
  );

  Widget _ratingRow(String label, int value, void Function(int) onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
    Row(children: List.generate(5, (i) => IconButton(
      icon: Icon(i < value ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.gold, size: 32),
      onPressed: () => onChanged(i + 1),
    ))),
  ]);

  String _adjTitle(String type) {
    switch (type) {
      case 'price_change': return 'تعديل سعر منتج';
      case 'substitute':
      case 'substitute_suggested': return 'اقتراح بديل للمنتج';
      case 'item_added': return 'إضافة صنف جديد';
      case 'quantity_change':
      case 'qty_change': return 'تعديل الكمية';
      default: return 'تعديل على الطلب';
    }
  }

  /// True iff this adjustment is a substitute proposal awaiting the
  /// customer's response.
  bool _isSubstitute(OrderAdjustmentModel a) =>
      a.adjustmentType == 'substitute_suggested' ||
      a.adjustmentType == 'substitute';

  /// Builds the pending-adjustments cards. Substitute suggestions for the
  /// SAME item are bundled into a single card with up to 3 product tiles
  /// side-by-side.
  List<Widget> _buildPendingAdjustments(OrderModel o) {
    final pending = o.adjustments.where((a) => a.isPending).toList();
    if (pending.isEmpty) return const [];

    // Bucket substitute_suggested by orderItemId; keep everything else as-is.
    final Map<int, List<OrderAdjustmentModel>> subGroups = {};
    final List<OrderAdjustmentModel> other = [];
    for (final a in pending) {
      if (_isSubstitute(a) && a.orderItemId != null) {
        subGroups.putIfAbsent(a.orderItemId!, () => []).add(a);
      } else {
        other.add(a);
      }
    }

    final widgets = <Widget>[];

    // ── Substitute groups (one card per OrderItem, max 3 suggestions) ──
    subGroups.forEach((itemId, group) {
      // Keep only first 3 suggestions per item.
      final picks = group.take(3).toList();
      final original = o.items.firstWhere(
        (it) => it.id == itemId,
        orElse: () => o.items.isNotEmpty
            ? o.items.first
            : (throw StateError('no items')),
      );
      widgets.add(_substituteGroupCard(
        originalName: original.productNameAr,
        suggestions: picks,
      ));
    });

    // ── Other adjustment types (original layout) ──
    for (final adj in other) {
      widgets.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.peach,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.coral.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(_adjTitle(adj.adjustmentType),
                style: const TextStyle(fontWeight: FontWeight.w700,
                    color: AppColors.coral, fontFamily: 'Cairo'))),
          ]),
          const SizedBox(height: 6),
          // Explicit dark color — the global theme is Brightness.dark so
          // unstyled text on the peach card renders white-and-invisible.
          Text('من: ${adj.oldValue}  →  إلى: ${adj.newValue}',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.midnight)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mint,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => _approveAdjustment(adj.id, true),
              child: const Text('موافق ✅',
                  style: TextStyle(fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => _approveAdjustment(adj.id, false),
              child: const Text('رفض ❌',
                  style: TextStyle(color: AppColors.error,
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)))),
          ]),
        ]),
      ));
    }

    return widgets;
  }

  /// One unified card for the substitute-suggestions of a single item.
  /// Shows the unavailable item name and a row of up to 3 product tiles.
  Widget _substituteGroupCard({
    required String originalName,
    required List<OrderAdjustmentModel> suggestions,
  }) {
    // Reject-all: hit reject on every suggestion in the group.
    Future<void> rejectAll() async {
      for (final s in suggestions) {
        await _approveAdjustment(s.id, false);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🔄', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'بدائل مقترحة بدل: $originalName',
            style: const TextStyle(fontWeight: FontWeight.w700,
                color: AppColors.coral, fontFamily: 'Cairo'),
          )),
        ]),
        const SizedBox(height: 4),
        const Text('اختر منتج واحد أو ارفض الجميع',
            style: TextStyle(color: AppColors.textMuted,
                fontFamily: 'Cairo', fontSize: 12)),
        const SizedBox(height: 10),
        // Fixed-height strip with fixed-width tiles, horizontally scrollable.
        // Using a fixed tile width (110px) keeps a lone suggestion small and
        // ensures all 3 fit on a phone screen (~360-410dp wide ≈ 330+ usable).
        SizedBox(
          // Internal tile is ~176-180px tall (image 80 + name 30 + price ~18
          // + button 26 + 4 gaps + 12 padding). Give a little headroom.
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = suggestions[i];
              return SizedBox(
                width: 110,
                child: _SubstituteTile(
                  adj: s,
                  onPick: () => _approveAdjustment(s.id, true),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.close, color: AppColors.error, size: 18),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: rejectAll,
            label: const Text('رفض كل البدائل',
                style: TextStyle(color: AppColors.error,
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  String _payLabel(String method) {
    switch (method) {
      case 'cash': return 'كاش عند الاستلام';
      case 'card': return 'بطاقة / فيزا';
      case 'wallet': return 'المحفظة الإلكترونية';
      case 'points': return 'نقاط الولاء';
      default: return method;
    }
  }
}

/// Small compact tile shown inside the substitute-suggestions row.
/// Three of these fit comfortably side-by-side. Explicit dark text colors
/// because the surrounding card uses the peach accent background which can
/// wash out default text on some themes.
class _SubstituteTile extends StatelessWidget {
  final OrderAdjustmentModel adj;
  final VoidCallback onPick;
  const _SubstituteTile({required this.adj, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final info = adj.substituteInfo ?? const {};
    final nameAr = (info['name_ar'] ?? info['name_en'] ?? adj.newValue ?? '').toString();
    final priceRaw = (info['price'] ?? '').toString();
    final priceNum = double.tryParse(priceRaw);
    final priceStr = priceNum != null ? '${priceNum.toStringAsFixed(2)} ج' : priceRaw;
    final img = (info['image_url'] ?? '').toString();

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fixed-size image area (~92x80) — does NOT use AspectRatio so a
            // lone suggestion can't blow up to fill its parent.
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.ice,
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: img.isNotEmpty
                  ? Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.shopping_bag_outlined,
                            color: AppColors.sky, size: 28),
                      ))
                  : const Center(
                      child: Icon(Icons.shopping_bag_outlined,
                          color: AppColors.sky, size: 28),
                    ),
            ),
            const SizedBox(height: 4),
            // Product name — explicit dark color, 2 lines max.
            SizedBox(
              height: 30,
              child: Text(nameAr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1.2,
                      color: AppColors.midnight)),
            ),
            const SizedBox(height: 2),
            Text(priceStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.sapphire)),
            const SizedBox(height: 4),
            SizedBox(
              height: 26,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mint,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: onPick,
                child: const Text('اختر',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
