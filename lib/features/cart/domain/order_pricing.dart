/// Order pricing shared by the cart and checkout.
///
/// Mirrors the backend exactly (pricing_rules.js): money is computed in whole
/// paise and each component is rounded once, so the app shows the same
/// amounts the server charges and saves with the order.
///
///   Grand Total = Subtotal − Dealer Discount + GST + Delivery/Freight
///
/// * Subtotal: Σ unit price × quantity.
/// * Dealer discount: [PricingRules.dealerDiscountPercent] of the subtotal.
/// * GST: only for "With GST" checkout, [PricingRules.gstPercent] of
///   (subtotal − discount). Never added in the cart.
/// * Delivery: [PricingRules.deliveryCharge], free when the subtotal is above
///   [PricingRules.freeDeliveryAbove].
library;

import 'package:flutter/foundation.dart';

/// Pricing rules configured on the server (GET /api/pricing-rules).
@immutable
class PricingRules {
  const PricingRules({
    required this.dealerDiscountPercent,
    required this.dealerTierLabel,
    required this.gstPercent,
    required this.deliveryCharge,
    required this.freeDeliveryAbove,
  });

  /// The server's default rules. Used only until the server's configured
  /// rules have loaded (or if an older server has no rules endpoint); orders
  /// are always re-priced by the server.
  static const fallback = PricingRules(
    dealerDiscountPercent: 10,
    dealerTierLabel: 'Gold Dealer',
    gstPercent: 18,
    deliveryCharge: 250,
    freeDeliveryAbove: 5000,
  );

  final double dealerDiscountPercent;
  final String dealerTierLabel;
  final double gstPercent;
  final double deliveryCharge;
  final double freeDeliveryAbove;

  factory PricingRules.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback, {double max = double.infinity}) {
      final value = num.tryParse('${json[key]}')?.toDouble();
      return value == null || value.isNaN || value < 0 || value > max
          ? fallback
          : value;
    }

    final label = '${json['dealerTierLabel'] ?? ''}'.trim();
    return PricingRules(
      dealerDiscountPercent: read(
        'dealerDiscountPercent',
        fallback.dealerDiscountPercent,
        max: 100,
      ),
      dealerTierLabel: label.isEmpty ? fallback.dealerTierLabel : label,
      gstPercent: read('gstPercent', fallback.gstPercent, max: 100),
      deliveryCharge: read('deliveryCharge', fallback.deliveryCharge),
      freeDeliveryAbove: read('freeDeliveryAbove', fallback.freeDeliveryAbove),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PricingRules &&
      other.dealerDiscountPercent == dealerDiscountPercent &&
      other.dealerTierLabel == dealerTierLabel &&
      other.gstPercent == gstPercent &&
      other.deliveryCharge == deliveryCharge &&
      other.freeDeliveryAbove == freeDeliveryAbove;

  @override
  int get hashCode => Object.hash(
    dealerDiscountPercent,
    dealerTierLabel,
    gstPercent,
    deliveryCharge,
    freeDeliveryAbove,
  );
}

/// One priced line: unit price (rupees) × quantity.
typedef PricedLine = ({double unitPrice, int quantity});

/// A fully priced order. All amounts are in rupees, exact to the paisa.
@immutable
class OrderTotals {
  const OrderTotals._({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.gstPaise,
    required this.deliveryPaise,
    required this.itemCount,
    required this.withGst,
    required this.rules,
  });

  static int _paise(double rupees) => (rupees * 100).round();

  /// Prices [lines] with [rules]. Lines with an invalid price or a quantity
  /// below 1 are ignored (they can't be ordered).
  factory OrderTotals.compute(
    Iterable<PricedLine> lines, {
    required PricingRules rules,
    bool withGst = false,
    // Bulk Orders lines: in the subtotal, but no dealer discount (same rule
    // as the server, pricing_rules.js).
    Iterable<PricedLine> undiscountedLines = const [],
  }) {
    var subtotal = 0;
    var discountable = 0;
    var count = 0;
    for (final (line, discounted) in [
      for (final l in lines) (l, true),
      for (final l in undiscountedLines) (l, false),
    ]) {
      // Skip lines that can't be ordered (invalid price or quantity).
      if (!line.unitPrice.isFinite || line.quantity < 1) continue;
      final unit = _paise(line.unitPrice);
      if (unit <= 0) continue;
      subtotal += unit * line.quantity;
      if (discounted) discountable += unit * line.quantity;
      count += line.quantity;
    }
    final discount = (discountable * rules.dealerDiscountPercent / 100).round();
    final taxable = subtotal - discount;
    final gst = withGst ? (taxable * rules.gstPercent / 100).round() : 0;
    final delivery = subtotal == 0 || subtotal > _paise(rules.freeDeliveryAbove)
        ? 0
        : _paise(rules.deliveryCharge);
    return OrderTotals._(
      subtotalPaise: subtotal,
      discountPaise: discount,
      gstPaise: gst,
      deliveryPaise: delivery,
      itemCount: count,
      withGst: withGst,
      rules: rules,
    );
  }

  final int subtotalPaise;
  final int discountPaise;
  final int gstPaise;
  final int deliveryPaise;

  /// Total pieces across all lines.
  final int itemCount;
  final bool withGst;
  final PricingRules rules;

  bool get isEmpty => subtotalPaise == 0;
  int get grandTotalPaise =>
      subtotalPaise - discountPaise + gstPaise + deliveryPaise;

  double get subtotal => subtotalPaise / 100;
  double get discount => discountPaise / 100;
  double get taxableAmount => (subtotalPaise - discountPaise) / 100;
  double get gst => gstPaise / 100;
  double get deliveryFee => deliveryPaise / 100;
  double get grandTotal => grandTotalPaise / 100;
  bool get freeDelivery => !isEmpty && deliveryPaise == 0;
}

/// "Gold Dealer Discount (10%)"; with Bulk Orders lines in the cart it adds
/// that they are not discounted.
String discountLabel(PricingRules rules, {bool hasBulk = false}) =>
    '${rules.dealerTierLabel} Discount (${formatPercent(rules.dealerDiscountPercent)}%)'
    '${hasBulk ? ' · not on Bulk Orders' : ''}';

/// 10 → "10", 12.5 → "12.5".
String formatPercent(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// Rupee formatting with Indian digit grouping: 125000.5 → "₹1,25,000.50".
String formatInr(double rupees, {bool decimals = true}) {
  final paise = (rupees * 100).round();
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = (decimals ? abs ~/ 100 : (abs / 100).round()).toString();
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  final fraction = decimals ? '.${(abs % 100).toString().padLeft(2, '0')}' : '';
  return '${negative ? '-' : ''}₹$grouped$fraction';
}
