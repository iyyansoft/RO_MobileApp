import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ro_wholesale_dealer_app/core/widgets/app_scroll_behavior.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';

void main() {
  testWidgets('overflowing gallery thumbnails can be swiped and selected', (
    tester,
  ) async {
    final product = ProductModel(
      id: 'gallery',
      name: 'Gallery Product',
      sku: 'GALLERY',
      categoryId: 'systems',
      categoryName: 'RO Systems',
      brand: 'Aqua',
      mrp: 100,
      dealerPrice: 80,
      imageUrl: 'assets/images/purifier.jpg',
      galleryImages: List.filled(20, 'assets/images/purifier.jpg'),
      stockStatus: StockStatus.inStock,
      moq: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => [product]),
        ],
        child: MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: ProductDetailsScreen(product: product),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final lastThumbnail = find.byKey(const ValueKey('product-thumbnail-19'));
    await tester.dragUntilVisible(lastThumbnail, strip, const Offset(-250, 0));
    await tester.pumpAndSettle();
    await tester.tap(lastThumbnail);
    await tester.pumpAndSettle();
    final gallery = tester.widget<PageView>(find.byType(PageView).first);
    expect(gallery.controller!.page, 19);
    expect(tester.takeException(), isNull);
  });
  for (final device in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('horizontal lists reach and select last item with $device', (
      tester,
    ) async {
      var selected = -1;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: SizedBox(
              height: 80,
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: 12,
                itemBuilder: (context, index) => SizedBox(
                  width: 180,
                  child: TextButton(
                    onPressed: () => selected = index,
                    child: Text('Item $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var swipe = 0; swipe < 5; swipe++) {
        final gesture = await tester.startGesture(
          const Offset(700, 40),
          kind: device,
        );
        for (var step = 0; step < 10; step++) {
          await gesture.moveBy(const Offset(-50, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }
      expect(controller.offset, controller.position.maxScrollExtent);
      await tester.tap(find.text('Item 11'));
      expect(selected, 11);
      expect(tester.takeException(), isNull);
    });
  }
}
