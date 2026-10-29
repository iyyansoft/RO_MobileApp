import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/brand_logo.dart';

void main() {
  testWidgets('RO logo asset loads contained without a background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: BrandLogo(width: 220, height: 79))),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/RO_LOGO.png',
    );
    expect(image.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });
}
