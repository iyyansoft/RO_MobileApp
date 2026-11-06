import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/home_footer.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';

void main() {
  final categories = [
    for (final name in [
      'RO Systems',
      'Membranes',
      'Filters & Cartridges',
      'Booster Pumps',
      'Pipes & Tubing',
      'Spare Parts & Valves',
    ])
      CategoryModel.fromJson({'id': name.toLowerCase(), 'name': name}),
  ];

  for (final width in [1280.0, 700.0, 360.0]) {
    testWidgets('footer lays out at width $width and links navigate', (
      tester,
    ) async {
      final visited = <String>[];
      CategoryModel? tapped;
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(Size(width, 1100));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: HomeFooter(
                  categories: categories,
                  onNavigate: visited.add,
                  onCategoryTap: (c) => tapped = c,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('My orders'));
      await tester.tap(find.text('Profile'));
      await tester.tap(find.text('Membranes'));
      expect(visited, ['/orders', '/profile']);
      expect(tapped?.name, 'Membranes');

      final out = Platform.environment['PREVIEW_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$out/footer_${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
