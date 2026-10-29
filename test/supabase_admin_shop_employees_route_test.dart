import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_shop_employees_route.dart';

void main() {
  test('routes only the read-only admin shop employee list GET', () {
    expect(
      isSupabaseAdminShopEmployeesRequest('shop/employees', method: 'GET'),
      isTrue,
    );
    expect(
      isSupabaseAdminShopEmployeesRequest(
        '/shop/employees?active=true',
        method: 'get',
      ),
      isTrue,
    );
    expect(
      isSupabaseAdminShopEmployeesRequest('shop/employees', method: 'POST'),
      isFalse,
    );
    expect(
      isSupabaseAdminShopEmployeesRequest(
        'shop/employees/1/active',
        method: 'PUT',
      ),
      isFalse,
    );
    expect(
      isSupabaseAdminShopEmployeesRequest('shop/orders', method: 'GET'),
      isFalse,
    );
  });
}
