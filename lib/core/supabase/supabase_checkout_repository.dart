import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Trusted checkout operations are proxied through Supabase Edge Functions.
/// This class never accesses order, payment, price, or inventory tables from
/// the Flutter client.
class SupabaseCheckoutRepository {
  const SupabaseCheckoutRepository();

  Future<Map<String, dynamic>> createRazorpayOrder({
    required String requestId,
    required Map<String, dynamic> checkout,
  }) => _invoke('create-razorpay-order', {
    'requestId': requestId,
    'checkout': checkout,
  });

  Future<Map<String, dynamic>> placeCodOrder({
    required String requestId,
    required Map<String, dynamic> checkout,
  }) => _invoke('place-cod-order', {
    'requestId': requestId,
    'checkout': checkout,
  });

  Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String requestId,
    required Map<String, dynamic> checkout,
    required Map<String, String> payment,
  }) => _invoke('verify-razorpay-payment', {
    'requestId': requestId,
    'checkout': checkout,
    ...payment,
  });

  /// Cancels an unfulfilled COD order only. The server rejects paid orders
  /// until a verified online refund operation exists.
  Future<Map<String, dynamic>> cancelUnfulfilledOrder({
    required String orderId,
  }) => _invoke('cancel-order', {'orderId': orderId});

  Future<Map<String, dynamic>> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    if (!SupabaseConfig.checkoutSessionActive) {
      throw StateError(
        'Sign in with a verified Supabase account to use this checkout.',
      );
    }
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        function,
        body: body,
      );
      final result = response.data;
      if (result is! Map) {
        throw StateError('Checkout service returned an invalid response.');
      }
      final data = Map<String, dynamic>.from(result);
      if (data['success'] != true) {
        throw StateError(
          '${data['error'] ?? 'Checkout could not be completed.'}',
        );
      }
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw StateError('${details['error']}');
      }
      throw StateError('Checkout could not be completed. Please retry.');
    }
  }
}
