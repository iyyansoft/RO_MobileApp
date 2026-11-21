import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/screens/home_screen.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/hero_carousel/hero_banner_carousel.dart';
import 'package:ro_wholesale_dealer_app/features/home/presentation/widgets/hero_carousel/hero_slide_view.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

const _categories = [
  CategoryModel(
    id: 'systems',
    name: 'RO Systems',
    imagePath: '',
    productCount: 3,
    description: 'Purifiers',
  ),
  CategoryModel(
    id: 'spares',
    name: 'Spares',
    imagePath: '',
    productCount: 2,
    description: 'Spare parts',
  ),
];

List<ProductModel> _products() => [
  for (final (i, cat, price) in [
    (0, _categories[0], 8500.0),
    (1, _categories[0], 12500.0),
    (2, _categories[0], 125000.0),
    (3, _categories[1], 450.0),
    (4, _categories[1], 1200.0),
  ])
    ProductModel(
      id: 'p$i',
      name: 'Product $i',
      sku: 'SKU-$i',
      categoryId: cat.id,
      categoryName: cat.name,
      brand: 'Neero+',
      mrp: price * 1.4,
      dealerPrice: price,
      imageUrl: 'assets/images/banners_cutout/filter.png',
      stockStatus: StockStatus.inStock,
      moq: 2,
    ),
];

/// Indexes of the slides currently on screen, left to right.
List<int> _visible(WidgetTester tester) {
  final width = tester.view.physicalSize.width;
  final shown = <(double, int)>[];
  for (var i = 0; i < kHeroSlides.length; i++) {
    for (final el
        in find.text(kHeroSlides[i].title, findRichText: true).evaluate()) {
      final box = el.renderObject! as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final x = box.localToGlobal(box.size.center(Offset.zero)).dx;
      if (x > 0 && x < width) shown.add((x, i));
    }
  }
  shown.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in shown) s.$2];
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

/// The selected pagination dot (the current slide).
Finder _dot(int i) => find.byKey(ValueKey('hero-dot-$i'));
bool _dotSelected(WidgetTester tester, int i) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: _dot(i), matching: find.byType(AnimatedContainer)),
  );
  return container.constraints?.maxWidth == 28;
}

Finder _inHero(Finder f) =>
    find.descendant(of: find.byType(HeroBannerCarousel), matching: f);

Future<GlobalKey> _pumpHome(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1100);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      for (final page in ['products', 'orders', 'profile', 'cart'])
        GoRoute(
          path: '/$page',
          builder: (_, __) =>
              Scaffold(body: Center(child: Text('${page.toUpperCase()} PAGE'))),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogProductsProvider.overrideWith((ref) async => _products()),
        catalogCategoriesProvider.overrideWith((ref) async => _categories),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (context, child) => RepaintBoundary(key: key, child: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(HeroBannerCarousel));
    for (final s in kHeroSlides) {
      await precacheImage(AssetImage(s.image), ctx);
    }
  });
  await tester.pump(const Duration(milliseconds: 50));
  return key;
}

