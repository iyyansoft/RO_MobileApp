import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_card.dart';

void main() {
  testWidgets('customer card shows dealer price and MRP, never purchase price', (
    tester,
  ) async {
    final product = ProductModel.fromJson({
      'id': 'price-split',
      'name': 'Filter',
      'sku': 'SKU',
      'img': 'assets/images/purifier.jpg',
      'purchase_price': 500,
      'dealer_price': 8500,
      'mrp': 12000,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 280,
            child: ProductCard(product: product),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('₹8,500'), findsOneWidget);
    expect(find.text('MRP ₹12,000'), findsOneWidget);
    expect(find.textContaining('500'), findsOneWidget, reason: 'only ₹8,500');
    expect(tester.takeException(), isNull);
  });
  testWidgets('grid product card fits short and narrow layouts', (
    tester,
  ) async {
    const product = ProductModel(
      id: 'filter-1',
      name: 'Whole House Water Purifier',
      sku: 'RO-FILTER-001',
      categoryId: 'filters',
      categoryName: 'Filters',
      brand: 'Pure Water',
      mrp: 1500,
      dealerPrice: 1200,
      imageUrl: 'assets/images/purifier.jpg',
      stockStatus: StockStatus.inStock,
      moq: 5,
    );

    for (final size in [const Size(165, 245), const Size(140, 220)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ProductCard(
                  product: product,
                  onTap: () {},
                  onAddToCart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: 'Card size: $size, exception: $exception',
      );
    }
  });
}
