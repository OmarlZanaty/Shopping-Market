import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final _notesCtrl      = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _buildingCtrl   = TextEditingController();
  final _floorCtrl      = TextEditingController();
  final _apartmentCtrl  = TextEditingController();
  final _landmarkCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        _nameCtrl.text  = user.fullName;
        _phoneCtrl.text = user.phone;
      }
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose(); _nameCtrl.dispose(); _phoneCtrl.dispose();
    _addressCtrl.dispose(); _buildingCtrl.dispose(); _floorCtrl.dispose();
    _apartmentCtrl.dispose(); _landmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder(BuildContext context) async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty ||
        _addressCtrl.text.trim().isEmpty || _buildingCtrl.text.trim().isEmpty ||
        _floorCtrl.text.trim().isEmpty || _apartmentCtrl.text.trim().isEmpty) {
      _showSnack('يرجى ملء جميع حقول العنوان المطلوبة', AppColors.error);
      return;
    }
    setState(() => _placing = true);
    try {
      final order = await _api.createOrder({
        'items': cart.items.map((i) => {'product_id': i.product.id, 'quantity': i.quantity}).toList(),
        'delivery_name':     _nameCtrl.text.trim(),
        'delivery_phone':    _phoneCtrl.text.trim(),
        'delivery_address':  _addressCtrl.text.trim(),
        'building_number':   _buildingCtrl.text.trim(),
        'floor_number':      _floorCtrl.text.trim(),
        'apartment_number':  _apartmentCtrl.text.trim(),
        'landmark':          _landmarkCtrl.text.trim(),
        'payment_method':    _paymentMethod,
        'customer_notes':    _notesCtrl.text.trim(),
        'points_to_use':     cart.pointsToUse,
      });
      cart.clear();
      if (mounted) {
        context.go('/orders/${order.orderId}');
        _showSnack('تم تأكيد الطلب رقم ${order.orderId} ✅', AppColors.mint);
      }
    } catch (e) {
      if (mounted) _showSnack('خطأ: ${e.toString()}', AppColors.error);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.midnight,
        elevation: 0,
        title: Text(
          'السلة (${cart.itemCount})',
          style: const TextStyle(
            fontFamily: 'Cairo', fontSize: 18,
            fontWeight: FontWeight.w700, color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: cart.clear,
              child: const Text('مسح الكل',
                style: TextStyle(
                  color: AppColors.watermelon,
                  fontFamily: 'Cairo', fontWeight: FontWeight.w600,
                )),
            ),
        ],
      ),

      body: cart.isEmpty ? _buildEmpty() : Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              // ── Cart items ───────────────────────────────────────────────
              _sectionLabel('🛒 منتجاتك'),
              const SizedBox(height: 8),
              ...cart.items.map((item) => _CartItemCard(
                item: item,
                onIncrease: () => cart.updateQuantity(item.product.id, item.quantity + 1),
                onDecrease: () => cart.updateQuantity(item.product.id, item.quantity - 1),
              )),

              const SizedBox(height: 16),

              // ── Delivery address ─────────────────────────────────────────
              _sectionLabel('📍 عنوان التوصيل'),
              const SizedBox(height: 8),
              _card(Column(children: [
                _field(_nameCtrl,      'الاسم',                    Icons.person_outline_rounded),
                _field(_phoneCtrl,     'رقم الهاتف',               Icons.phone_outlined,        type: TextInputType.phone),
                _field(_addressCtrl,   'الشارع / المنطقة',          Icons.home_outlined),
                Row(children: [
                  Expanded(child: _field(_buildingCtrl, 'المبنى', Icons.apartment_outlined,    type: TextInputType.number, last: false)),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_floorCtrl,    'الدور',  Icons.layers_outlined,       type: TextInputType.number, last: false)),
                ]),
                _field(_apartmentCtrl, 'رقم الشقة',                Icons.meeting_room_outlined, type: TextInputType.number),
                _field(_landmarkCtrl,  'علامة مميزة (اختياري)',    Icons.place_outlined,        last: true),
              ])),

              const SizedBox(height: 16),

              // ── Payment method ───────────────────────────────────────────
              _sectionLabel('💳 طريقة الدفع'),
              const SizedBox(height: 8),
              _card(Row(children: [
                _payOption('cash',   '💵', 'كاش'),
                const SizedBox(width: 8),
                _payOption('card',   '💳', 'فيزا'),
                const SizedBox(width: 8),
                _payOption('wallet', '📱', 'محفظة'),
                const SizedBox(width: 8),
                _payOption('points', '⭐', 'نقاط'),
              ])),

              const SizedBox(height: 16),

              // ── Notes ────────────────────────────────────────────────────
              _sectionLabel('📝 ملاحظات'),
              const SizedBox(height: 8),
              _card(TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textMain),
                decoration: InputDecoration(
                  hintText: 'مثل: يرجى التواصل قبل الوصول...',
                  hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              )),

              const SizedBox(height: 16),

              // ── Loyalty points ───────────────────────────────────────────
              if (user != null && user.loyaltyPoints > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.gold.withOpacity(0.15), AppColors.lemon],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Text('⭐', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('لديك ${user.loyaltyPoints} نقطة',
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            color: AppColors.textMain, fontFamily: 'Cairo')),
                      Text('= ${(user.loyaltyPoints * 0.05).toStringAsFixed(2)} جنيه',
                        style: const TextStyle(color: AppColors.textMuted,
                            fontSize: 11, fontFamily: 'Cairo')),
                    ])),
                    GestureDetector(
                      onTap: () => cart.setPointsToUse(user.loyaltyPoints),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('استخدم',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 12)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Summary ──────────────────────────────────────────────────
              _sectionLabel('🧾 ملخص الطلب'),
              const SizedBox(height: 8),
              _card(Column(children: [
                _summaryRow('إجمالي المنتجات', '${cart.subtotal.toStringAsFixed(2)} ج'),
                _summaryRow('رسوم التوصيل',    '${cart.deliveryFee.toStringAsFixed(2)} ج'),
                if (cart.savings > 0)
                  _summaryRow('الوفر', '-${cart.savings.toStringAsFixed(2)} ج', color: AppColors.mint),
                if (cart.pointsToUse > 0)
                  _summaryRow('خصم النقاط', '-${cart.pointsValue.toStringAsFixed(2)} ج', color: AppColors.mint),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('الإجمالي',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                        fontFamily: 'Cairo', color: AppColors.textMain)),
                  Text('${cart.total.toStringAsFixed(2)} ج',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20,
                        color: AppColors.coral, fontFamily: 'Cairo')),
                ]),
              ])),

              const SizedBox(height: 20),
            ],
          ),
        ),

        // ── Place order button ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _placing ? null : () => _placeOrder(context),
              child: _placing
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 22),
                    const SizedBox(width: 10),
                    Text('تأكيد الطلب · ${cart.total.toStringAsFixed(1)} ج',
                      style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w800, fontFamily: 'Cairo')),
                  ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  Widget _buildEmpty() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(color: AppColors.ice, shape: BoxShape.circle),
        child: const Icon(Icons.shopping_cart_outlined,
            size: 48, color: AppColors.sky),
      ),
      const SizedBox(height: 20),
      const Text('السلة فارغة',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: AppColors.textMain, fontFamily: 'Cairo')),
      const SizedBox(height: 8),
      const Text('أضف منتجات لتبدأ طلبك',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontFamily: 'Cairo')),
    ],
  ));

  Widget _sectionLabel(String text) => Text(text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
        color: AppColors.textMain, fontFamily: 'Cairo'));

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: AppColors.midnight.withOpacity(0.05),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text, bool last = false}) =>
    Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        textDirection: TextDirection.rtl,
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textMain),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.background,
          prefixIcon: Icon(icon, size: 18, color: AppColors.sky),
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
          ),
        ),
      ),
    );

  Widget _payOption(String method, String emoji, String label) =>
    Expanded(child: GestureDetector(
      onTap: () => setState(() => _paymentMethod = method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _paymentMethod == method ? AppColors.coral : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _paymentMethod == method ? AppColors.coral : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            fontFamily: 'Cairo',
            color: _paymentMethod == method ? Colors.white : AppColors.textMuted,
          )),
        ]),
      ),
    ));

  Widget _summaryRow(String label, String value, {Color? color}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted,
            fontFamily: 'Cairo', fontSize: 13)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600,
            fontFamily: 'Cairo', color: color ?? AppColors.textMain, fontSize: 13)),
      ]),
    );
}

