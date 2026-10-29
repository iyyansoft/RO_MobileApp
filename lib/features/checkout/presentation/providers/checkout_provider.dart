import 'dart:convert';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/supabase/supabase_dealer_data_repository.dart';
import '../../../../core/supabase/supabase_checkout_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../cart/presentation/providers/cart_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/address_model.dart';
import '../../data/razorpay_checkout.dart';
import '../../../../core/utils/gstin.dart';

enum PaymentMethodType {
  cashOnDelivery,
  upi,
  card,
  netbanking,
  razorpay;

  String get label {
    switch (this) {
      case PaymentMethodType.cashOnDelivery:
        return 'Cash on Delivery';
      case PaymentMethodType.upi:
        return 'BHIM UPI / GPay / PhonePe';
      case PaymentMethodType.card:
        return 'Credit / Debit Card';
      case PaymentMethodType.netbanking:
        return 'Net Banking (HDFC, ICICI, SBI)';
      case PaymentMethodType.razorpay:
        return 'Razorpay';
    }
  }

  String get subtitle {
    switch (this) {
      case PaymentMethodType.cashOnDelivery:
        return 'Pay when your order arrives';
      case PaymentMethodType.upi:
        return 'Instant zero-fee B2B bank transfer';
      case PaymentMethodType.card:
        return 'Visa, Mastercard, RuPay Corporate Cards';
      case PaymentMethodType.netbanking:
        return 'All major Indian commercial banks';
      case PaymentMethodType.razorpay:
        return 'Credit/Debit Card, UPI, Net Banking, Wallets';
    }
  }
}

class CheckoutState {
  final List<AddressModel> addresses;
  final String selectedAddressId;
  final PaymentMethodType selectedPaymentMethod;
  final bool isPlacingOrder;

  const CheckoutState({
    this.addresses = const [
      AddressModel(
        id: 'delivery',
        name: '',
        mobile: '',
        address: '',
        city: '',
        state: '',
        pincode: '',
      ),
    ],
    this.selectedAddressId = 'delivery',
    this.selectedPaymentMethod = PaymentMethodType.cashOnDelivery,
    this.isPlacingOrder = false,
  });

  AddressModel get selectedAddress {
    return addresses.firstWhere(
      (a) => a.id == selectedAddressId,
      orElse: () => addresses.first,
    );
  }

  CheckoutState copyWith({
    List<AddressModel>? addresses,
    String? selectedAddressId,
    PaymentMethodType? selectedPaymentMethod,
    bool? isPlacingOrder,
  }) {
    return CheckoutState(
      addresses: addresses ?? this.addresses,
      selectedAddressId: selectedAddressId ?? this.selectedAddressId,
      selectedPaymentMethod:
          selectedPaymentMethod ?? this.selectedPaymentMethod,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
    );
  }
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  final Ref ref;
  CheckoutNotifier(this.ref) : super(const CheckoutState()) {
    final user = ref.read(authProvider).currentUser;
    if (user != null) {
      state = state.copyWith(
        addresses: [
          AddressModel(
            id: 'delivery',
            name: user.name,
            mobile: user.phoneNumber,
            address: user.address,
            city: '',
            state: '',
            pincode: '',
          ),
        ],
      );
      loadAddresses();
    }
  }

