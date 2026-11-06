import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Android/iOS: native Razorpay SDK via `razorpay_flutter`.
Future<Map<String, String>> openRazorpayCheckout(
  Map<String, dynamic> options, {
  required String expectedOrderId,
}) async {
  final gateway = Razorpay();
  final completed = Completer<Map<String, String>>();
  gateway.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
    if (completed.isCompleted) return;
    if (response.orderId != expectedOrderId ||
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
    gateway.open(options);
    return await completed.future.timeout(const Duration(minutes: 10));
  } finally {
    gateway.clear();
  }
}
