enum StockStatus {
  inStock,
  lowStock,
  outOfStock;

  String get label {
    switch (this) {
      case StockStatus.inStock:
        return 'IN STOCK';
      // Stock above 0 but below the MOQ: the minimum order is unavailable.
      case StockStatus.lowStock:
        return 'BELOW MOQ';
      case StockStatus.outOfStock:
        return 'OUT OF STOCK';
    }
  }
}

class ProductModel {
  final String id;
  final String name;
  final String sku;
  final String categoryId;
  final String categoryName;
  final String brand;
  final double mrp;
  final double dealerPrice;
  final double? purchasePrice;

  /// Cabinet Price (products.cabinet_price) for Cabinet products; null when
  /// not set or for other categories. Never derived from Dealer Price or MRP.
  final double? cabinetPrice;

  /// True when a Cabinet Price should be shown.
  bool get hasCabinetPrice => cabinetPrice != null && cabinetPrice! > 0;

  /// Bulk Orders offer (products.bulk_*; server rule in bulk_orders.js):
  /// [bulkPrice] per piece, from [bulkMinQty] in steps of [bulkStep]
  /// (Domestic PDF: one pack, e.g. 42, 84, 126; Mukhil PDF: Mini qty, then
  /// +1). Null = not sold in Bulk Orders. Never replaces [dealerPrice].
  final double? bulkPrice;
  final int? bulkMinQty;
  final int? bulkStep;

  /// As printed in the PDF, e.g. "42 PCS" or "10 NOS".
  final String? bulkPackLabel;

  bool get hasBulkOffer =>
      bulkPrice != null &&
      bulkPrice! > 0 &&
      (bulkMinQty ?? 0) >= 1 &&
      (bulkStep ?? 0) >= 1 &&
      bulkMinQty! % bulkStep! == 0 &&
      (bulkPackLabel ?? '').trim().isNotEmpty;

  /// True when [quantity] is a valid bulk quantity (minimum + whole steps).
  bool isValidBulkQuantity(int quantity) =>
      hasBulkOffer &&
      quantity >= bulkMinQty! &&
      (quantity - bulkMinQty!) % bulkStep! == 0;

  /// Why [quantity] cannot be bought in Bulk Orders, or null (same rule as
  /// the server, bulk_orders.js: offer, stock, minimum + whole steps). The
  /// normal-purchase maximum does not apply to bulk lines.
  String? bulkQuantityProblem(int quantity) {
    if (!hasBulkOffer) return '$name is not available in Bulk Orders.';
    if (stockStatus == StockStatus.outOfStock) return '$name is out of stock.';
    if (!isValidBulkQuantity(quantity)) {
      return 'Bulk quantity for $name starts at $bulkMinQty and goes up in '
          'steps of $bulkStep.';
    }
    final stock = stockQuantity;
    if (stock != null && quantity > stock) {
      return 'Only $stock of $name in stock.';
    }
    return null;
  }

  /// The smallest bulk order: [bulkMinQty] x [bulkPrice].
  double? get bulkMinimumOrderValue =>
      hasBulkOffer ? bulkMinQty! * bulkPrice! : null;

  double get detailsPrice => purchasePrice ?? dealerPrice;
  final String imageUrl;
  final List<String> galleryImages;
  final StockStatus stockStatus;
  final int moq; // Minimum Order Quantity (1 when not set, for cart maths)
  /// False when the catalogue has no MOQ for this product (blank in the
  /// database). Screens then show "MOQ not set" instead of a number.
  final bool moqSet;

  /// Real inventory (products.stock_quantity); null when not tracked, or
  /// when a local preview has stock checks off. Never derived from the MOQ.
  final int? stockQuantity;

  /// Most units per order line, from the server: for the supplier-PDF
  /// catalogue this is the PDF quantity ("10 nos" -> 10). Null = no limit.
  final int? maxOrderQuantity;

  /// Stock 0 (or marked out of stock).
  bool get isOutOfStock => stockStatus == StockStatus.outOfStock;

  /// Not used by the current rule (kept for older data).
  bool get isBelowMoq => stockStatus == StockStatus.lowStock;

  /// Smallest quantity that may be ordered: always 1.
  int get minOrderQty => 1;

  /// Largest quantity allowed: the product maximum and the stock, whichever
  /// is lower (null when neither applies).
  int? get maxOrderQty {
    final limits = [?maxOrderQuantity, ?stockQuantity];
    if (limits.isEmpty) return null;
    return limits.reduce((a, b) => a < b ? a : b);
  }

  /// Can be added to the cart and ordered.
  bool get canOrder => !isOutOfStock;

  /// The MOQ as saved, for messages ("10 nos"), or "1".
  String get moqText =>
      moqSet ? '$moq${moqUnit == null ? '' : ' $moqUnit'}' : '1';

  /// Why it cannot be ordered at all, or null when it can.
  String? get orderBlockedReason =>
      isOutOfStock ? '$name is out of stock.' : null;

