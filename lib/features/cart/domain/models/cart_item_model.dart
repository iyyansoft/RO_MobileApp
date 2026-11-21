import '../../../products/domain/models/product_model.dart';

/// How a cart line is bought (server rule: bulk_orders.js).
enum PurchaseMode {
  /// Dealer Price; normal MOQ / maximum / stock rules.
  normal,

  /// Bulk price per piece; minimum + whole steps (see [ProductModel.bulkPrice]).
  bulk;

  String get api => name;

  static PurchaseMode fromApi(Object? value) =>
      '$value'.trim().toLowerCase() == 'bulk'
      ? PurchaseMode.bulk
      : PurchaseMode.normal;
}

class CartItemModel {
  final ProductModel product;
  final int quantity;
  final PurchaseMode mode;

  const CartItemModel({
    required this.product,
    required this.quantity,
    this.mode = PurchaseMode.normal,
  });

  CartItemModel copyWith({
    ProductModel? product,
    int? quantity,
    PurchaseMode? mode,
  }) {
    return CartItemModel(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      mode: mode ?? this.mode,
    );
  }

  bool get isBulk => mode == PurchaseMode.bulk;

  /// Price per piece for this line: the bulk price for bulk lines, the
  /// Dealer Price otherwise (never one in place of the other).
  double get unitPrice =>
      isBulk && product.hasBulkOffer ? product.bulkPrice! : product.dealerPrice;

  double get totalPrice => unitPrice * quantity;
}
