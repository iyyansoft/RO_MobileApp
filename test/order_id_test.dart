import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/utils/order_id.dart';

void main() {
  group('Order ID Generation and Formatting', () {
    test('generate6CharOrderId returns exactly 6 uppercase alphanumeric chars with letters and numbers', () {
      for (var i = 0; i < 50; i++) {
        final id = generate6CharOrderId();
        expect(id.length, 6);
        expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(id), isTrue, reason: '$id must be 6 alphanumeric');
        expect(RegExp(r'[A-Z]').hasMatch(id), isTrue, reason: '$id must contain at least 1 letter');
        expect(RegExp(r'[0-9]').hasMatch(id), isTrue, reason: '$id must contain at least 1 number');
      }
    });

    test('formatOrderId handles 6-char IDs directly', () {
      expect(formatOrderId('A12B3C'), 'A12B3C');
      expect(formatOrderId('7X9K2M'), '7X9K2M');
    });

    test('formatOrderId converts legacy UUIDs and RO- prefixes into 6-character strings', () {
      expect(formatOrderId('RO-e0o4a198-1595-5c92-962b-f5822eaa01b2'), 'E0O4A1');
      expect(formatOrderId('RO-A12B3C'), 'A12B3C');
      expect(formatOrderId('e0o4a198-1595-5c92-962b-f5822eaa01b2'), 'E0O4A1');
    });

    test('formatOrderId handles empty or null safely', () {
      expect(formatOrderId(''), '');
      expect(formatOrderId(null), '');
    });
  });
}

