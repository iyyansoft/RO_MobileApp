/// Indian Rupee formatting shared by every customer-facing price.
library;

/// 16500 → "16,500"; 125000 → "1,25,000" (Indian grouping, no decimals).
String formatRupees(double value) {
  final digits = value.round().abs().toString();
  final sign = value.round() < 0 ? '-' : '';
  if (digits.length <= 3) return '$sign$digits';
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '$sign${parts.join(',')},$last3';
}

/// 8500 → "₹8,500"; 1499.5 → "₹1,499.50" (paise shown only when present).
String rupee(double value) {
  final paise = (value * 100).round();
  final whole = formatRupees((paise ~/ 100).toDouble());
  final fraction = paise.abs() % 100;
  return fraction == 0
      ? '₹$whole'
      : '₹$whole.${fraction.toString().padLeft(2, '0')}';
}
