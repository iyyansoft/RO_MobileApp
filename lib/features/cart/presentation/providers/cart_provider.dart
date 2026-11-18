import '../../../products/presentation/providers/product_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/models/product_model.dart';
import '../../../products/presentation/widgets/max_quantity_dialog.dart'
    show MaxOrderQuantityExceeded;
import '../../domain/models/cart_item_model.dart';
import '../../domain/order_pricing.dart';

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

  /// Prices this cart with [rules] (see order_pricing.dart). GST is only
  /// included when [withGst] is true, i.e. at checkout.
  OrderTotals totals(PricingRules rules, {bool withGst = false}) =>
      OrderTotals.compute(
        items.map(
          (i) => (unitPrice: i.product.dealerPrice, quantity: i.quantity),
        ),
        rules: rules,
        withGst: withGst,
      );

  // Convenience getters using the default rules. Screens use
  // [cartTotalsProvider], which applies the server's configured rules.
  OrderTotals get _defaultTotals => totals(PricingRules.fallback);

  double get subtotal => _defaultTotals.subtotal;
  double get dealerDiscount => _defaultTotals.discount;
  double get taxableAmount => _defaultTotals.taxableAmount;
  double get gstAmount => totals(PricingRules.fallback, withGst: true).gst;
  double get deliveryFee => _defaultTotals.deliveryFee;

  /// Cart total: no GST is added while shopping.
  double get grandTotal => _defaultTotals.grandTotal;
  double get grandTotalWithGst =>
      totals(PricingRules.fallback, withGst: true).grandTotal;
  double get grandTotalWithoutGst => _defaultTotals.grandTotal;

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
    // Same rule as the server (order_rules.js): a cart line holds 1 up to the
    // product maximum (the PDF quantity for the PDF catalogue) and the stock.
    // The server checks again.
    final qty = quantity ?? 1;
    if (qty < 1) {
      throw StateError('Quantity must be at least 1.');
    }
    final inCart = state.items
        .where((item) => item.product.id == product.id)
        .fold<int>(0, (sum, item) => sum + item.quantity);
    if (product.exceedsMaximum(inCart + qty)) {
      throw MaxOrderQuantityExceeded(product.maxOrderQuantity!);
    }
    final problem = product.quantityProblem(inCart + qty);
    if (problem != null) throw StateError(problem);
    await _sync('cart/add', data: {'productId': product.id, 'quantity': qty});
  }

  bool updateQuantity(String productId, int newQuantity) {
    if (!mounted || state.isLoading) return false;
    final items = state.items.where((i) => i.product.id == productId);
    if (items.isEmpty || newQuantity < 0) return false;
    final product = items.first.product;
    // Going below the MOQ removes the line (it cannot be ordered smaller).
    if (newQuantity == 0 || newQuantity < product.minOrderQty) {
      removeItem(productId);
      return true;
    }
    final max = product.maxOrderQty;
    if (max != null &&
        newQuantity > max &&
        newQuantity > items.first.quantity) {
      return false;
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

/// Pricing rules configured on the server. Falls back to the default rules
/// if the server has no rules endpoint (orders are re-priced server-side).
final pricingRulesProvider = FutureProvider<PricingRules>((ref) async {
  try {
    final response = await ref.watch(apiClientProvider).get('pricing-rules');
    final data = response.data;
    if (data is Map && data['rules'] is Map) {
      return PricingRules.fromJson(
        Map<String, dynamic>.from(data['rules'] as Map),
      );
    }
  } catch (_) {
    // Older backend without the endpoint, or offline.
  }
  return PricingRules.fallback;
});

/// Live cart totals (recomputed whenever the cart or the rules change).
/// The family argument is whether GST is included (checkout "With GST").
final cartTotalsProvider = Provider.family<OrderTotals, bool>((ref, withGst) {
  final cart = ref.watch(cartProvider);
  final rules =
      ref.watch(pricingRulesProvider).valueOrNull ?? PricingRules.fallback;
  return cart.totals(rules, withGst: withGst);
});
