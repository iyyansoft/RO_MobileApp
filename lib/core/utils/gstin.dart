bool isValidGstin(String value) {
  final gst = value.trim().toUpperCase();
  if (!RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gst)) {
    return false;
  }
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var sum = 0, factor = 2;
  for (var index = 13; index >= 0; index--) {
    final product = alphabet.indexOf(gst[index]) * factor;
    sum += product ~/ 36 + product % 36;
    factor = factor == 2 ? 1 : 2;
  }
  return gst[14] == alphabet[(36 - sum % 36) % 36];
}
