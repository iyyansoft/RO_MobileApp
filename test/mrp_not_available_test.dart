import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/listing_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_card.dart';

// A Cabinet product: MRP 0 means "not available" (the PDF has none).
final cabinet = ProductModel.fromJson({
  'id': 'PDF_CAB_01',
  'sku': 'CAB-01',
  'name': 'Dolphin king/ABS',
  'category': 'cabinets',
  'category_name': 'Cabinet',
  'brand': '',
  'dealer_price': 1100,
  'mrp': 0,
  'moq': '10 nos',
  'img': '',
  'max_order_quantity': 10,
  'stock_enforced': false,
});

void expectNoMrp(WidgetTester tester) {
  expect(find.textContaining('MRP'), findsNothing);
  expect(find.textContaining('₹0'), findsNothing);
  expect(
    find.textContaining('₹1,100'),
    findsWidgets,
    reason: 'dealer price shown',
  );
}

void main() {
  testWidgets('cards never show MRP when it is not available', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SizedBox(
                width: 240,
                height: 340,
                child: ProductCard(product: cabinet, onTap: () {}),
              ),
              SizedBox(
                width: 600,
                height: 200,
                child: ProductCard(
                  product: cabinet,
                  isGrid: false,
                  onTap: () {},
                ),
              ),
              SizedBox(
                width: 260,
                height: 380,
                child: HomeProductCard(
                  product: cabinet,
                  heroTag: 'h',
                  onTap: () {},
                  onAddToCart: () {},
                ),
              ),
              SizedBox(
                width: 320,
                height: 520,
                child: ListingProductCard(
                  product: cabinet,
                  isDark: false,
                  onTap: () {},
                  onAddToCart: (_) async => true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expectNoMrp(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details page never shows MRP when it is not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => [cabinet]),
        ],
        child: MaterialApp(home: ProductDetailsScreen(product: cabinet)),
      ),
    );
    await tester.pumpAndSettle();
    expectNoMrp(tester);
    expect(find.text('Add to Cart'), findsOneWidget);
  });
}
