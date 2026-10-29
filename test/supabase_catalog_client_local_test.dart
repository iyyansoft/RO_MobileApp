import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _fixtureImageUrl =
    'http://127.0.0.1:54331/storage/v1/object/public/'
    'ro-product-images/local-test/catalog-image.png';

void main() {
  test(
    'Flutter catalog providers use local Supabase Auth, RLS, and images',
    () async {
      final localUri = Uri.parse(_url);
      expect(localUri.scheme, 'http');
      expect(localUri.host, '127.0.0.1');
      expect(localUri.port, 54331);
      expect(_publishableKey, isNotEmpty);

      final client = SupabaseClient(
        _url,
        _publishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          supabaseCatalogClientProvider.overrideWith((ref) => client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async => client.dispose());

      final anonymousProducts = await container.read(
        catalogProductsProvider.future,
      );
      final anonymousCategories = await container.read(
        catalogCategoriesProvider.future,
      );

      expect(anonymousProducts.map((product) => product.id), [
        'local-product-active',
        'local-product-draft',
      ]);
      final active = anonymousProducts.singleWhere(
        (product) => product.id == 'local-product-active',
      );
      expect(active.name, 'Local Active Product');
      expect(active.categoryId, 'filters');
      expect(active.categoryName, 'Local Test Filters');
      expect(active.dealerPrice, 10);
      expect(active.mrp, 12);
      expect(
        active.purchasePrice,
        isNull,
        reason: 'catalog view must never provide purchase cost',
      );
      expect(active.imageUrl, _fixtureImageUrl);
      expect(active.displayImageUrl, _fixtureImageUrl);
      expect(anonymousCategories.map((category) => category.id), [
        'filters',
        'membranes',
      ]);
      expect(anonymousCategories.first.imagePath, _fixtureImageUrl);
      expect(
        anonymousCategories
            .map(
              (category) => anonymousProducts
                  .where(category.matchesProduct)
                  .map((product) => product.id)
                  .toList(),
            )
            .toList(),
        [
          ['local-product-active'],
          ['local-product-draft'],
        ],
        reason: 'catalog category ID/name mapping matches product data',
      );

      final imageBytes = await client.storage
          .from('ro-product-images')
          .download('local-test/catalog-image.png');
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1);
      expect(frame.image.height, 1);
      frame.image.dispose();
      codec.dispose();

      await expectLater(
        client.from('products').select('purchase_price').limit(1),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        client
            .from('products')
            .update({'price': 0.01})
            .eq('id', 'local-product-active'),
        throwsA(isA<PostgrestException>()),
      );

      final nonce = DateTime.now().microsecondsSinceEpoch;
      final signUp = await client.auth.signUp(
        email: 'flutter-catalog-$nonce@example.test',
        password: 'Local-catalog-$nonce-Aa1!',
      );
      expect(signUp.user, isNotNull);
      expect(
        signUp.session,
        isNotNull,
        reason: 'isolated local Auth has email confirmation disabled',
      );

      container.invalidate(catalogProductsProvider);
      container.invalidate(catalogCategoriesProvider);
      final dealerProducts = await container.read(
        catalogProductsProvider.future,
      );
      final dealerCategories = await container.read(
        catalogCategoriesProvider.future,
      );
      expect(dealerProducts.map((product) => product.id), [
        'local-product-active',
        'local-product-draft',
      ]);
      expect(dealerCategories, hasLength(2));
      await expectLater(
        client.from('products').select('purchase_price').limit(1),
        throwsA(isA<PostgrestException>()),
        reason: 'authenticated dealers must not read purchase price',
      );
      await expectLater(
        client
            .from('products')
            .update({'price': 0.01})
            .eq('id', 'local-product-active'),
        throwsA(isA<PostgrestException>()),
        reason: 'authenticated dealers must not write catalog rows',
      );
      await client.auth.signOut();
    },
  );
}
