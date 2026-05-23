import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../utils/constants.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _api = ApiService();
  bool _placing = false;
  String _paymentMethod = 'cash';
  final _notesCtrl = TextEditingController();

  // Address controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _apartmentCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill with user data if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        _nameCtrl.text = user.fullName ?? '';
        _phoneCtrl.text = user.phone ?? '';
      }
    });
  }

  Future<void> _placeOrder(BuildContext context) async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;

    // Validate required fields
    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _addressCtrl.text.trim().isEmpty ||
        _buildingCtrl.text.trim().isEmpty ||
        _floorCtrl.text.trim().isEmpty ||
        _apartmentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى ملء جميع حقول العنوان المطلوبة', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _placing = true);
    try {
      final payload = {
        'items': cart.items.map((item) => {
          'product_id': item.product.id,
          'quantity': item.quantity,
        }).toList(),
        'delivery_name': _nameCtrl.text.trim(),
        'delivery_phone': _phoneCtrl.text.trim(),
        'delivery_address': _addressCtrl.text.trim(),
        'building_number': _buildingCtrl.text.trim(),
        'floor_number': _floorCtrl.text.trim(),
        'apartment_number': _apartmentCtrl.text.trim(),
        'landmark': _landmarkCtrl.text.trim(),
        'payment_method': _paymentMethod,
        'customer_notes': _notesCtrl.text.trim(),
        'points_to_use': cart.pointsToUse,
      };

      final order = await _api.createOrder(payload);
      cart.clear();
      if (mounted) {
        context.go('/orders/${order.orderId}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم تأكيد الطلب رقم ${order.orderId} ✅', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.mint, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ: ${e.toString()}', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('السلة (${cart.itemCount})', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.midnight,
        elevation: 0,
        actions: [if (cart.isNotEmpty) TextButton(
          onPressed: () => cart.clear(),
          child: const Text('مسح الكل', style: TextStyle(color: AppColors.watermelon, fontFamily: 'Cairo')),
        )],
      ),
      body: cart.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.shopping_cart_outlined, size: 80, color: AppColors.sky),
        SizedBox(height: 16),
        Text('السلة فارغة', style: TextStyle(fontSize: 18, color: AppColors.textMuted, fontFamily: 'Cairo')),
      ]))
          : Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          // Items
          ...cart.items.map((item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.ice, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.shopping_bag_outlined, color: AppColors.sky, size: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.product.nameAr, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 13)),
                Text('${item.product.currentPrice.toStringAsFixed(1)} ج', style: const TextStyle(color: AppColors.sapphire, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              ])),
              Row(children: [
                _qtyBtn(Icons.remove, () => cart.updateQuantity(item.product.id, item.quantity - 1), AppColors.sky),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('${item.quantity.toInt()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Cairo'))),
                _qtyBtn(Icons.add, () => cart.updateQuantity(item.product.id, item.quantity + 1), AppColors.coral),
              ]),
            ]),
          )),

          // Delivery Address
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.location_on_outlined, color: AppColors.coral, size: 18),
                const SizedBox(width: 6),
                const Text('عنوان التوصيل', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: AppColors.midnight)),
              ]),
              const SizedBox(height: 12),
              _addressField(_nameCtrl, 'الاسم', Icons.person_outline),
              const SizedBox(height: 10),
              _addressField(_phoneCtrl, 'رقم الهاتف', Icons.phone_outlined, keyboard: TextInputType.phone),
              const SizedBox(height: 10),
              _addressField(_addressCtrl, 'العنوان (الشارع / المنطقة)', Icons.home_outlined),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _addressField(_buildingCtrl, 'المبنى', Icons.apartment_outlined, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _addressField(_floorCtrl, 'الدور', Icons.layers_outlined, keyboard: TextInputType.number)),
              ]),
              const SizedBox(height: 10),
              _addressField(_apartmentCtrl, 'رقم الشقة', Icons.meeting_room_outlined, keyboard: TextInputType.number),
              const SizedBox(height: 10),
              _addressField(_landmarkCtrl, 'علامة مميزة (اختياري)', Icons.place_outlined),
            ]),
          ),

          // Notes
          Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('📝 ملاحظات', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.coral, fontSize: 12, fontFamily: 'Cairo')),
                const SizedBox(height: 8),
                TextField(controller: _notesCtrl, maxLines: 2,
                    decoration: const InputDecoration.collapsed(hintText: 'مثل: يرجى التواصل قبل الوصول...', hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12))),
              ])),

          // Payment method
          Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo', color: AppColors.midnight)),
                const SizedBox(height: 12),
                Row(children: [
                  _payOption('cash',   '💵', 'كاش'),
                  const SizedBox(width: 8),
                  _payOption('card',   '💳', 'فيزا'),
                  const SizedBox(width: 8),
                  _payOption('wallet', '📱', 'محفظة'),
                  const SizedBox(width: 8),
                  _payOption('points', '⭐', 'نقاط'),
                ]),
              ])),

          // Points redemption
          if (user != null && user.loyaltyPoints > 0)
            Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.gold.withOpacity(0.1), AppColors.peach]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Text('⭐', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('لديك ${user.loyaltyPoints} نقطة', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.midnight, fontFamily: 'Cairo')),
                    Text('= ${(user.loyaltyPoints * 0.05).toStringAsFixed(2)} جنيه', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Cairo')),
                  ])),
                  TextButton(onPressed: () => cart.setPointsToUse(user.loyaltyPoints),
                      child: const Text('استخدم', style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w700, fontFamily: 'Cairo'))),
                ])),

          // Summary
          Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                _summaryRow('إجمالي المنتجات', '${cart.subtotal.toStringAsFixed(2)} ج'),
                _summaryRow('رسوم التوصيل', '${cart.deliveryFee.toStringAsFixed(2)} ج'),
                if (cart.savings > 0) _summaryRow('الوفر', '-${cart.savings.toStringAsFixed(2)} ج', color: AppColors.mint),
                if (cart.pointsToUse > 0) _summaryRow('خصم النقاط', '-${cart.pointsValue.toStringAsFixed(2)} ج', color: AppColors.mint),
                const Divider(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Cairo')),
                  Text('${cart.total.toStringAsFixed(2)} ج', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.sapphire, fontFamily: 'Cairo')),
                ]),
              ])),
        ])),

        // Checkout button
        Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0,-4))]),
            child: SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _placing ? null : () => _placeOrder(context),
              child: _placing
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text('تأكيد الطلب · ${cart.total.toStringAsFixed(1)} ج', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Cairo')),
              ]),
            ))),
      ]),
    );
  }

  Widget _addressField(TextEditingController ctrl, String hint, IconData icon, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18, color: AppColors.sky),
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.coral)),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, Color color) => GestureDetector(
    onTap: onTap,
    child: Container(width: 28, height: 28, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, size: 16, color: color)),
  );

  Widget _payOption(String method, String icon, String label) => Expanded(child: GestureDetector(
    onTap: () => setState(() => _paymentMethod = method),
    child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _paymentMethod == method ? AppColors.midnight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _paymentMethod == method ? AppColors.midnight : AppColors.border, width: 1.5),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _paymentMethod == method ? Colors.white : AppColors.textMuted, fontFamily: 'Cairo')),
        ])),
  ));

  Widget _summaryRow(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontFamily: 'Cairo', fontSize: 13)),
      Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Cairo', color: color ?? AppColors.midnight, fontSize: 13)),
    ]),
  );
}