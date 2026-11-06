import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/wholesale_promo_banner.dart';

void main() {
  // Desktop, tablet and phone widths must lay out without overflow.
  for (final width in [1200.0, 700.0, 360.0]) {
    testWidgets('promo banner fits at width $width', (tester) async {
      var taps = 0;
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(Size(width + 40, 340));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  color: const Color(0xFFF1F7FD),
                  padding: const EdgeInsets.all(20),
                  width: width + 40,
                  child: WholesalePromoBanner(
                    isDesktop: width >= 1024,
                    onExplore: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Explore Wholesale Deals'));
      expect(taps, 1);
      await tester.pumpAndSettle();

      final out = Platform.environment['PREVIEW_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/promo_${width.toInt()}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
