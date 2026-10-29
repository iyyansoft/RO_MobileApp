import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

Map<String, dynamic> _order() => {
  'orderId': 'RO-TEST-1',
  'vendorName': 'Priya Enterprises',
  'companyName': 'Priya Supplies',
  'orderDate': '2026-10-16T10:00:00Z',
  'paymentStatus': 'pending',
  'paymentMethod': 'Cash on Delivery',
  'status': 'Pending',
  'items': [
    {
      'id': '501',
      'name': 'RO Membrane 75 GPD',
      'sku': 'MEM-1',
      'quantity': 5,
      'unitPrice': 650,
      'deliveredQuantity': 0,
      'deliveryConfirmed': false,
      'image': '',
    },
    {
      'id': '502',
      'name': 'Filter',
      'sku': 'FIL-1',
      'quantity': 3,
      'unitPrice': 200,
      'deliveredQuantity': 0,
      'deliveryConfirmed': false,
      'image': '',
    },
  ],
};

Future<void> _mount(
  WidgetTester tester,
  ShopOrderCard card, {
  Size size = const Size(1200, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: [card])),
    ),
  );
}

void main() {
  testWidgets('summary shows all original rows and Supply, not edit controls', (
    tester,
  ) async {
    await _mount(
      tester,
      ShopOrderCard(order: _order(), save: (_, _, _, _) async => null),
    );

    expect(find.textContaining('Priya Enterprises'), findsOneWidget);
    expect(find.textContaining('RO Membrane 75 GPD'), findsOneWidget);
    expect(find.textContaining('Filter'), findsOneWidget);
    expect(find.textContaining('Original Order Value'), findsOneWidget);
    expect(find.text('Supply'), findsOneWidget);
    expect(find.text('Actual Qty (+ / -)'), findsNothing);
    expect(find.text('Delivered'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('summary renders every product row in a multi-product order', (
    tester,
  ) async {
    final order = _order();
    order['items'] = [
      ...order['items'] as List,
      for (var index = 3; index <= 5; index++)
        {
          'id': '${500 + index}',
          'name': 'Additional RO Product $index',
          'sku': 'RO-$index',
          'quantity': index,
          'unitPrice': 100 * index,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
    ];
    await _mount(
      tester,
      ShopOrderCard(order: order, save: (_, _, _, _) async => null),
    );

    for (final name in [
      'RO Membrane 75 GPD',
      'Filter',
      'Additional RO Product 3',
      'Additional RO Product 4',
      'Additional RO Product 5',
    ]) {
      expect(find.textContaining(name), findsOneWidget);
    }
    expect(find.text('5'), findsNWidgets(2));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsNWidgets(2));
    expect(find.textContaining('Original Order Value'), findsOneWidget);
    expect(find.textContaining('8850.00'), findsOneWidget);
    expect(find.text('Supply'), findsOneWidget);
  });

  testWidgets('only checked physical deliveries count in live totals', (
    tester,
  ) async {
    await _mount(
      tester,
      ShopOrderCard(order: _order(), save: (_, _, _, _) async => null),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();

    expect(find.text('Supply Order'), findsOneWidget);
    expect(find.text('Actual Qty (+ / -)'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm Supply'), findsOneWidget);
    final increase = find.byTooltip('Increase delivered quantity');
    for (var i = 0; i < 4; i++) {
      await tester.tap(increase.at(0));
      await tester.pump();
    }
    for (var i = 0; i < 3; i++) {
      await tester.tap(increase.at(1));
      await tester.pump();
    }

    // Quantity edits update the live preview without confirming delivery.
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isFalse);
    expect(find.text('₹3200.00'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('₹650.00'), findsNWidgets(3));

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    // The checkbox stays independent while quantities continue to recalculate.
    await tester.tap(increase.at(0));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isTrue);
    expect(find.text('₹3850.00'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Decrease delivered quantity').at(0));
    await tester.pump();
    expect(find.text('₹3200.00'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();

    expect(find.text('₹3200.00'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('₹650.00'), findsNWidgets(3));
  });

  testWidgets(
    'quantity changes stay bounded and checkbox toggles independently',
    (tester) async {
      final order = _order();
      order['items'] = [
        {
          'id': '701',
          'name': 'Filter',
          'sku': 'FIL-2',
          'quantity': 2,
          'unitPrice': 500,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
      ];
      await _mount(
        tester,
        ShopOrderCard(order: order, save: (_, _, _, _) async => null),
        size: const Size(390, 844),
      );
      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox).first;
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      final increase = find.byTooltip('Increase delivered quantity').first;
      final decrease = find.byTooltip('Decrease delivered quantity').first;
      await tester.tap(increase);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(increase);
      await tester.pump();
      final increaseButton = find.ancestor(
        of: find.byIcon(Icons.add_circle_outline).first,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(increaseButton.first).onPressed, isNull);
      expect(find.textContaining('1000.00'), findsNWidgets(3));

      await tester.tap(decrease);
      await tester.pump();
      final decreaseButton = find.ancestor(
        of: find.byIcon(Icons.remove_circle_outline).first,
        matching: find.byType(IconButton),
      );
      expect(
        tester.widget<IconButton>(decreaseButton.first).onPressed,
        isNotNull,
      );
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('500.00')),
        findsNWidgets(3),
      );
      expect(find.textContaining('Original Order Value'), findsNWidgets(2));

      await tester.tap(decrease);
      await tester.pump();
      expect(tester.widget<IconButton>(decreaseButton.first).onPressed, isNull);

      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(
        tester.widget<Checkbox>(checkbox).activeColor,
        const Color(0xFF2E9D59),
      );
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three product order adjusts actual quantities and totals independently',
    (tester) async {
      final order = _order();
      order['items'] = [
        {
          'id': '601',
          'name': 'RO Membrane',
          'sku': 'MEM-3',
          'quantity': 3,
          'unitPrice': 650,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
        {
          'id': '602',
          'name': 'Filter',
          'sku': 'FIL-2',
          'quantity': 2,
          'unitPrice': 200,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
        {
          'id': '603',
          'name': 'Pipes',
          'sku': 'PIPE-1',
          'quantity': 1,
          'unitPrice': 80,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
      ];
      await _mount(
        tester,
        ShopOrderCard(order: order, save: (_, _, _, _) async => null),
        size: const Size(1200, 1000),
      );
      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();

      for (final name in ['RO Membrane', 'Filter', 'Pipes']) {
        expect(find.textContaining(name), findsNWidgets(2));
      }
      expect(find.byType(Checkbox), findsNWidgets(3));
      final increase = find.byTooltip('Increase delivered quantity');
      for (var index = 0; index < 2; index++) {
        await tester.tap(increase.at(0));
        await tester.pump();
      }
      for (var index = 0; index < 2; index++) {
        await tester.tap(increase.at(1));
        await tester.pump();
      }
      await tester.ensureVisible(increase.at(2));
      await tester.pumpAndSettle();
      await tester.tap(increase.at(2));
      await tester.pump();

      expect(find.text('₹2430.00'), findsOneWidget);
      expect(find.text('₹1780.00'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(4));
      expect(find.textContaining('650.00'), findsNWidgets(3));
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );

      await tester.ensureVisible(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final checks = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checks.map((checkbox) => checkbox.value), [true, false, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Actual Qty 3 to 2 matches dealer price totals and stays bounded',
    (tester) async {
      final order = _order();
      order['items'] = [
        {
          'id': '801',
          'name': 'RO Membrane',
          'sku': 'MEM-3',
          'quantity': 3,
          'unitPrice': 650,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
      ];
      await _mount(
        tester,
        ShopOrderCard(order: order, save: (_, _, _, _) async => null),
        size: const Size(1200, 1000),
      );
      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();

      final increase = find.byTooltip('Increase delivered quantity').first;
      final decrease = find.byTooltip('Decrease delivered quantity').first;
      final checkbox = find.byType(Checkbox).first;
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      for (var i = 0; i < 3; i++) {
        await tester.tap(increase);
        await tester.pump();
      }
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byIcon(Icons.add_circle_outline).first,
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );

      await tester.tap(decrease);
      await tester.pump();
      final dialog = find.byType(Dialog);
      expect(find.text('2'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91950.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91300.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B9650.00')),
        findsNWidgets(2),
      );
      expect(find.text('Undelivered Quantity'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('1')),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);

      await tester.tap(decrease);
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B9650.00')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91300.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(increase);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91300.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B9650.00')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91950.00')),
        findsOneWidget,
      );

      await tester.tap(increase);
      await tester.pump();
      expect(
        find.descendant(of: dialog, matching: find.text('3')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: dialog, matching: find.text('\u20B91950.00')),
        findsNWidgets(2),
      );
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('supply popup has independent controls for every order item', (
    tester,
  ) async {
    final order = _order();
    order['items'] = [
      ...order['items'] as List,
      for (var index = 3; index <= 5; index++)
        {
          'id': '${500 + index}',
          'name': 'Additional RO Product $index',
          'sku': 'RO-$index',
          'quantity': index,
          'unitPrice': 100 * index,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
    ];
    await _mount(
      tester,
      ShopOrderCard(order: order, save: (_, _, _, _) async => null),
      size: const Size(1200, 1000),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();

    for (final name in [
      'RO Membrane 75 GPD',
      'Filter',
      'Additional RO Product 3',
      'Additional RO Product 4',
      'Additional RO Product 5',
    ]) {
      expect(find.textContaining(name), findsNWidgets(2));
    }
    expect(find.byType(Checkbox), findsNWidgets(5));
    expect(find.byTooltip('Increase delivered quantity'), findsNWidgets(5));
    expect(find.byTooltip('Decrease delivered quantity'), findsNWidgets(5));

    await tester.tap(find.byTooltip('Increase delivered quantity').at(4));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(4));
    await tester.pump();

    final checks = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(checks.map((check) => check.value), [
      false,
      false,
      false,
      false,
      true,
    ]);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Delivered Value'), findsOneWidget);
    expect(find.text('Undelivered Quantity'), findsOneWidget);
    expect(find.text('Refund / Adjustment'), findsOneWidget);
    expect(find.textContaining('Original Order Value'), findsNWidgets(2));
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm Supply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel on the supply popup closes it without saving', (
    tester,
  ) async {
    var saveCalls = 0;
    await _mount(
      tester,
      ShopOrderCard(
        order: _order(),
        save: (_, _, _, _) async {
          saveCalls++;
          return null;
        },
      ),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Supply Order'), findsNothing);
    expect(saveCalls, 0);
  });

  testWidgets(
    'supply popup keeps totals and actions usable on a phone-sized screen',
    (tester) async {
      final order = _order();
      order['items'] = [
        ...order['items'] as List,
        {
          'id': '503',
          'name': 'Tubing',
          'sku': 'TUBE-1',
          'quantity': 2,
          'unitPrice': 120,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
        {
          'id': '504',
          'name': 'Housing',
          'sku': 'HOUS-1',
          'quantity': 1,
          'unitPrice': 340,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
      ];
      await _mount(
        tester,
        ShopOrderCard(order: order, save: (_, _, _, _) async => null),
        size: const Size(390, 844),
      );
      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();
      expect(find.text('Supply Order'), findsOneWidget);
      expect(find.textContaining('Original Order Value'), findsNWidgets(2));
      expect(find.text('Delivered Value'), findsOneWidget);
      expect(find.text('Undelivered Quantity'), findsOneWidget);
      expect(find.text('Refund / Adjustment'), findsOneWidget);
      expect(find.text('Product Name'), findsNWidgets(2));
      expect(find.text('Dealer\nPrice'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.startsWith('Actual Qty') == true,
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Increase delivered quantity'), findsNWidgets(4));
      expect(find.byType(Checkbox), findsNWidgets(4));
      final lastIncrease = find.byTooltip('Increase delivered quantity').last;
      await tester.ensureVisible(lastIncrease);
      await tester.tap(lastIncrease);
      await tester.pump();
      final lastCheckbox = find.byType(Checkbox).last;
      await tester.ensureVisible(lastCheckbox);
      await tester.tap(lastCheckbox);
      await tester.pump();
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox)).last.value,
        isTrue,
      );
      expect(find.text('Confirm Supply'), findsOneWidget);
      expect(
        tester.getRect(find.text('Confirm Supply')).bottom,
        lessThanOrEqualTo(844),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checked zero quantity is rejected; full delivery totals reconcile',
    (tester) async {
      var saveCalls = 0;
      await _mount(
        tester,
        ShopOrderCard(
          order: _order(),
          save: (_, _, _, _) async {
            saveCalls++;
            return null;
          },
        ),
      );
      await tester.tap(find.text('Supply'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.text('Confirm Supply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Actual Qty above zero'), findsOneWidget);
      expect(find.text('Confirm Supply?'), findsNothing);
      expect(saveCalls, 0);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      final increase = find.byTooltip('Increase delivered quantity');
      for (var i = 0; i < 5; i++) {
        await tester.tap(increase.at(0));
        await tester.pump();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(increase.at(1));
        await tester.pump();
      }
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      expect(find.text('₹3850.00'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.text('Confirm Supply'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Supply?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(saveCalls, 1);
    },
  );

  testWidgets(
    'cancel confirmation saves nothing; successful retry saves once',
    (tester) async {
      var saveCalls = 0;
      Map<int, int>? savedQuantities;
      Set<int>? savedConfirmed;
      String? savedMode;
      bool? savedCashCollected;
      await _mount(
        tester,
        ShopOrderCard(
          order: _order(),
          save: (quantities, confirmed, mode, cashCollected) async {
            saveCalls++;
            savedQuantities = quantities;
            savedConfirmed = confirmed;
            savedMode = mode;
            savedCashCollected = cashCollected;
            return null;
          },
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
      expect(find.text('Confirm Supply?'), findsOneWidget);
      expect(
        find.textContaining('Cash collection remains pending'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(saveCalls, 0);
      expect(find.text('Supply Order'), findsOneWidget);

      await tester.tap(find.text('Confirm Supply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(saveCalls, 1);
      expect(savedQuantities, {501: 1, 502: 0});
      expect(savedConfirmed, {501});
      expect(savedMode, 'confirm');
      expect(savedCashCollected, false);
      expect(find.text('Success!'), findsOneWidget);
      expect(
        find.textContaining('Cash on Delivery remains pending'),
        findsOneWidget,
      );
    },
  );

  testWidgets('COD cash is sent only after explicit employee confirmation', (
    tester,
  ) async {
    final order = _order()
      ..['items'] = [
        {
          'id': '501',
          'name': 'RO Membrane',
          'quantity': 1,
          'unitPrice': 650,
          'deliveredQuantity': 0,
          'deliveryConfirmed': false,
          'image': '',
        },
      ];
    bool? cashCollected;
    await _mount(
      tester,
      ShopOrderCard(
        order: order,
        save: (_, _, _, cash) async {
          cashCollected = cash;
          return null;
        },
      ),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase delivered quantity'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Confirm Supply'));
    await tester.pumpAndSettle();
    expect(find.text('Cash was collected from the customer'), findsOneWidget);
    await tester.tap(find.text('Cash was collected from the customer'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();
    expect(cashCollected, true);
    expect(
      find.text('Cash Collected and Products Delivered Successfully.'),
      findsOneWidget,
    );
  });

  testWidgets('quantity adjustment clears validation and remains bounded', (
    tester,
  ) async {
    await _mount(
      tester,
      ShopOrderCard(order: _order(), save: (_, _, _, _) async => null),
    );
    await tester.tap(find.text('Supply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('Confirm Supply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Actual Qty above zero'), findsOneWidget);

    final increase = find.byTooltip('Increase delivered quantity').first;
    for (var i = 0; i < 7; i++) {
      await tester.tap(increase);
      await tester.pump();
    }
    expect(find.textContaining('Actual Qty above zero'), findsNothing);
    // Ordered quantity is five; further increases are disabled at the cap.
    expect(find.textContaining('3250.00'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'server error remains visible and leaves supply available to retry',
    (tester) async {
      var saveCalls = 0;
      await _mount(
        tester,
        ShopOrderCard(
          order: _order(),
          save: (_, _, _, _) async {
            saveCalls++;
            return 'Delivery details could not be saved.';
          },
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
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(saveCalls, 1);
      expect(find.textContaining('Supply could not be saved'), findsOneWidget);
      expect(find.text('Supply Order'), findsOneWidget);
      expect(find.text('Success!'), findsNothing);

      // The same order remains available for a deliberate retry.
      await tester.tap(find.text('Confirm Supply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Supply Order'), findsOneWidget);
    },
  );
}
