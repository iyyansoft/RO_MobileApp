import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/cabinet_price_text.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/listing_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_card.dart';

ProductModel product(Map<String, dynamic> extra) => ProductModel.fromJson({
  'id': 'p1',
  'name': 'Cabinet with a fairly long product name for wrapping',
  'sku': 'CAB-40',
  'category': 'cabinets',
  'brand': 'Brand',
  'price': 400,
  'mrp': 520,
  'moq': '10 nos',
  'img': '',
  ...extra,
});

final cabinet = product({'cabinet_price': 375});
final plain = product({
  'category': 'spares',
  'sku': 'V-1',
  'cabinet_price': null,
});

/// Overflow messages from the last pump. Only bottom (height) overflows are
/// checked: the test font is wider than the real one, so the sideways
/// overflows it causes appear with or without a Cabinet Price.
final overflows = <String>[];
void expectNoBottomOverflow() {
  expect(overflows.where((m) => m.contains('bottom')), isEmpty);
  overflows.clear();
}

void main() {
  test('reads cabinet_price; blank, 0 or missing -> not shown', () {
    expect(cabinet.cabinetPrice, 375);
    expect(cabinet.dealerPrice, 400, reason: 'Dealer Price untouched');
    expect(cabinet.mrp, 520, reason: 'MRP untouched');
    expect(CabinetPriceText.label(cabinet), 'Cabinet Price: ₹375');
    expect(
      CabinetPriceText.label(product({'cabinet_price': 300})),
      'Cabinet Price: ₹300',
    );
    for (final empty in [null, 0, '0', '', 'abc', -5]) {
      final p = product({'cabinet_price': empty});
      expect(p.hasCabinetPrice, isFalse, reason: '$empty');
      expect(CabinetPriceText.label(p), isNull, reason: '$empty');
    }
    expect(plain.cabinetPrice, isNull);
    expect(
      product({}).cabinetPrice,
      isNull,
      reason: 'older API without the field',
    );
  });

  Future<void> pumpBox(
    WidgetTester tester,
    double w,
    double h,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m);
      } else {
        previous?.call(d);
      }
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: w, height: h, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
    FlutterError.onError = previous;
  }

  final cabinetText = find.text('Cabinet Price: ₹375');

  for (final width in [150.0, 170.0, 200.0, 260.0, 340.0]) {
    testWidgets('Home card $width px: Cabinet Price shown, no overflow', (
      tester,
    ) async {
      await pumpBox(
        tester,
        width,
        HomeProductCard.extentFor(width),
        HomeProductCard(product: cabinet, onTap: () {}, onAddToCart: () {}),
      );
      expect(cabinetText, findsOneWidget);
      expectNoBottomOverflow();
      await pumpBox(
        tester,
        width,
        HomeProductCard.extentFor(width),
        HomeProductCard(product: plain, onTap: () {}, onAddToCart: () {}),
      );
      expect(find.textContaining('Cabinet Price'), findsNothing);
      expectNoBottomOverflow();
    });

    testWidgets('Listing tile $width px: Cabinet Price shown, no overflow', (
      tester,
    ) async {
      await pumpBox(
        tester,
        width,
        ListingProductCard.tileExtent(width),
        ListingProductCard(
          product: cabinet,
          onTap: () {},
          onAddToCart: (_) async => true,
        ),
      );
      expect(cabinetText, findsOneWidget);
      expectNoBottomOverflow();
    });
  }

  for (final width in [340.0, 600.0, 1000.0]) {
    testWidgets('Listing row $width px: Cabinet Price shown, no overflow', (
      tester,
    ) async {
      await pumpBox(
        tester,
        width,
        ListingProductCard.rowExtentFor([cabinet]),
        ListingProductCard(
          product: cabinet,
          layout: ListingCardLayout.row,
          onTap: () {},
          onAddToCart: (_) async => true,
        ),
      );
      expect(cabinetText, findsOneWidget);
      expectNoBottomOverflow();
    });
  }

  testWidgets('related-products card (160 x 240) and list item: no overflow', (
    tester,
  ) async {
    await pumpBox(
      tester,
      160,
      240,
      ProductCard(product: cabinet, isGrid: true, onTap: () {}),
    );
    expect(cabinetText, findsOneWidget);
    expectNoBottomOverflow();
    await pumpBox(
      tester,
      360,
      400, // list item is content-sized (not used in a fixed grid)
      ProductCard(product: cabinet, isGrid: false, onTap: () {}),
    );
    expect(cabinetText, findsOneWidget);
    expectNoBottomOverflow();
  });
}
