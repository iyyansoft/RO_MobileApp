import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_image.dart';

// In widget tests every network request fails (HTTP 400), which stands in
// for a phone briefly losing its connection.
void main() {
  testWidgets('a failed product image is retried, then gives up', (
    tester,
  ) async {
    var placeholders = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppImage(
          '/api/product-images/img_1.jpg',
          errorBuilder: (_, __, ___) {
            placeholders++;
            return const Text('PLACEHOLDER');
          },
        ),
      ),
    );
    Future<void> settle() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await settle();
    await tester.pump();
    expect(find.text('PLACEHOLDER'), findsOneWidget);
    Image image() => tester.widget<Image>(find.byType(Image));
    expect(
      (image().key! as ValueKey<String>).value,
      endsWith('/api/product-images/img_1.jpg#0'),
    );

    // Retries after 2s, 5s and 10s, each with a fresh Image (new key).
    for (final (attempt, delay) in [(1, 2), (2, 5), (3, 10)]) {
      await tester.pump(Duration(seconds: delay));
      expect((image().key! as ValueKey<String>).value, endsWith('#$attempt'));
      await settle();
      await tester.pump();
      expect(find.text('PLACEHOLDER'), findsOneWidget);
    }

    // No further retries after the third.
    final before = placeholders;
    await tester.pump(const Duration(seconds: 30));
    expect((image().key! as ValueKey<String>).value, endsWith('#3'));
    expect(placeholders, greaterThanOrEqualTo(before));
  });
}
