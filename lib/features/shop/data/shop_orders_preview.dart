/// Sample records used only when launching with
/// `--dart-define=SHOP_ORDERS_PREVIEW=true`.
///
/// The normal Shop App path always loads orders from the backend.
List<Map<String, dynamic>> buildShopOrderPreview(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(int offset) => today.add(Duration(days: offset));
  String iso(DateTime value) => value.toIso8601String();

  return [
    {
      'orderId': 'SAMPLE-RO-2401',
      'vendorName': 'Priya Enterprises',
      'companyName': 'Priya Enterprises',
      'orderDate': iso(day(-1)),
      'dueDate': iso(day(3)),
      'paymentMethod': 'Cash on Delivery',
      'paymentStatus': 'pending',
      'status': 'Pending',
      'items': [
        _previewItem(910001, 'RO Membrane 75 GPD', 'MEM-75', 3, 650),
        _previewItem(910002, 'Sediment Filter 10 inch', 'SF-10', 2, 120),
        _previewItem(910003, 'Flow Restrictor 300 ml', 'FR-300', 1, 85),
      ],
    },
    {
      'orderId': 'SAMPLE-RO-2402',
      'vendorName': 'SB Distributors',
      'companyName': 'SB Distributors',
      'orderDate': iso(day(-3)),
      'dueDate': iso(day(1)),
      'paymentMethod': 'Cash on Delivery',
      'paymentStatus': 'pending',
      'status': 'Partially Delivered',
      'items': [
        _previewItem(
          910011,
          'Booster Pump 100 GPD',
          'BP-100',
          2,
          1450,
          deliveredQuantity: 1,
        ),
        _previewItem(
          910012,
          'Inline Carbon Filter',
          'IC-10',
          4,
          190,
          deliveredQuantity: 2,
        ),
      ],
    },
    {
      'orderId': 'SAMPLE-RO-2403',
      'vendorName': 'Aqua Care Supplies',
      'companyName': 'Aqua Care Supplies',
      'orderDate': iso(day(-5)),
      'dueDate': iso(day(-1)),
      'paymentMethod': 'Cash on Delivery',
      'paymentStatus': 'pending',
      'status': 'Delivered',
      'items': [
        _previewItem(910021, 'RO Membrane 100 GPD', 'MEM-100', 2, 850),
        _previewItem(910022, 'Post Carbon Filter', 'PC-10', 3, 225),
        _previewItem(910023, 'Housing Set 10 inch', 'HS-10', 1, 310),
        _previewItem(910024, 'White Tubing 1/4 inch', 'TUBE-14', 5, 45),
      ],
    },
    {
      'orderId': 'SAMPLE-RO-2404',
      'vendorName': 'Neeraj Water Solutions',
      'companyName': 'Neeraj Water Solutions',
      'orderDate': iso(day(-2)),
      'dueDate': iso(day(2)),
      'paymentMethod': 'Cash on Delivery',
      'paymentStatus': 'pending',
      'status': 'Pending',
      'items': [_previewItem(910031, 'UV Lamp 11W', 'UV-11', 2, 720)],
    },
  ];
}

/// Applies a delivery only to the caller's in-memory sample order.
/// Returns an error string when validation fails; it performs no network or
/// database operation.
String? applyShopOrderPreviewDelivery(
  Map<String, dynamic> order,
  Map<int, int> quantities,
  Set<int> confirmedItems,
) {
  final items = (order['items'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  for (final item in items) {
    final id = int.tryParse('${item['id']}');
    if (id == null || !quantities.containsKey(id)) {
      return 'The sample order contains an invalid item ID.';
    }
    final actual = quantities[id]!;
    final ordered = int.tryParse('${item['quantity']}') ?? 0;
    if (actual < 0 || actual > ordered) {
      return 'Actual quantity must be between zero and the ordered quantity.';
    }
    item['deliveredQuantity'] = actual;
    item['deliveryConfirmed'] = confirmedItems.contains(id);
    item['delivered'] = confirmedItems.contains(id);
  }
  final anyConfirmed = items.any(
    (item) =>
        item['deliveryConfirmed'] == true &&
        (int.tryParse('${item['deliveredQuantity']}') ?? 0) > 0,
  );
  final fullyDelivered = items.every((item) {
    final quantity = int.tryParse('${item['quantity']}') ?? 0;
    final actual = int.tryParse('${item['deliveredQuantity']}') ?? 0;
    return item['deliveryConfirmed'] == true && quantity == actual;
  });
  order['items'] = items;
  order['status'] = fullyDelivered
      ? 'Delivered'
      : anyConfirmed
      ? 'Partially Delivered'
      : 'Pending';
  return null;
}

Map<String, dynamic> _previewItem(
  int id,
  String name,
  String sku,
  int quantity,
  num dealerPrice, {
  int deliveredQuantity = 0,
}) => {
  'id': '$id',
  'productId': 'SAMPLE-$sku',
  'name': name,
  'brand': 'RO Wholesale',
  'sku': sku,
  'quantity': quantity,
  // `unitPrice` is the field used by the existing order model and represents
  // the dealer-price snapshot stored on the order item.
  'unitPrice': dealerPrice,
  'deliveredQuantity': deliveredQuantity,
  'deliveryConfirmed': false,
  'delivered': false,
  // Use the existing catalog sprite so the preview has the same local,
  // category-specific product artwork as the product catalogue.
  'image': _previewImageFor(sku),
};

String _previewImageFor(String sku) => switch (sku) {
  'MEM-75' => 'catalog-sprite://5',
  'MEM-100' => 'catalog-sprite://6',
  'SF-10' => 'catalog-sprite://2',
  'FR-300' => 'catalog-sprite://9',
  'BP-100' => 'catalog-sprite://11',
  'IC-10' || 'PC-10' => 'catalog-sprite://1',
  'HS-10' => 'catalog-sprite://13',
  'TUBE-14' => 'catalog-sprite://7',
  _ => '',
};
