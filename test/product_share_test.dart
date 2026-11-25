import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_share.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/screens/product_details_screen.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_card.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/widgets/product_share_sheet.dart';
import 'package:flutter/services.dart';

void main() {
  setUp(ProductShareCards.clear);
  // Optional real font for preview images (PREVIEW_FONT=path/to/font.ttf).
  setUpAll(() async {
    final font = Platform.environment['PREVIEW_FONT'];
    if (font == null || !File(font).existsSync()) return;
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
    await loader.load();
  });
  const rupee = '\u20B9';
  const bullet = '\u2022';
  final product = ProductModel.fromJson({
    'id': 'filter-share',
    'name': 'Public Filter',
    'sku': 'FILTER-001',
    'category': 'filters',
    'category_name': 'Water Filters',
    'brand': 'Aqua Flow',
    'purchase_price': 500,
    'dealer_price': 900,
    'mrp': 1200,
    'moq': 'MOQ: 1 Unit',
    'description': 'A replacement filter for clean drinking water.',
    'specs': {'Material': 'Carbon block', 'Fit': 'Universal'},
    'features': ['Improves taste', 'Easy replacement'],
    'img': 'assets/images/purifier.jpg',
  });

  test('share text contains all product fields and MRP only', () {
    final text = productShareText(product);
    expect(text, contains('Product Name: Public Filter'));
    expect(text, contains('Product Code (SKU): FILTER-001'));
    expect(text, contains('Brand: Aqua Flow'));
    expect(text, contains('MRP: ${rupee}1,200'));
    expect(text, contains('Category: Water Filters'));
    expect(text, contains('Availability: IN STOCK'));
    expect(text, contains('MOQ: 1'));
    expect(
      text,
      contains('Description: A replacement filter for clean drinking water.'),
    );
    expect(text, contains('Material: Carbon block'));
    expect(text, contains('$bullet Easy replacement'));
    expect(text, isNot(contains('Dealer Price')));
    expect(text, isNot(contains('Purchase Price')));
    expect(text, isNot(contains('900')));
    expect(text, isNot(contains('500')));
    expect(text, isNot(contains('View product')));
    expect(text, isNot(contains('http')), reason: 'no product link');
    expect(text, isNot(contains('share/products')));
  });

  test('WhatsApp message carries name, MRP, SKU, brand, category and details, no product link', () {
    final uri = whatsAppShareUri(product);
    expect(uri.host, 'wa.me');
    final text = uri.queryParameters['text']!;
    expect(text, startsWith('Product Name: Public Filter'));
    expect(text, contains('MRP: ${rupee}1,200'));
    expect(text, contains('SKU: FILTER-001'));
    expect(text, contains('Brand: Aqua Flow'));
    expect(text, contains('Category: Water Filters'));
    expect(text, contains('A replacement filter for clean drinking water.'));
    // Full Admin Dashboard details as readable text, in this layout.
    expect(
      text,
      contains('DESCRIPTION:\nA replacement filter for clean drinking water.'),
    );
    expect(
      text,
      contains('SPECIFICATIONS:\nMaterial: Carbon block\nFit: Universal'),
    );
    expect(
      text,
      contains('KEY FEATURES:\n- Improves taste\n- Easy replacement'),
    );
    expect(text, contains('Contact us for orders and enquiries.'));
    for (final url in ['Product Link', 'http', 'share/products', 'onrender']) {
      expect(text, isNot(contains(url)), reason: 'no product URL');
    }
    expect(text, endsWith('Contact us for orders and enquiries.'));
    for (final hidden in ['900', '500', 'Dealer', 'Purchase']) {
      expect(text, isNot(contains(hidden)));
      expect(uri.toString(), isNot(contains(hidden)));
    }
  });

  test('the product card is a high-resolution portrait PNG built from the real photo', () async {
    WidgetsFlutterBinding.ensureInitialized();
    final photo = File('assets/images/purifier.jpg').readAsBytesSync();
    final card = await buildProductShareCardFile(
      product,
      ShareImageFile(bytes: photo, mimeType: 'image/jpeg', fileName: 'p.jpg'),
    );
    expect(card.mimeType, 'image/png');
    expect(card.fileName, 'FILTER-001.png');
    expect(card.bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(card.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1440);
    expect(frame.image.height, greaterThanOrEqualTo(1800));
    frame.image.dispose();
    codec.dispose();
    // The data-URI path renders the same card.
    final source = 'data:image/jpeg;base64,${base64Encode(photo)}';
    final again = await renderProductShareImage(product, imageSource: source);
    expect(again.take(4).toList(), [137, 80, 78, 71]);
  });

  test('the image prints category, name, SKU and MRP only (details go in '
      'the text; never dealer price)', () {
    final text = shareCardText(product);
    expect(text, [
      'WATER FILTERS',
      'Public Filter',
      'SKU: FILTER-001',
      'MRP',
      '${rupee}1,200',
    ]);
    for (final hidden in ['900', '500', 'Dealer', 'Purchase']) {
      expect(text.join(' '), isNot(contains(hidden)));
    }
  });

  testWidgets(
    'product details show Dealer Price with struck-through MRP, never Purchase Price',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProductsProvider.overrideWith((ref) async => [product]),
          ],
          child: MaterialApp(home: ProductDetailsScreen(product: product)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dealer Price (Excl. GST)'), findsOneWidget);
      final dealer = tester.widget<Text>(
        find.byKey(const ValueKey('details-dealer-price')),
      );
      expect(dealer.data, '${rupee}900');
      final mrp = tester.widget<Text>(
        find.byKey(const ValueKey('details-mrp')),
      );
      expect(mrp.data, 'MRP ${rupee}1,200');
      expect(mrp.style?.decoration, TextDecoration.lineThrough);
      expect(find.textContaining('Purchase Price'), findsNothing);
      expect(find.textContaining('500'), findsNothing);
    },
  );

  final otherProduct = ProductModel.fromJson({
    'id': 'pump-share',
    'name': 'Booster Pump 300',
    'sku': 'PMP-300',
    'category': 'pumps',
    'category_name': 'Booster Pumps',
    'brand': 'Aqua Mars',
    'purchase_price': 2500,
    'dealer_price': 3100,
    'mrp': 4800,
    'img': 'cat_pump.jpg',
  });
  // Distinct bytes per product stand in for each product's own image.
  Uint8List imageBytesFor(ProductModel p) =>
      Uint8List.fromList([0xFF, 0xD8, 0xFF, ...p.id.codeUnits]);
  // ...and for the product card built from it.
  Uint8List cardBytesFor(ProductModel p) =>
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...p.id.codeUnits]);

  Future<void> openSheet(
    WidgetTester tester,
    ProductSharer sharer, {
    ProductModel? item,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProductShareSheet(
                context,
                product: item ?? product,
                sharer: sharer,
              ),
              child: const Text('Share'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
  }

  ProductSharer fakeSharer({
    required bool canAttach,
    List<ProductModel>? fetched,
    List<(ShareImageFile, String)>? shared,
    List<(List<int>, String)>? downloaded,
    List<Uri>? launched,
    String outcome = 'shared',
    bool fetchFails = false,
    bool textReachesWhatsApp = true,
    List<(ProductModel, List<int>)>? cards,
  }) => ProductSharer(
    buildCard: (p, photo, view) async {
      cards?.add((p, photo?.bytes ?? const <int>[]));
      return ShareImageFile(
        bytes: cardBytesFor(p),
        mimeType: 'image/png',
        fileName: '${shareFileName(p)}.png',
      );
    },
    fetchImage: (p) async {
      fetched?.add(p);
      if (fetchFails) throw StateError('offline');
      return ShareImageFile(
        bytes: imageBytesFor(p),
        mimeType: 'image/jpeg',
        fileName: '${shareFileName(p)}.jpg',
      );
    },
    canShareFile: (_) => canAttach,
    shareFile: (file, text) async {
      shared?.add((file, text));
      return outcome;
    },
    downloader: (bytes, name, mime) async {
      downloaded?.add((bytes, name));
      return true;
    },
    launcher: (uri) async {
      launched?.add(uri);
      return true;
    },
    textReachesWhatsApp: () => textReachesWhatsApp,
  );

  List<String> captureClipboard(WidgetTester tester) {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return clipboard;
  }

  testWidgets('WhatsApp share sends the product card with the details text', (
    tester,
  ) async {
    final shared = <(ShareImageFile, String)>[];
    final cards = <(ProductModel, List<int>)>[];
    final launched = <Uri>[];
    final downloaded = <(List<int>, String)>[];
    await openSheet(
      tester,
      fakeSharer(
        canAttach: true,
        shared: shared,
        cards: cards,
        launched: launched,
        downloaded: downloaded,
      ),
    );
    expect(find.byKey(const ValueKey('share-image-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
    await tester.pumpAndSettle();

    expect(
      cards.single.$2,
      imageBytesFor(product),
      reason: "card built from the product's own photo",
    );
    final (file, text) = shared.single;
    expect(file.bytes, cardBytesFor(product));
    expect(file.mimeType, 'image/png');
    expect(file.fileName, 'FILTER-001.png');
    expect(
      text,
      whatsAppShareText(product),
      reason: 'ONE share: image + every detail as the caption',
    );
    expect(launched, isEmpty, reason: 'no text-only wa.me share');
    expect(downloaded, isEmpty);
  });

  testWidgets('each product shares its own card', (tester) async {
    final fetched = <ProductModel>[];
    final cards = <(ProductModel, List<int>)>[];
    final shared = <(ShareImageFile, String)>[];
    for (final item in [product, otherProduct]) {
      await openSheet(
        tester,
        fakeSharer(
          canAttach: true,
          fetched: fetched,
          cards: cards,
          shared: shared,
        ),
        item: item,
      );
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();
    }
    expect(fetched.map((p) => p.id), ['filter-share', 'pump-share']);
    expect(cards.map((c) => c.$1.id), ['filter-share', 'pump-share']);
    expect(cards[1].$2, imageBytesFor(otherProduct));
    expect(shared[1].$1.bytes, cardBytesFor(otherProduct));
    expect(shared[1].$1.fileName, 'PMP-300.png');
    expect(shared[0].$2, whatsAppShareText(product));
    expect(shared[1].$2, whatsAppShareText(otherProduct));
    expect(shareCardText(otherProduct), contains('${rupee}4,800'));
    for (final hidden in ['3,100', '3100', '2,500', '2500']) {
      expect(shareCardText(otherProduct).join(' '), isNot(contains(hidden)));
    }
  });

  testWidgets(
    'without file sharing the card is downloaded and attaching is explained',
    (tester) async {
      final downloaded = <(List<int>, String)>[];
      final launched = <Uri>[];
      final shared = <(ShareImageFile, String)>[];
      final clipboard = captureClipboard(tester);
      await openSheet(
        tester,
        fakeSharer(
          canAttach: false,
          downloaded: downloaded,
          launched: launched,
          shared: shared,
        ),
      );
      expect(
        find.text('This browser cannot share an image with text'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();

      expect(shared, isEmpty);
      expect(downloaded.single.$1, cardBytesFor(product));
      expect(downloaded.single.$2, 'FILTER-001.png');
      expect(clipboard, [whatsAppShareText(product)], reason: 'kept');
      expect(find.byKey(const ValueKey('share-manual-attach')), findsOneWidget);
      expect(find.textContaining('FILTER-001.png'), findsOneWidget);
      expect(launched, isEmpty, reason: 'WhatsApp opens only when asked');
      await tester.tap(find.byKey(const ValueKey('share-open-whatsapp')));
      await tester.pumpAndSettle();
      expect(launched.single.host, 'web.whatsapp.com');
    },
  );

  testWidgets(
    'without file sharing, the details can be sent as WhatsApp text',
    (tester) async {
      final launched = <Uri>[];
      captureClipboard(tester);
      await openSheet(tester, fakeSharer(canAttach: false, launched: launched));
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-whatsapp-text')));
      await tester.pumpAndSettle();
      expect(launched.single.host, 'wa.me');
      expect(
        launched.single.queryParameters['text'],
        whatsAppShareText(product),
      );
    },
  );

  testWidgets(
    'if the share sheet fails the card download fallback is offered',
    (tester) async {
      final downloaded = <(List<int>, String)>[];
      captureClipboard(tester);
      await openSheet(
        tester,
        fakeSharer(
          canAttach: true,
          downloaded: downloaded,
          outcome: 'failed: NotAllowedError',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();
      expect(downloaded.single.$1, cardBytesFor(product));
      expect(find.byKey(const ValueKey('share-manual-attach')), findsOneWidget);
    },
  );

  testWidgets(
    'if the saved image cannot be loaded, the placeholder card is still shared',
    (tester) async {
      final shared = <(ShareImageFile, String)>[];
      final cards = <(ProductModel, List<int>)>[];
      await openSheet(
        tester,
        fakeSharer(
          canAttach: true,
          fetchFails: true,
          shared: shared,
          cards: cards,
        ),
      );
      expect(find.byKey(const ValueKey('share-image-error')), findsNothing);
      expect(cards.single.$2, isEmpty, reason: 'no photo: placeholder card');
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();
      expect(shared.single.$1.bytes, cardBytesFor(product));
      expect(shared.single.$2, whatsAppShareText(product));
    },
  );

  testWidgets('copy copies the share message, never a product link', (tester) async {
    final clipboard = captureClipboard(tester);
    await openSheet(tester, fakeSharer(canAttach: true));
    expect(find.byKey(const ValueKey('share-copy-link')), findsNothing);
    expect(find.text('Copy product link'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('share-copy-details')));
    await tester.pumpAndSettle();
    expect(clipboard.single, whatsAppShareText(product));
    expect(clipboard.single, isNot(contains('http')));
    expect(find.text('Product details copied'), findsOneWidget);
  });

  test('product image file URL uses the app backend (works locally too)', () {
    expect(
      productImageFileUrl(
        product,
        apiBaseUrl: 'http://localhost:8080/api/',
      ).toString(),
      'http://localhost:8080/share/products/filter-share/image',
    );
  });

  group('product card with different amounts of admin content', () {
    ProductModel variant(String id, Map<String, Object?> extra) =>
        ProductModel.fromJson({
          'id': id,
          'name': 'Aqua 2090 raga series cabinets',
          'sku': 'CAB-18',
          'category_name': 'Cabinet',
          'dealer_price': 5300,
          'mrp': 13800,
          'img': 'assets/images/purifier.jpg',
          ...extra,
        });
    const longDescription =
        'Premium RO + UV + UF cabinet with a food-grade ABS body, a large '
        'transparent tank window and a smart tap. Designed for Indian water '
        'conditions, it removes dissolved salts, heavy metals and microbes '
        'while keeping essential minerals. Easy filter access from the front, '
        'wall-mounted or counter-top installation, and a low-noise booster '
        'pump make it ideal for homes and small offices. Every unit is '
        'factory tested for leaks and supplied with the complete fitting kit.';
    final cases = {
      'description only': variant('c1', {'description': 'Compact cabinet.'}),
      'description + specifications': variant('c2', {
        'description': 'Compact cabinet.',
        'specs': {'Capacity': '12 L', 'Body': 'ABS food grade'},
      }),
      'description + specifications + features': variant('c3', {
        'description': 'Compact cabinet.',
        'specs': {'Capacity': '12 L', 'Body': 'ABS food grade'},
        'features': ['Transparent tank window', 'Smart tap'],
      }),
      'long description + many features': variant('c4', {
        'description': longDescription,
        'specs': {
          'Capacity': '12 L storage, 15 L/hour purification',
          'Purification': 'RO + UV + UF + Mineral',
          'Power': '24 V DC adapter, 36 W',
          'Dimensions': '380 x 270 x 480 mm',
          'details': 'Wall-mount kit included.',
        },
        'features': [
          for (var i = 1; i <= 8; i++)
            'Feature number $i with enough words to wrap onto a second line on the card',
        ],
      }),
    };
    final heights = <String, int>{};
    for (final entry in cases.entries) {
      test(entry.key, () async {
        WidgetsFlutterBinding.ensureInitialized();
        final p = entry.value;
        // Image: photo, category, name, SKU, MRP only.
        expect(shareCardText(p), [
          'CABINET',
          'Aqua 2090 raga series cabinets',
          'SKU: CAB-18',
          'MRP',
          '${rupee}13,800',
        ]);
        // Text: every admin detail, in full; empty sections left out.
        final text = whatsAppShareText(p);
        expect(text, contains('DESCRIPTION:\n${p.description}'));
        expect(text.contains('SPECIFICATIONS:'), p.specifications.isNotEmpty);
        expect(text.contains('KEY FEATURES:'), p.features.isNotEmpty);
        for (final f in p.features) {
          expect(text, contains('- $f'), reason: 'every feature');
        }
        for (final e in p.specifications.entries) {
          expect(text, contains(e.value), reason: 'every specification');
          if (e.key != 'details') {
            expect(text, contains('${e.key}: ${e.value}'));
          }
        }
        expect(text, isNot(contains('5,300')), reason: 'MRP only');
        final photo = File('assets/images/purifier.jpg').readAsBytesSync();
        final bytes = await renderProductShareCard(p, photo);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1440);
        heights[entry.key] = frame.image.height;
        frame.image.dispose();
        codec.dispose();
        final dir = Platform.environment['PREVIEW_DIR'];
        if (dir != null) {
          File('$dir/share_${p.id}.png').writeAsBytesSync(bytes);
          File('$dir/share_${p.id}.txt').writeAsStringSync(text);
        }
      });
    }
    test('the image stays the same size whatever the details (photo stays '
        'large)', () {
      expect(heights.values.toSet(), hasLength(1));
      // ~1440 x 1800: never the old tall catalogue image.
      expect(heights.values.first, lessThan(1950));
    });
  });

  testWidgets(
    'one click on Share: ONE share with the image and every detail, no '
    'sheet, no second step',
    (tester) async {
      final shared = <(ShareImageFile, String)>[];
      final clipboard = captureClipboard(tester);
      final sharer = fakeSharer(canAttach: true, shared: shared);
      // Built when the Product Details page opens.
      await ProductShareCards.prepare(product, sharer);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => shareProductInOneClick(
                  context,
                  product: product,
                  sharer: sharer,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();
      final (file, text) = shared.single;
      expect(file.mimeType, 'image/png');
      expect(file.bytes, cardBytesFor(product));
      expect(text, whatsAppShareText(product));
      for (final part in [
        'Product Name: Public Filter',
        'DESCRIPTION:',
        'Material: Carbon block',
        'Fit: Universal',
        '- Improves taste',
        '- Easy replacement',
        'Contact us for orders and enquiries.',
      ]) {
        expect(text, contains(part));
      }
      expect(text, isNot(contains('Product Link')));
      expect(text, isNot(contains('http')));
      expect(find.byType(BottomSheet), findsNothing, reason: 'no sheet');
      expect(find.byType(AlertDialog), findsNothing, reason: 'no modal');
      expect(clipboard, isEmpty, reason: 'WhatsApp gets the caption');
    },
  );

  testWidgets('one click before the card is ready opens the sheet, whose '
      'WhatsApp action is the same single share', (tester) async {
    final shared = <(ShareImageFile, String)>[];
    final sharer = fakeSharer(canAttach: true, shared: shared);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareProductInOneClick(
                context,
                product: product,
                sharer: sharer,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-whatsapp')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
    await tester.pumpAndSettle();
    expect(shared.single.$2, whatsAppShareText(product));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'WhatsApp Desktop: still one share; details copied and a short note '
    '(no modal) in case WhatsApp drops the caption',
    (tester) async {
      final shared = <(ShareImageFile, String)>[];
      final clipboard = captureClipboard(tester);
      await openSheet(
        tester,
        fakeSharer(canAttach: true, shared: shared, textReachesWhatsApp: false),
      );
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shared.single.$2, whatsAppShareText(product));
      expect(clipboard, [whatsAppShareText(product)]);
      expect(find.textContaining('Ctrl+V'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a cancelled share shows nothing else', (tester) async {
    final shared = <(ShareImageFile, String)>[];
    await openSheet(
      tester,
      fakeSharer(canAttach: true, shared: shared, outcome: 'dismissed'),
    );
    await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
