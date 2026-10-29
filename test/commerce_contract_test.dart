import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';
import 'package:ro_wholesale_dealer_app/features/cart/domain/models/cart_item_model.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';

void main() {
  test(
    'catalog and cart response formats preserve price and minimum quantity',
    () {
      final product = ProductModel.fromJson({
        'id': 'filter-1',
        'name': 'Filter',
        'price': '₹1,200',
        'mrp': '1500',
        'moq': 'MOQ: 5 Units',
        'imgSrc': '/uploads/filter.jpg',
      });
      expect(product.dealerPrice, 1200);
      expect(product.moq, 5);
      expect(product.imageUrl, '/uploads/filter.jpg');
      expect(product.discountPercentage, 20);
      final cartProduct = ProductModel.fromJson({
        'product_id': 'filter-1',
        'numericPrice': 1200,
        'moq': 5,
      });
      expect(cartProduct.id, product.id);
      expect(cartProduct.dealerPrice, product.dealerPrice);
    },
  );

  test('wholesale cart totals apply discount, tax and delivery threshold', () {
    final product = ProductModel.fromJson({'id': '1', 'numericPrice': 1000});
    final cart = CartState(
      items: [CartItemModel(product: product, quantity: 5)],
    );
    expect(cart.subtotal, 5000);
    expect(cart.dealerDiscount, 500);
    expect(cart.gstAmount, 810);
    expect(cart.deliveryFee, 250);
    expect(cart.grandTotal, 5560);
    expect(
      CartState(items: [CartItemModel(product: product, quantity: 6)])
          .deliveryFee,
      0,
    );
    expect(const CartState().grandTotal, 0);
  });
}
