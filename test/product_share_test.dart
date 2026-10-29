import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_share.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_card.dart';

void main() {
  const rupee = '\u20B9';
  const bullet = '\u2022';
  final product = ProductModel.fromJson({
    'id': 'filter-share',
    'name': 'Public Filter',
    'sku': 'FILTER-001',
    'category': 'filters',
    'category_name': 'Water Filters',
    'brand': 'Aqua Flow',
    'purchase_price': 500,
    'dealer_price': 900,
    'mrp': 1200,
    'description': 'A replacement filter for clean drinking water.',
    'specs': {'Material': 'Carbon block', 'Fit': 'Universal'},
    'features': ['Improves taste', 'Easy replacement'],
    'img': 'assets/images/purifier.jpg',
  });

  test('share text contains all product fields and MRP only', () {
    final text = productShareText(product);
    expect(text, contains('Product Name: Public Filter'));
    expect(text, contains('Product Code (SKU): FILTER-001'));
    expect(text, contains('Brand: Aqua Flow'));
    expect(
      text,
      contains(
        'MRP: $rupee'
        '1200',
      ),
    );
    expect(text, contains('Category: Water Filters'));
    expect(text, contains('Availability: IN STOCK'));
    expect(text, contains('MOQ: 1'));
    expect(
      text,
      contains('Description: A replacement filter for clean drinking water.'),
    );
    expect(text, contains('Material: Carbon block'));
    expect(text, contains('$bullet Easy replacement'));
    expect(text, isNot(contains('Dealer Price')));
    expect(text, isNot(contains('Purchase Price')));
    expect(text, isNot(contains('900')));
    expect(text, isNot(contains('500')));
  });

  test('share image renders a portrait product card', () async {
    WidgetsFlutterBinding.ensureInitialized();
    final photo = File('assets/images/purifier.jpg').readAsBytesSync();
    final source = 'data:image/jpeg;base64,${base64Encode(photo)}';
    final bytes = await renderProductShareImage(product, imageSource: source);

    expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, greaterThan(500));
    frame.image.dispose();
    codec.dispose();
  });

  testWidgets(
    'product details show Dealer Price without MRP or Purchase Price',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProductsProvider.overrideWith((ref) async => [product]),
          ],
          child: MaterialApp(home: ProductDetailsScreen(product: product)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dealer Price (Excl. GST)'), findsOneWidget);
      expect(find.textContaining('900'), findsAtLeastNWidgets(1));
      expect(find.textContaining('MRP'), findsNothing);
      expect(find.textContaining('Purchase Price'), findsNothing);
    },
  );
}
