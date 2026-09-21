class CategoryModel {
  final String id;
  final String name;
  final String imagePath;
  final int productCount;
  final String description;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.productCount,
    required this.description,
  });

  static const List<CategoryModel> defaultCategories = [
    CategoryModel(
      id: 'membranes',
      name: 'RO Membranes',
      imagePath: 'assets/images/membrane.jpg',
      productCount: 142,
      description: 'High rejection 75 GPD, 80 GPD & 100 GPD RO membranes',
    ),
    CategoryModel(
      id: 'pumps',
      name: 'RO Pumps',
      imagePath: 'assets/images/cat_pump.jpg',
      productCount: 88,
      description: 'Heavy duty 24V/36V DC booster pumps & diaphragm pumps',
    ),
    CategoryModel(
      id: 'smps',
      name: 'SMPS',
      imagePath: 'assets/images/spares.jpg',
      productCount: 64,
      description: 'Copper transformer 24V 2.5A & 36V SMPS power adapters',
    ),
    CategoryModel(
      id: 'filters',
      name: 'Filters',
      imagePath: 'assets/images/cat_filter.jpg',
      productCount: 215,
      description: 'Spun, sediment, carbon block & inline post carbon filters',
    ),
    CategoryModel(
      id: 'housings',
      name: 'Filter Housing',
      imagePath: 'assets/images/housing.jpg',
      productCount: 95,
      description: 'Heavy 10" pre-filter housings, membrane housings & bowl wrenches',
    ),
    CategoryModel(
      id: 'spares',
      name: 'RO Spares',
      imagePath: 'assets/images/cat_spares.jpg',
      productCount: 310,
      description: 'O-rings, clamps, brackets, FRs & maintenance spares',
    ),
    CategoryModel(
      id: 'purifier_parts',
      name: 'Water Purifier Parts',
      imagePath: 'assets/images/purifier.jpg',
      productCount: 178,
      description: 'Cabinets, water tanks, faucets, float valves & tap handles',
    ),
    CategoryModel(
      id: 'accessories',
      name: 'Accessories',
      imagePath: 'assets/images/tank.jpg',
      productCount: 124,
      description: 'TDS meters, pH testers, installation kits & wrenches',
    ),
    CategoryModel(
      id: 'complete_ro',
      name: 'Complete RO Systems',
      imagePath: 'assets/images/purifier_hq.jpg',
      productCount: 52,
      description: 'Commercial 50 LPH, 100 LPH & domestic RO cabinets',
    ),
    CategoryModel(
      id: 'electrical',
      name: 'Electrical Components',
      imagePath: 'assets/images/pump_hq.jpg',
      productCount: 76,
      description: 'Solenoid valves, high pressure switches & low pressure switches',
    ),
    CategoryModel(
      id: 'adapters',
      name: 'Adapters',
      imagePath: 'assets/images/spares.jpg',
      productCount: 45,
      description: 'Power supply cords, DC jacks & heavy duty power sockets',
    ),
    CategoryModel(
      id: 'connectors',
      name: 'Connectors',
      imagePath: 'assets/images/cat_spares.jpg',
      productCount: 190,
      description: 'Quick fit push connectors, elbows, tees, stems & unions',
    ),
    CategoryModel(
      id: 'valves',
      name: 'Valves',
      imagePath: 'assets/images/cat_filter.jpg',
      productCount: 110,
      description: 'SV 24V DC valves, non-return valves (NRV) & diverter valves',
    ),
    CategoryModel(
      id: 'pipes',
      name: 'Pipes',
      imagePath: 'assets/images/membrane.jpg',
      productCount: 82,
      description: '1/4" & 3/8" LLDPE food-grade RO water tubing rolls',
    ),
  ];
}
