import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/theme/app_theme.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_files.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/admin_repository.dart';
import 'package:ro_wholesale_dealer_app/features/admin/presentation/screens/admin_screen.dart';
import 'package:ro_wholesale_dealer_app/features/admin/presentation/screens/bulk_products_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

class _AdminApi extends AdminRepository {
  final products = <Map<String, dynamic>>[];
  Map<String, dynamic>? saved;
  Map<String, dynamic>? createdShopEmployee;
  _AdminApi() {
    token = 'test-admin';
  }
  @override
  Future<bool> restoreSession() async => true;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    dynamic data,
  }) async {
    if (path == 'shop/employees' && method == 'POST') {
      createdShopEmployee = Map<String, dynamic>.from(data as Map);
    }
    if (path == 'products' && method == 'POST') {
      saved = Map<String, dynamic>.from(data as Map);
      products.add({...saved!, 'id': 'new-product'});
    }
    if (path == 'shop/employees') {
      if (method == 'POST' && createdShopEmployee != null) {
        return {
          'success': true,
          'employees': [
            {
              'id': 'new-employee',
              'shop_name': createdShopEmployee!['shopName'],
              'employee_id': createdShopEmployee!['loginId'],
              'active': true,
            },
          ],
        };
      }
      return {
        'success': true,
        'employees': createdShopEmployee == null
            ? []
            : [
                {
                  'id': 'new-employee',
                  'shop_name': createdShopEmployee!['shopName'],
                  'employee_id': createdShopEmployee!['loginId'],
                  'active': true,
                },
              ],
      };
    }
    if (path == 'shop/notifications') {
      return {'success': true, 'notifications': []};
    }
    if (path == 'shop/enquiries') {
      return {'success': true, 'enquiries': []};
    }
    return {
      'success': true,
      'products': products,
      'analytics': {},
      'message': 'Saved',
    };
  }
}

Uint8List workbook(Map<String, dynamic> row) {
  final excel = Excel.createExcel();
  final sheet = excel.tables.values.first;
  sheet.appendRow(AdminFiles.productHeaders.map(TextCellValue.new).toList());
  sheet.appendRow(
    AdminFiles.productHeaders
        .map((key) => TextCellValue('${row[key] ?? ''}'))
        .toList(),
  );
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  test(
    'bulk template maps every field and keeps purchase/dealer prices separate',
    () {
      final rows = AdminFiles.parseProductsWorkbook(
        workbook(AdminFiles.productExample),
      );
      final row = rows.single;
      expect(row['purchase_price'], 400);
      expect(row['price'], 500);
      expect(row['stock_quantity'], 50);
      expect(row['moq'], '1');
      expect(row['img'], AdminFiles.productExample['Image']);
      expect(row['desc'], AdminFiles.productExample['Product Description']);
      expect(
        () => AdminFiles.parseProductsWorkbook(
          workbook({...AdminFiles.productExample, 'Stock': -1}),
        ),
        throwsException,
      );
      expect(
        () => AdminFiles.parseProductsWorkbook(
          workbook({...AdminFiles.productExample, 'MOQ': 0}),
        ),
        throwsException,
      );
    },
  );

  testWidgets(
    'mobile admin adds a product and refreshes the shared category/catalog data',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _AdminApi();
      final container = ProviderContainer(
        overrides: [
          catalogProductsProvider.overrideWith(
            (ref) async => api.products.map(ProductModel.fromJson).toList(),
          ),
          catalogCategoriesProvider.overrideWith(
            (ref) async => [
              const CategoryModel(
                id: 'membranes',
                name: 'Membranes',
                imagePath: '',
                productCount: 0,
                description: '',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(catalogProductsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: AdminScreen(repository: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      expect(find.text('Single Product'), findsOneWidget);
      expect(find.text('Bulk Products'), findsOneWidget);
      await tester.tap(find.text('Single Product'));
      await tester.pumpAndSettle();
      Future<void> enter(String label, String value) async {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      await enter('Name', 'New Membrane');
      await enter('SKU', 'NEW-1');
      final category = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Membranes').last);
      await tester.pumpAndSettle();
      await enter('Purchase Price', '500');
      await enter('Dealer Price', '900');
      await enter('MRP', '1000');
      await enter('Stock', '12');
      await enter('Description', 'New membrane description');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(api.saved!['purchase_price'], 500);
      expect(api.saved!['price'], 900);
      expect(api.saved!['category'], 'membranes');
      final refreshed = await container.read(catalogProductsProvider.future);
      expect(refreshed.single.detailsPrice, 500);
      expect(refreshed.single.dealerPrice, 900);
      await container.read(catalogCategoriesProvider.future);
      expect(container.read(categoriesProvider).single.productCount, 1);
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulk Products'));
      await tester.pumpAndSettle();
      expect(find.byType(BulkProductsScreen), findsOneWidget);
      expect(find.text('Save All Products (1)'), findsOneWidget);
      expect(find.text('Import Excel'), findsNothing);
      expect(find.text('Paste JSON'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shop employee dialog submits and closes without lifecycle errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _AdminApi();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: AdminScreen(repository: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop Employees'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add employee'));
    await tester.pumpAndSettle();

    Future<void> enter(String label, String value) async {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(field, value);
      await tester.pump();
    }

    await enter('Shop name', 'North Store');
    await enter('Login ID', 'NORTH-STORE-1');
    await enter('Password (minimum 10 characters)', 'safe-test-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    // The admin page intentionally keeps an indeterminate progress bar visible
    // while its success dialog is open, so pump a bounded transition instead
    // of waiting for all animations to stop.
    for (var i = 0; i < 20 && find.text('Employee account created').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.createdShopEmployee, {
      'shopName': 'North Store',
      'loginId': 'NORTH-STORE-1',
      'password': 'safe-test-password',
    });
    expect(find.text('Employee account created'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
