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
      await tester.binding.setSurfaceSize(Size(width + 40, 500));
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
      // The banner is the big_banner.png artwork, full width.
      final banner = find.byKey(const ValueKey('wholesale-promo-banner'));
      final size = tester.getSize(banner);
      expect(size.width, width);
      // Whole image (3:1) on wide screens; at least 150 px tall on phones.
      final expected = width / WholesalePromoBanner.aspectRatio;
      expect(size.height, closeTo(expected < 150 ? 150 : expected, 0.5));
      final ink = tester.widget<Ink>(
        find.descendant(of: banner, matching: find.byType(Ink)),
      );
      final image = (ink.decoration! as BoxDecoration).image!;
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/big_banner.png',
      );
      expect(image.fit, BoxFit.cover);
      // Tapping anywhere on it opens the catalogue.
      await tester.tap(banner);
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
