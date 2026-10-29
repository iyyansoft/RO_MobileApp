import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/api_client.dart';
import 'supabase_config.dart';
import 'supabase_password_change_policy.dart';

/// Supabase Auth adapter for dealer identity. It synchronizes the authenticated
/// identity to the existing dealer row via the reviewed SQL RPC, then exchanges
/// the Supabase JWT for the short-lived legacy API token used by retained
/// Express routes. No privileged credential is used by this client.
class SupabaseAuthAdapter {
  const SupabaseAuthAdapter();

  SupabaseClient get _client => SupabaseConfig.client;

  Future<void> signUpDealer({
    required String email,
    required String password,
    required String name,
    required String mobile,
    required String companyName,
    required String address,
    required String gstNumber,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        'name': name.trim(),
        'mobile': mobile.trim(),
        'companyName': companyName.trim(),
        'address': address.trim(),
        'gstNumber': gstNumber.trim().toUpperCase(),
      },
    );
    // If email confirmation is disabled in Supabase, create/link the dealer
    // profile now. Otherwise profile sync occurs after the user verifies and
    // signs in; no unverified profile is exposed to the app.
    if (response.session != null) await _syncProfile();
  }

  Future<Map<String, dynamic>> signInWithPassword(
    String email,
    String password,
  ) async {
    await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _syncAndExchange();
  }

  Future<void> sendEmailOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim().toLowerCase(),
      shouldCreateUser: false,
    );
  }

  Future<Map<String, dynamic>> verifyEmailOtp(String email, String otp) async {
    await _client.auth.verifyOTP(
      type: OtpType.email,
      email: email.trim().toLowerCase(),
      token: otp.trim(),
    );
    return _syncAndExchange();
  }

  Future<void> requestPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String password,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email.trim().toLowerCase(),
      token: otp.trim(),
    );
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  /// Changes the password for the currently signed-in Supabase identity.
  /// Reauthentication is required, and a changed identity aborts the update.
  Future<void> changePassword({
    required String expectedEmail,
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = _client.auth.currentSession;
    final user = _client.auth.currentUser;
    final email = user?.email;
    if (session == null ||
        user == null ||
        email == null ||
        user.emailConfirmedAt == null) {
      throw const AuthException(
        'A verified, signed-in account is required to change the password.',
      );
    }
    if (email.trim().toLowerCase() != expectedEmail.trim().toLowerCase()) {
      throw const AuthException(
        'The signed-in account does not match this profile. Sign in again.',
      );
    }

    await changePasswordAfterReauthentication(
      email: email,
      expectedUserId: user.id,
      currentPassword: currentPassword,
      newPassword: newPassword,
      reauthenticate: (accountEmail, password) async {
        final response = await _client.auth.signInWithPassword(
          email: accountEmail,
          password: password,
        );
        return response.user?.id;
      },
      updatePassword: (password) async {
        await _client.auth.updateUser(UserAttributes(password: password));
      },
    );
  }

  Future<Map<String, dynamic>> restoreDealerSession() async {
    if (_client.auth.currentSession == null) {
      throw const AuthException('Please sign in again.');
    }
    return _syncAndExchange();
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<Map<String, dynamic>> _syncAndExchange() async {
    await _syncProfile();
    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Please sign in again.');
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiClient.defaultBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    final response = await dio.post<Map<String, dynamic>>(
      'auth/supabase/exchange',
      data: const <String, dynamic>{},
    );
    final data = response.data ?? const <String, dynamic>{};
    if (data['success'] != true || data['user'] is! Map) {
      throw ApiException(
        message: '${data['error'] ?? 'Could not complete sign in.'}',
        statusCode: response.statusCode,
        responseData: data,
      );
    }
    final user = Map<String, dynamic>.from(data['user'] as Map);
    user['token'] ??= data['token'];
    return user;
  }

  Future<void> _syncProfile() async {
    final session = _client.auth.currentSession;
    if (session == null) return;
    await _client.rpc('sync_current_dealer_profile');
  }
}