// ── Cart item card ────────────────────────────────────────────────────────────

class _CartItemCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _CartItemCard({required this.item, required this.onIncrease, required this.onDecrease});

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final hasImage = p.mainImageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.midnight.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        // Product image
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
          child: SizedBox(
            width: 72, height: 72,
            child: hasImage
              ? CachedNetworkImage(
                  imageUrl: p.mainImageUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.ice,
                    child: const Center(child: Icon(Icons.shopping_basket_outlined,
                        color: AppColors.sky, size: 24))),
                  errorWidget: (_, __, ___) => Container(color: AppColors.ice,
                    child: const Center(child: Icon(Icons.shopping_basket_outlined,
                        color: AppColors.sky, size: 24))),
                )
              : Container(color: AppColors.ice,
                  child: const Center(child: Icon(Icons.shopping_basket_outlined,
                      color: AppColors.sky, size: 24))),
          ),
        ),

        // Name + price
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nameAr,
                style: const TextStyle(fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo', fontSize: 13, color: AppColors.textMain),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                p.currentPrice > 0
                  ? '${(p.currentPrice * item.quantity).toStringAsFixed(2)} ج'
                  : 'السعر عند الطلب',
                style: TextStyle(
                  fontWeight: FontWeight.w800, fontFamily: 'Cairo', fontSize: 14,
                  color: p.currentPrice > 0 ? AppColors.coral : AppColors.textMuted,
                ),
              ),
            ]),
          ),
        ),

        // Qty controls
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(children: [
            _qtyBtn(Icons.remove_rounded, onDecrease, AppColors.sky),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${item.quantity.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 16, fontFamily: 'Cairo', color: AppColors.textMain)),
            ),
            _qtyBtn(Icons.add_rounded, onIncrease, AppColors.coral),
          ]),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, Color color) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
}
