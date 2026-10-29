import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_auth_adapter.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../domain/models/dealer_registration_model.dart';

class RegistrationState {
  final DealerRegistrationModel data;
  final bool isSubmitting;
  final String? errorMessage;
  const RegistrationState({
    required this.data,
    this.isSubmitting = false,
    this.errorMessage,
  });
  RegistrationState copyWith({
    DealerRegistrationModel? data,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) => RegistrationState(
    data: data ?? this.data,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class RegistrationNotifier extends StateNotifier<RegistrationState> {
  RegistrationNotifier()
    : super(const RegistrationState(data: DealerRegistrationModel.empty));

  void clearError() {
    if (state.errorMessage != null) state = state.copyWith(clearError: true);
  }

  void resetForNewPage() =>
      state = state.copyWith(isSubmitting: false, clearError: true);

  Future<bool> submitRegistration({
    required String businessName,
    required String ownerName,
    required String mobile,
    required String email,
    required String address,
    required String city,
    required String stateName,
    required String pincode,
    required String gstNumber,
    required String panNumber,
    required String businessType,
    required String dealerType,
    required String password,
    required String confirmPassword,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final fullAddress = [
        address,
        city,
        stateName,
        pincode,
      ].where((part) => part.trim().isNotEmpty).join(', ');
      if (SupabaseConfig.authEnabled) {
        await const SupabaseAuthAdapter().signUpDealer(
          email: email,
          password: password,
          name: ownerName,
          mobile: mobile,
          companyName: businessName,
          address: fullAddress,
          gstNumber: gstNumber,
        );
      } else {
        final response = await ApiClient().post<Map<String, dynamic>>(
          'auth/signup',
          data: {
            'name': ownerName.trim(),
            'mobile': mobile.trim(),
            'email': email.trim(),
            'password': password,
            'confirmPassword': confirmPassword,
            'companyName': businessName.trim(),
            'gstNumber': gstNumber.trim().toUpperCase(),
            'address': fullAddress,
          },
        );
        final result = response.data ?? {};
        if (result['success'] != true) {
          throw ApiException(
            message: '${result['error'] ?? 'Registration failed.'}',
          );
        }
      }
      state = state.copyWith(
        isSubmitting: false,
        data: DealerRegistrationModel(
          applicationId: '',
          businessName: businessName,
          ownerName: ownerName,
          mobile: mobile,
          email: email,
          address: address,
          city: city,
          state: stateName,
          pincode: pincode,
          gstNumber: gstNumber,
          panNumber: panNumber,
          businessType: businessType,
          dealerType: dealerType,
          documents: const [],
          // Account creation never grants wholesale access. Only the existing
          // administrator approval workflow may move a dealer out of pending.
          status: ApprovalStatus.pending,
          submittedDate: DateTime.now().toLocal().toString(),
        ),
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: error is ApiException ? error.message : '$error',
      );
      return false;
    }
  }
}

final registrationProvider =
    StateNotifierProvider<RegistrationNotifier, RegistrationState>(
      (ref) => RegistrationNotifier(),
    );
