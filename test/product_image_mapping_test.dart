import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_image.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

void main() {
  const samples = <({String sku, String category, String image})>[
    (sku: 'RO-FLT-CTO', category: 'filters', image: 'cat_filter.jpg'),
    (sku: 'RO-MEM-75', category: 'membranes', image: 'membrane.jpg'),
    (sku: 'RO-PIPE-14', category: 'pipes', image: 'cat_spares.jpg'),
    (sku: 'RO-PMP-100', category: 'pumps', image: 'cat_pump.jpg'),
    (sku: 'RO-SYS-25', category: 'systems', image: 'purifier.jpg'),
    (sku: 'RO-SYS-10L', category: 'systems', image: 'purifier.jpg'),
    (sku: 'PUMP-100GPD-24V', category: 'pumps', image: 'purifier.jpg'),
  ];

  ProductModel sample(({String sku, String category, String image}) item) =>
      ProductModel(
        id: item.sku,
        name: item.sku,
        sku: item.sku,
        categoryId: item.category,
        categoryName: item.category,
        brand: 'Sample',
        mrp: 100,
        dealerPrice: 80,
        imageUrl: item.image,
        stockStatus: StockStatus.inStock,
        moq: 1,
      );

  test('old shared demo images are "no picture yet", never substitute artwork', () {
    for (final item in samples) {
      final display = sample(item).displayImageUrl;
      expect(display, '', reason: item.sku);
      expect(display.startsWith('catalog-sprite://'), isFalse);
    }
  });

  test('uploaded product images remain unchanged', () {
    final uploaded = sample((
      sku: 'RO-FLT-CTO',
      category: 'filters',
      image: 'uploads/prod_123.jpg',
    ));

    expect(uploaded.displayImageUrl, 'uploads/prod_123.jpg');
  });

  testWidgets('a product without a picture shows the water-drop placeholder', (
    tester,
  ) async {
    final product = sample(samples.last);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppImage(product.displayImageUrl, width: 120, height: 120),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('app-image-placeholder')), findsOneWidget);
    expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
