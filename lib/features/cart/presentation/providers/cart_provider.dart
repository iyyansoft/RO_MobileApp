import '../../../products/presentation/providers/product_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/models/product_model.dart';
import '../../domain/models/cart_item_model.dart';

class CartState {
  final List<CartItemModel> items;
  final bool isLoading;
  final String? errorMessage;

  const CartState({
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  CartState copyWith({
    List<CartItemModel>? items,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  double get subtotal {
    return _money(items.fold(0.0, (sum, item) => sum + item.totalPrice));
  }

  static double _money(double value) => (value * 100).round() / 100;

  double get dealerDiscount {
    // 10% Gold Dealer Wholesale Discount
    return _money(subtotal * 0.10);
  }

  double get taxableAmount {
    return _money(subtotal - dealerDiscount);
  }

  double get gstAmount {
    // 18% B2B GST tax rate
    return _money(taxableAmount * 0.18);
  }

  double get deliveryFee {
    if (subtotal == 0 || subtotal > 5000) return 0.0;
    return 250.0;
  }

  double get grandTotal {
    if (items.isEmpty) return 0.0;
    return _money(taxableAmount + gstAmount + deliveryFee);
  }

  int get totalItemCount {
    return items.fold(0, (count, item) => count + item.quantity);
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final ApiClient api;
  final String userId;
  final List<ProductModel> Function() catalog;
  CartNotifier(this.api, this.userId, {List<ProductModel> Function()? catalog})
    : catalog = catalog ?? (() => []),
      super(const CartState()) {
    refreshCart();
  }

  void _set(CartState next) {
    if (mounted) state = next;
  }

  Future<void> _sync(
    String path, {
    String method = 'post',
    Map<String, dynamic>? data,
  }) async {
    if (!mounted || state.isLoading) {
      throw StateError('Wait for the cart update to finish.');
    }
    if (userId.isEmpty) {
      throw StateError('Sign in before adding products to your cart.');
    }
    data = {...?data, 'userId': userId};
    _set(state.copyWith(isLoading: true));
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        const repository = SupabaseDealerDataRepository();
        switch (path) {
          case 'cart/add':
            await repository.addCartItem(
              userId,
              '${data['productId']}',
              int.tryParse('${data['quantity']}') ?? 0,
            );
          case 'cart/update':
            await repository.updateCartQuantity(
              userId,
              '${data['productId']}',
              int.tryParse('${data['quantity']}') ?? 0,
            );
          case 'cart/remove':
            await repository.removeCartItem(userId, '${data['productId']}');
          default:
            throw StateError('Unsupported cart operation.');
        }
        if (!mounted) return;
        await refreshCart();
        return;
      }
      final response = method == 'put'
          ? await api.put(path, data: data)
          : method == 'delete'
          ? await api.delete(path, data: data)
          : await api.post(path, data: data);
      if (!mounted) return;
      final body = response.data as Map;
      if (body['success'] != true) {
        throw StateError('${body['error'] ?? 'Cart update failed'}');
      }
      await refreshCart();
    } catch (e) {
      if (mounted) _set(state.copyWith(isLoading: false, errorMessage: '$e'));
      rethrow;
    } finally {
      if (mounted) {
        _set(
          state.copyWith(isLoading: false, errorMessage: state.errorMessage),
        );
      }
    }
  }

  Future<void> addToCart(ProductModel product, {int? quantity}) async {
    final qty = quantity ?? 1;
    if (qty < 1) {
      throw StateError('Quantity must be at least 1.');
    }
    if (product.stockStatus == StockStatus.outOfStock) {
      throw StateError('This product is out of stock.');
    }
    await _sync('cart/add', data: {'productId': product.id, 'quantity': qty});
  }

  bool updateQuantity(String productId, int newQuantity) {
    if (!mounted || state.isLoading) return false;
    final items = state.items.where((i) => i.product.id == productId);
    if (items.isEmpty || newQuantity < 0) return false;
    if (newQuantity == 0) {
      removeItem(productId);
      return true;
    }
    _sync(
      'cart/update',
      method: 'put',
      data: {'productId': productId, 'quantity': newQuantity},
    ).catchError((Object _) {});
    return true;
  }

  void removeItem(String productId) {
    if (!mounted || state.isLoading) return;
    _sync(
      'cart/remove',
      method: 'delete',
      data: {'productId': productId},
    ).catchError((Object _) {});
  }

  Future<void> clearCart() async {
    if (!mounted || state.isLoading) {
      throw StateError('Wait for the cart update to finish.');
    }
    _set(state.copyWith(isLoading: true));
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        await const SupabaseDealerDataRepository().clearCart(userId);
      } else {
        await api.delete('cart/clear', data: {'userId': userId});
      }
      if (mounted) _set(const CartState());
    } finally {
      if (mounted) _set(state.copyWith(isLoading: false));
    }
  }

  Future<void> refreshCart() async {
    if (!mounted) return;
    _set(state.copyWith(isLoading: true));
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        final items = await const SupabaseDealerDataRepository().loadCart(
          userId,
          cachedProducts: catalog(),
        );
        if (mounted) _set(CartState(items: items));
        return;
      }
      final response = await api.get(
        'cart',
        queryParameters: {'userId': userId},
      );
      if (!mounted) return;
      final products = catalog();
      final items = ((response.data as Map)['items'] as List).map((e) {
        final json = Map<String, dynamic>.from(e as Map);
        final fallback = ProductModel.fromJson(json);
        final matches = products.where((p) => p.id == fallback.id);
        return CartItemModel(
          product: matches.isEmpty ? fallback : matches.first,
          quantity: int.tryParse('${json['quantity']}') ?? 1,
        );
      }).toList();
      _set(CartState(items: items));
    } catch (e) {
      if (mounted) _set(state.copyWith(isLoading: false, errorMessage: '$e'));
    }
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(
    ref.watch(apiClientProvider),
    ref.watch(authProvider.select((auth) => auth.currentUser?.id ?? '')),
    catalog: () => ref.read(allProductsProvider),
  ),
);
