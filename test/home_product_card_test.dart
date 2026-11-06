import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_product_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

void main() {
  final product = ProductModel.fromJson({
    'id': 'cto',
    'name': 'Carbon CTO Filter 10 Inch with a long descriptive name',
    'brand': 'RO Wholesale',
    'sku': 'RO-FLT-CTO',
    'img': 'assets/images/filter.jpg',
    'dealer_price': 180,
    'mrp': 300,
    'moq': 1,
  });

  // Desktop, tablet and narrow-phone card widths must lay out without overflow.
  for (final width in [400.0, 300.0, 165.0]) {
    testWidgets('Home product card fits at width $width', (tester) async {
      var added = 0;
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(500, 500));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  color: const Color(0xFFF1F7FD),
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: width,
                    height: HomeProductCard.extentFor(width),
                    child: HomeProductCard(
                      product: product,
                      onTap: () {},
                      onAddToCart: () => added++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('40% OFF'), findsOneWidget);
      expect(find.text('₹180'), findsOneWidget);
      expect(find.text('Save ₹120'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_shopping_cart_rounded));
      expect(added, 1);
      await tester.pumpAndSettle();

      final out = Platform.environment['PREVIEW_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/card_${width.toInt()}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
