import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart' show ApiException;

/// Thrown when a cart line would go above the product's maximum order
/// quantity (the PDF quantity for the supplier-PDF catalogue).
class MaxOrderQuantityExceeded implements Exception {
  const MaxOrderQuantityExceeded(this.max);
  final int max;

  @override
  String toString() =>
      'You can order a maximum of $max units for this product.';
}

/// The "Maximum Order Quantity Reached" popup.
Future<void> showMaxQuantityDialog(BuildContext context, int max) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('max-quantity-dialog'),
      title: const Text('Maximum Order Quantity Reached'),
      content: Text('You can order a maximum of $max units for this product.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// The maximum behind [error] when it is a "maximum reached" refusal (from
/// the app or from the server), else null.
int? maxQuantityFromError(Object error) {
  if (error is MaxOrderQuantityExceeded) return error.max;
  if (error is ApiException) {
    final data = error.responseData;
    if (data is Map && data['code'] == 'MAX_ORDER_QTY') {
      return int.tryParse('${data['max']}');
    }
  }
  final match = RegExp(r'You can order a maximum of (\d+) units')
      .firstMatch('$error');
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Shows the popup when [error] is a "maximum reached" refusal.
/// Returns true when it did.
bool showMaxQuantityDialogFor(BuildContext context, Object error) {
  final max = maxQuantityFromError(error);
  if (max == null) return false;
  showMaxQuantityDialog(context, max);
  return true;
}
