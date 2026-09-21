import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/address_model.dart';

enum PaymentMethodType {
  upi,
  card,
  netbanking,
  razorpay;

  String get label {
    switch (this) {
      case PaymentMethodType.upi:
        return 'BHIM UPI / GPay / PhonePe';
      case PaymentMethodType.card:
        return 'Credit / Debit Card';
      case PaymentMethodType.netbanking:
        return 'Net Banking (HDFC, ICICI, SBI)';
      case PaymentMethodType.razorpay:
        return 'Razorpay / B2B Pay Later';
    }
  }

  String get subtitle {
    switch (this) {
      case PaymentMethodType.upi:
        return 'Instant zero-fee B2B bank transfer';
      case PaymentMethodType.card:
        return 'Visa, Mastercard, RuPay Corporate Cards';
      case PaymentMethodType.netbanking:
        return 'All major Indian commercial banks';
      case PaymentMethodType.razorpay:
        return 'Secure online checkout gateway';
    }
  }
}

class CheckoutState {
  final List<AddressModel> addresses;
  final String selectedAddressId;
  final PaymentMethodType selectedPaymentMethod;
  final bool isPlacingOrder;

  const CheckoutState({
    this.addresses = AddressModel.sampleAddresses,
    this.selectedAddressId = 'addr_1',
    this.selectedPaymentMethod = PaymentMethodType.upi,
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
      selectedPaymentMethod: selectedPaymentMethod ?? this.selectedPaymentMethod,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
    );
  }
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier() : super(const CheckoutState());

  void selectAddress(String addressId) {
    state = state.copyWith(selectedAddressId: addressId);
  }

  void selectPaymentMethod(PaymentMethodType method) {
    state = state.copyWith(selectedPaymentMethod: method);
  }

  void addAddress(AddressModel newAddress) {
    final updated = [...state.addresses, newAddress];
    state = state.copyWith(
      addresses: updated,
      selectedAddressId: newAddress.id,
    );
  }

  void updateAddress(AddressModel updatedAddress) {
    final updated = state.addresses.map((a) {
      return a.id == updatedAddress.id ? updatedAddress : a;
    }).toList();
    state = state.copyWith(addresses: updated);
  }

  void deleteAddress(String addressId) {
    if (state.addresses.length <= 1) return; // Prevent deleting last address
    final updated = state.addresses.where((a) => a.id != addressId).toList();
    state = state.copyWith(
      addresses: updated,
      selectedAddressId: updated.first.id,
    );
  }

  Future<String> placeOrder() async {
    state = state.copyWith(isPlacingOrder: true);
    await Future.delayed(const Duration(milliseconds: 1600));

    state = state.copyWith(isPlacingOrder: false);
    final orderId = 'ORD-2026-${10000 + (DateTime.now().millisecond * 80).round()}';
    return orderId;
  }
}

final checkoutProvider = StateNotifierProvider<CheckoutNotifier, CheckoutState>((ref) {
  return CheckoutNotifier();
});
