import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../cart/domain/models/cart_item_model.dart';
import '../../cart/presentation/providers/cart_provider.dart';
import '../../products/domain/models/product_model.dart';
import '../../products/presentation/widgets/cart_actions.dart';

/// Adds [quantity] of [product] as a Bulk Orders line (the server checks the
/// minimum / step and prices it at the bulk price). Shows the compact toast.
Future<bool> addBulkToCart(
  BuildContext context,
  WidgetRef ref,
  ProductModel product,
  int quantity,
) async {
  if (product.stockStatus == StockStatus.outOfStock) {
    AppToast.error(context, '${product.name} is out of stock.');
    return false;
  }
  try {
    await ref
        .read(cartProvider.notifier)
        .addToCart(product, quantity: quantity, mode: PurchaseMode.bulk);
    if (context.mounted) showAddedToCartToast(context);
    return true;
  } catch (error) {
    if (context.mounted) AppToast.error(context, cartErrorText(error));
    return false;
  }
}

/// Bulk Orders list, keeping the category ([categoryId] = its key, e.g.
/// "filters").
String bulkOrdersLocation([String? categoryId]) =>
    categoryId == null || categoryId.isEmpty
    ? '/bulk-orders'
    : '/bulk-orders?category=${Uri.encodeQueryComponent(categoryId)}';

/// Bulk Product Details for [productId], remembering the category.
String bulkProductLocation(String productId, [String? categoryId]) =>
    '/bulk-orders/product/${Uri.encodeComponent(productId)}'
    '${categoryId == null || categoryId.isEmpty ? '' : '?category=${Uri.encodeQueryComponent(categoryId)}'}';
