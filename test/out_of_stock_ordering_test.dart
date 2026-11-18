import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_card.dart';

ProductModel _product({required int stock}) => ProductModel.fromJson({
  'id': 'PDF_DOM_27',
  'sku': 'DOM-27',
  'name': 'Vero membrane 80 gpd',
  'category': 'membranes',
  'category_name': 'Membranes',
  'brand': '',
  'dealer_price': 300,
  'mrp': 2490,
  'img': 'assets/images/purifier.jpg',
  'stock_quantity': stock,
});

void main() {
  test('stock 0 means out of stock', () {
    expect(_product(stock: 0).isOutOfStock, isTrue);
    expect(_product(stock: 5).isOutOfStock, isFalse);
  });

  testWidgets('details: stock 0 disables Add to Cart and Buy Now', (
    tester,
  ) async {
    final product = _product(stock: 0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => [product]),
        ],
        child: MaterialApp(home: ProductDetailsScreen(product: product)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Out of Stock'), findsOneWidget);
    expect(find.text('Add to Cart'), findsNothing);
    final buttons = [
      ...tester.widgetList<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Out of Stock'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      ),
      ...tester.widgetList<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Buy Now'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      ),
    ];
    expect(buttons, hasLength(2));
    expect(buttons.every((b) => b.onPressed == null), isTrue);
  });

  testWidgets('details: in-stock products keep both buttons', (tester) async {
    final product = _product(stock: 5);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => [product]),
        ],
        child: MaterialApp(home: ProductDetailsScreen(product: product)),
      ),
    );
    await tester.pumpAndSettle();
    final add = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Add to Cart'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(add.onPressed, isNotNull);
  });

  testWidgets('cards: the add button does nothing for stock 0', (tester) async {
    var adds = 0;
    final product = _product(stock: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SizedBox(
                width: 240,
                height: 340,
                child: ProductCard(
                  product: product,
                  onTap: () {},
                  onAddToCart: () => adds++,
                ),
              ),
              SizedBox(
                width: 260,
                height: 380,
                child: HomeProductCard(
                  product: product,
                  heroTag: 'h',
                  onTap: () {},
                  onAddToCart: () => adds++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    for (final icon in [Icons.add_rounded, Icons.add_shopping_cart_rounded]) {
      for (final e in find.byIcon(icon).evaluate().toList()) {
        await tester.tap(find.byWidget(e.widget).first, warnIfMissed: false);
      }
    }
    await tester.pump();
    expect(adds, 0);
  });

  group('PDF quantity as maximum order quantity', () {
    test('1 up to the PDF quantity; no limit invented without one', () {
      final p = _pdfProduct(max: 10);
      expect(p.minOrderQty, 1);
      expect(p.maxOrderQuantity, 10);
      expect(p.canOrder, isTrue, reason: 'preview: stock checks off');
      expect(p.quantityProblem(1), isNull);
      expect(p.quantityProblem(10), isNull);
      expect(
        p.quantityProblem(11),
        'You can order a maximum of 10 units for this product.',
      );
      expect(_pdfProduct(max: null).maxOrderQuantity, isNull);
      expect(_pdfProduct(max: null).quantityProblem(500), isNull);
    });

    test('production data: real stock 0 is still Out of Stock', () {
      final p = _pdfProduct(max: 10, stockEnforced: null, stock: 0);
      expect(p.isOutOfStock, isTrue);
      expect(p.canOrder, isFalse);
    });

    testWidgets(
      'details: starts at 1, + up to the maximum, then the popup; quantity stays',
      (tester) async {
        final product = _pdfProduct(max: 10);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogProductsProvider.overrideWith((ref) async => [product]),
            ],
            child: MaterialApp(home: ProductDetailsScreen(product: product)),
          ),
        );
        await tester.pumpAndSettle();
        final qty = find.descendant(
          of: find.ancestor(
            of: find.byIcon(Icons.remove_rounded),
            matching: find.byType(Row),
          ),
          matching: find.text('1'),
        );
        expect(qty, findsOneWidget, reason: 'default quantity is 1');
        expect(find.text('You can order 1 to 10'), findsOneWidget);
        final plus = _selectorButton(Icons.add_rounded);
        await tester.ensureVisible(plus);
        await tester.pumpAndSettle();
        for (var i = 0; i < 9; i++) {
          await tester.tap(plus);
          await tester.pump();
        }
        expect(find.text('Total: ₹10,500'), findsOneWidget);
        await tester.tap(plus);
        await tester.pumpAndSettle();
        expect(find.text('Maximum Order Quantity Reached'), findsOneWidget);
        expect(
          find.text('You can order a maximum of 10 units for this product.'),
          findsOneWidget,
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('Maximum Order Quantity Reached'), findsNothing);
        expect(find.text('Total: ₹10,500'), findsOneWidget, reason: 'still 10');
        // Decrease works, down to 1 and no further.
        final minus = _selectorButton(Icons.remove_rounded);
        for (var i = 0; i < 12; i++) {
          await tester.tap(minus);
          await tester.pump();
        }
        expect(find.text('Total: ₹1,050'), findsOneWidget);
        // Add to Cart and Buy Now are enabled in the preview (stock not enforced).
        for (final label in ['Add to Cart', 'Buy Now']) {
          final button = tester.widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          );
          expect(button.onPressed, isNotNull, reason: label);
        }
      },
    );

    testWidgets('the popup shows each product own maximum', (tester) async {
      final product = _pdfProduct(max: 6);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProductsProvider.overrideWith((ref) async => [product]),
          ],
          child: MaterialApp(home: ProductDetailsScreen(product: product)),
        ),
      );
      await tester.pumpAndSettle();
      final plus = _selectorButton(Icons.add_rounded);
      await tester.ensureVisible(plus);
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.tap(plus);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        find.text('You can order a maximum of 6 units for this product.'),
        findsOneWidget,
      );
    });
  });
}

/// The +/- button of the details page quantity selector (the Row that holds
/// both), not the "+" on related-product cards.
Finder _selectorButton(IconData icon) => find.descendant(
  of: find
      .ancestor(
        of: find.byIcon(Icons.remove_rounded).first,
        matching: find.byType(Row),
      )
      .first,
  matching: find.byIcon(icon),
);

ProductModel _pdfProduct({
  required int? max,
  bool? stockEnforced = false,
  int stock = 0,
}) => ProductModel.fromJson({
  'id': 'PDF_MUK_01',
  'sku': 'MUK-01',
  'name': 'BLUEBERRY 100 GPD Pump',
  'category': 'pumps',
  'category_name': 'Booster Pumps',
  'brand': '',
  'dealer_price': 1050,
  'mrp': 2700,
  'img': 'assets/images/purifier.jpg',
  'stock_quantity': stock,
  'moq': max == null ? null : '$max nos',
  'max_order_quantity': max,
  'stock_enforced': ?stockEnforced,
});
