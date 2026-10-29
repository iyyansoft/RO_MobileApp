import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_auth_adapter.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../domain/models/user_model.dart';

class AuthState {
  final String phoneNumber, email, otpCode;
  final bool isLoading, canResend, isLoggedIn;
  final String? errorMessage;
  final int countdownSeconds;
  final UserModel? currentUser;
  const AuthState({
    this.phoneNumber = '',
    this.email = '',
    this.otpCode = '',
    this.isLoading = false,
    this.errorMessage,
    this.countdownSeconds = 30,
    this.canResend = false,
    this.isLoggedIn = false,
    this.currentUser,
  });
  AuthState copyWith({
    String? phoneNumber,
    String? email,
    String? otpCode,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    int? countdownSeconds,
    bool? canResend,
    bool? isLoggedIn,
    UserModel? currentUser,
  }) => AuthState(
    phoneNumber: phoneNumber ?? this.phoneNumber,
    email: email ?? this.email,
    otpCode: otpCode ?? this.otpCode,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    canResend: canResend ?? this.canResend,
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    currentUser: currentUser ?? this.currentUser,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._client) : super(const AuthState());
  final ApiClient _client;
  final SupabaseAuthAdapter _supabase = const SupabaseAuthAdapter();
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'ro_dealer_session';
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void setPhoneNumber(String phone) =>
      state = state.copyWith(phoneNumber: phone, clearError: true);
  void setOtpCode(String otp) =>
      state = state.copyWith(otpCode: otp, clearError: true);
  void clearError() => state = state.copyWith(clearError: true);

  Future<void> restoreSession() async {
    try {
      if (SupabaseConfig.authEnabled &&
          SupabaseConfig.client.auth.currentSession != null) {
        final profile = await _supabase.restoreDealerSession();
        final user = UserModel.fromJson(profile);
        await _signIn(user);
        return;
      }
      final saved = await _storage.read(key: _sessionKey);
      if (saved == null) return;
      final data = jsonDecode(saved);
      if (data is! Map) return;
      final savedUser = UserModel.fromJson(Map<String, dynamic>.from(data));
      if (savedUser.email.isEmpty || savedUser.token.isEmpty) return;
      ApiClient.sessionToken = savedUser.token;
      final response = await _client.get<Map<String, dynamic>>('auth/session');
      if (response.data?['success'] != true || response.data?['user'] is! Map) {
        throw StateError('This registered account is no longer active.');
      }
      final user = UserModel.fromJson(
        Map<String, dynamic>.from(response.data!['user'] as Map),
      );
      state = state.copyWith(
        isLoggedIn: true,
        currentUser: user,
        email: user.email,
        clearError: true,
      );
    } catch (_) {
      ApiClient.sessionToken = null;
      await _storage.delete(key: _sessionKey).catchError((_) {});
    }
  }

  Future<void> _signIn(UserModel user) async {
    ApiClient.sessionToken = user.token;
    state = state.copyWith(
      isLoading: false,
      isLoggedIn: true,
      currentUser: user,
      email: user.email,
      clearError: true,
    );
    try {
      await _storage.write(key: _sessionKey, value: jsonEncode(user.toJson()));
    } catch (_) {
      /* The active session still works if device storage is unavailable. */
    }
  }

