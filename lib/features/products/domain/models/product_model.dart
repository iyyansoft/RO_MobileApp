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
    required this.imageUrl,
    this.galleryImages = const [],
    required this.stockStatus,
    required this.moq,
    this.rating = 4.8,
    this.reviewCount = 36,
    this.isFeatured = false,
    this.description =
        'High-grade commercial and domestic RO water purification system component. Designed for maximum water recovery, low energy consumption, and long operational lifespan in high TDS water conditions.',
    this.specifications = const {
      'Flow Rate': '75 GPD / 100 GPD',
      'Salt Rejection Rate': '98.5%',
      'Max Operating Pressure': '125 PSI',
      'Operating Temperature': '4°C - 45°C',
      'Material Grade': 'Food Grade Polyamide TFC',
      'Warranty': '1 Year B2B Warranty',
    },
    this.features = const [
      'High Rejection Rate (98.5%) for crystal clear drinking water',
      'Dry membrane design for extended shelf life during storage',
      'Compatible with standard 1812 & 2012 membrane housings',
      'Tested under ISO 9001 & NSF Standard 58 quality guidelines',
    ],
  });

  List<String> get allImages {
    if (galleryImages.isNotEmpty) return galleryImages;
    return [imageUrl, 'assets/images/purifier_hq.jpg', 'assets/images/membrane_hq.jpg', 'assets/images/pump_hq.jpg'];
  }

  int get discountPercentage {
    if (mrp <= 0 || dealerPrice >= mrp) return 0;
    return (((mrp - dealerPrice) / mrp) * 100).round();
  }

  static const List<ProductModel> sampleProducts = [
    ProductModel(
      id: 'p1',
      name: 'Vontron 75 GPD RO Membrane High Rejection',
      sku: 'MEM-75G-01',
      categoryId: 'membranes',
      categoryName: 'RO Membranes',
      brand: 'Vontron',
      mrp: 1450.0,
      dealerPrice: 820.0,
      imageUrl: 'assets/images/membrane.jpg',
      galleryImages: [
        'assets/images/membrane.jpg',
        'assets/images/membrane_hq.jpg',
        'assets/images/spares.jpg',
      ],
      stockStatus: StockStatus.inStock,
      moq: 10,
      rating: 4.9,
      reviewCount: 128,
      isFeatured: true,
      description:
          'Original Vontron 75 GPD Reverse Osmosis Membrane Element. Engineered with premium Polyamide Thin-Film Composite technology for maximum salt rejection and high permeate flow in Indian hard water conditions up to 2000 PPM TDS.',
      specifications: {
        'Permeate Flow Rate': '75 GPD (283 Liters/Day)',
        'Stabilized Salt Rejection': '98.5%',
        'Max Feedwater TDS': '2000 PPM',
        'Operating Pressure': '60 - 100 PSI',
        'Membrane Material': 'Thin-Film Composite (TFC)',
        'Certification': 'NSF/ANSI Standard 58',
      },
      features: [
        '98.5% High Rejection Rate for pure & safe water',
        'Advanced anti-fouling technology prevents scaling',
        'Universal fit for 1812 standard domestic RO cabinets',
        'Dry element packaging for 3-year shelf storage',
      ],
    ),
    ProductModel(
      id: 'p2',
      name: 'E-Chen 100 GPD Heavy Duty Booster Pump 24V DC',
      sku: 'PMP-100G-EC',
      categoryId: 'pumps',
      categoryName: 'RO Pumps',
      brand: 'E-Chen',
      mrp: 2200.0,
      dealerPrice: 1350.0,
      imageUrl: 'assets/images/cat_pump.jpg',
      galleryImages: [
        'assets/images/cat_pump.jpg',
        'assets/images/pump_hq.jpg',
        'assets/images/purifier.jpg',
      ],
      stockStatus: StockStatus.inStock,
      moq: 5,
      rating: 4.8,
      reviewCount: 94,
      isFeatured: true,
      description:
          'E-Chen 100 GPD 24V DC Diaphragm Booster Pump for domestic and commercial RO systems. Features 100% pure copper motor winding, low noise vibration dampers, and continuous 24-hour operation capability.',
      specifications: {
        'Voltage': '24V DC',
        'Current Draw': '1.2A @ 80 PSI',
        'Open Flow Rate': '1.8 LPM',
        'Max Working Pressure': '125 PSI',
        'Motor Winding': '100% Pure Copper',
        'Port Size': '3/8" NPT Female',
      },
      features: [
        'Heavy duty 100% copper motor with thermal overload protection',
        'Super quiet operation (< 45 dB) with anti-vibration rubber feet',
        'High pressure delivery up to 125 PSI for dense membranes',
        'Built for 100 GPD, 150 GPD & double membrane systems',
      ],
    ),
    ProductModel(
      id: 'p3',
      name: 'Pureit 24V 2.5A SMPS Power Supply Adapter',
      sku: 'SMP-24V-25A',
      categoryId: 'smps',
      categoryName: 'SMPS',
      brand: 'PowerAmp',
      mrp: 750.0,
      dealerPrice: 420.0,
      imageUrl: 'assets/images/spares.jpg',
      stockStatus: StockStatus.inStock,
      moq: 20,
      rating: 4.7,
      reviewCount: 65,
    ),
    ProductModel(
      id: 'p4',
      name: '10 Inch Spun PP Sediment Filter 5 Micron (Pack of 50)',
      sku: 'FLT-SPN-10',
      categoryId: 'filters',
      categoryName: 'Filters',
      brand: 'AquaClean',
      mrp: 1250.0,
      dealerPrice: 650.0,
      imageUrl: 'assets/images/cat_filter.jpg',
      stockStatus: StockStatus.inStock,
      moq: 50,
      rating: 4.9,
      reviewCount: 210,
      isFeatured: true,
    ),
    ProductModel(
      id: 'p5',
      name: 'Heavy Pre-Filter Housing 10" Transparent Double O-Ring',
      sku: 'HSG-10-TRN',
      categoryId: 'housings',
      categoryName: 'Filter Housing',
      brand: 'AquaClean',
      mrp: 480.0,
      dealerPrice: 260.0,
      imageUrl: 'assets/images/housing.jpg',
      stockStatus: StockStatus.lowStock,
      moq: 12,
      rating: 4.6,
      reviewCount: 42,
    ),
    ProductModel(
      id: 'p6',
      name: 'Commercial 50 LPH RO Water Plant Double Pump System',
      sku: 'SYS-50LPH-COMM',
      categoryId: 'complete_ro',
      categoryName: 'Complete RO Systems',
      brand: 'AquaTech',
      mrp: 28500.0,
      dealerPrice: 18900.0,
      imageUrl: 'assets/images/purifier.jpg',
      stockStatus: StockStatus.inStock,
      moq: 1,
      rating: 5.0,
      reviewCount: 38,
      isFeatured: true,
    ),
  ];
}
