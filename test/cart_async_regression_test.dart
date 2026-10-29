import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/network/api_client.dart';
import 'package:ro_wholesale_dealer_app/features/cart/presentation/providers/cart_provider.dart';
import 'package:ro_wholesale_dealer_app/features/products/domain/models/product_model.dart';

void main() {
  test(
    'old account cart response is ignored after notifier disposal',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      final api = ApiClient(
        interceptors: [
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              started.complete();
              await pending.future;
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'success': true,
                    'items': [
                      {
                        'id': 'old-account-product',
                        'price': 100,
                        'quantity': 1,
                      },
                    ],
                  },
                ),
              );
            },
          ),
        ],
      );
      final oldCart = CartNotifier(api, 'old-account');
      await started.future;
      oldCart.dispose();
      pending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // flutter_test fails on uncaught asynchronous errors, including state writes after disposal.
    },
  );

  test(
    'cart blocks overlapping mutations and allows single units below MOQ',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      var mutations = 0;
      final api = ApiClient(
        interceptors: [
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              if (options.method == 'PUT') {
                mutations++;
                started.complete();
                await pending.future;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'success': true,
                    'items': [
                      {'id': 'filter', 'price': 100, 'moq': 5, 'quantity': 5},
                    ],
                  },
                ),
              );
            },
          ),
        ],
      );
      final cart = CartNotifier(api, 'dealer');
      addTearDown(cart.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cart.updateQuantity('filter', 6), isTrue);
      expect(cart.updateQuantity('filter', 7), isFalse);
      await started.future;
      expect(mutations, 1);
      pending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final product = ProductModel.fromJson({
        'id': 'filter',
        'price': 100,
        'moq': 5,
      });
      await cart.addToCart(product, quantity: 4);
      await expectLater(cart.addToCart(product, quantity: 0), throwsStateError);
      final unavailable = ProductModel.fromJson({
        'id': 'empty',
        'price': 100,
        'stock_quantity': 0,
      });
      expect(unavailable.stockStatus, StockStatus.outOfStock);
      await expectLater(cart.addToCart(unavailable), throwsStateError);
    },
  );
}
