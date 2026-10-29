enum StockStatus {
  inStock,
  lowStock,
  outOfStock;

  String get label {
    switch (this) {
      case StockStatus.inStock:
        return 'IN STOCK';
      case StockStatus.lowStock:
        return 'LOW STOCK';
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

  double get detailsPrice => purchasePrice ?? dealerPrice;
  final String imageUrl;
  final List<String> galleryImages;
  final StockStatus stockStatus;
  final int moq; // Minimum Order Quantity
  final double rating;
  final int reviewCount;
  final bool isFeatured;
  final String description;
  final Map<String, String> specifications;
  final List<String> features;

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
    required this.imageUrl,
    this.galleryImages = const [],
    required this.stockStatus,
    required this.moq,
    this.rating = 0,
    this.reviewCount = 0,
    this.isFeatured = false,
    this.description = '',
    this.specifications = const {},
    this.features = const [],
  });

  static const Map<String, int> _catalogSpriteBySku = {
    'RO-FLT-CTO': 0,
    'RO-FLT-INLINE': 1,
    'RO-FLT-SED': 2,
    'ABC': 3,
    'RO-MEM-100': 6,
    'RO-MEM-4040': 4,
    'RO-MEM-75': 5,
    'RO-PIPE-14': 7,
    'RO-PIPE-38': 8,
    'RO-PIPE-KIT': 9,
    'RO-PMP-100': 11,
    'RO-PMP-300': 12,
    'RO-PMP-75': 10,
    'RO-SPR-HOUSING': 13,
    'RO-SPR-SMPS': 14,
    'RO-SPR-SV': 15,
    'RO-SYS-25': 17,
    'RO-SYS-50': 18,
    'RO-SYS-10L': 16,
  };

  static const Set<String> _categoryPlaceholderImages = {
    'purifier.jpg',
    'cat_filter.jpg',
    'cat_pump.jpg',
    'cat_spares.jpg',
    'membrane.jpg',
  };

  /// Uses distinct category-appropriate art for the bundled demo placeholders,
  /// while leaving actual uploaded product images untouched.
  String get displayImageUrl {
    final parsedSource = Uri.tryParse(imageUrl);
    final sourcePath = parsedSource?.pathSegments.isNotEmpty == true
        ? parsedSource!.pathSegments.last.toLowerCase()
        : imageUrl.toLowerCase();
    if (!_categoryPlaceholderImages.contains(sourcePath)) return imageUrl;

    final spriteIndex = _catalogSpriteBySku[sku.toUpperCase()];
    if (spriteIndex != null) return 'catalog-sprite://$spriteIndex';

    final category = '$categoryId $categoryName'.toLowerCase();
    final fallbackIndex = category.contains('membrane')
        ? 4
        : category.contains('filter')
        ? 0
        : category.contains('pipe') || category.contains('tubing')
        ? 7
        : category.contains('pump')
        ? 10
        : category.contains('spare') || category.contains('valve')
        ? 13
        : 16;
    return 'catalog-sprite://$fallbackIndex';
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
    final quantity = RegExp(r'\d+').firstMatch('${json['moq'] ?? 1}');
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
      imageUrl: '${json['img'] ?? json['imgSrc'] ?? ''}',
      stockStatus:
          ('${json['badge']}'.toLowerCase().contains('out of stock') ||
              (json['stock_quantity'] != null &&
                  number(json['stock_quantity']) <= 0))
          ? StockStatus.outOfStock
          : StockStatus.inStock,
      moq: int.tryParse(quantity?.group(0) ?? '1') ?? 1,
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
    );
  }
}
