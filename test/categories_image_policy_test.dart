import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/categories_image_policy.dart';

void main() {
  const supabase =
      'https://abc123.supabase.co/storage/v1/object/public/ro-product-images';

  test('1. valid Supabase Storage public URLs are shown', () {
    for (final url in [
      '$supabase/booster-pumps/Max%20flow%20pump%201%20year%20warranty%20100%20gpd.jpg',
      '$supabase/pdf-catalog/DOM-02.jpg',
      '$supabase/membrane/membrane.jpg',
      '  $supabase/cabinets/Aqua%20roma%20grey.jpg  ',
    ]) {
      expect(isSupabaseStorageImage(url), isTrue, reason: url);
      expect(categoriesPageUsesPlaceholder(url), isFalse, reason: url);
    }
  });

  test('2. backend /api/product-images/ URLs are hidden', () {
    for (final url in [
      '/api/product-images/img_1795000000000_11bd3814a519b303.jpg',
      'https://ro-mobileapp.onrender.com/api/product-images/img_1_ab.jpg',
      'http://localhost:8080/api/product-images/img_1_ab.jpg',
    ]) {
      expect(categoriesPageUsesPlaceholder(url), isTrue, reason: url);
    }
  });

  test('3. backend static file names are hidden', () {
    for (final url in [
      'purifier.jpg',
      'cat_pump.jpg',
      'cat_filter.jpg',
      'cat_spares.jpg',
      'membrane.jpg',
      'https://ro-mobileapp.onrender.com/purifier.jpg',
    ]) {
      expect(categoriesPageUsesPlaceholder(url), isTrue, reason: url);
    }
  });

  test('4. /uploads/ URLs are hidden', () {
    for (final url in [
      '/uploads/prod_1_2.jpg',
      'uploads/prod_1_2.jpg',
      'https://ro-mobileapp.onrender.com/uploads/prod_1_2.jpg',
    ]) {
      expect(categoriesPageUsesPlaceholder(url), isTrue, reason: url);
    }
  });

  test('5. empty, invalid and non-Supabase URLs are hidden', () {
    for (final url in [
      '',
      '   ',
      'not a url',
      'https://',
      'catalog-sprite://4',
      'data:image/png;base64,AAAA',
      'http://abc123.supabase.co/storage/v1/object/public/ro-product-images/a.jpg', // not https
      'https://abc123.supabase.co/rest/v1/products', // not Storage
      'https://abc123.supabase.co/storage/v1/object/sign/ro-product-images/a.jpg', // signed, not public
      'https://abc123.supabase.co/storage/v1/object/public/ro-product-images', // no file
      'https://abc123.supabase.co/storage/v1/object/public/ro-product-images/', // no file
      'https://evil.example.com/storage/v1/object/public/ro-product-images/a.jpg',
      'https://supabase.co.evil.com/storage/v1/object/public/ro-product-images/a.jpg',
      'https://abc.https://abc123.supabase.co/storage/v1/object/public/ro-product-images/a.jpg', // joined
      '$supabase/cabinets/Aqua roma grey.jpg', // raw space
      'https://cdn.example.com/a.jpg',
    ]) {
      expect(categoriesPageUsesPlaceholder(url), isTrue, reason: url);
    }
  });

  test('6. same rule on every platform: no platform condition in the policy or the page', () {
    final policy = File('lib/features/products/domain/categories_image_policy.dart').readAsStringSync();
    final page = File('lib/features/products/presentation/screens/categories_screen.dart').readAsStringSync();
    for (final source in [policy, page]) {
      expect(source.contains('kIsWeb'), isFalse);
      expect(source.contains('defaultTargetPlatform'), isFalse);
      expect(source.contains('Platform.is'), isFalse);
    }
    // The function takes only the image value: identical answer everywhere.
    expect(categoriesPageUsesPlaceholder('/api/product-images/x.jpg'), isTrue);
    expect(categoriesPageUsesPlaceholder('$supabase/booster-pumps/a.jpg'), isFalse);
    // The Categories product card uses the policy on the saved image.
    expect(page.contains('categoriesPageUsesPlaceholder(product.imageUrl)'), isTrue);
  });
}