  Future<bool> sendOtp(String target) async {
    final clean = target.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) {
      state = state.copyWith(errorMessage: 'Enter a valid email address.');
      return false;
    }
    // Retain the address even when delivery fails so the OTP screen can let
    // the dealer retry delivery without submitting the signup form again.
    state = state.copyWith(
      email: clean,
      isLoading: true,
      canResend: true,
      countdownSeconds: 0,
      clearError: true,
    );
    try {
      if (SupabaseConfig.authEnabled) {
        await _supabase.sendEmailOtp(clean);
        state = state.copyWith(
          email: clean,
          isLoading: false,
          countdownSeconds: 30,
          canResend: false,
          clearError: true,
        );
        _startCountdownTimer();
        return true;
      }
      final response = await _client.post<Map<String, dynamic>>(
        'auth/send-otp',
        data: {'email': clean},
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final data = response.data ?? {};
      if (data['success'] != true) {
        throw ApiException(
          message: '${data['error'] ?? 'Could not send OTP.'}',
        );
      }
      state = state.copyWith(
        email: '${data['email'] ?? clean}',
        isLoading: false,
        countdownSeconds: 30,
        canResend: false,
        clearError: true,
      );
      _startCountdownTimer();
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _message(error));
      return false;
    }
  }

  Future<bool> verifyOtp(String otp, {bool signIn = true}) async {
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      state = state.copyWith(errorMessage: 'Enter the complete 6-digit code.');
      return false;
    }
    if (state.email.isEmpty) {
      state = state.copyWith(errorMessage: 'Request a new code to continue.');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (SupabaseConfig.authEnabled) {
        final profile = await _supabase.verifyEmailOtp(state.email, otp);
        final user = UserModel.fromJson(profile);
        _timer?.cancel();
        if (signIn) {
          await _signIn(user);
        } else {
          state = state.copyWith(isLoading: false, clearError: true);
        }
        return true;
      }
      final response = await _client.post<Map<String, dynamic>>(
        'auth/verify-otp',
        data: {'email': state.email, 'otp': otp},
      );
      final data = response.data ?? {};
      if (data['success'] != true || data['user'] is! Map) {
        throw ApiException(
          message: '${data['error'] ?? 'Verification failed.'}',
        );
      }
      final payload = Map<String, dynamic>.from(data['user'] as Map);
      payload['token'] ??= data['token'];
      final user = UserModel.fromJson(payload);
      _timer?.cancel();
      if (signIn) {
        await _signIn(user);
      } else {
        state = state.copyWith(isLoading: false, clearError: true);
      }
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _message(error));
      return false;
    }
  }

  Future<bool> requestPasswordResetOtp(String target) async {
    final clean = target.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(clean)) {
      state = state.copyWith(errorMessage: 'Enter a valid email address.');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (SupabaseConfig.authEnabled) {
        await _supabase.requestPasswordReset(clean);
        state = state.copyWith(
          email: clean,
          isLoading: false,
          clearError: true,
        );
        return true;
      }
      final response = await _client.post<Map<String, dynamic>>(
        'auth/forgot-password',
        data: {'email': clean},
      );
      final data = response.data ?? {};
      if (data['success'] != true) {
        throw ApiException(
          message: '${data['error'] ?? 'Could not send OTP.'}',
        );
      }
      state = state.copyWith(email: clean, isLoading: false, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _message(error));
      return false;
    }
  }

  Future<bool> resetPassword({
    required String otp,
    required String password,
    required String confirmPassword,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      state = state.copyWith(errorMessage: 'Enter the complete 6-digit code.');
      return false;
    }
    if (password.length < 8 || password != confirmPassword) {
      state = state.copyWith(
        errorMessage: password.length < 8
            ? 'Use at least 8 characters.'
            : 'Passwords do not match.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (SupabaseConfig.authEnabled) {
        await _supabase.resetPassword(
          email: state.email,
          otp: otp,
          password: password,
        );
        state = state.copyWith(isLoading: false, clearError: true);
        return true;
      }
      final response = await _client.post<Map<String, dynamic>>(
        'auth/reset-password',
        data: {
          'email': state.email,
          'otp': otp,
          'password': password,
          'confirmPassword': confirmPassword,
        },
      );
      final data = response.data ?? {};
      if (data['success'] != true) {
        throw ApiException(
          message: '${data['error'] ?? 'Password reset failed.'}',
        );
      }
      state = state.copyWith(isLoading: false, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _message(error));
      return false;
    }
  }

  Future<bool> loginWithPassword(String identifier, String password) async {
    if (identifier.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Enter your email or mobile and password.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanIdentifier = identifier.trim();
      final looksLikeEmail = cleanIdentifier.contains('@');
      if (SupabaseConfig.authEnabled && looksLikeEmail) {
        final profile = await _supabase.signInWithPassword(
          cleanIdentifier,
          password,
        );
        await _signIn(UserModel.fromJson(profile));
        return true;
      }
      final response = await _client.post<Map<String, dynamic>>(
        'auth/login',
        data: {'identifier': identifier.trim(), 'password': password},
      );
      final data = response.data ?? {};
      if (data['success'] != true || data['user'] is! Map) {
        throw ApiException(message: '${data['error'] ?? 'Sign in failed.'}');
      }
      final payload = Map<String, dynamic>.from(data['user'] as Map);
      payload['token'] ??= data['token'];
      final user = UserModel.fromJson(payload);
      await _signIn(user);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _message(error));
      return false;
    }
  }

  Future<void> resendOtp() async {
    if (state.canResend && !state.isLoading) await sendOtp(state.email);
  }

  void updateUser(UserModel user) {
    state = state.copyWith(currentUser: user);
    _storage
        .write(key: _sessionKey, value: jsonEncode(user.toJson()))
        .catchError((_) {});
  }

  void _startCountdownTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.countdownSeconds <= 1) {
        timer.cancel();
        state = state.copyWith(countdownSeconds: 0, canResend: true);
      } else {
        state = state.copyWith(countdownSeconds: state.countdownSeconds - 1);
      }
    });
  }

  static String _message(Object error) =>
      error is ApiException ? error.message : '$error';
  Future<void> logout() async {
    _timer?.cancel();
    if (SupabaseConfig.isConfigured) {
      try {
        await _supabase.signOut();
      } catch (_) {}
    }
    ApiClient.sessionToken = null;
    state = const AuthState();
    try {
      await _storage.delete(key: _sessionKey);
    } catch (_) {}
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ApiClient()),
);
