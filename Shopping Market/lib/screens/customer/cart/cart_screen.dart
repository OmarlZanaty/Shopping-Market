import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../providers/cart_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../models/models.dart';
import '../../../core/utils/formatters.dart';
import '../../../utils/constants.dart';
import '../map_location_picker_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _api = ApiService();
  bool _placing = false;

  // ── Address state ─────────────────────────────────────────────────────────
  List<AddressModel> _addresses = [];
  AddressModel? _selectedAddress;
  bool _loadingAddresses = true;

  // ── Payment + notes ───────────────────────────────────────────────────────
  String _paymentMethod = 'cash';
  final _notesCtrl = TextEditingController();

  static const _paymentKey = 'checkout_payment';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([_loadAddresses(), _loadPaymentPref()]);
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Load saved addresses from backend ─────────────────────────────────────
  Future<void> _loadAddresses() async {
    try {
      final list = await _api.getAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = list;
        // Pick the default address, or the first one.
        _selectedAddress = list.isEmpty
            ? null
            : list.firstWhere((a) => a.isDefault, orElse: () => list.first);
        _loadingAddresses = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  Future<void> _loadPaymentPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_paymentKey);
    // 'card' was removed — fall back to 'cash'
    const validMethods = {'cash', 'points', 'pos'};
    if (saved != null && validMethods.contains(saved) && mounted) {
      setState(() => _paymentMethod = saved);
    }
  }

  Future<void> _savePaymentPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paymentKey, _paymentMethod);
  }

  // ── Place order ───────────────────────────────────────────────────────────
  Future<void> _placeOrder(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      _showSnack('يرجى تسجيل الدخول أولاً', AppColors.error);
      context.push('/login');
      return;
    }
    if (_selectedAddress == null) {
      _showSnack('يرجى إضافة عنوان توصيل أولاً', AppColors.error);
      _showAddressPicker();
      return;
    }
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;

    setState(() => _placing = true);
    try {
      final order = await _api.createOrder({
        'items': cart.items
            .map((i) => {'product_id': i.product.id, 'quantity': i.quantity})
            .toList(),
        'address_id':     _selectedAddress!.id,
        'payment_method': _paymentMethod,
        'customer_notes': _notesCtrl.text.trim(),
        'points_to_use':  cart.pointsToUse,
      });
      await _savePaymentPref();
      cart.clear();
      if (mounted) {
        context.go('/orders/${order.orderId}');
        _showSnack('تم تأكيد الطلب رقم ${order.orderId} ✅', AppColors.mint);
      }
    } catch (e) {
      // ApiService.createOrder throws Exception(<arabic message>) — strip
      // the "Exception: " prefix so the snackbar reads cleanly in Arabic.
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (mounted) _showSnack(msg, AppColors.error);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  // ── Address picker bottom sheet ───────────────────────────────────────────
  void _showAddressPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddressPickerSheet(
        addresses: _addresses,
        selected: _selectedAddress,
        onSelect: (addr) {
          setState(() => _selectedAddress = addr);
          Navigator.pop(context);
        },
        onAddNew: () {
          Navigator.pop(context);
          _showAddAddressForm();
        },
      ),
    );
  }

  // ── Add new address form ──────────────────────────────────────────────────
  void _showAddAddressForm() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddAddressSheet(
        api: _api,
        onSaved: (addr) {
          setState(() {
            _addresses.add(addr);
            _selectedAddress = addr;
          });
        },
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.midnight,
        elevation: 0,
        title: Text('السلة (${cart.itemCount})',
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 18,
                fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: true,
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: cart.clear,
              child: const Text('مسح الكل',
                  style: TextStyle(color: AppColors.watermelon,
                      fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            ),
        ],
      ),

      body: cart.isEmpty ? _buildEmpty() : Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [

              // ── Cart items ─────────────────────────────────────────────
              _sectionLabel('🛒 منتجاتك'),
              const SizedBox(height: 8),
              ...cart.items.map((item) {
                // Weight-based items step by 250 g (0.25 kg); piece items by 1.
                final step = item.product.isWeighed ? 0.25 : 1.0;
                return _CartItemCard(
                  item: item,
                  onIncrease: () => cart.updateQuantity(item.product.id, item.quantity + step),
                  onDecrease: () => cart.updateQuantity(item.product.id, item.quantity - step),
                );
              }),
              const SizedBox(height: 16),

              // ── Delivery address ───────────────────────────────────────
              _sectionLabel('📍 عنوان التوصيل'),
              const SizedBox(height: 8),
              _buildAddressCard(),
              const SizedBox(height: 16),

              // ── Customer info (read-only from profile) ─────────────────
              if (user != null) ...[
                _sectionLabel('👤 بيانات التوصيل'),
                const SizedBox(height: 8),
                _card(Row(children: [
                  const Icon(Icons.person_outline_rounded, color: AppColors.sky, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(user.fullName,
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600,
                          color: AppColors.textMain))),
                  const SizedBox(width: 16),
                  const Icon(Icons.phone_outlined, color: AppColors.sky, size: 18),
                  const SizedBox(width: 6),
                  Text(user.phone,
                      style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted)),
                ])),
                const SizedBox(height: 16),
              ],

              // ── Payment method ─────────────────────────────────────────
              _sectionLabel('💳 طريقة الدفع'),
              const SizedBox(height: 8),
              _card(Column(children: [
                // Row: cash / points
                Row(children: [
                  _payOption('cash',   '💵', 'كاش'),
                  const SizedBox(width: 8),
                  _payOption('points', '⭐', 'نقاط'),
                ]),
                const SizedBox(height: 8),
                // POS — full-width with subtitle
                _payOptionPos(),
                const SizedBox(height: 8),
                // Online payment — coming soon
                _payOptionOnlineComingSoon(),
              ])),
              const SizedBox(height: 16),

              // ── Notes ──────────────────────────────────────────────────
              _sectionLabel('📝 ملاحظات (اختياري)'),
              const SizedBox(height: 8),
              _card(TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.textMain),
                decoration: const InputDecoration(
                  hintText: 'مثل: يرجى التواصل قبل الوصول...',
                  hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
                  border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
              )),
              const SizedBox(height: 16),

              // ── Loyalty points ─────────────────────────────────────────
              if (LoyaltyConfig.enabled && user != null && user.loyaltyPoints > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.gold.withValues(alpha: 0.15), AppColors.lemon]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    const Text('⭐', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('لديك ${user.loyaltyPoints} نقطة',
                          style: const TextStyle(fontWeight: FontWeight.w700,
                              color: AppColors.textMain, fontFamily: 'Cairo')),
                      Text('= ${LoyaltyConfig.valueForPoints(user.loyaltyPoints).toStringAsFixed(2)} جنيه',
                          style: const TextStyle(color: AppColors.textMuted,
                              fontSize: 11, fontFamily: 'Cairo')),
                    ])),
                    GestureDetector(
                      onTap: () => cart.setPointsToUse(user.loyaltyPoints),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                        child: const Text('استخدم',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontFamily: 'Cairo', fontSize: 12)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Summary ────────────────────────────────────────────────
              _sectionLabel('🧾 ملخص الطلب'),
              const SizedBox(height: 8),
              _card(Column(children: [
                _summaryRow('إجمالي المنتجات', '${cart.subtotal.toStringAsFixed(2)} ج'),
                _summaryRow('رسوم التوصيل', '${cart.deliveryFee.toStringAsFixed(2)} ج'),
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

        // ── Place order button ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral, foregroundColor: Colors.white,
                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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

  // ── Address card ──────────────────────────────────────────────────────────
  Widget _buildAddressCard() {
    if (_loadingAddresses) {
      return const _InfoCard(child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2),
        ),
      ));
    }

    if (_selectedAddress == null) {
      // No address saved yet
      return GestureDetector(
        onTap: _showAddAddressForm,
        child: const _InfoCard(child: Row(children: [
          Icon(Icons.add_location_alt_outlined, color: AppColors.coral, size: 28),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('أضف عنوان توصيل', style: TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                color: AppColors.coral, fontSize: 14)),
            SizedBox(height: 2),
            Text('اضغط لإضافة عنوانك الأول', style: TextStyle(
                fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12)),
          ])),
          Icon(Icons.chevron_left_rounded, color: AppColors.coral),
        ])),
      );
    }

    final a = _selectedAddress!;
    return GestureDetector(
      onTap: _showAddressPicker,
      child: _InfoCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.location_on_rounded, color: AppColors.coral, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(labelAr(a.label), style: const TextStyle(fontWeight: FontWeight.w700,
                fontFamily: 'Cairo', color: AppColors.textMain, fontSize: 14)),
            if (a.isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.sapphire.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100)),
                child: const Text('الافتراضي',
                    style: TextStyle(color: AppColors.sapphire, fontSize: 10, fontFamily: 'Cairo')),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(
            [
              a.fullAddress,
              if (a.buildingNumber.isNotEmpty) 'عمارة ${a.buildingNumber}',
              if (a.floorNumber.isNotEmpty)    'دور ${a.floorNumber}',
              if (a.apartmentNumber.isNotEmpty) 'شقة ${a.apartmentNumber}',
              if (a.landmark.isNotEmpty)        a.landmark,
            ].join(' - '),
            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 12),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
        ])),
        const Icon(Icons.swap_horiz_rounded, color: AppColors.sky, size: 20),
      ])),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _buildEmpty() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 100, height: 100,
        decoration: BoxDecoration(color: AppColors.ice, shape: BoxShape.circle),
        child: const Icon(Icons.shopping_cart_outlined, size: 48, color: AppColors.sky)),
      const SizedBox(height: 20),
      const Text('السلة فارغة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
          color: AppColors.textMain, fontFamily: 'Cairo')),
      const SizedBox(height: 8),
      const Text('أضف منتجات لتبدأ طلبك',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontFamily: 'Cairo')),
    ],
  ));

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain, fontFamily: 'Cairo'));

  Widget _card(Widget child) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: AppColors.midnight.withValues(alpha: 0.05),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
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
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              fontFamily: 'Cairo',
              color: _paymentMethod == method ? Colors.white : AppColors.textMuted)),
        ]),
      ),
    ));

  // ── POS option (full-width with subtitle) ─────────────────────────────────
  Widget _payOptionPos() {
    final selected = _paymentMethod == 'pos';
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = 'pos'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.coral : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.coral : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(children: [
          const Text('🖥️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الدفع بالماكينة (POS)',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14,
                    color: selected ? Colors.white : AppColors.textMain)),
            const SizedBox(height: 2),
            Text('إحضار ماكينة الدفع مع مندوب التوصيل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 11,
                    color: selected ? Colors.white70 : AppColors.textMuted)),
          ])),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        ]),
      ),
    );
  }

  // ── Online payment — coming soon (disabled) ───────────────────────────────
  Widget _payOptionOnlineComingSoon() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border, width: 1.5),
    ),
    child: Row(children: [
      const Text('💳', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 12),
      const Expanded(child: Text('الدفع الإلكتروني (أونلاين)',
          style: TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14,
              color: AppColors.textMuted))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: const Text('قريباً',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.gold)),
      ),
    ]),
  );

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

