import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_repository.dart';
import 'package:ro_wholesale_dealer_app/features/admin/presentation/screens/bulk_products_screen.dart';

class _BulkApi extends AdminRepository {
  bool unavailable = false;
  bool partial = false;
  final requests = <List<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    dynamic data,
  }) async {
    expect(path, 'products/bulk');
    expect(method, 'POST');
    final rows = (data['products'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    requests.add(rows);
    if (unavailable) {
      throw Exception('MySQL is unavailable. No products were saved.');
    }
    final saved = partial ? rows.take(1).toList() : rows;
    return {
      'success': true,
      'importedCount': saved.length,
      'imported': saved,
      'skipped': partial
          ? [
              {'sku': rows.last['sku'], 'reason': 'Database write failed'},
            ]
          : [],
    };
  }
}

Future<void> enter(
  WidgetTester tester,
  int row,
  String label,
  String text,
) async {
  final field = find
      .byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      )
      .at(row);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, int row, String sku) async {
  await enter(tester, row, 'Image URL', 'https://example.test/$sku.png');
  await enter(tester, row, 'Name', 'Product $sku');
  await enter(tester, row, 'SKU', sku);
  await enter(tester, row, 'Category', 'membranes');
  await enter(tester, row, 'Brand', 'Aqua');
  await enter(tester, row, 'Purchase Price', '500');
  await enter(tester, row, 'Dealer Price', '900');
  await enter(tester, row, 'MRP', '1200');
  await enter(tester, row, 'MOQ', '2');
  await enter(tester, row, 'Stock', '12');
  await enter(tester, row, 'Description', 'Complete details for $sku');
}

void main() {
  for (final unavailable in [false, true]) {
    testWidgets(
      unavailable
          ? 'MySQL failure retains every entered product'
          : 'mobile Save All submits every direct-entry row once',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _BulkApi()..unavailable = unavailable;
        var refreshes = 0;
        int? savedCount;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    savedCount = await Navigator.push<int>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BulkProductsScreen(
                          repository: api,
                          onSaved: () => refreshes++,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open bulk'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open bulk'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Excel'), findsNothing);
        expect(find.textContaining('JSON'), findsNothing);
        await fill(tester, 0, 'ROW-1');
        await tester.ensureVisible(find.text('+ Add Product'));
        await tester.tap(find.text('+ Add Product'));
        await tester.pumpAndSettle();
        await fill(tester, 1, 'ROW-2');
        await tester.tap(find.text('Save All Products (2)'));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(api.requests.single, hasLength(2));
        for (final product in api.requests.single) {
          expect(product['purchase_price'], 500);
          expect(product['price'], 900);
          expect(product['stock_quantity'], 12);
          expect(product['moq'], '2');
          expect(product['img'], contains('.png'));
          expect(product['desc'], startsWith('Complete details'));
        }
        if (unavailable) {
          expect(refreshes, 0);
          expect(savedCount, isNull);
          expect(find.text('Save All Products (2)'), findsOneWidget);
          final values = tester
              .widgetList<TextField>(find.byType(TextField))
              .map((field) => field.controller?.text);
          expect(values, containsAll(['ROW-1', 'ROW-2', '500', '900']));
        } else {
          expect(refreshes, 1);
          expect(savedCount, 2);
          expect(find.byType(BulkProductsScreen), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('partial save removes confirmed products and retains failures', (
    tester,
  ) async {
    final api = _BulkApi()..partial = true;
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BulkProductsScreen(repository: api, onSaved: () => refreshes++),
      ),
    );
    await fill(tester, 0, 'FIRST');
    await tester.ensureVisible(find.text('+ Add Product'));
    await tester.tap(find.text('+ Add Product'));
    await tester.pumpAndSettle();
    await fill(tester, 1, 'SECOND');
    await tester.tap(find.text('Save All Products (2)'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Save All Products (1)'), findsOneWidget);
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller?.text);
    expect(values, contains('SECOND'));
    expect(values, isNot(contains('FIRST')));
    expect(tester.takeException(), isNull);
  });
}
