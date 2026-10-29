import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_catalog_route.dart';

void main() {
  group('mapSupabaseAdminCatalogRequest', () {
    test('maps product list/create/update and deactivation calls', () {
      expect(
        mapSupabaseAdminCatalogRequest('products', method: 'GET')?.toJson(),
        {'action': 'list_products'},
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'products',
          method: 'POST',
          data: {'name': 'Membrane'},
        )?.toJson(),
        {
          'action': 'create_product',
          'values': {'name': 'Membrane'},
        },
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'products/prod_1',
          method: 'PUT',
          data: {'stock': 4},
        )?.toJson(),
        {
          'action': 'update_product',
          'targetId': 'prod_1',
          'values': {'stock': 4},
        },
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'products/SKU%2F1',
          method: 'DELETE',
        )?.targetId,
        'SKU/1',
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'products/SKU%2F1',
          method: 'DELETE',
        )?.action,
        'deactivate_product',
      );
    });

    test('maps category CRUD calls', () {
      expect(
        mapSupabaseAdminCatalogRequest('categories', method: 'GET')?.action,
        'list_categories',
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'categories',
          method: 'POST',
          data: {'title': 'RO Systems'},
        )?.action,
        'create_category',
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'categories/CAT_1',
          method: 'PUT',
          data: {'title': 'RO Systems'},
        )?.targetId,
        'CAT_1',
      );
      expect(
        mapSupabaseAdminCatalogRequest(
          'categories/CAT_1',
          method: 'DELETE',
        )?.action,
        'delete_category',
      );
    });

    test(
      'keeps bulk import on Express unless its separate flag is enabled',
      () {
        expect(
          mapSupabaseAdminCatalogRequest(
            'products/bulk',
            method: 'POST',
            data: {'products': []},
          ),
          isNull,
        );
        final bulk = mapSupabaseAdminCatalogRequest(
          'products/bulk',
          method: 'POST',
          data: {
            'products': [
              {'sku': 'SKU-1'},
            ],
          },
          allowCatalog: false,
          allowBulkImport: true,
        );
        expect(bulk?.action, 'bulk_import_products');
        expect(bulk?.values?['products'], hasLength(1));
        expect(
          mapSupabaseAdminCatalogRequest(
            'products',
            method: 'GET',
            allowCatalog: false,
            allowBulkImport: true,
          ),
          isNull,
        );
        expect(mapSupabaseAdminCatalogRequest('orders', method: 'GET'), isNull);
        expect(
          mapSupabaseAdminCatalogRequest('products', method: 'PATCH'),
          isNull,
        );
      },
    );
  });
}
