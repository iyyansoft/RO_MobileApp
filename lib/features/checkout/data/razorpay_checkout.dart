import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayCheckout {
  static const _storage = FlutterSecureStorage();
  final Map<String, Map<String, dynamic>> _pending = {};
  Future<Map<String, dynamic>?> pending(String email) async {
    if (_pending.containsKey(email)) return _pending[email];
    final saved = await _storage.read(key: 'pending_payment_$email');
    return saved == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(saved) as Map);
  }

  Future<void> remember(String email, Map<String, dynamic> payload) async {
    _pending[email] = Map<String, dynamic>.from(payload);
    try {
      await _storage.write(
        key: 'pending_payment_$email',
        value: jsonEncode(payload),
      );
    } catch (_) {
      /* Continue confirming the actual payment with the server. */
    }
  }

  Future<void> clearPending(String email) async {
    _pending.remove(email);
    try {
      await _storage.delete(key: 'pending_payment_$email');
    } catch (_) {}
  }

  /// Returns the same durable checkout key while the cart/checkout payload is
  /// unchanged, so an HTTP timeout retry cannot create a second COD order.
  Future<String> checkoutRequestId(
    String email,
    Map<String, dynamic> payload,
  ) async {
    final storageKey = 'checkout_request_$email';
    final fingerprint = jsonEncode({
      'items': (payload['items'] as List?)
          ?.map((item) => [item['id'], item['quantity']])
          .toList(),
      'paymentMethod': payload['paymentMethod'],
      'grandTotal': payload['grandTotal'],
      'withGst': payload['withGst'],
      'gstin': payload['gstin'],
      'companyName': payload['companyName'],
      'deliveryAddress': payload['deliveryAddress'],
    });
    final saved = await _storage.read(key: storageKey);
    if (saved != null) {
      try {
        final value = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        if (value['fingerprint'] == fingerprint &&
            value['requestId'] is String) {
          return value['requestId'] as String;
        }
      } catch (_) {
        // Replace a malformed local retry marker with a new random key.
      }
    }
    final random = Random.secure();
    final hex = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final requestId =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(
      key: storageKey,
      value: jsonEncode({'fingerprint': fingerprint, 'requestId': requestId}),
    );
    return requestId;
  }

  Future<void> clearCheckoutRequestId(String email) async {
    try {
      await _storage.delete(key: 'checkout_request_$email');
    } catch (_) {}
  }

  Future<Map<String, String>> pay(
    Map<String, dynamic> order, {
    required String email,
    required String name,
  }) async {
    if (kIsWeb) {
      throw StateError(
        'Razorpay checkout is available in the Android/iOS app.',
      );
    }
    final gateway = Razorpay();
    final completed = Completer<Map<String, String>>();
    gateway.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
      PaymentSuccessResponse response,
    ) {
      if (completed.isCompleted) return;
      if (response.orderId != order['id'] ||
          response.paymentId == null ||
          response.signature == null) {
        completed.completeError(
          StateError('Payment confirmation was incomplete.'),
        );
        return;
      }
      completed.complete({
        'razorpay_order_id': response.orderId!,
        'razorpay_payment_id': response.paymentId!,
        'razorpay_signature': response.signature!,
      });
    });
    gateway.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      if (!completed.isCompleted) {
        completed.completeError(
          StateError(response.message ?? 'Payment was cancelled or failed.'),
        );
      }
    });
    try {
      gateway.open({
        'key': order['key'],
        'order_id': order['id'],
        'amount': order['amount'],
        'currency': 'INR',
        'name': 'RO Wholesale',
        'description': 'Product order',
        'prefill': {'email': email, 'name': name},
      });
      return await completed.future.timeout(const Duration(minutes: 10));
    } finally {
      gateway.clear();
    }
  }
}

final razorpayCheckoutProvider = Provider<RazorpayCheckout>(
  (ref) => RazorpayCheckout(),
);
