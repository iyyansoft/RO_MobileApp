import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../products/domain/models/product_model.dart';
import '../../domain/models/cart_item_model.dart';

class CartState {
  final List<CartItemModel> items;
  final bool isLoading;

  const CartState({
    this.items = const [],
    this.isLoading = false,
  });

  CartState copyWith({
    List<CartItemModel>? items,
    bool? isLoading,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  double get subtotal {
    return items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double get dealerDiscount {
    // 10% Gold Dealer Wholesale Discount
    return subtotal * 0.10;
  }

  double get taxableAmount {
    return subtotal - dealerDiscount;
  }

  double get gstAmount {
    // 18% B2B GST tax rate
    return taxableAmount * 0.18;
  }

  double get deliveryFee {
    if (subtotal == 0 || subtotal >= 10000) return 0.0;
    return 250.0;
  }

  double get grandTotal {
    if (items.isEmpty) return 0.0;
    return taxableAmount + gstAmount + deliveryFee;
  }

  int get totalItemCount {
    return items.fold(0, (count, item) => count + item.quantity);
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier()
      : super(
          CartState(
            items: [
              CartItemModel(
                product: ProductModel.sampleProducts[0], // Vontron 75 GPD
                quantity: 10,
              ),
              CartItemModel(
                product: ProductModel.sampleProducts[1], // E-Chen Pump 100 GPD
                quantity: 5,
              ),
            ],
          ),
        );

  void addToCart(ProductModel product, {int? quantity}) {
    final qtyToAdd = quantity ?? product.moq;
    final index = state.items.indexWhere((item) => item.product.id == product.id);

    if (index >= 0) {
      final updatedItems = List<CartItemModel>.from(state.items);
      final currentItem = updatedItems[index];
      updatedItems[index] = currentItem.copyWith(quantity: currentItem.quantity + qtyToAdd);
      state = state.copyWith(items: updatedItems);
    } else {
      state = state.copyWith(
        items: [
          ...state.items,
          CartItemModel(product: product, quantity: qtyToAdd),
        ],
      );
    }
  }

  bool updateQuantity(String productId, int newQuantity) {
    final index = state.items.indexWhere((item) => item.product.id == productId);
    if (index < 0) return false;

    final item = state.items[index];

    // Enforce MOQ check
    if (newQuantity < item.product.moq) {
      return false; // Cannot reduce below MOQ
    }

    final updatedItems = List<CartItemModel>.from(state.items);
    updatedItems[index] = item.copyWith(quantity: newQuantity);
    state = state.copyWith(items: updatedItems);
    return true;
  }

  void removeItem(String productId) {
    state = state.copyWith(
      items: state.items.where((item) => item.product.id != productId).toList(),
    );
  }

  void clearCart() {
    state = state.copyWith(items: []);
  }

  void refreshCart() async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(milliseconds: 500));
    state = state.copyWith(isLoading: false);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
