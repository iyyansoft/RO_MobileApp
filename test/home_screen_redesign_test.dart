import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

void main() {
  testWidgets('HomeScreen renders search bar, 4 quick actions, and balanced carousel matching reference', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => <ProductModel>[]),
          catalogCategoriesProvider.overrideWith((ref) async => <CategoryModel>[]),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify search placeholder text
    expect(
      find.text('Search RO systems, membranes, pumps, spares...'),
      findsOneWidget,
    );

    // Verify 4 quick action cards
    expect(find.text('Bulk Order'), findsOneWidget);
    expect(find.text('Track Orders'), findsOneWidget);
    expect(find.text('GST Invoice'), findsOneWidget);
    expect(find.text('Credit Limit'), findsOneWidget);

    // Verify primary center banner title and action button matching reference
    expect(find.text('Neero+ RO\nWater Purifiers'), findsOneWidget);
    expect(find.text('Shop Now  →'), findsWidgets);
    expect(find.text('BEST SELLER'), findsOneWidget);
  });
}
