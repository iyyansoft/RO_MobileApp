import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

void main() {
  const samples = <({String sku, String category, String image})>[
    (sku: 'RO-FLT-CTO', category: 'filters', image: 'cat_filter.jpg'),
    (sku: 'RO-FLT-INLINE', category: 'filters', image: 'cat_filter.jpg'),
    (sku: 'RO-FLT-SED', category: 'filters', image: 'cat_filter.jpg'),
    (sku: 'ABC', category: 'membranes', image: 'purifier.jpg'),
    (sku: 'RO-MEM-100', category: 'membranes', image: 'membrane.jpg'),
    (sku: 'RO-MEM-4040', category: 'membranes', image: 'membrane.jpg'),
    (sku: 'RO-MEM-75', category: 'membranes', image: 'membrane.jpg'),
    (sku: 'RO-PIPE-14', category: 'pipes', image: 'cat_spares.jpg'),
    (sku: 'RO-PIPE-38', category: 'pipes', image: 'cat_spares.jpg'),
    (sku: 'RO-PIPE-KIT', category: 'pipes', image: 'cat_spares.jpg'),
    (sku: 'RO-PMP-100', category: 'pumps', image: 'cat_pump.jpg'),
    (sku: 'RO-PMP-300', category: 'pumps', image: 'cat_pump.jpg'),
    (sku: 'RO-PMP-75', category: 'pumps', image: 'cat_pump.jpg'),
    (sku: 'RO-SPR-HOUSING', category: 'spares', image: 'cat_spares.jpg'),
    (sku: 'RO-SPR-SMPS', category: 'spares', image: 'cat_spares.jpg'),
    (sku: 'RO-SPR-SV', category: 'spares', image: 'cat_spares.jpg'),
    (sku: 'RO-SYS-25', category: 'systems', image: 'purifier.jpg'),
    (sku: 'RO-SYS-50', category: 'systems', image: 'purifier.jpg'),
    (sku: 'RO-SYS-10L', category: 'systems', image: 'purifier.jpg'),
  ];

  ProductModel sample(({String sku, String category, String image}) item) =>
      ProductModel(
        id: item.sku,
        name: item.sku,
        sku: item.sku,
        categoryId: item.category,
        categoryName: item.category,
        brand: 'Sample',
        mrp: 100,
        dealerPrice: 80,
        imageUrl: item.image,
        stockStatus: StockStatus.inStock,
        moq: 1,
      );

  test('generic catalog placeholders resolve to unique product artwork', () {
    final displayImages = samples.map(sample).map((p) => p.displayImageUrl);

    expect(displayImages.toSet(), hasLength(samples.length));
    expect(
      displayImages.every((image) => image.startsWith('catalog-sprite://')),
      isTrue,
    );
  });

  test('uploaded product images remain unchanged', () {
    final uploaded = sample((
      sku: 'RO-FLT-CTO',
      category: 'filters',
      image: 'uploads/prod_123.jpg',
    ));

    expect(uploaded.displayImageUrl, 'uploads/prod_123.jpg');
  });
}