  /// True when [quantity] is above the product maximum (shows the
  /// "Maximum Order Quantity Reached" popup).
  bool exceedsMaximum(int quantity) =>
      maxOrderQuantity != null && quantity > maxOrderQuantity!;

  /// "You can order a maximum of 10 units for this product."
  String get maximumMessage =>
      'You can order a maximum of $maxOrderQuantity units for this product.';

  /// Why [quantity] (in total, in the cart) cannot be ordered, or null.
  String? quantityProblem(int quantity) {
    final blocked = orderBlockedReason;
    if (blocked != null) return blocked;
    if (quantity < 1) return 'Quantity must be at least 1.';
    if (exceedsMaximum(quantity)) return maximumMessage;
    final stock = stockQuantity;
    if (stock != null && quantity > stock)
      return 'Only $stock of $name in stock.';
    return null;
  }

  /// "MOQ: 10 Pcs", or "MOQ not set" when the catalogue has no value.
  /// Unit as saved with the quantity ("10 nos" -> "nos"), or null.
  final String? moqUnit;

  /// "MOQ: 10 nos" with the saved unit (or [unit] when none was saved), or
  /// "MOQ not set" when the catalogue has no value.
  String moqLabel([String unit = 'Pcs']) =>
      moqSet ? 'MOQ: $moq ${moqUnit ?? unit}' : 'MOQ not set';
  final double rating;
  final int reviewCount;
  final bool isFeatured;
  final String description;
  final Map<String, String> specifications;
  final List<String> features;

  /// When the product was added (from the database); null for older API
  /// responses. Used for "New Arrivals" and the "Newest First" sort.
  final DateTime? createdAt;

  const ProductModel({
    required this.id,
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.categoryName,
    required this.brand,
    required this.mrp,
    required this.dealerPrice,
    this.purchasePrice,
    this.cabinetPrice,
    this.bulkPrice,
    this.bulkMinQty,
    this.bulkStep,
    this.bulkPackLabel,
    required this.imageUrl,
    this.galleryImages = const [],
    required this.stockStatus,
    required this.moq,
    this.moqSet = true,
    this.moqUnit,
    this.stockQuantity,
    this.maxOrderQuantity,
    this.rating = 0,
    this.reviewCount = 0,
    this.isFeatured = false,
    this.description = '',
    this.specifications = const {},
    this.features = const [],
    this.createdAt,
  });

  /// The same product with another category name (everything else equal).
  ProductModel withCategoryName(String name) => ProductModel(
    id: id,
    name: this.name,
    sku: sku,
    categoryId: categoryId,
    categoryName: name,
    brand: brand,
    mrp: mrp,
    dealerPrice: dealerPrice,
    purchasePrice: purchasePrice,
    cabinetPrice: cabinetPrice,
    bulkPrice: bulkPrice,
    bulkMinQty: bulkMinQty,
    bulkStep: bulkStep,
    bulkPackLabel: bulkPackLabel,
    imageUrl: imageUrl,
    galleryImages: galleryImages,
    stockStatus: stockStatus,
    moq: moq,
    moqSet: moqSet,
    moqUnit: moqUnit,
    stockQuantity: stockQuantity,
    maxOrderQuantity: maxOrderQuantity,
    rating: rating,
    reviewCount: reviewCount,
    isFeatured: isFeatured,
    description: description,
    specifications: specifications,
    features: features,
    createdAt: createdAt,
  );

  /// Old shared demo picture names stored before real product photos
  /// existed. They are not this product's photo, so nothing is substituted
  /// for them: the product shows the water-drop "no picture yet" placeholder
  /// until a real image (e.g. Supabase Storage) is saved in the Admin Panel.
  static const Set<String> legacyPlaceholderImages = {
    'purifier.jpg',
    'cat_filter.jpg',
    'cat_pump.jpg',
    'cat_spares.jpg',
    'membrane.jpg',
  };

