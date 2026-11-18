import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart' show ApiException;
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/product_model.dart';
import 'max_quantity_dialog.dart';

Future<bool> addProductToCart(
  BuildContext context,
  WidgetRef ref,
  ProductModel product, {
  int? quantity,
}) async {
  // Out of Stock or Below MOQ: say why instead of trying.
  final blocked = product.orderBlockedReason;
  if (blocked != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(blocked)));
    return false;
  }
  try {
    await ref
        .read(cartProvider.notifier)
        .addToCart(product, quantity: quantity);
    if (!context.mounted) {
      return true;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Added ${product.name} to cart')));
    return true;
  } catch (error) {
    if (context.mounted && !showMaxQuantityDialogFor(context, error)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(cartErrorText(error))));
    }
    return false;
  }
}

/// Readable cart error text (drops Dart's "Bad state: " prefix and shows
/// the server's message when there is one).
String cartErrorText(Object error) {
  if (error is StateError) return error.message;
  if (error is ApiException) return error.message;
  return '$error'.replaceFirst(RegExp(r'^(Bad state|Exception): '), '');
}
