import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/models/product_model.dart';

Future<bool> addProductToCart(
  BuildContext context,
  WidgetRef ref,
  ProductModel product, {
  int? quantity,
}) async {
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
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return false;
  }
}