  Future<void> loadAddresses() async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;
    try {
      if (SupabaseConfig.dealerDataSessionActive) {
        final rows = await const SupabaseDealerDataRepository().loadAddresses(
          user.id,
        );
        final list = rows.map(_addressFromApi).toList();
        if (list.isEmpty && mounted) {
          state = state.copyWith(
            addresses: [
              AddressModel(
                id: 'delivery',
                name: user.name,
                mobile: user.phoneNumber,
                address: user.address,
                city: '',
                state: '',
                pincode: '',
              ),
            ],
            selectedAddressId: 'delivery',
          );
        } else if (mounted) {
          state = state.copyWith(
            addresses: list,
            selectedAddressId: list
                .firstWhere(
                  (address) => address.isDefault,
                  orElse: () => list.first,
                )
                .id,
          );
        }
        return;
      }
      final response = await ref
          .read(apiClientProvider)
          .get(
            'user/addresses',
            queryParameters: {'email': user.email, 'userId': user.id},
          );
      final list = ((response.data as Map)['addresses'] as List).map((value) {
        final a = value as Map;
        return AddressModel(
          id: '${a['id']}',
          name: '${a['fullName'] ?? ''}',
          mobile: '${a['phone'] ?? ''}',
          address: [
            a['doorNo'],
            a['street'],
            a['area'],
          ].where((v) => v != null && '$v'.isNotEmpty).join(', '),
          city: '${a['city'] ?? ''}',
          state: '${a['state'] ?? ''}',
          pincode: '${a['pincode'] ?? ''}',
          isDefault: a['isDefault'] == true,
          doorNo: '${a['doorNo'] ?? ''}',
          street: '${a['street'] ?? ''}',
          area: '${a['area'] ?? ''}',
        );
      }).toList();
      if (list.isEmpty && mounted) {
        state = state.copyWith(
          addresses: [
            AddressModel(
              id: 'delivery',
              name: user.name,
              mobile: user.phoneNumber,
              address: '',
              city: '',
              state: '',
              pincode: '',
            ),
          ],
          selectedAddressId: 'delivery',
        );
      }
      if (list.isNotEmpty && mounted) {
        state = state.copyWith(
          addresses: list,
          selectedAddressId: list
              .firstWhere((a) => a.isDefault, orElse: () => list.first)
              .id,
        );
      }
    } catch (_) {
      /* The user can still enter a delivery address manually. */
    }
  }

  void selectAddress(String addressId) {
    state = state.copyWith(selectedAddressId: addressId);
  }

  void selectPaymentMethod(PaymentMethodType method) {
    if (state.isPlacingOrder) return;
    state = state.copyWith(selectedPaymentMethod: method);
  }

  Future<void> addAddress(AddressModel address) async => _saveAddress(address);
  Future<void> updateAddress(AddressModel address) async =>
      _saveAddress(address);
  Future<void> _saveAddress(AddressModel address) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) throw StateError('Sign in to save an address.');
    if (SupabaseConfig.dealerDataSessionActive) {
      final savedId = await const SupabaseDealerDataRepository().saveAddress(
        user.id,
        {
          'id': address.id == 'delivery' ? null : address.id,
          'fullName': address.name,
          'phone': address.mobile,
          'street': address.street.isEmpty ? address.address : address.street,
          'doorNo': address.doorNo,
          'area': address.area,
          'city': address.city,
          'state': address.state,
          'pincode': address.pincode,
          'addressType': 'Office',
          'isDefault': address.isDefault,
        },
      );
      if (!mounted) return;
      await loadAddresses();
      if (mounted && state.addresses.any((saved) => saved.id == savedId)) {
        selectAddress(savedId);
      }
      return;
    }
    final result = await ref
        .read(apiClientProvider)
        .post(
          'user/addresses/save',
          data: {
            'email': user.email,
            'userId': user.id,
            'id': address.id,
            'fullName': address.name,
            'phone': address.mobile,
            'street': address.street.isEmpty ? address.address : address.street,
            'doorNo': address.doorNo,
            'area': address.area,
            'city': address.city,
            'state': address.state,
            'pincode': address.pincode,
            'isDefault': address.isDefault,
          },
        );
    if (!mounted) return;
    if ((result.data as Map)['success'] != true) {
      throw StateError('Address could not be saved.');
    }
    await loadAddresses();
    if (mounted && state.addresses.any((a) => a.id == address.id)) {
      selectAddress(address.id);
    }
  }

  Future<void> deleteAddress(String addressId) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;
    if (SupabaseConfig.dealerDataSessionActive) {
      await const SupabaseDealerDataRepository().deleteAddress(
        user.id,
        addressId,
      );
      if (mounted) await loadAddresses();
      return;
    }
    await ref
        .read(apiClientProvider)
        .post(
          'user/addresses/delete',
          data: {
            'email': user.email,
            'userId': user.id,
            'addressId': addressId,
          },
        );
    if (mounted) await loadAddresses();
  }

  static AddressModel _addressFromApi(Map<String, dynamic> address) {
    final street = '${address['street'] ?? ''}';
    final doorNo = '${address['doorNo'] ?? ''}';
    final area = '${address['area'] ?? ''}';
    return AddressModel(
      id: '${address['id'] ?? ''}',
      name: '${address['fullName'] ?? ''}',
      mobile: '${address['phone'] ?? ''}',
      address: [
        doorNo,
        street,
        area,
      ].where((part) => part.isNotEmpty).join(', '),
      city: '${address['city'] ?? ''}',
      state: '${address['state'] ?? ''}',
      pincode: '${address['pincode'] ?? ''}',
      isDefault: address['isDefault'] == true,
      doorNo: doorNo,
      street: street,
      area: area,
    );
  }

  Future<String> placeOrder({
    bool withGst = true,
    String? companyName,
    String? gstin,
    String panNumber = '',
    String deliveryNote = '',
    bool sameAsDelivery = true,
    Map<String, String>? billingAddress,
  }) async {
    if (!sameAsDelivery &&
        (billingAddress == null ||
            [
              'name',
              'mobile',
              'address',
              'city',
              'state',
              'pincode',
            ].any((key) => (billingAddress[key] ?? '').trim().isEmpty))) {
      throw StateError('Enter a complete billing address.');
    }
    if (state.isPlacingOrder) {
      throw StateError('An order is already being submitted.');
    }
    final user = ref.read(authProvider).currentUser;
    final cart = ref.read(cartProvider);
    if (cart.isLoading || cart.errorMessage != null) {
      throw StateError(
        'Wait for the cart to sync successfully before checkout.',
      );
    }
    final address = state.selectedAddress;
    if (user == null || cart.items.isEmpty) {
      throw StateError('Sign in and add products before checkout.');
    }
    final invoiceGst = withGst
        ? (gstin ?? user.gstNumber).trim().toUpperCase()
        : '';
    if (withGst && !isValidGstin(invoiceGst)) {
      throw StateError('Enter a valid GST number for With GST checkout.');
    }
    if (![
      PaymentMethodType.cashOnDelivery,
      PaymentMethodType.razorpay,
    ].contains(state.selectedPaymentMethod)) {
      throw StateError('Select Cash on Delivery or Razorpay.');
    }
    if (address.name.trim().isEmpty ||
        address.mobile.trim().isEmpty ||
        address.address.trim().isEmpty ||
        address.city.trim().isEmpty ||
        address.state.trim().isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(address.pincode)) {
      throw StateError(
        'Add a complete delivery address with a six-digit pincode.',
      );
    }
    state = state.copyWith(isPlacingOrder: true);
    try {
      final payload = <String, dynamic>{
        'email': user.email,
        'items': cart.items
            .map(
              (i) => {
                'id': i.product.id,
                'name': i.product.name,
                'brand': i.product.brand,
                'numericPrice': i.product.dealerPrice,
                'quantity': i.quantity,
                'imgSrc': i.product.imageUrl,
              },
            )
            .toList(),
        'subtotal': cart.subtotal,
        'discount': cart.dealerDiscount,
        'withGst': withGst,
        'gst': withGst ? cart.gstAmount : 0,
        'deliveryFee': cart.deliveryFee,
        'grandTotal': withGst
            ? cart.grandTotal
            : double.parse(
                (cart.grandTotal - cart.gstAmount).toStringAsFixed(2),
              ),
        'paymentMethod': state.selectedPaymentMethod.label,
        'deliveryAddress': {
          'name': address.name,
          'mobile': address.mobile,
          'address': address.address,
          'city': address.city,
          'state': address.state,
          'pincode': address.pincode,
        },
        'sameAsDelivery': sameAsDelivery,
        'billingAddress': billingAddress,
        'companyName': companyName ?? user.companyName,
        'gstin': invoiceGst,
        'panNumber': panNumber,
        'deliveryNote': deliveryNote,
      };
      final gateway = ref.read(razorpayCheckoutProvider);
      final pending = await gateway.pending(user.email);
      if (SupabaseConfig.useSupabaseCheckout && !SupabaseConfig.checkoutSessionActive) {
        throw StateError('Sign in with your verified Supabase account before using Supabase checkout.');
      }
      final useSupabaseCheckout = SupabaseConfig.checkoutSessionActive;
      if (!useSupabaseCheckout && pending?['supabaseCheckout'] == true) {
        throw StateError('A Supabase payment is pending confirmation. Sign in with the same Supabase account to finish it.');
      }
      if (useSupabaseCheckout) {
        if (pending != null && pending['supabaseCheckout'] != true) {
          throw StateError('A payment from the previous checkout service is pending. Restore that checkout before starting another.');
        }
        String requestId;
        Map<String, dynamic> checkout;
        Map<String, String>? payment;
        if (pending != null) {
          if (state.selectedPaymentMethod != PaymentMethodType.razorpay ||
              pending['withGst'] != withGst ||
              pending['grandTotal'] != payload['grandTotal'] ||
              jsonEncode(
                    (pending['items'] as List)
                        .map((item) => [item['id'], item['quantity']])
                        .toList(),
                  ) !=
                  jsonEncode(
                    cart.items
                        .map((item) => [item.product.id, item.quantity])
                        .toList(),
                  )) {
            throw StateError(
              'A Razorpay payment needs order confirmation. Select Razorpay and restore the original cart and GST choice to retry without paying again.',
            );
          }
          requestId = '${pending['checkoutRequestId'] ?? ''}';
          if (requestId.isEmpty) throw StateError('The pending payment cannot be safely retried.');
          payment = {
            'razorpay_order_id': '${pending['razorpay_order_id'] ?? ''}',
            'razorpay_payment_id': '${pending['razorpay_payment_id'] ?? ''}',
            'razorpay_signature': '${pending['razorpay_signature'] ?? ''}',
          };
          checkout = Map<String, dynamic>.from(pending)
            ..remove('supabaseCheckout')
            ..remove('checkoutRequestId')
            ..remove('razorpay_order_id')
            ..remove('razorpay_payment_id')
            ..remove('razorpay_signature');
        } else {
          requestId = await gateway.checkoutRequestId(user.email, payload);
          checkout = Map<String, dynamic>.from(payload)..remove('email');
          if (state.selectedPaymentMethod == PaymentMethodType.razorpay) {
            final created = await const SupabaseCheckoutRepository()
                .createRazorpayOrder(requestId: requestId, checkout: checkout);
            final paymentOrder = Map<String, dynamic>.from(created['order'] as Map);
            final completedPayment = await gateway.pay(
              paymentOrder,
              email: user.email,
              name: user.name,
            );
            payment = completedPayment;
            await gateway.remember(user.email, {
              ...checkout,
              'supabaseCheckout': true,
              'checkoutRequestId': requestId,
              ...completedPayment,
            });
          }
        }
        final response = state.selectedPaymentMethod == PaymentMethodType.cashOnDelivery
            ? await const SupabaseCheckoutRepository().placeCodOrder(
                requestId: requestId,
                checkout: checkout,
              )
            : await const SupabaseCheckoutRepository().verifyRazorpayPayment(
                requestId: requestId,
                checkout: checkout,
                payment: payment!,
              );
        final orderId = (response['order'] as Map?)?['orderId'];
        if (orderId == null) throw StateError('Checkout service returned no order ID.');
        await gateway.clearPending(user.email);
        await gateway.clearCheckoutRequestId(user.email);
        return '$orderId';
      }

      final api = ref.read(apiClientProvider);
      if (pending != null) {
        if (state.selectedPaymentMethod != PaymentMethodType.razorpay ||
            pending['withGst'] != withGst ||
            pending['grandTotal'] != payload['grandTotal'] ||
            jsonEncode(
                  (pending['items'] as List)
                      .map((item) => [item['id'], item['quantity']])
                      .toList(),
                ) !=
                jsonEncode(
                  cart.items
                      .map((item) => [item.product.id, item.quantity])
                      .toList(),
                )) {
          throw StateError(
            'A Razorpay payment needs order confirmation. Select Razorpay and restore the original cart and GST choice to retry without paying again.',
          );
        }
        payload.clear();
        payload.addAll(pending);
      } else if (state.selectedPaymentMethod == PaymentMethodType.razorpay) {
        final created = await api.post(
          'payments/razorpay/order',
          data: payload,
        );
        final payment = await ref
            .read(razorpayCheckoutProvider)
            .pay(
              Map<String, dynamic>.from(created.data['order'] as Map),
              email: user.email,
              name: user.name,
            );
        payload.addAll(payment);
        await gateway.remember(user.email, payload);
      } else {
        payload['checkoutRequestId'] = await gateway.checkoutRequestId(
          user.email,
          payload,
        );
      }
      final response = await api.post('user/orders/create', data: payload);
      final body = response.data as Map;
      final orderId = (body['order'] as Map?)?['orderId'];
      if (body['success'] != true || orderId == null) {
        throw StateError('${body['error'] ?? 'Order could not be created'}');
      }
      await gateway.clearPending(user.email);
      if (state.selectedPaymentMethod == PaymentMethodType.cashOnDelivery) {
        await gateway.clearCheckoutRequestId(user.email);
      }
      return '$orderId';
    } finally {
      if (mounted) state = state.copyWith(isPlacingOrder: false);
    }
  }
}

final checkoutProvider = StateNotifierProvider<CheckoutNotifier, CheckoutState>(
  (ref) {
    ref.watch(authProvider.select((auth) => auth.currentUser?.id ?? ''));
    return CheckoutNotifier(ref);
  },
);
