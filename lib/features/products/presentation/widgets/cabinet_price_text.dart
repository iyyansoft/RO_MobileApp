import 'package:flutter/material.dart';

import '../../../../core/utils/rupee_format.dart';
import '../../domain/models/product_model.dart';

/// "Cabinet Price: ₹375" for Cabinet products that have one saved
/// (products.cabinet_price). Shows nothing otherwise — never ₹0, and never
/// Dealer Price or MRP in its place.
class CabinetPriceText extends StatelessWidget {
  final ProductModel product;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const CabinetPriceText(
    this.product, {
    super.key,
    this.fontSize = 12,
    this.padding = EdgeInsets.zero,
  });

  static String? label(ProductModel product) => product.hasCabinetPrice
      ? 'Cabinet Price: ${rupee(product.cabinetPrice!)}'
      : null;

  @override
  Widget build(BuildContext context) {
    final text = label(product);
    if (text == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: padding,
      child: Text(
        text,
        key: const ValueKey('cabinet_price_text'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
