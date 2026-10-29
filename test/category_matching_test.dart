import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/category_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/presentation/providers/product_provider.dart';

void main() {
  test(
    'counts and listings match API keys, database IDs and category names',
    () async {
      final categories = [
        CategoryModel.fromJson({
          'id': 'CAT_FLT',
          'key_name': 'filters',
          'title': 'Filters & Cartridges',
        }),
        CategoryModel.fromJson({
          'id': 'CAT_PMP',
          'key_name': 'pumps',
          'title': 'Booster Pumps',
        }),
        CategoryModel.fromJson({
          'id': 'CAT_EMPTY',
          'key_name': '',
          'key': 'empty',
          'title': 'Empty',
        }),
      ];
      final products = [
        ProductModel.fromJson({'id': 'key', 'category': ' FILTERS '}),
        ProductModel.fromJson({'id': 'db-id', 'category_id': 'CAT_FLT'}),
        ProductModel.fromJson({
          'id': 'name',
          'category_name': 'filters & cartridges',
        }),
        ProductModel.fromJson({
          'id': 'category-key',
          'category': '',
          'category_key': 'filters',
        }),
        ProductModel.fromJson({'id': 'other', 'category': 'pumps'}),
        ProductModel.fromJson({'id': 'unassigned'}),
      ];
      final pendingProducts = Completer<List<ProductModel>>();
      final container = ProviderContainer(
        overrides: [
          catalogCategoriesProvider.overrideWith((ref) async => categories),
          catalogProductsProvider.overrideWith((ref) => pendingProducts.future),
        ],
      );
      addTearDown(container.dispose);
      await container.read(catalogCategoriesProvider.future);
      container.read(categoriesProvider);
      pendingProducts.complete(products);
      await container.read(catalogProductsProvider.future);

      final counted = container.read(categoriesProvider);
      expect(counted.map((category) => category.productCount), [4, 1, 0]);
      expect(counted.last.id, 'empty');
      final filters = container.read(productFilterProvider.notifier);
      filters.selectCategory('filters');
      expect(
        container.read(filteredProductsProvider).map((p) => p.id).toSet(),
        {'key', 'db-id', 'name', 'category-key'},
      );
      filters.selectCategory('CAT_FLT');
      expect(
        container.read(filteredProductsProvider).length,
        counted.first.productCount,
      );
      filters.selectCategory('pumps');
      expect(container.read(filteredProductsProvider).map((p) => p.id), [
        'other',
      ]);
      filters.selectCategory('empty');
      expect(container.read(filteredProductsProvider), isEmpty);
      filters.selectCategory(null);
      expect(container.read(filteredProductsProvider).length, products.length);

      // Counts describe the full category even while a listing is searched.
      filters.setSearchQuery('no match');
      expect(container.read(filteredProductsProvider), isEmpty);
      expect(container.read(categoriesProvider).first.productCount, 4);
    },
  );
}
