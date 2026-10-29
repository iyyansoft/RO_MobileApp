import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_orders_route.dart';

void main() {
  test('routes only Admin Orders GET to the opt-in Supabase path', () {
    expect(isSupabaseAdminOrdersRequest('orders', method: 'GET'), isTrue);
    expect(
      isSupabaseAdminOrdersRequest('/orders?status=Pending', method: 'get'),
      isTrue,
    );
    expect(isSupabaseAdminOrdersRequest('orders', method: 'POST'), isFalse);
    expect(
      isSupabaseAdminOrdersRequest('orders/order-1/status', method: 'PUT'),
      isFalse,
    );
    expect(isSupabaseAdminOrdersRequest('analytics', method: 'GET'), isFalse);
  });
}
