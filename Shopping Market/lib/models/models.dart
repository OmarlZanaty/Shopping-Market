// ─── User Model ───────────────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String phone;
  final String fullName;
  final String? email;
  final String? avatarUrl;
  final String role;
  final double walletBalance;
  final int loyaltyPoints;
  final int orderStreak;
  final double? rating;
  final bool isOnline;
  final String? fcmToken;

  const UserModel({
    required this.id,
    required this.phone,
    required this.fullName,
    this.email,
    this.avatarUrl,
    required this.role,
    this.walletBalance = 0,
    this.loyaltyPoints = 0,
    this.orderStreak = 0,
    this.rating,
    this.isOnline = false,
    this.fcmToken,
  });

  bool get isCustomer => role == 'customer';
  bool get isDriver   => role == 'driver';
  bool get isAdmin    => role == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id:             j['id'] ?? '',
    phone:          j['phone'] ?? '',
    fullName:       j['full_name'] ?? '',
    email:          j['email'],
    avatarUrl:      j['avatar_url'],
    role:           j['role'] ?? 'customer',
    walletBalance:  double.tryParse(j['wallet_balance']?.toString() ?? '0') ?? 0,
    loyaltyPoints:  j['loyalty_points'] ?? 0,
    orderStreak:    j['order_streak'] ?? 0,
    rating:         double.tryParse(j['rating']?.toString() ?? ''),
    isOnline:       j['is_online'] ?? false,
    fcmToken:       j['fcm_token'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'full_name': fullName,
    'email': email,
    'role': role,
    'avatar_url': avatarUrl,
    'wallet_balance': walletBalance.toString(),
    'loyalty_points': loyaltyPoints,
    'order_streak': orderStreak,
    'rating': rating?.toString(),
    'is_online': isOnline,
    'fcm_token': fcmToken,
  };

  UserModel copyWith({String? fcmToken, int? loyaltyPoints, double? walletBalance}) => UserModel(
    id: id, phone: phone, fullName: fullName, email: email,
    avatarUrl: avatarUrl, role: role,
    walletBalance: walletBalance ?? this.walletBalance,
    loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
    orderStreak: orderStreak, rating: rating, isOnline: isOnline,
    fcmToken: fcmToken ?? this.fcmToken,
  );
}

// ─── Address Model ─────────────────────────────────────────────────────────────
class AddressModel {
  final int? id;
  final String label;
  final String fullAddress;
  final String buildingNumber;
  final String floorNumber;
  final String apartmentNumber;
  final String landmark;
  final double latitude;
  final double longitude;
  final bool isDefault;

  const AddressModel({
    this.id,
    required this.label,
    required this.fullAddress,
    required this.buildingNumber,
    required this.floorNumber,
    required this.apartmentNumber,
    this.landmark = '',
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
  });

  factory AddressModel.fromJson(Map<String, dynamic> j) => AddressModel(
    id:              j['id'],
    label:           j['label'] ?? 'Home',
    fullAddress:     j['full_address'] ?? '',
    buildingNumber:  j['building_number'] ?? '',
    floorNumber:     j['floor_number'] ?? '',
    apartmentNumber: j['apartment_number'] ?? '',
    landmark:        j['landmark'] ?? '',
    latitude:        double.tryParse(j['latitude']?.toString() ?? '0') ?? 0,
    longitude:       double.tryParse(j['longitude']?.toString() ?? '0') ?? 0,
    isDefault:       j['is_default'] ?? false,
  );
}

// ─── Category Model ────────────────────────────────────────────────────────────
class CategoryModel {
  final int id;
  final String nameAr;
  final String nameEn;
  final String? imageUrl;
  final String icon;
  final int sortOrder;
  final int productCount;

