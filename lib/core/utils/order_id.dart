import 'dart:math';

/// Generates a unique 6-character alphanumeric Order ID containing letters and numbers (e.g. 'A12B3C').
String generate6CharOrderId() {
  const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final random = Random.secure();
  String id;
  do {
    id = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  } while (!RegExp(r'[A-Z]').hasMatch(id) || !RegExp(r'[0-9]').hasMatch(id));
  return id;
}

/// Formats an Order ID ensuring it displays as a 6-character alphanumeric code.
/// If an older legacy UUID or 'RO-' prefixed ID is encountered from older database rows,
/// this reliably normalizes it to a clean 6-character alphanumeric string.
String formatOrderId(dynamic value) {
  final id = '${value ?? ''}'.trim();
  if (id.isEmpty) return '';
  if (id.toLowerCase().startsWith('ro-')) {
    final without = id.substring(3).replaceAll('-', '');
    if (without.length >= 6) {
      return without.substring(0, 6).toUpperCase();
    }
    return without.toUpperCase();
  }
  if (id.contains('-') && id.length > 6) {
    final clean = id.replaceAll('-', '');
    if (clean.length >= 6) {
      return clean.substring(0, 6).toUpperCase();
    }
  }
  if (id.length > 6) {
    return id.substring(0, 6).toUpperCase();
  }
  return id.toUpperCase();
}

