import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_dealers_route.dart';

void main() {
  test('routes only the dealer directory GET when its caller has opted in', () {
    expect(isSupabaseAdminDealersRequest('dealers', method: 'GET'), isTrue);
    expect(
      isSupabaseAdminDealersRequest('/dealers?status=pending', method: 'GET'),
      isTrue,
    );
    expect(isSupabaseAdminDealersRequest('dealers', method: 'POST'), isFalse);
    expect(
      isSupabaseAdminDealersRequest('set-status', method: 'POST'),
      isFalse,
    );
    expect(
      isSupabaseAdminDealersRequest('users/dealer-1', method: 'DELETE'),
      isFalse,
    );
  });
}