  const CategoryModel({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.imageUrl,
    this.icon = '🛍️',
    this.sortOrder = 0,
    this.productCount = 0,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> j) => CategoryModel(
    id:           j['id'],
    nameAr:       j['name_ar'] ?? '',
    nameEn:       j['name_en'] ?? '',
    imageUrl:     j['image'],
    icon:         j['icon'] ?? '🛍️',
    sortOrder:    j['sort_order'] ?? 0,
    productCount: j['product_count'] ?? 0,
  );

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

// ─── Product Model ─────────────────────────────────────────────────────────────
class ProductModel {
  final String id;
  final String? barcode;
  final String nameAr;
  final String nameEn;
  final String descriptionAr;
  final String descriptionEn;
  final double originalPrice;
  final double? discountPrice;
  final double currentPrice;
  final double discountPercentage;
  final int quantityInStock;
  final bool isAvailable;
  final bool isFeatured;
  final String sellUnit;
  final bool isWeightBased;
  final String mainImageUrl;
  /// Extra gallery image URLs (from the ProductImage table).
  final List<String> galleryUrls;
  final List<CategoryModel> categories;
  final List<ProductModel> alternatives;
  final List<ProductModel> related;
  final bool isOnSale;
  final bool isOutOfStock;
  /// True when the authenticated customer has already joined this product's waitlist.
  final bool isOnWaitlist;
  /// Number of pending (un-notified) waitlist entries — populated in admin responses.
  final int waitlistCount;

  const ProductModel({
    required this.id,
    this.barcode,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr = '',
    this.descriptionEn = '',
    required this.originalPrice,
    this.discountPrice,
    required this.currentPrice,
    this.discountPercentage = 0,
    this.quantityInStock = 0,
    this.isAvailable = true,
    this.isFeatured = false,
    this.sellUnit = 'piece',
    this.isWeightBased = false,
    this.mainImageUrl = '',
    this.galleryUrls = const [],
    this.categories = const [],
    this.alternatives = const [],
    this.related = const [],
    this.isOnSale = false,
    this.isOutOfStock = false,
    this.isOnWaitlist = false,
    this.waitlistCount = 0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) => ProductModel(
    id:                  j['id'] ?? '',
    barcode:             j['barcode'],
    nameAr:              j['name_ar'] ?? '',
    nameEn:              j['name_en'] ?? '',
    descriptionAr:       j['description_ar'] ?? '',
    descriptionEn:       j['description_en'] ?? '',
    originalPrice:       double.tryParse(j['original_price']?.toString() ?? '0') ?? 0,
    discountPrice:       j['discount_price'] != null ? double.tryParse(j['discount_price'].toString()) : null,
    currentPrice:        double.tryParse(j['current_price']?.toString() ?? '0') ?? 0,
    discountPercentage:  double.tryParse(j['discount_percentage']?.toString() ?? '0') ?? 0,
    quantityInStock:     j['quantity_in_stock'] ?? 0,
    isAvailable:         j['is_available'] ?? true,
    isFeatured:          j['is_featured'] ?? false,
    sellUnit:            j['sell_unit'] ?? 'piece',
    isWeightBased:       j['is_weight_based'] ?? false,
    mainImageUrl:        j['image_url_s3'] ?? j['thumbnail_url'] ?? j['main_image_url'] ?? j['image_url'] ?? '',
    galleryUrls:         (j['images'] as List? ?? [])
                            .map((im) => (im is Map
                                ? (im['image_url_full'] ?? im['image_url'] ?? '')
                                : '').toString())
                            .where((u) => u.isNotEmpty)
                            .toList()
                            .cast<String>(),
    categories:          (j['categories'] as List? ?? []).map((c) => CategoryModel.fromJson(c)).toList(),
    alternatives:        (j['alternatives'] as List? ?? []).map((p) => ProductModel.fromJson(p)).toList(),
    related:             (j['related'] as List? ?? []).map((p) => ProductModel.fromJson(p)).toList(),
    isOnSale:            j['is_on_sale'] ?? false,
    isOutOfStock:        j['is_out_of_stock'] ?? false,
    isOnWaitlist:        j['is_on_waitlist'] ?? false,
    waitlistCount:       j['waitlist_count'] ?? 0,
  );

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
  String description(String lang) => lang == 'ar' ? descriptionAr : descriptionEn;
  double get savings => originalPrice - currentPrice;

  /// True when this product is sold by weight (price is per kg) — the customer
  /// picks grams instead of a piece count. Honours the explicit backend flag
  /// and also infers it from a weight/volume sell unit for older rows.
  bool get isWeighed =>
      isWeightBased || sellUnit == 'kg' || sellUnit == 'gram' || sellUnit == 'liter';

  /// All images for the carousel: main image first, then the gallery, deduped.
  List<String> get allImageUrls {
    final urls = <String>[];
    if (mainImageUrl.isNotEmpty) urls.add(mainImageUrl);
    for (final u in galleryUrls) {
      if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
    }
    return urls;
  }
}

// ─── Cart Item ─────────────────────────────────────────────────────────────────
class CartItem {
  final ProductModel product;
  double quantity;
  String? notes;

  CartItem({required this.product, this.quantity = 1, this.notes});

  double get lineTotal => product.currentPrice * quantity;
}

// ─── Order Models ─────────────────────────────────────────────────────────────
class OrderModel {
  final String id;
  final String orderId;
  final String status;
  final String? customerName;
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;
  final double? driverRating;
  final String deliveryAddress;
  final String buildingNumber;
  final String floorNumber;
  final String apartmentNumber;
  final String landmark;
  final double deliveryLat;
  final double deliveryLng;
  final String deliveryPhone;
  final String paymentMethod;
  final String paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final double totalSavings;
  final int pointsUsed;
  final int pointsEarned;
  final String customerNotes;
  final List<OrderItemModel> items;
  final List<OrderAdjustmentModel> adjustments;
  final OrderRatingModel? rating;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  const OrderModel({
    required this.id,
    required this.orderId,
    required this.status,
    this.customerName,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
    this.driverRating,
    required this.deliveryAddress,
    this.buildingNumber = '',
    this.floorNumber = '',
    this.apartmentNumber = '',
    this.landmark = '',
    this.deliveryLat = 0,
    this.deliveryLng = 0,
    this.deliveryPhone = '',
    this.paymentMethod = 'cash',
    this.paymentStatus = 'pending',
    this.subtotal = 0,
    this.deliveryFee = 15,
    this.totalAmount = 0,
    this.totalSavings = 0,
    this.pointsUsed = 0,
    this.pointsEarned = 0,
    this.customerNotes = '',
    this.items = const [],
    this.adjustments = const [],
    this.rating,
    required this.createdAt,
    this.deliveredAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final driverInfo = j['driver_info'] as Map<String, dynamic>?;
    return OrderModel(
      id:              j['id'] ?? '',
      orderId:         j['order_id'] ?? '',
      status:          j['status'] ?? 'new',
      customerName:    j['customer_name'] ?? j['delivery_name'] ?? (j['customer_info'] as Map<String, dynamic>?)?['name'],
      driverName:      driverInfo?['name'],
      driverPhone:     driverInfo?['phone'],
      driverLat:       double.tryParse(driverInfo?['latitude']?.toString() ?? ''),
      driverLng:       double.tryParse(driverInfo?['longitude']?.toString() ?? ''),
      driverRating:    double.tryParse(driverInfo?['rating']?.toString() ?? ''),
      deliveryAddress: j['delivery_address'] ?? '',
      buildingNumber:  j['building_number'] ?? '',
      floorNumber:     j['floor_number'] ?? '',
      apartmentNumber: j['apartment_number'] ?? '',
      landmark:        j['landmark'] ?? '',
      deliveryLat:     double.tryParse(j['delivery_latitude']?.toString() ?? '0') ?? 0,
      deliveryLng:     double.tryParse(j['delivery_longitude']?.toString() ?? '0') ?? 0,
      deliveryPhone:   j['delivery_phone'] ?? '',
      paymentMethod:   j['payment_method'] ?? 'cash',
      paymentStatus:   j['payment_status'] ?? 'pending',
      subtotal:        double.tryParse(j['subtotal']?.toString() ?? '0') ?? 0,
      deliveryFee:     double.tryParse(j['delivery_fee']?.toString() ?? '15') ?? 15,
      totalAmount:     double.tryParse(j['total_amount']?.toString() ?? '0') ?? 0,
      totalSavings:    double.tryParse(j['total_savings']?.toString() ?? '0') ?? 0,
      pointsUsed:      j['points_used'] ?? 0,
      pointsEarned:    j['points_earned'] ?? 0,
      customerNotes:   j['customer_notes'] ?? '',
      items:           (j['items'] as List? ?? []).map((i) => OrderItemModel.fromJson(i)).toList(),
      adjustments:     (j['adjustments'] as List? ?? []).map((a) => OrderAdjustmentModel.fromJson(a)).toList(),
      rating:          j['rating'] != null ? OrderRatingModel.fromJson(j['rating']) : null,
      createdAt:       DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      deliveredAt:     j['delivered_at'] != null ? DateTime.tryParse(j['delivered_at']) : null,
    );
  }
}

class OrderItemModel {
  final int id;
  final String productId;
  final String productNameAr;
  final String productNameEn;
  final String? productBarcode;
  final String? productImageUrl;
  final double quantity;
  final double? deliveredQuantity;
  final double unitPrice;
  final double? finalUnitPrice;
  final String status;
  final bool addedByDriver;
  final bool? customerApproved;
  final String driverNotes;
  final double weightVariance;
  final double weightVarianceAmount;

  const OrderItemModel({
    required this.id,
    required this.productId,
    required this.productNameAr,
    required this.productNameEn,
    this.productBarcode,
    this.productImageUrl,
    required this.quantity,
    this.deliveredQuantity,
    required this.unitPrice,
    this.finalUnitPrice,
    this.status = 'pending',
    this.addedByDriver = false,
    this.customerApproved,
    this.driverNotes = '',
    this.weightVariance = 0,
    this.weightVarianceAmount = 0,
  });

  double get effectivePrice => finalUnitPrice ?? unitPrice;
  double get effectiveQty   => deliveredQuantity ?? quantity;
  double get lineTotal      => effectivePrice * effectiveQty;
  String name(String lang)  => lang == 'ar' ? productNameAr : productNameEn;

  factory OrderItemModel.fromJson(Map<String, dynamic> j) => OrderItemModel(
    id:                    j['id'],
    productId:             j['product'] ?? '',
    productNameAr:         j['product_name_ar'] ?? '',
    productNameEn:         j['product_name_en'] ?? '',
    productBarcode:        j['product_barcode'],
    productImageUrl:       j['product_image'],
    quantity:              double.tryParse(j['quantity']?.toString() ?? '1') ?? 1,
    deliveredQuantity:     j['delivered_quantity'] != null ? double.tryParse(j['delivered_quantity'].toString()) : null,
    unitPrice:             double.tryParse(j['unit_price']?.toString() ?? '0') ?? 0,
    finalUnitPrice:        j['final_unit_price'] != null ? double.tryParse(j['final_unit_price'].toString()) : null,
    status:                j['status'] ?? 'pending',
    addedByDriver:         j['added_by_driver'] ?? false,
    customerApproved:      j['customer_approved'],
    driverNotes:           j['driver_notes'] ?? '',
    weightVariance:        double.tryParse(j['weight_variance']?.toString() ?? '0') ?? 0,
    weightVarianceAmount:  double.tryParse(j['weight_variance_amount']?.toString() ?? '0') ?? 0,
  );
}

class OrderAdjustmentModel {
  final int id;
  final String adjustmentType;
  final String oldValue;
  final String newValue;
  final String reason;
  final bool? customerApproved;
  final double? newTotal;
  /// FK to the OrderItem (null on order-level adjustments). Used to group
  /// multiple substitute suggestions for the SAME line item.
  final int? orderItemId;
  /// "pending" | "approved" | "rejected" (or null on legacy records).
  final String? approvalStatus;
  /// Parsed substitute payload from the backend (only set for
  /// `substitute_suggested` / `substitute` adjustments). Keys:
  /// `product_id`, `name_ar`, `name_en`, `barcode`, `price`, `image_url`.
  final Map<String, dynamic>? substituteInfo;

  const OrderAdjustmentModel({
    required this.id,
    required this.adjustmentType,
    this.oldValue = '',
    this.newValue = '',
    this.reason = '',
    this.customerApproved,
    this.newTotal,
    this.orderItemId,
    this.approvalStatus,
    this.substituteInfo,
  });

  /// True iff the customer hasn't responded yet (pending or null status).
  bool get isPending =>
      (approvalStatus == null || approvalStatus == 'pending') &&
      customerApproved == null;

  factory OrderAdjustmentModel.fromJson(Map<String, dynamic> j) {
    int? _itemId() {
      final v = j['order_item'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      return null;
    }
    Map<String, dynamic>? _sub() {
      final v = j['substitute_info'];
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }
    return OrderAdjustmentModel(
      id:               j['id'],
      adjustmentType:   j['adjustment_type'] ?? j['action_type'] ?? '',
      oldValue:         j['old_value'] ?? '',
      newValue:         j['new_value'] ?? '',
      reason:           j['reason'] ?? '',
      customerApproved: j['customer_approved'],
      newTotal:         j['new_total'] != null ? double.tryParse(j['new_total'].toString()) : null,
      orderItemId:      _itemId(),
      approvalStatus:   j['customer_approval_status']?.toString(),
      substituteInfo:   _sub(),
    );
  }
}

class OrderRatingModel {
  final int productRating;
  final int deliveryRating;
  final String comment;

  const OrderRatingModel({
    required this.productRating,
    required this.deliveryRating,
    this.comment = '',
  });

  factory OrderRatingModel.fromJson(Map<String, dynamic> j) => OrderRatingModel(
    productRating:  j['product_rating'] ?? 5,
    deliveryRating: j['delivery_rating'] ?? 5,
    comment:        j['comment'] ?? '',
  );
}

class BannerModel {
  final int id;
  final String titleAr;
  final String titleEn;
  final String subtitleAr;
  final String subtitleEn;
  final String imageUrl;
  final String position;
  final String linkType;
  final String? linkProductId;
  final int? linkCategoryId;

  const BannerModel({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    this.subtitleAr = '',
    this.subtitleEn = '',
    required this.imageUrl,
    this.position = 'home_main',
    this.linkType = 'none',
    this.linkProductId,
    this.linkCategoryId,
  });

  factory BannerModel.fromJson(Map<String, dynamic> j) => BannerModel(
    id:             j['id'],
    titleAr:        j['title_ar'] ?? '',
    titleEn:        j['title_en'] ?? '',
    subtitleAr:     j['subtitle_ar'] ?? '',
    subtitleEn:     j['subtitle_en'] ?? '',
    imageUrl:       j['image_url'] ?? j['image'] ?? '',
    position:       j['position'] ?? 'home_main',
    linkType:       j['link_type'] ?? 'none',
    linkProductId:  j['link_product'],
    linkCategoryId: j['link_category'],
  );

  String title(String lang)    => lang == 'ar' ? titleAr : titleEn;
  String subtitle(String lang) => lang == 'ar' ? subtitleAr : subtitleEn;
}
