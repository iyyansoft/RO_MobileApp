import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart' show ApiException;
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/product_model.dart';
import 'max_quantity_dialog.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../app/config/router/app_router.dart';

Future<bool> addProductToCart(
  BuildContext context,
  WidgetRef ref,
  ProductModel product, {
  int? quantity,
}) async {
  // Out of Stock or Below MOQ: say why instead of trying.
  final blocked = product.orderBlockedReason;
  if (blocked != null) {
    AppToast.error(context, blocked);
    return false;
  }
  try {
    await ref
        .read(cartProvider.notifier)
        .addToCart(product, quantity: quantity);
    if (!context.mounted) {
      return true;
    }
    showAddedToCartToast(context);
    return true;
  } catch (error) {
    if (context.mounted && !showMaxQuantityDialogFor(context, error)) {
      AppToast.error(context, cartErrorText(error));
    }
    return false;
  }
}

/// The one "added to cart" confirmation used across the app.
const addedToCartMessage = 'Product added to cart successfully';

void showAddedToCartToast(BuildContext context) => AppToast.success(
  context,
  addedToCartMessage,
  actionLabel: 'View Cart',
  onAction: () => AppRouter.router.push('/cart'),
);

/// Readable cart error text (drops Dart's "Bad state: " prefix and shows
/// the server's message when there is one).
String cartErrorText(Object error) {
  if (error is StateError) return error.message;
  if (error is ApiException) return error.message;
  return '$error'.replaceFirst(RegExp(r'^(Bad state|Exception): '), '');
}
