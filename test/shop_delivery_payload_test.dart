import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/shop/data/shop_employee_repository.dart';

void main() {
  test('delivery payload sends explicit status for every order item', () {
    final payload = ShopEmployeeRepository.buildDeliveryItemsPayload(
      {101: 2, 102: 0, 103: 1},
      {101, 103},
    );

    expect(payload, [
      {
        'orderItemId': 101,
        'deliveredQuantity': 2,
        'deliveryConfirmed': true,
        'deliveryStatus': 'delivered',
        'delivered': true,
      },
      {
        'orderItemId': 102,
        'deliveredQuantity': 0,
        'deliveryConfirmed': false,
        'deliveryStatus': 'not_delivered',
        'delivered': false,
      },
      {
        'orderItemId': 103,
        'deliveredQuantity': 1,
        'deliveryConfirmed': true,
        'deliveryStatus': 'delivered',
        'delivered': true,
      },
    ]);
  });
}