  /// The product's own picture, or '' when it has none (shown as the
  /// water-drop placeholder). A full web address saved by the admin (e.g. a
  /// Supabase Storage URL) is always shown as-is, even if its file name
  /// happens to be "membrane.jpg"; only bare legacy names are "no picture".
  String get displayImageUrl {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }
    final parsedSource = Uri.tryParse(trimmed);
    final sourcePath = parsedSource?.pathSegments.isNotEmpty == true
        ? parsedSource!.pathSegments.last.toLowerCase()
        : trimmed.toLowerCase();
    if (legacyPlaceholderImages.contains(sourcePath)) return '';
    return imageUrl;
  }

  List<String> get allImages {
    if (galleryImages.isNotEmpty) return galleryImages;
    return [displayImageUrl];
  }

  int get discountPercentage {
    if (mrp <= 0 || dealerPrice >= mrp) return 0;
    return (((mrp - dealerPrice) / mrp) * 100).round();
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    double number(dynamic value) =>
        double.tryParse('$value'.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final moqRaw = '${json['moq'] ?? ''}';
    // stock_enforced is false only in a local preview with stock checks off.
    final stockQuantity =
        json['stock_quantity'] == null || json['stock_enforced'] == false
        ? null
        : number(json['stock_quantity']).floor();
    final maxOrderQuantity = int.tryParse(
      '${json['max_order_quantity'] ?? ''}',
    );
    final quantity = RegExp(r'\d+').firstMatch(moqRaw);
    // The unit written after the number, kept as saved ("10 nos" -> "nos").
    final moqUnit = RegExp(r'\d+\s*([A-Za-z][A-Za-z.]*)')
        .firstMatch(moqRaw)
        ?.group(1);
    final rawRating = '${json['rating'] ?? 0}';
    final ratingMatch = RegExp(r'\d+(?:\.\d+)?').firstMatch(rawRating);
    String categoryValue(List<dynamic> values) => values
        .map((value) => '${value ?? ''}'.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final category = categoryValue([
      json['category_key'],
      json['category'],
      json['category_id'],
    ]);
    return ProductModel(
      id: '${json['product_id'] ?? json['id']}',
      name: '${json['name'] ?? ''}',
      sku: '${json['sku'] ?? ''}',
      categoryId: category,
      categoryName: categoryValue([
        json['category_name'],
        json['category_title'],
        category.replaceAll('_', ' '),
      ]),
      brand: '${json['brand'] ?? ''}',
      mrp: number(json['mrp']),
      dealerPrice: number(
        json['dealerPrice'] ??
            json['dealer_price'] ??
            json['numericPrice'] ??
            json['price'],
      ),
      purchasePrice:
          json['purchase_price'] == null && json['purchasePrice'] == null
          ? null
          : number(json['purchase_price'] ?? json['purchasePrice']),
      cabinetPrice: _positiveOrNull(
        json['cabinet_price'] ?? json['cabinetPrice'],
      ),
      bulkPrice: _positiveOrNull(json['bulk_price'] ?? json['bulkPrice']),
      bulkMinQty: int.tryParse(
        '${json['bulk_min_qty'] ?? json['bulkMinQty'] ?? ''}',
      ),
      bulkStep: int.tryParse('${json['bulk_step'] ?? json['bulkStep'] ?? ''}'),
      bulkPackLabel: (json['bulk_pack_label'] ?? json['bulkPackLabel'])
          ?.toString(),
      imageUrl: '${json['img'] ?? json['imgSrc'] ?? ''}',
      stockStatus: _stockStatus(
        markedOutOfStock: '${json['badge']}'.toLowerCase().contains(
          'out of stock',
        ),
        stock: stockQuantity,
        minOrder: 1,
      ),
      stockQuantity: stockQuantity,
      maxOrderQuantity: maxOrderQuantity != null && maxOrderQuantity >= 1
          ? maxOrderQuantity
          : null,
      moq: int.tryParse(quantity?.group(0) ?? '1') ?? 1,
      moqSet: quantity != null,
      moqUnit: moqUnit,
      rating: double.tryParse(ratingMatch?.group(0) ?? '0') ?? 0,
      reviewCount: 0,
      isFeatured: '${json['badge'] ?? ''}'.isNotEmpty,
      description: '${json['desc'] ?? json['description'] ?? ''}',
      specifications: json['specs'] is Map
          ? (json['specs'] as Map).map((k, v) => MapEntry('$k', '$v'))
          : {},
      features: json['features'] is List
          ? (json['features'] as List).map((v) => '$v').toList()
          : [],
      createdAt: DateTime.tryParse(
        '${json['created_at'] ?? json['createdAt'] ?? ''}',
      ),
    );
  }

  /// Newest first by [createdAt]; products without a date keep their order
  /// after the dated ones.
  static List<ProductModel> newestFirst(Iterable<ProductModel> products) {
    final indexed = products.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final ad = a.value.createdAt, bd = b.value.createdAt;
      if (ad != null && bd != null) {
        final c = bd.compareTo(ad);
        if (c != 0) return c;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return a.key.compareTo(b.key);
    });
    return [for (final e in indexed) e.value];
  }
}

/// A price above zero, or null (blank, 0 or not a number: never shown as ₹0).
double? _positiveOrNull(dynamic value) {
  if (value == null) return null;
  final amount = value is num
      ? value.toDouble()
      : double.tryParse('$value'.trim());
  return amount != null && amount.isFinite && amount > 0 ? amount : null;
}

/// Stock 0 -> Out of Stock; stock below the MOQ -> Below MOQ; else In Stock.
/// Stock is the real inventory and is never set from the MOQ.
StockStatus _stockStatus({
  required bool markedOutOfStock,
  required int? stock,
  required int minOrder,
}) {
  if (markedOutOfStock || (stock != null && stock <= 0)) {
    return StockStatus.outOfStock;
  }
  if (stock != null && stock < minOrder) return StockStatus.lowStock;
  return StockStatus.inStock;
}
