import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';
import '../../../widgets/shared/product_card.dart';

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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final order = await _api.getOrder(widget.orderId);
      if (mounted) setState(() { _order = order; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _approveAdjustment(int adjId, bool approved) async {
    try {
      await _api.approveAdjustment(adjId, approved);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved ? 'تم القبول ✅' : 'تم الرفض ❌', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: approved ? AppColors.mint : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (_) {}
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

          // Pending adjustments requiring approval
          ...o.adjustments.where((a) => a.customerApproved == null).map((adj) =>
            Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.peach, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.coral.withOpacity(0.4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('⚠️', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_adjTitle(adj.adjustmentType), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.coral, fontFamily: 'Cairo'))),
                ]),
                const SizedBox(height: 6),
                Text('من: ${adj.oldValue}  →  إلى: ${adj.newValue}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.mint, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => _approveAdjustment(adj.id, true),
                    child: const Text('موافق ✅', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => _approveAdjustment(adj.id, false),
                    child: const Text('رفض ❌', style: TextStyle(color: AppColors.error, fontFamily: 'Cairo', fontWeight: FontWeight.w700)))),
                ]),
              ])),
          ),

          // Items
          _card(title: 'الأصناف (${o.items.length})', child: Column(children: o.items.map((item) =>
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.shopping_bag_outlined, color: AppColors.sky, size: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.productNameAr, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 13)),
                Text('${item.effectiveQty.toStringAsFixed(1)} × ${item.effectivePrice.toStringAsFixed(1)} ج',
                  style: const TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 11)),
              ])),
              Text('${item.lineTotal.toStringAsFixed(2)} ج', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.sapphire, fontFamily: 'Cairo')),
            ]))
          ).toList())),
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

          // Delivery address
          _card(title: 'عنوان التوصيل', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.deliveryAddress, style: const TextStyle(fontFamily: 'Cairo')),
            if (o.buildingNumber.isNotEmpty)
              Text('عمارة ${o.buildingNumber} - دور ${o.floorNumber} - شقة ${o.apartmentNumber}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Cairo')),
            if (o.landmark.isNotEmpty) Text('علامة مميزة: ${o.landmark}',
              style: const TextStyle(color: AppColors.sky, fontSize: 12, fontFamily: 'Cairo')),
          ])),
          const SizedBox(height: 10),

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
      case 'substitute': return 'اقتراح بديل للمنتج';
      case 'item_added': return 'إضافة صنف جديد';
      case 'quantity_change': return 'تعديل الكمية';
      default: return 'تعديل على الطلب';
    }
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
