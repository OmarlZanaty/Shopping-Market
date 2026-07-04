import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../../utils/constants.dart';
class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];
  String? _customerNotes;
  AddressModel? _selectedAddress;
  String _paymentMethod = 'cash';
  int _pointsToUse = 0;

  List<CartItem> get items => _items;
  String? get customerNotes => _customerNotes;
  AddressModel? get selectedAddress => _selectedAddress;
  String get paymentMethod => _paymentMethod;
  int get pointsToUse => _pointsToUse;
  // Weight-based lines (e.g. 0.5 kg) count as a single item for the badge;
  // piece lines count by their whole quantity.
  int get itemCount => _items.fold(0, (sum, i) =>
      sum + (i.product.isWeighed ? 1 : i.quantity.toInt()));

  double get subtotal => _items.fold(0, (sum, i) => sum + i.lineTotal);
  double get deliveryFee => 15.0;
  double get savings     => _items.fold(0, (sum, i) => sum + i.product.savings * i.quantity);
  double get pointsValue => LoyaltyConfig.valueForPoints(_pointsToUse);
  double get total       => (subtotal + deliveryFee - pointsValue).clamp(0, double.infinity);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  double getQuantity(String productId) {
    final idx = _items.indexWhere((i) => i.product.id == productId);
    return idx >= 0 ? _items[idx].quantity : 0;
  }

  void decrementItem(String productId) {
    final idx = _items.indexWhere((i) => i.product.id == productId);
    if (idx < 0) return;
    if (_items[idx].quantity <= 1) {
      _items.removeAt(idx);
    } else {
      _items[idx].quantity -= 1;
    }
    _persist();
    notifyListeners();
  }

  void addItem(ProductModel product, {double qty = 1}) {
    final idx = _items.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      _items[idx].quantity += qty;
    } else {
      _items.add(CartItem(product: product, quantity: qty));
    }
    _persist();
    notifyListeners();
  }

  void removeItem(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    _persist();
    notifyListeners();
  }

  void updateQuantity(String productId, double qty) {
    final idx = _items.indexWhere((i) => i.product.id == productId);
    if (idx >= 0) {
      if (qty <= 0) {
        _items.removeAt(idx);
      } else {
        _items[idx].quantity = qty;
      }
      _persist();
      notifyListeners();
    }
  }

  void setNotes(String notes) {
    _customerNotes = notes;
    notifyListeners();
  }

  void setAddress(AddressModel addr) {
    _selectedAddress = addr;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setPointsToUse(int points) {
    _pointsToUse = points;
    notifyListeners();
  }

  Map<String, dynamic> toOrderPayload() {
    return {
      'items': _items.map((i) => {
        'product_id': i.product.id,
        'quantity': i.quantity,
      }).toList(),
      if (_selectedAddress != null) 'address_id': _selectedAddress!.id,
      'delivery_name': '',
      'delivery_phone': '',
      'delivery_address': _selectedAddress?.fullAddress ?? '',
      'building_number': _selectedAddress?.buildingNumber ?? '',
      'floor_number': _selectedAddress?.floorNumber ?? '',
      'apartment_number': _selectedAddress?.apartmentNumber ?? '',
      'landmark': _selectedAddress?.landmark ?? '',
      if (_selectedAddress != null) 'delivery_latitude': _selectedAddress!.latitude,
      if (_selectedAddress != null) 'delivery_longitude': _selectedAddress!.longitude,
      'payment_method': _paymentMethod,
      'customer_notes': _customerNotes ?? '',
      'points_to_use': _pointsToUse,
    };
  }

  void clear() {
    _items.clear();
    _customerNotes = null;
    _pointsToUse = 0;
    _persist();
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(StorageKeys.cartItems);
      if (json != null) {
        final list = jsonDecode(json) as List;
        // Note: We only persist basic cart data; products are refetched
        // In production, store product snapshots
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Store minimal cart data for session persistence
      await prefs.setString(StorageKeys.cartItems, jsonEncode(
        _items.map((i) => {'product_id': i.product.id, 'quantity': i.quantity}).toList()
      ));
    } catch (_) {}
  }
}
