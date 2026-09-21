import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/user_model.dart';

class AuthState {
  final String phoneNumber;
  final String otpCode;
  final bool isLoading;
  final String? errorMessage;
  final int countdownSeconds;
  final bool canResend;
  final bool isLoggedIn;
  final UserModel? currentUser;

  const AuthState({
    this.phoneNumber = '',
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
    String? otpCode,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    int? countdownSeconds,
    bool? canResend,
    bool? isLoggedIn,
    UserModel? currentUser,
  }) {
    return AuthState(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      otpCode: otpCode ?? this.otpCode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      canResend: canResend ?? this.canResend,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      currentUser: currentUser ?? this.currentUser,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  Timer? _timer;

  AuthNotifier() : super(const AuthState());

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void setPhoneNumber(String phone) {
    state = state.copyWith(phoneNumber: phone, clearError: true);
  }

  void setOtpCode(String otp) {
    state = state.copyWith(otpCode: otp, clearError: true);
  }

  Future<bool> sendOtp(String phone) async {
    // Validate phone number length
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length != 10) {
      state = state.copyWith(
        errorMessage: 'Please enter a valid 10-digit mobile number.',
      );
      return false;
    }

    state = state.copyWith(
      isLoading: true,
      phoneNumber: cleanPhone,
      clearError: true,
    );

    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 1200));

    state = state.copyWith(
      isLoading: false,
      countdownSeconds: 30,
      canResend: false,
    );

    _startCountdownTimer();
    return true;
  }

  Future<bool> verifyOtp(String otp) async {
    if (otp.length != 6) {
      state = state.copyWith(
        errorMessage: 'Please enter the complete 6-digit OTP.',
      );
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    await Future.delayed(const Duration(milliseconds: 1400));

    // Mock OTP verification: '123456' or any 6 digits starting with '1' is valid
    if (otp == '123456' || otp.startsWith('1') || otp == '666666') {
      state = state.copyWith(
        isLoading: false,
        isLoggedIn: true,
        currentUser: UserModel.demoDealer,
        clearError: true,
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid OTP! Enter 123456 for demo login.',
      );
      return false;
    }
  }

  Future<void> resendOtp() async {
    if (!state.canResend) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );
    await Future.delayed(const Duration(milliseconds: 1000));

    state = state.copyWith(
      isLoading: false,
      countdownSeconds: 30,
      canResend: false,
    );

    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.countdownSeconds > 1) {
        state = state.copyWith(countdownSeconds: state.countdownSeconds - 1);
      } else {
        timer.cancel();
        state = state.copyWith(
          countdownSeconds: 0,
          canResend: true,
        );
      }
    });
  }

  void logout() {
    _timer?.cancel();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
