import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_order_status_route.dart';

void main() {
  test(
    'maps only an order status PUT and keeps its request payload explicit',
    () {
      final request = mapSupabaseAdminOrderStatusRequest(
        '/orders/RO%2F123/status',
        method: 'put',
        data: {'status': 'Shipped'},
      );
      expect(request?.orderId, 'RO/123');
      expect(request?.toJson(), {'orderId': 'RO/123', 'status': 'Shipped'});
      expect(
        mapSupabaseAdminOrderStatusRequest(
          'orders/RO-1/status',
          method: 'GET',
          data: {'status': 'Shipped'},
        ),
        isNull,
      );
      expect(
        mapSupabaseAdminOrderStatusRequest(
          'orders/RO-1/status',
          method: 'PUT',
          data: null,
        )?.status,
        'Processing',
      );
      expect(
        mapSupabaseAdminOrderStatusRequest(
          'orders/RO-1/items/status',
          method: 'PUT',
          data: {'status': 'Shipped'},
        ),
        isNull,
      );
    },
  );
}
