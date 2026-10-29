import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_shop_notifications_route.dart';

void main() {
  test('routes only the read-only admin shop notification inbox GET', () {
    expect(
      isSupabaseAdminShopNotificationsRequest(
        'shop/notifications',
        method: 'GET',
      ),
      isTrue,
    );
    expect(
      isSupabaseAdminShopNotificationsRequest(
        '/shop/notifications?unread=true',
        method: 'get',
      ),
      isTrue,
    );
    expect(
      isSupabaseAdminShopNotificationsRequest(
        'shop/notifications',
        method: 'POST',
      ),
      isFalse,
    );
    expect(
      isSupabaseAdminShopNotificationsRequest('shop/enquiries', method: 'GET'),
      isFalse,
    );
    expect(
      isSupabaseAdminShopNotificationsRequest(
        'shop/notifications/1',
        method: 'DELETE',
      ),
      isFalse,
    );
  });
}
