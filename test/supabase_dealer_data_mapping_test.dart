import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_dealer_data_repository.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

void main() {
  test('profile update exposes only dealer-editable fields', () {
    final values = SupabaseDealerDataRepository.profileUpdateValues({
      'name': '  Priya  ',
      'mobile': '98765 43210',
      'business': '  RO Supplies  ',
      'address': '  Main Road  ',
      'status': 'approved',
      'isApproved': true,
      'password_hash': 'must-not-be-forwarded',
    });
    expect(values, {
      'name': 'Priya',
      'owner_name': 'Priya',
      'mobile': '9876543210',
      'business_name': 'RO Supplies',
      'address': 'Main Road',
    });
    expect(values, isNot(contains('status')));
    expect(values, isNot(contains('is_approved')));
    expect(values, isNot(contains('password_hash')));
  });

  test('profile update rejects invalid names and mobile numbers', () {
    expect(
      () => SupabaseDealerDataRepository.profileUpdateValues({
        'name': '',
        'mobile': '9876543210',
      }),
      throwsStateError,
    );
    expect(
      () => SupabaseDealerDataRepository.profileUpdateValues({
        'name': 'Priya',
        'mobile': '12345',
      }),
      throwsStateError,
    );
  });

  test(
    'cart mapping preserves each quantity without exposing purchase price',
    () {
      final products = SupabaseDealerDataRepository.cartRowsToModels(
        [
          {'product_id': 'p-1', 'quantity': 2},
          {'product_id': 'retired-p', 'quantity': 1},
        ],
        [
          {
            'id': 'p-1',
            'name': 'RO Membrane',
            'sku': 'RO-MEM-75',
            'category_key': 'ro_systems',
            'category_name': 'RO Systems',
            'brand': 'Aqua',
            'mrp': 900,
            'dealer_price': 650,
            'img': 'https://images.example/membrane.png',
            'moq': '1',
            'stock_quantity': 10,
            'status': 'active',
          },
        ],
        const <ProductModel>[],
      );
      expect(products, hasLength(2));
      expect(products.first.quantity, 2);
      expect(products.first.product.dealerPrice, 650);
      expect(products.first.product.purchasePrice, isNull);
      expect(products.last.product.stockStatus, StockStatus.outOfStock);
    },
  );

  test(
    'address mapping preserves the current profile and checkout contract',
    () {
      final address = SupabaseDealerDataRepository.addressToApi({
        'id': 'ADDR-1',
        'label': 'Warehouse',
        'full_name': 'Priya',
        'phone': '9876543210',
        'door_no': '12',
        'street': 'Main Road',
        'area': 'Industrial Estate',
        'city': 'Chennai',
        'district': 'Chennai',
        'state': 'Tamil Nadu',
        'pincode': '600098',
        'address_type': 'Warehouse',
        'is_default': true,
      });
      expect(address['id'], 'ADDR-1');
      expect(address['fullName'], 'Priya');
      expect(address['addressType'], 'Warehouse');
      expect(address['isDefault'], isTrue);
    },
  );

  test(
    'order mapping preserves order amounts, status and all line details',
    () {
      final item = SupabaseDealerDataRepository.orderItemToApi({
        'product_id': 'membrane-1',
        'product_name': 'RO Membrane',
        'brand': 'Aqua',
        'unit_price': 650,
        'quantity': 2,
        'img_src': 'https://images.example/membrane.png',
        'sku': 'RO-MEM-75',
      });
      final order = SupabaseDealerDataRepository.orderToApi(
        {
          'order_id': 'RO-12345678',
          'user_email': 'dealer@example.test',
          'subtotal': 1300,
          'discount': 0,
          'gst': 234,
          'delivery_fee': 0,
          'grand_total': 1534,
          'payment_method': 'Cash on Delivery',
          'payment_status': 'pending',
          'delivery_address': '{"city":"Chennai"}',
          'status': 'Pending',
          'created_at': '2026-10-27T10:00:00Z',
        },
        [item],
      );
      expect(order['orderId'], 'RO-12345678');
      expect(order['grandTotal'], 1534);
      expect(order['paymentStatus'], 'pending');
      expect((order['items'] as List).single['numericPrice'], 650);
      expect((order['items'] as List).single['quantity'], 2);
    },
  );

  test('rewards mapping keeps profile balance and ledger totals separate', () {
    final rewards = SupabaseDealerDataRepository.rewardsToApi(
      {'reward_points': 80},
      [
        {
          'order_id': 'RO-1',
          'order_amount': 1200,
          'points_earned': 12,
          'created_at': '2026-10-27T10:00:00Z',
        },
        {
          'order_id': 'RO-2',
          'order_amount': 800,
          'points_earned': 8,
          'created_at': '2026-10-26T10:00:00Z',
        },
      ],
    );
    expect(rewards['totalPoints'], 80);
    expect(rewards['totalPointsEarned'], 20);
    expect((rewards['history'] as List).length, 2);
  });

  test('GST invoice mapping returns only GST orders with legacy totals', () {
    final invoices = SupabaseDealerDataRepository.gstInvoicesToApi([
      {
        'order_id': 'RO-GST-1',
        'invoice_number': 'INV-1',
        'grand_total': 1534,
        'gst': 234,
        'with_gst': true,
        'created_at': '2026-10-27T10:00:00Z',
      },
      {
        'order_id': 'RO-NO-GST',
        'invoice_number': 'INV-2',
        'grand_total': 1000,
        'gst': 0,
        'with_gst': false,
        'created_at': '2026-10-26T10:00:00Z',
      },
    ]);
    expect(invoices['creditLimit'], 250000);
    expect(invoices['availableCredit'], 248466);
    expect(invoices['invoices'], hasLength(1));
    expect((invoices['invoices'] as List).single['invoiceNumber'], 'INV-1');
    expect((invoices['invoices'] as List).single['amount'], 1534);
    expect((invoices['invoices'] as List).single['gstAmount'], 234);
  });
}
