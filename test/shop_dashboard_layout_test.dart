import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_orders_preview.dart';
import 'package:ro_wholesale_dealer_app/features/shop/presentation/shop_screens.dart';

/// Responses shaped like the /api/shop/* endpoints.
Map<String, dynamic> _respond(String path) {
  if (path.endsWith('shop/auth/session')) {
    return {
      'success': true,
      'employee': {
        'name': 'Iyyan Kumar',
        'loginId': 'IYYAN',
        'shopName': 'ROSHOP',
        'role': 'shop_employee',
      },
    };
  }
  if (path.endsWith('shop/dashboard')) {
    return {
      'success': true,
      'metrics': {
        'todaySales': 12850.5,
        'monthlySales': 286400,
        'todayOrders': 6,
        'newEnquiries': 3,
      },
    };
  }
  if (path.endsWith('shop/orders')) {
    return {'success': true, 'orders': buildShopOrderPreview(DateTime.now())};
  }
  if (path.endsWith('shop/categories')) {
    return {
      'success': true,
      'categories': [
        {'key_name': 'membranes', 'title': 'Membranes'},
        {'key_name': 'pumps', 'title': 'Booster Pumps'},
      ],
    };
  }
  if (path.endsWith('shop/products')) {
    return {
      'success': true,
      'products': [
        for (final (i, name, cat, title, stock) in [
          (1, 'RO Membrane 75 GPD', 'membranes', 'Membranes', 40),
          (2, 'RO Booster Pump 100 GPD', 'pumps', 'Booster Pumps', 12),
          (
            3,
            'Commercial RO System 25 LPH with long product name',
            'systems',
            'RO Systems',
            0,
          ),
          (4, 'Sediment Filter 10 Inch', 'filters', 'Filters & Cartridges', 85),
          (5, 'PE Tubing 1/4 Inch 10 Metres', 'pipes', 'Pipes & Tubing', 200),
        ])
          {
            'id': 'p$i',
            'name': name,
            'sku': 'SKU-00$i',
            'category_key': cat,
            'category_name': title,
            'brand': 'RO Wholesale',
            'mrp': 1200 * i,
            'price': 900 * i,
            'image': 'assets/images/RO_System.png',
            'stock': stock,
          },
      ],
    };
  }
  if (path.endsWith('shop/reports')) {
    return {
      'success': true,
      'rows': [
        for (var i = 1; i <= 4; i++)
          {
            'productName': 'RO Membrane 75 GPD',
            'quantitySold': 3 * i,
            'sale_date': '2026-11-0$i',
            'deliveredAmount': 1950 * i,
            'pendingAmount': 650,
            'refundAmount': 0,
          },
      ],
      'totals': {
        'quantitySold': 30,
        'deliveredAmount': 19500,
        'pendingAmount': 2600,
        'refundAmount': 0,
      },
    };
  }
  return {'success': true};
}

ShopEmployeeRepository _repo() {
  final dio = Dio(BaseOptions(baseUrl: 'http://shop.test/api/'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(requestOptions: options, data: _respond(options.path)),
      ),
    ),
  );
  return ShopEmployeeRepository.forTesting(dio);
}

const _pages = [
  'Overview',
  'Current Orders',
  'Deliveries',
  'Vendors',
  'Products',
  'New Enquiries',
  'Sales Reports',
  'Profile',
];

void main() {
  final previewDir = Platform.environment['PREVIEW_DIR'];
  final previewFont = Platform.environment['PREVIEW_FONT'];

  setUpAll(() async {
    if (previewFont != null && File(previewFont).existsSync()) {
      for (final family in ['Roboto', 'Outfit']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(previewFont).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    }
  });

  for (final (label, size) in [
    ('desktop', const Size(1440, 900)),
    ('tablet', const Size(820, 1100)),
    ('mobile', const Size(390, 844)),
  ]) {
    testWidgets('Shop App pages lay out without overflow on $label', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'ro_shop_employee_token': 'test-token',
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: ShopAppScreen(repository: _repo()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      Future<void> capture(String name) async {
        if (previewDir == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$previewDir/shop_${label}_$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      Future<void> open(int index) async {
        if (label == 'mobile') {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationDrawer),
              matching: find.text(_pages[index]),
            ),
          );
        } else if (label == 'tablet') {
          // Icon rail: items are labelled by their tooltips.
          await tester.tap(find.byTooltip(_pages[index]).first);
        } else {
          await tester.tap(find.widgetWithText(InkWell, _pages[index]).first);
        }
        await tester.pumpAndSettle();
      }

      // Starts on Current Orders.
      expect(find.text('Supply'), findsWidgets);
      expect(find.text('New Enquiry'), findsOneWidget);
      await capture('1_current_orders');

      for (final (i, name) in [
        (0, '0_overview'),
        (2, '2_deliveries'),
        (3, '3_vendors'),
        (4, '4_products'),
        (5, '5_enquiries'),
        (6, '6_reports'),
        (7, '7_profile'),
      ]) {
        await open(i);
        expect(tester.takeException(), isNull, reason: name);
        await capture(name);
      }

      // The supply dialog opens from an order card.
      await open(1);
      final supply = find.text('Supply').hitTestable().evaluate().isNotEmpty
          ? find.text('Supply').hitTestable().first
          : find.text('Supply').first;
      await tester.ensureVisible(supply);
      await tester.pumpAndSettle();
      await tester.tap(supply);
      await tester.pumpAndSettle();
      expect(find.text('Supply Order'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('8_supply_dialog');
    });
  }
}
