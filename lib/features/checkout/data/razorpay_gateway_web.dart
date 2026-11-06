import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Razorpay's browser checkout (`window.Razorpay`, loaded by
/// https://checkout.razorpay.com/v1/checkout.js in web/index.html).
@JS('Razorpay')
extension type _RazorpayJs._(JSObject _) implements JSObject {
  external factory _RazorpayJs(JSObject options);
  external void open();
  external void on(String event, JSFunction handler);
}

/// Web: same contract as the native implementation.
Future<Map<String, String>> openRazorpayCheckout(
  Map<String, dynamic> options, {
  required String expectedOrderId,
}) async {
  if (!globalContext.has('Razorpay')) {
    throw StateError(
      'Razorpay checkout could not load. Check your internet connection '
      'and try again.',
    );
  }

  final completed = Completer<Map<String, String>>();
  String? field(JSObject obj, String name) =>
      obj.getProperty<JSAny?>(name.toJS)?.dartify()?.toString();

  final jsOptions = options.jsify()! as JSObject;

  // Payment succeeded: Razorpay calls options.handler(response).
  jsOptions.setProperty(
    'handler'.toJS,
    ((JSObject response) {
      if (completed.isCompleted) return;
      final orderId = field(response, 'razorpay_order_id');
      final paymentId = field(response, 'razorpay_payment_id');
      final signature = field(response, 'razorpay_signature');
      if (orderId != expectedOrderId ||
          paymentId == null ||
          signature == null) {
        completed.completeError(
          StateError('Payment confirmation was incomplete.'),
        );
        return;
      }
      completed.complete({
        'razorpay_order_id': orderId!,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
    }).toJS,
  );

  // Checkout closed without paying.
  final modal = JSObject();
  modal.setProperty(
    'ondismiss'.toJS,
    (() {
      if (!completed.isCompleted) {
        completed.completeError(StateError('Payment was cancelled or failed.'));
      }
    }).toJS,
  );
  jsOptions.setProperty('modal'.toJS, modal);

  final checkout = _RazorpayJs(jsOptions);
  checkout.on(
    'payment.failed',
    ((JSObject response) {
      if (completed.isCompleted) return;
      final error = response.getProperty<JSObject?>('error'.toJS);
      final message = error == null ? null : field(error, 'description');
      completed.completeError(
        StateError(message ?? 'Payment was cancelled or failed.'),
      );
    }).toJS,
  );
  checkout.open();
  return completed.future.timeout(const Duration(minutes: 10));
}
