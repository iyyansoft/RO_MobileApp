import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_image.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_orders_preview.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

void main() {
  test('preview fixtures include one, two, three, and four-product orders', () {
    final orders = buildShopOrderPreview(DateTime(2026, 10, 23));

    expect(orders, hasLength(4));
    expect(orders.map((order) => (order['items'] as List).length), [
      3,
      2,
      4,
      1,
    ]);
    expect(
      orders.map((order) => order['vendorName']),
      contains('Priya Enterprises'),
    );
    expect(
      orders.map((order) => order['vendorName']),
      contains('SB Distributors'),
    );
    expect(
      (orders.first['items'] as List)
          .map((item) => (item as Map)['image'])
          .toList(),
      ['catalog-sprite://5', 'catalog-sprite://2', 'catalog-sprite://9'],
    );
    for (final order in orders) {
      for (final item in order['items'] as List<Map<String, dynamic>>) {
        expect(item['unitPrice'], isPositive); // Dealer-price snapshot.
        expect(item['deliveryConfirmed'], isFalse);
      }
    }
  });

  test('preview delivery validates and updates only the in-memory order', () {
    final order = buildShopOrderPreview(DateTime(2026, 10, 23)).first;
    final originalValue = (order['items'] as List).fold<double>(
      0,
      (sum, item) =>
          sum + (item['unitPrice'] as num) * (item['quantity'] as int),
    );
    final ids = (order['items'] as List)
        .map((item) => int.parse('${item['id']}'))
        .toList();

    expect(
      applyShopOrderPreviewDelivery(order, {ids.first: 1}, {ids.first}),
      contains('invalid item ID'),
    );
    expect(order['status'], 'Pending');

    final quantities = {
      for (var index = 0; index < ids.length; index++)
        ids[index]: index == 0 ? 2 : 0,
    };
    expect(
      applyShopOrderPreviewDelivery(order, quantities, {ids.first}),
      isNull,
    );
    expect(order['status'], 'Partially Delivered');
    final items = order['items'] as List<Map<String, dynamic>>;
    expect(items.first['deliveredQuantity'], 2);
    expect(items.first['deliveryConfirmed'], isTrue);
    expect(items[1]['deliveryConfirmed'], isFalse);
    final afterValue = items.fold<double>(
      0,
      (sum, item) =>
          sum + (item['unitPrice'] as num) * (item['quantity'] as int),
    );
    expect(afterValue, originalValue);
    expect(order['paymentStatus'], 'pending');
  });

  testWidgets(
    'preview product images resolve from the bundled catalog sprite',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AppImage('catalog-sprite://5', width: 64, height: 64),
                AppImage('catalog-sprite://2', width: 64, height: 64),
                AppImage('catalog-sprite://9', width: 64, height: 64),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing preview image uses the existing fallback immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppImage('', width: 48, height: 48)),
      ),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview popup has each product row and independently selectable controls',
    (tester) async {
      final order = buildShopOrderPreview(DateTime(2026, 10, 23)).first;
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ShopOrderCard(
                  order: order,
                  previewOnly: true,
                  save: (quantities, confirmed, _, _) async =>
                      applyShopOrderPreviewDelivery(
                        order,
                        quantities,
                        confirmed,
                      ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();
      expect(find.text('Supply Order'), findsOneWidget);
      expect(find.textContaining('RO Membrane 75 GPD'), findsNWidgets(2));
      expect(find.textContaining('Sediment Filter 10 inch'), findsNWidgets(2));
      expect(find.textContaining('Flow Restrictor 300 ml'), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.byTooltip('Increase delivered quantity'), findsNWidgets(3));
      expect(find.byTooltip('Decrease delivered quantity'), findsNWidgets(3));
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm Supply'), findsOneWidget);

      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes.every((box) => box.value == false), isTrue);
      await tester.tap(find.byTooltip('Increase delivered quantity').at(0));
      await tester.pump();
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox)).first.value,
        isFalse,
      );
    },
  );

  testWidgets('preview confirmation displays a local-only success message', (
    tester,
  ) async {
    final order = buildShopOrderPreview(DateTime(2026, 10, 23)).first;
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ShopOrderCard(
                order: order,
                previewOnly: true,
                save: (quantities, confirmed, _, _) async =>
                    applyShopOrderPreviewDelivery(order, quantities, confirmed),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase delivered quantity').first);
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Confirm Supply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Success!'), findsOneWidget);
    expect(find.textContaining('preview only'), findsOneWidget);
    expect(order['status'], 'Partially Delivered');
    expect(order['paymentStatus'], 'pending');
  });
}
