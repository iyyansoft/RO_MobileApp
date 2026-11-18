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

    final link = productShareUrl(
      product,
      apiBaseUrl: 'https://api.example.com/api/',
    );
    expect(
      link.toString(),
      'https://api.example.com/share/products/filter-share',
    );
    expect(
      productShareText(product, link: link),
      endsWith(
        'View product: https://api.example.com/share/products/filter-share',
      ),
    );
  });

  test('WhatsApp link carries name, MRP, SKU, brand, category, description and page link only', () {
    final uri = whatsAppShareUri(
      product,
      apiBaseUrl: 'https://api.example.com/api/',
    );
    expect(uri.host, 'wa.me');
    final text = uri.queryParameters['text']!;
    expect(text, contains('*Public Filter*'));
    expect(text, contains('MRP: ${rupee}1,200'));
    expect(text, contains('SKU: FILTER-001'));
    expect(text, contains('Brand: Aqua Flow'));
    expect(text, contains('Category: Water Filters'));
    expect(text, contains('A replacement filter for clean drinking water.'));
    expect(
      text,
      endsWith('https://api.example.com/share/products/filter-share'),
    );
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

  test(
    'the card prints name, SKU, category and MRP only (never dealer price)',
    () {
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
    },
  );

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

  test('shared links never use localhost or LAN addresses', () {
    for (final api in [
      'http://localhost:8080/api/',
      'http://127.0.0.1:8081/api/',
      'http://10.0.2.2:8081/api/',
      'http://192.168.1.20:8081/api/',
    ]) {
      expect(
        productShareUrl(product, apiBaseUrl: api).toString(),
        '$kPublicShareOrigin/share/products/filter-share',
      );
    }
    expect(
      productShareUrl(
        product,
        publicBaseUrl: 'https://shop.example.com',
      ).toString(),
      'https://shop.example.com/share/products/filter-share',
    );
  });

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
    List<(ProductModel, List<int>)>? cards,
  }) => ProductSharer(
    buildCard: (p, photo) async {
      cards?.add((p, photo.bytes));
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

  testWidgets('WhatsApp share sends only the product card image (no text)', (
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
    expect(text, isEmpty, reason: 'no caption or long text message');
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
    expect(shared.every((s) => s.$2.isEmpty), isTrue);
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
        find.text('Downloads the product card to attach in WhatsApp'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
      await tester.pumpAndSettle();

      expect(shared, isEmpty);
      expect(downloaded.single.$1, cardBytesFor(product));
      expect(downloaded.single.$2, 'FILTER-001.png');
      expect(
        clipboard,
        isEmpty,
        reason: 'no text to paste: details are in the image',
      );
      expect(find.byKey(const ValueKey('share-manual-attach')), findsOneWidget);
      expect(find.textContaining('FILTER-001.png'), findsOneWidget);
      expect(launched, isEmpty, reason: 'WhatsApp opens only when asked');
      await tester.tap(find.byKey(const ValueKey('share-open-whatsapp')));
      await tester.pumpAndSettle();
      expect(launched.single.host, 'web.whatsapp.com');
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

  testWidgets('if the image cannot be loaded nothing is shared without it', (
    tester,
  ) async {
    final shared = <(ShareImageFile, String)>[];
    final launched = <Uri>[];
    await openSheet(
      tester,
      fakeSharer(
        canAttach: true,
        fetchFails: true,
        shared: shared,
        launched: launched,
      ),
    );
    expect(find.byKey(const ValueKey('share-image-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-whatsapp')));
    await tester.pumpAndSettle();
    expect(shared, isEmpty);
    expect(launched, isEmpty);
  });

  testWidgets('copy link copies the public product page', (tester) async {
    final clipboard = captureClipboard(tester);
    await openSheet(tester, fakeSharer(canAttach: true));
    await tester.tap(find.byKey(const ValueKey('share-copy-link')));
    await tester.pumpAndSettle();
    expect(clipboard.single, '$kPublicShareOrigin/share/products/filter-share');
    expect(find.text('Product link copied'), findsOneWidget);
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
}
