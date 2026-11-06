/// Opens Razorpay Checkout and completes with the payment confirmation
/// (`razorpay_order_id`, `razorpay_payment_id`, `razorpay_signature`).
///
/// One API for every platform: Android/iOS use the `razorpay_flutter`
/// plugin, Web uses Razorpay's official browser checkout (checkout.js).
library;

export 'razorpay_gateway_native.dart'
    if (dart.library.js_interop) 'razorpay_gateway_web.dart';
