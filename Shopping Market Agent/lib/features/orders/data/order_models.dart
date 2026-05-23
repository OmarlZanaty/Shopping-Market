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

  factory OrderItemModel.fromJson(Map<String, dynamic> j) => OrderItemModel(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id'].toString()) ?? 0,
        productId: j['product_id']?.toString() ?? j['product']?.toString() ?? '',
        nameAr: (j['product_name_ar'] ?? j['name_ar'] ?? j['name'] ?? '').toString(),
        imageUrl: j['product_image'] ?? j['image_url'],
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

  OrderModel({
    required this.id, required this.orderNumber, required this.status,
    required this.customerName, required this.customerPhone,
    required this.addressFull, this.lat, this.lng,
    required this.paymentMethod, required this.total,
    this.deliveryFee = 0, this.notes = '',
    this.branchName, required this.createdAt,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final cust = j['customer'] is Map ? Map<String, dynamic>.from(j['customer']) : {};
    final addr = j['delivery_address'] is Map
        ? Map<String, dynamic>.from(j['delivery_address']) : {};
    final itemsJson = (j['items'] as List?) ?? const [];
    return OrderModel(
      id: j['id']?.toString() ?? '',
      orderNumber: (j['order_number'] ?? j['order_id'] ?? '').toString(),
      status: (j['status'] ?? 'new').toString(),
      customerName: (cust['full_name'] ?? j['customer_name'] ?? '').toString(),
      customerPhone: (cust['phone'] ?? j['customer_phone'] ?? '').toString(),
      addressFull: (addr['full_address'] ?? j['delivery_address_text'] ?? '').toString(),
      lat: double.tryParse((addr['latitude'] ?? j['delivery_latitude'] ?? '').toString()),
      lng: double.tryParse((addr['longitude'] ?? j['delivery_longitude'] ?? '').toString()),
      paymentMethod: (j['payment_method'] ?? 'cash').toString(),
      total: double.tryParse((j['total_amount'] ?? j['total'] ?? '0').toString()) ?? 0,
      deliveryFee: double.tryParse((j['delivery_fee'] ?? '0').toString()) ?? 0,
      notes: (j['customer_notes'] ?? j['notes'] ?? '').toString(),
      branchName: j['branch_name']?.toString() ?? (j['branch'] is Map ? j['branch']['name'] : null)?.toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
      items: itemsJson.map((i) => OrderItemModel.fromJson(Map<String, dynamic>.from(i))).toList(),
    );
  }
}