void main() {
  final previewDir = Platform.environment['PREVIEW_DIR'];
  final previewFont = Platform.environment['PREVIEW_FONT'];

  setUpAll(() async {
    if (previewFont != null && File(previewFont).existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(File(previewFont).readAsBytesSync()),
          ),
        );
      await loader.load();
    }
  });

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    if (previewDir == null) return;
    await tester.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$previewDir/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  test('exactly six slides and Indian price grouping', () {
    expect(kHeroSlides, hasLength(6));
    expect(formatIndianAmount(450), '450');
    expect(formatIndianAmount(125000), '1,25,000');
  });

  for (final (label, width, perView) in [
    ('desktop', 1280.0, 2),
    ('tablet', 800.0, 1),
    ('mobile', 390.0, 1),
  ]) {
    testWidgets('carousel on $label shows $perView slide(s)', (tester) async {
      final key = await _pumpHome(tester, width);
      expect(tester.takeException(), isNull);
      expect(HeroLayout.forWidth(width - 32).visibleSlides, perView);

      List<int> expected(int first) => [
        for (var i = 0; i < perView; i++) (first + i) % 6,
      ];

      expect(_visible(tester), expected(0));
      expect(_dotSelected(tester, 0), isTrue);
      expect(find.byKey(const ValueKey('hero-dot-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('hero-dot-6')), findsNothing);

      // Equal card heights.
      final hero = tester.getRect(find.byType(HeroBannerCarousel));
      expect(hero.left, greaterThanOrEqualTo(0));
      expect(hero.right, lessThanOrEqualTo(width));
      await shot(tester, key, 'hero2_$label');

      if (perView == 2) {
        // Live figures for the purifier slide (visible on desktop).
        expect(
          _inHero(find.textContaining('3 products', findRichText: true)),
          findsOneWidget,
        );
        expect(
          _inHero(find.textContaining('₹8,500', findRichText: true)),
          findsOneWidget,
        );
      }

      // Autoplay starts by itself: nothing before 4 s, next slide at 4 s.
      await tester.pump(const Duration(milliseconds: 3900));
      await tester.pump();
      expect(_visible(tester), expected(0), reason: 'not before 4 s');
      await tester.pump(const Duration(milliseconds: 100));
      await _settle(tester);
      expect(_visible(tester), expected(1), reason: 'autoplay at 4 s');
      expect(_dotSelected(tester, 1), isTrue);

      if (perView == 2 || width >= 600) {
        // Arrows: manual navigation restarts (never stops) the 4 s interval.
        await tester.pump(const Duration(milliseconds: 3000));
        await tester.tap(_inHero(find.byTooltip('Next slide')));
        await _settle(tester);
        expect(_visible(tester), expected(2), reason: 'next arrow');
        await tester.pump(const Duration(milliseconds: 2800)); // ~3.6 s
        await tester.pump();
        expect(_visible(tester), expected(2), reason: 'interval was reset');
        await tester.pump(const Duration(milliseconds: 800)); // > 4 s
        await _settle(tester);
        await _settle(tester);
        expect(_visible(tester), expected(3), reason: 'autoplay continues');

        await tester.tap(_inHero(find.byTooltip('Previous slide')));
        await _settle(tester);
        expect(_visible(tester), expected(2), reason: 'previous arrow');
        for (var i = 0; i < 3; i++) {
          await tester.tap(_inHero(find.byTooltip('Previous slide')));
          await _settle(tester);
        }
        expect(_visible(tester), expected(5), reason: 'loops backwards');
        await shot(tester, key, 'hero2_${label}_wrap');
      } else {
        expect(_inHero(find.byTooltip('Next slide')), findsNothing);
        await tester.fling(find.byType(PageView), const Offset(-250, 0), 1500);
        await _settle(tester);
        expect(_visible(tester), expected(2), reason: 'swipe next');
        await tester.fling(find.byType(PageView), const Offset(250, 0), 1500);
        await _settle(tester);
        expect(_visible(tester), expected(1), reason: 'swipe back');
      }
      expect(tester.takeException(), isNull);

      // Dots jump straight to a slide; counter follows.
      await tester.tap(find.byKey(const ValueKey('hero-dot-4')));
      await _settle(tester);
      expect(_visible(tester), expected(4), reason: 'dot');
      expect(_dotSelected(tester, 4), isTrue);
      await shot(tester, key, 'hero2_${label}_dot4');

      // Shop Now on the green filters slide (index 5) opens products.
      await tester.tap(find.byKey(const ValueKey('hero-dot-5')));
      await _settle(tester);
      await tester.tap(_inHero(find.text('Shop Now')).first);
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTS PAGE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('autoplay keeps sliding while the pointer is over the slider', (
    tester,
  ) async {
    await _pumpHome(tester, 1280);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(5, 1090));
    await mouse.moveTo(tester.getCenter(find.byType(PageView)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4000));
    await _settle(tester);
    expect(_visible(tester), [1, 2], reason: 'no pause on hover');
    await tester.pump(const Duration(milliseconds: 3200));
    await _settle(tester);
    expect(_visible(tester), [2, 3], reason: 'still sliding');
  });

  testWidgets('rapid manual navigation leaves one timer: one slide per 4 s', (
    tester,
  ) async {
    await _pumpHome(tester, 1280);
    for (var i = 0; i < 3; i++) {
      await tester.tap(_inHero(find.byTooltip('Next slide')));
      await _settle(tester);
    }
    expect(_visible(tester), [3, 4]);
    // Exactly one advance per interval afterwards (no stacked timers).
    for (final expected in [
      [4, 5],
      [5, 0],
      [0, 1],
    ]) {
      await tester.pump(const Duration(milliseconds: 3200));
      await _settle(tester);
      expect(_visible(tester), expected);
    }
  });

  testWidgets(
    'autoplay rotates through all 6 slides every 4 s and loops back to the 1st',
    (tester) async {
      await _pumpHome(tester, 390); // phone: one slide at a time
      expect(_visible(tester), [0]);
      expect(_dotSelected(tester, 0), isTrue);
      // Check 1 s after each change (the slide animation takes 650 ms).
      await tester.pump(const Duration(seconds: 1));
      for (var step = 1; step <= 7; step++) {
        await tester.pump(const Duration(milliseconds: 3200));
        await _settle(tester);
        final slide = step % 6;
        expect(_visible(tester), [slide], reason: 'after step $step');
        expect(
          _dotSelected(tester, slide),
          isTrue,
          reason: 'dot after step $step',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
