import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_shop_enquiries_route.dart';

void main() {
  test('routes only the read-only admin shop enquiry inbox GET', () {
    expect(
      isSupabaseAdminShopEnquiriesRequest('shop/enquiries', method: 'GET'),
      isTrue,
    );
    expect(
      isSupabaseAdminShopEnquiriesRequest(
        '/shop/enquiries?state=new',
        method: 'get',
      ),
      isTrue,
    );
    expect(
      isSupabaseAdminShopEnquiriesRequest('shop/enquiries', method: 'POST'),
      isFalse,
    );
    expect(
      isSupabaseAdminShopEnquiriesRequest('shop/orders', method: 'GET'),
      isFalse,
    );
    expect(
      isSupabaseAdminShopEnquiriesRequest('shop/enquiries/1', method: 'DELETE'),
      isFalse,
    );
  });
}
