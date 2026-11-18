import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_share.dart';

Map<String, dynamic> _row(Object? moq) => {
  'id': 'DOM-01',
  'sku': 'DOM-01',
  'name': 'Cruze gold inline',
  'category_key': 'filters',
  'brand': '',
  'price': 80,
  'mrp': 590,
  'img': '',
  'stock_quantity': 0,
  'moq': moq,
};

void main() {
  test('a blank MOQ is "not set", never shown as 1', () {
    for (final blank in [null, '', '   ']) {
      final product = ProductModel.fromJson(_row(blank));
      expect(product.moqSet, isFalse, reason: 'moq=$blank');
      expect(product.moqLabel(), 'MOQ not set');
      expect(product.moqLabel('pcs'), 'MOQ not set');
      // Cart maths still has a safe minimum of 1.
      expect(product.moq, 1);
    }
  });

  test('a saved MOQ is shown with its saved unit', () {
    final expected = {
      '10 nos': 'MOQ: 10 nos', // exactly as printed in the supplier PDF
      'MOQ: 10 Units': 'MOQ: 10 Units',
      'MOQ: 1 Unit': 'MOQ: 1 Unit',
      '10': 'MOQ: 10 Pcs', // no unit saved
      10: 'MOQ: 10 Pcs',
    };
    expected.forEach((value, label) {
      final product = ProductModel.fromJson(_row(value));
      expect(product.moqSet, isTrue, reason: '$value');
      expect(product.moqLabel(), label, reason: '$value');
    });
    expect(ProductModel.fromJson(_row('25 nos')).moq, 25);
  });

  test('WhatsApp share text says "MOQ not set" for a blank MOQ', () {
    final text = productShareText(ProductModel.fromJson(_row(null)));
    expect(text, contains('MOQ not set'));
    expect(text, isNot(contains('MOQ: 1')));
  });
}
