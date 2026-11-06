import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/why_choose_section.dart';

void main() {
  for (final width in [1240.0, 760.0, 360.0]) {
    testWidgets('Why Choose section lays out at width $width', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(Size(width, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const WhyChooseSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Why Choose NeeroPlus?'), findsOneWidget);
      for (final title in [
        'Lightning Fast Deliveries',
        '100% Genuine Products',
        'Pay on Delivery',
        'Bulk Order Savings',
      ]) {
        expect(find.text(title), findsOneWidget);
      }

      final out = Platform.environment['PREVIEW_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$out/why_${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
