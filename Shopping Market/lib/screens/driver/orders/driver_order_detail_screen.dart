import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class DriverOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const DriverOrderDetailScreen({super.key, required this.orderId});
  @override State<DriverOrderDetailScreen> createState() => _DriverOrderDetailScreenState();
}

class _DriverOrderDetailScreenState extends State<DriverOrderDetailScreen> {
  final _api = ApiService();
  OrderModel? _order;
  bool _loading = true;
  bool _showScanner = false;
  int? _scanningForItemId;
  String? _scanAction; // 'substitute' or 'add'

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final order = await _api.getAgentOrder(widget.orderId);
      if (mounted) setState(() { _order = order; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _showToast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: error ? AppColors.error : AppColors.mint,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  Future<void> _acceptOrder() async {
    try {
      await _api.acceptOrder(widget.orderId);
      _load();
      _showToast('تم قبول الطلب بنجاح ✅');
    } catch (e) { _showToast('خطأ: $e', error: true); }
  }

  Future<void> _startPreparing() async {
    try {
      await _api.startPreparing(widget.orderId);
      _load();
      _showToast('بدأ التحضير 📦');
    } catch (e) { _showToast('خطأ: $e', error: true); }
  }

  Future<void> _startDelivery() async {
    try {
      await _api.startDelivery(widget.orderId);
      _load();
      _showToast('الطلب جاهز للتوصيل 🛵');
    } catch (e) { _showToast('خطأ: $e', error: true); }
  }

  Future<void> _markDelivered() async {
    try {
      await _api.markDelivered(widget.orderId);
      _load();
      _showToast('تم التسليم - انتظار تأكيد العميل ⏳');
    } catch (e) { _showToast('خطأ: $e', error: true); }
  }

  Future<void> _adjustPrice(OrderItemModel item) async {
    final ctrl = TextEditingController(text: item.unitPrice.toString());
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('تعديل السعر', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(item.productNameAr, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر الجديد (جنيه)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'السبب', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال', style: TextStyle(fontFamily: 'Cairo'))),
      ],
    ));
    if (confirmed == true) {
      try {
        await _api.adjustItemPrice(widget.orderId, item.id, double.parse(ctrl.text), reasonCtrl.text);
        _showToast('تم إرسال طلب التعديل للعميل');
      } catch (_) { _showToast('خطأ', error: true); }
    }
  }

  Future<void> _addItem() async {
    final searchCtrl = TextEditingController();
    List<ProductModel> results = [];
    await showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (_, ss) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(height: 500, padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('إضافة صنف للطلب', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          TextField(controller: searchCtrl,
            decoration: InputDecoration(labelText: 'ابحث عن منتج', prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () {}),
              border: const OutlineInputBorder()),
            onChanged: (q) async {
              if (q.length >= 2) {
                final r = await _api.searchSuggestions(q);
                ss(() => results = r);
              }
            }),
          const SizedBox(height: 8),
          Expanded(child: ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
            final p = results[i];
            return ListTile(
              title: Text(p.nameAr, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
              subtitle: Text('${p.currentPrice} ج', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.sapphire)),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _api.addItemToOrder(widget.orderId, p.id, 1);
                  _showToast('تم إضافة ${p.nameAr} وإرسال طلب الموافقة للعميل');
                  _load();
                },
                child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo'))),
            );
          })),
        ])),
      )));
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
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: RefreshIndicator(onRefresh: _load, color: AppColors.coral, child: ListView(padding: const EdgeInsets.all(14), children: [

        // Status + action
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: OrderStatus.color(o.status).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(OrderStatus.icon(o.status), color: OrderStatus.color(o.status))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(OrderStatus.labelAr(o.status), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Cairo')),
                Text('الإجمالي: ${o.totalAmount.toStringAsFixed(2)} ج', style: const TextStyle(color: AppColors.sapphire, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _payColor(o.paymentMethod).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_payLabel(o.paymentMethod), style: TextStyle(color: _payColor(o.paymentMethod), fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
            ]),
            const SizedBox(height: 14),
            // Primary action button — full lifecycle: new → accepted → preparing → out_for_delivery → delivered
            if (o.status == 'new') SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.mint, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _acceptOrder,
              child: const Text('✅ قبول الطلب', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
            if (o.status == 'accepted') SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _startPreparing,
              child: const Text('📋 بدء التحضير', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
            if (o.status == 'preparing') SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _startDelivery,
              child: const Text('🛵 الطلب جاهز للتوصيل', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
            if (o.status == 'out_for_delivery') SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.sapphire, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _markDelivered,
              child: const Text('📦 تم التسليم', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Cairo')))),
          ])),
        const SizedBox(height: 10),

        // Customer info + map link
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.person_outline, color: AppColors.sapphire, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.customerName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                if (o.deliveryPhone.isNotEmpty)
                  Text(o.deliveryPhone, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontFamily: 'Cairo')),
              ])),
              if (o.deliveryPhone.isNotEmpty)
                IconButton(
                  icon: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18)),
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: o.deliveryPhone);
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  }),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, color: AppColors.coral, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text('${o.deliveryAddress}\nعمارة ${o.buildingNumber} - دور ${o.floorNumber} - شقة ${o.apartmentNumber}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12))),
            ]),
            if (o.landmark.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.info_outline, color: AppColors.sky, size: 14),
                const SizedBox(width: 6),
                Text(o.landmark, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.sky)),
              ]),
            ],
          ])),
        const SizedBox(height: 10),

        // Items
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('الأصناف (${o.items.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 14)),
              if (o.status == 'preparing')
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.coral),
                  label: const Text('إضافة صنف', style: TextStyle(color: AppColors.coral, fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                  onPressed: _addItem),
            ]),
            const Divider(),
            ...o.items.map((item) => _buildItemRow(item)),
          ])),
        const SizedBox(height: 10),

        // Notes
        if (o.customerNotes.isNotEmpty)
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.lemon, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.gold.withOpacity(0.4))),
            child: Row(children: [
              const Text('📝', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(o.customerNotes, style: const TextStyle(fontFamily: 'Cairo'))),
            ])),
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _buildItemRow(OrderItemModel item) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.addedByDriver ? AppColors.coral.withOpacity(0.3) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.productNameAr, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 13)),
            if (item.productBarcode?.isNotEmpty == true) Text('باركود: ${item.productBarcode}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'Cairo')),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${item.quantity.toStringAsFixed(1)} × ${item.unitPrice.toStringAsFixed(1)} ج', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.sapphire, fontFamily: 'Cairo')),
            if (item.addedByDriver) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.coral.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('أضافه المندوب', style: TextStyle(color: AppColors.coral, fontSize: 9, fontFamily: 'Cairo'))),
          ]),
        ]),
        if (_order?.status == 'preparing') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6), side: const BorderSide(color: AppColors.sky), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.sapphire),
              label: const Text('تعديل السعر', style: TextStyle(fontSize: 11, color: AppColors.sapphire, fontFamily: 'Cairo')),
              onPressed: () => _adjustPrice(item))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6), side: const BorderSide(color: AppColors.coral), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.swap_horiz_rounded, size: 14, color: AppColors.coral),
              label: const Text('بديل', style: TextStyle(fontSize: 11, color: AppColors.coral, fontFamily: 'Cairo')),
              onPressed: () async {
                final searchCtrl = TextEditingController();
                List<ProductModel> results = [];
                showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (ctx) => StatefulBuilder(builder: (_, ss) => Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                    child: SizedBox(height: 460, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                      Text('اختر بديلاً لـ ${item.productNameAr}', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      TextField(controller: searchCtrl, autofocus: true,
                        decoration: const InputDecoration(labelText: 'ابحث أو امسح الباركود', border: OutlineInputBorder()),
                        onChanged: (q) async { final r = await _api.searchSuggestions(q); ss(() => results = r); }),
                      const SizedBox(height: 8),
                      Expanded(child: ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                        final p = results[i];
                        return ListTile(
                          title: Text(p.nameAr, style: const TextStyle(fontFamily: 'Cairo')),
                          subtitle: Text('${p.currentPrice} ج', style: const TextStyle(color: AppColors.sapphire, fontFamily: 'Cairo')),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.mint),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _api.substituteItem(widget.orderId, item.id, p.id);
                              _showToast('تم اقتراح البديل ${p.nameAr} للعميل');
                              _load();
                            },
                            child: const Text('اختر', style: TextStyle(fontFamily: 'Cairo'))));
                      })),
                    ]))))));
              })),
          ]),
        ],
      ]),
    );
  }

  Color _payColor(String method) {
    switch (method) {
      case 'card': return AppColors.sapphire;
      case 'wallet': return AppColors.mint;
      case 'points': return AppColors.gold;
      default: return AppColors.coral;
    }
  }

  String _payLabel(String method) {
    switch (method) {
      case 'cash': return '💵 كاش';
      case 'card': return '💳 فيزا';
      case 'wallet': return '📱 محفظة';
      case 'points': return '⭐ نقاط';
      default: return method;
    }
  }
}