// ── Shared card container ─────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: AppColors.midnight.withValues(alpha: 0.05),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );
}

// ── Address picker bottom sheet ───────────────────────────────────────────────
class _AddressPickerSheet extends StatelessWidget {
  final List<AddressModel> addresses;
  final AddressModel? selected;
  final ValueChanged<AddressModel> onSelect;
  final VoidCallback onAddNew;

  const _AddressPickerSheet({
    required this.addresses,
    required this.selected,
    required this.onSelect,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('اختر عنوان التوصيل',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo', color: AppColors.textMain)),
          const SizedBox(height: 12),

          // Add new address button
          GestureDetector(
            onTap: onAddNew,
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.coral, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(children: [
                Icon(Icons.add_location_alt_outlined, color: AppColors.coral),
                SizedBox(width: 10),
                Text('إضافة عنوان جديد',
                    style: TextStyle(color: AppColors.coral, fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: addresses.length,
              itemBuilder: (_, i) {
                final a = addresses[i];
                final isSelected = selected?.id == a.id;
                return GestureDetector(
                  onTap: () => onSelect(a),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppColors.coral : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.location_on_rounded,
                          color: isSelected ? AppColors.coral : AppColors.sky, size: 22),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(labelAr(a.label), style: TextStyle(
                              fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                              color: isSelected ? AppColors.coral : AppColors.textMain)),
                          if (a.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.ice,
                                  borderRadius: BorderRadius.circular(100)),
                              child: const Text('الافتراضي',
                                  style: TextStyle(color: AppColors.sapphire,
                                      fontSize: 10, fontFamily: 'Cairo')),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 3),
                        Text(
                          [
                            a.fullAddress,
                            if (a.buildingNumber.isNotEmpty) 'عمارة ${a.buildingNumber}',
                            if (a.floorNumber.isNotEmpty)    'دور ${a.floorNumber}',
                            if (a.apartmentNumber.isNotEmpty) 'شقة ${a.apartmentNumber}',
                          ].join(' - '),
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted,
                              fontFamily: 'Cairo'),
                          maxLines: 2,
                        ),
                      ])),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded, color: AppColors.coral, size: 20),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Add new address bottom sheet ──────────────────────────────────────────────
class AddAddressSheet extends StatefulWidget {
  final ApiService api;
  final ValueChanged<AddressModel> onSaved;
  const AddAddressSheet({required this.api, required this.onSaved});
  @override State<AddAddressSheet> createState() => AddAddressSheetState();
}

// Valid label values accepted by the backend
const _labelOptions = [
  ('home',  '🏠', 'المنزل'),
  ('work',  '💼', 'العمل'),
  ('other', '📍', 'أخرى'),
];

String labelAr(String v) {
  for (final o in _labelOptions) { if (o.$1 == v) return o.$3; }
  return v;
}

class AddAddressSheetState extends State<AddAddressSheet> {
  String _label = 'home'; // enum value sent to backend
  final _streetCtrl   = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _floorCtrl    = TextEditingController();
  final _aptCtrl      = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  bool _isDefault = false;
  bool _saving = false;

  // ── Map location ──────────────────────────────────────────────────────────
  double? _lat;
  double? _lng;

  @override
  void dispose() {
    _streetCtrl.dispose(); _buildingCtrl.dispose();
    _floorCtrl.dispose(); _aptCtrl.dispose(); _landmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_streetCtrl.text.trim().isEmpty ||
        _buildingCtrl.text.trim().isEmpty ||
        _floorCtrl.text.trim().isEmpty ||
        _aptCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى ملء الحقول المطلوبة', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final addr = await widget.api.createAddress({
        'label':            _label,
        'full_address':     _streetCtrl.text.trim(),
        'building_number':  _buildingCtrl.text.trim(),
        'floor_number':     _floorCtrl.text.trim(),
        'apartment_number': _aptCtrl.text.trim(),
        'landmark':         _landmarkCtrl.text.trim(),
        'latitude':         _lat != null ? double.parse(_lat!.toStringAsFixed(6)) : 0,
        'longitude':        _lng != null ? double.parse(_lng!.toStringAsFixed(6)) : 0,
        'is_default':       _isDefault,
      });
      widget.onSaved(addr);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(), style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            const Center(child: Text('عنوان جديد',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo', color: AppColors.textMain))),
            const SizedBox(height: 20),

            // Label selector — home / work / other
            Row(children: _labelOptions.map((opt) {
              final selected = _label == opt.$1;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _label = opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.coral : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppColors.coral : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: Column(children: [
                    Text(opt.$2, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(opt.$3, style: TextStyle(
                      fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.textMuted,
                    )),
                  ]),
                ),
              ));
            }).toList()),
            const SizedBox(height: 14),

            _field(_streetCtrl,   'الشارع / المنطقة *', Icons.home_outlined),
            Row(children: [
              Expanded(child: _field(_buildingCtrl, 'المبنى *', Icons.apartment_outlined,
                  type: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: _field(_floorCtrl, 'الدور *', Icons.layers_outlined,
                  type: TextInputType.number)),
            ]),
            _field(_aptCtrl,      'رقم الشقة *', Icons.meeting_room_outlined,
                type: TextInputType.number),
            _field(_landmarkCtrl, 'علامة مميزة (اختياري)', Icons.place_outlined, last: true),

            const SizedBox(height: 14),

            // ── Map location picker button ────────────────────────────────
            GestureDetector(
              onTap: () async {
                final picked = await Navigator.of(context).push<LatLng>(
                  MaterialPageRoute(
                    builder: (_) => MapLocationPickerScreen(
                      initialPosition: (_lat != null && _lng != null)
                          ? LatLng(_lat!, _lng!)
                          : null,
                    ),
                  ),
                );
                if (picked != null) {
                  setState(() {
                    _lat = picked.latitude;
                    _lng = picked.longitude;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (_lat != null)
                      ? AppColors.mint.withValues(alpha: 0.12)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_lat != null) ? AppColors.mint : AppColors.border,
                    width: (_lat != null) ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    (_lat != null) ? Icons.check_circle : Icons.map_outlined,
                    color: (_lat != null) ? AppColors.mint : AppColors.sky,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (_lat != null)
                          ? '✅ تم تحديد الموقع على الخريطة'
                          : 'تحديد الموقع على الخريطة 📍',
                      style: TextStyle(
                        fontFamily: 'Cairo', fontSize: 13,
                        color: (_lat != null) ? AppColors.mint : AppColors.sky,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_left,
                      color: (_lat != null) ? AppColors.mint : AppColors.textMuted,
                      size: 18),
                ]),
              ),
            ),

            const SizedBox(height: 12),
            Row(children: [
              Checkbox(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                activeColor: AppColors.coral,
              ),
              const Text('اجعله العنوان الافتراضي',
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textMain)),
            ]),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coral, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('حفظ العنوان',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

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
          filled: true, fillColor: Colors.white,
          prefixIcon: Icon(icon, size: 18, color: AppColors.sky),
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.coral, width: 1.5)),
        ),
      ),
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
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.midnight.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
          child: SizedBox(width: 72, height: 72,
            child: hasImage
              ? CachedNetworkImage(imageUrl: p.mainImageUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => _imgPlaceholder(),
                  errorWidget: (_, __, ___) => _imgPlaceholder())
              : _imgPlaceholder()),
        ),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nameAr,
              style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Cairo',
                  fontSize: 13, color: AppColors.textMain),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(p.currentPrice > 0
                ? '${(p.currentPrice * item.quantity).toStringAsFixed(2)} ج'
                : 'السعر عند الطلب',
              style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Cairo', fontSize: 14,
                  color: p.currentPrice > 0 ? AppColors.coral : AppColors.textMuted)),
          ]),
        )),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(children: [
            _qtyBtn(Icons.remove_rounded, onDecrease, AppColors.sky),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                p.isWeighed ? Formatters.weightLabel(item.quantity) : '${item.quantity.toInt()}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: p.isWeighed ? 12 : 16,
                    fontFamily: 'Cairo', color: AppColors.textMain))),
            _qtyBtn(Icons.add_rounded, onIncrease, AppColors.coral),
          ]),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _imgPlaceholder() => Container(color: AppColors.ice,
    child: const Center(child: Icon(Icons.shopping_basket_outlined,
        color: AppColors.sky, size: 24)));

  Widget _qtyBtn(IconData icon, VoidCallback onTap, Color color) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Icon(icon, size: 16, color: color),
    ),
  );
}
