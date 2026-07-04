class OrderItemModel {
  final int id;
  final String productId;
  final String nameAr;
  final String? imageUrl;
  final String? barcode;
  final double requestedQty;
  final double? actualQty;
  final double unitPrice;
  final double? finalUnitPrice;
  final String unitType;
  final bool isWeightBased;
  final double weightTolerancePct;
  final String status;

  OrderItemModel({
    required this.id, required this.productId, required this.nameAr,
    this.imageUrl, this.barcode,
    required this.requestedQty, this.actualQty,
    required this.unitPrice, this.finalUnitPrice,
    this.unitType = 'piece', this.isWeightBased = false,
    this.weightTolerancePct = 5.0,
    this.status = 'pending',
  });

  double get effectiveQty => actualQty ?? requestedQty;
  double get effectivePrice => finalUnitPrice ?? unitPrice;
  double get lineTotal => effectiveQty * effectivePrice;

  /// True when this item is sold by weight (price per kg, picked in grams).
  /// Honours the backend flag and also infers it from a weight/volume unit so
  /// older orders (created before the flag existed) still behave correctly.
  bool get isWeighed =>
      isWeightBased ||
      unitType == 'kg' || unitType == 'gram' || unitType == 'liter';

  /// Human label for the quantity: weight (e.g. "500 جم" / "1.5 كجم") for
  /// weighed items, otherwise a plain count.
  String qtyLabel(double qty) {
    if (!isWeighed) {
      return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
    }
    if (qty < 1) return '${(qty * 1000).round()} جم';
    final s = qty == qty.roundToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s كجم';
  }

  static String? _nonEmpty(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory OrderItemModel.fromJson(Map<String, dynamic> j) => OrderItemModel(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id'].toString()) ?? 0,
        productId: j['product_id']?.toString() ?? j['product']?.toString() ?? '',
        nameAr: (j['product_name_ar'] ?? j['name_ar'] ?? j['name'] ?? '').toString(),
        // Treat empty string the same as null — an empty URL causes a NetworkImage crash.
        imageUrl: _nonEmpty(j['product_image']) ?? _nonEmpty(j['image_url']),
        barcode: j['product_barcode'] ?? j['barcode'],
        requestedQty: double.tryParse((j['requested_qty'] ?? j['quantity'] ?? '1').toString()) ?? 1,
        actualQty: j['actual_qty'] != null ? double.tryParse(j['actual_qty'].toString()) : null,
        unitPrice: double.tryParse((j['unit_price'] ?? j['price'] ?? '0').toString()) ?? 0,
        finalUnitPrice: j['final_unit_price'] != null
            ? double.tryParse(j['final_unit_price'].toString()) : null,
        unitType: (j['unit_type'] ?? 'piece').toString(),
        isWeightBased: j['is_weight_based'] == true,
        weightTolerancePct: double.tryParse(
            (j['weight_tolerance_pct'] ?? 5).toString()) ?? 5,
        status: (j['status'] ?? 'pending').toString(),
      );
}

class OrderModel {
  final String id;
  final String orderNumber;
  final String status;
  final String customerName;
  final String customerPhone;
  final String addressFull;
  final double? lat;
  final double? lng;
  final String paymentMethod;
  final double total;
  final double deliveryFee;
  final String notes;
  final String? branchName;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  /// From the list serializer's `items_count` field.
  /// Falls back to `items.length` when full items are loaded (detail view).
  final int? _itemsCount;
  /// Up to 3 lightweight item summaries from the list endpoint
  /// (name_ar / name_en / qty / unit_type) — used by OrderCard so the agent
  /// can see what's inside a queue order without opening the detail screen.
  /// Falls back to a built-from-items list when full items are loaded.
  final List<Map<String, String>> _itemsPreview;

  int get itemCount => _itemsCount ?? items.length;

  List<Map<String, String>> get itemsPreview {
    if (_itemsPreview.isNotEmpty) return _itemsPreview;
    return items.take(3).map((it) => {
      'name_ar': it.nameAr,
      'name_en': '',
      'qty': it.requestedQty.toString(),
      'unit_type': it.unitType,
    }).toList();
  }

  OrderModel({
    required this.id, required this.orderNumber, required this.status,
    required this.customerName, required this.customerPhone,
    required this.addressFull, this.lat, this.lng,
    required this.paymentMethod, required this.total,
    this.deliveryFee = 0, this.notes = '',
    this.branchName, required this.createdAt,
    this.items = const [],
    int? itemsCount,
    List<Map<String, String>> itemsPreview = const [],
  }) : _itemsCount = itemsCount,
       _itemsPreview = itemsPreview;

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    // Backend returns customer_info: {id, name, phone} as a SerializerMethodField.
    // j['customer'] is just the FK UUID — NOT a nested object.
    final custInfo = j['customer_info'] is Map
        ? Map<String, dynamic>.from(j['customer_info'] as Map)
        : <String, dynamic>{};

    // delivery_address is a flat string field on the Order model.
    // Build a readable full address from the flat fields.
    final addressParts = <String>[];
    final deliveryAddr = (j['delivery_address'] ?? '').toString().trim();
    if (deliveryAddr.isNotEmpty) addressParts.add(deliveryAddr);

    final building = (j['building_number'] ?? '').toString().trim();
    final floor    = (j['floor_number']    ?? '').toString().trim();
    final apt      = (j['apartment_number'] ?? '').toString().trim();
    if (building.isNotEmpty || floor.isNotEmpty || apt.isNotEmpty) {
      addressParts.add('عمارة $building - دور $floor - شقة $apt');
    }
    final landmark = (j['landmark'] ?? '').toString().trim();
    if (landmark.isNotEmpty) addressParts.add('علامة: $landmark');

    final itemsJson = (j['items'] as List?) ?? const [];

    return OrderModel(
      id:            j['id']?.toString() ?? '',
      orderNumber:   (j['order_number'] ?? j['order_id'] ?? '').toString(),
      status:        (j['status'] ?? 'new').toString(),
      // customer_info.name → delivery_name → fallback
      customerName:  (custInfo['name']  ?? j['delivery_name']  ?? j['customer_name']  ?? '').toString(),
      customerPhone: (custInfo['phone'] ?? j['delivery_phone'] ?? j['customer_phone'] ?? '').toString(),
      addressFull:   addressParts.join('\n'),
      lat: double.tryParse((j['delivery_latitude']  ?? '').toString()),
      lng: double.tryParse((j['delivery_longitude'] ?? '').toString()),
      paymentMethod: (j['payment_method'] ?? 'cash').toString(),
      total:       double.tryParse((j['total_amount'] ?? j['total'] ?? '0').toString()) ?? 0,
      deliveryFee: double.tryParse((j['delivery_fee'] ?? '0').toString()) ?? 0,
      notes:       (j['customer_notes'] ?? j['notes'] ?? '').toString(),
      branchName:  j['branch_name']?.toString() ??
                   (j['branch'] is Map ? (j['branch'] as Map)['name'] : null)?.toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
      items: itemsJson
          .map((i) => OrderItemModel.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList(),
      itemsCount: j['items_count'] is int ? j['items_count'] as int : null,
      itemsPreview: (j['items_preview'] is List)
          ? (j['items_preview'] as List).map<Map<String, String>>((e) {
              final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
              return {
                'name_ar':  (m['name_ar']  ?? '').toString(),
                'name_en':  (m['name_en']  ?? '').toString(),
                'qty':      (m['qty']      ?? '').toString(),
                'unit_type':(m['unit_type'] ?? '').toString(),
              };
            }).toList()
          : const [],
    );
  }
}
