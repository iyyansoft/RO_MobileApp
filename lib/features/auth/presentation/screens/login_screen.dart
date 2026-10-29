import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/brand_logo.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _usePassword = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_form.currentState!.validate()) return;
    final success = _usePassword
        ? await ref
              .read(authProvider.notifier)
              .loginWithPassword(_email.text, _password.text)
        : await ref.read(authProvider.notifier).sendOtp(_email.text);
    if (success && mounted) context.go(_usePassword ? '/home' : '/otp');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dealer sign in')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(width: 250, height: 90)),
                    const SizedBox(height: 20),
                    const Text(
                      'Welcome back, partner',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _usePassword ? 'Sign in with your account password.' : 'Enter your email address. We will send a six digit sign in code.',
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: _usePassword
                          ? TextInputType.text
                          : TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: _usePassword
                          ? const [AutofillHints.username]
                          : const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: _usePassword
                            ? 'Email or mobile number'
                            : 'Email address',
                        prefixIcon: Icon(
                          _usePassword
                              ? Icons.person_outline
                              : Icons.email_outlined,
                        ),
                      ),
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(input);
                        final validMobile = RegExp(r'^\d{10}$').hasMatch(input);
                        return validEmail || (_usePassword && validMobile)
                            ? null
                            : _usePassword
                            ? 'Enter a valid email or 10-digit mobile number'
                            : 'Enter a valid email address';
                      },
                      onFieldSubmitted: (_) => _sendCode(),
                    ),
                    if (_usePassword) const SizedBox(height: 16),
                    if (_usePassword)
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) =>
                            (value ?? '').isEmpty ? 'Enter password' : null,
                        onFieldSubmitted: (_) => _sendCode(),
                      ),
                    if (auth.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          auth.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.isLoading ? null : _sendCode,
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _usePassword ? 'Sign in' : 'Send sign in code',
                            ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          setState(() => _usePassword = !_usePassword),
                      child: Text(
                        _usePassword
                            ? 'Use email code instead'
                            : 'Sign in with password',
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: const Text('Create a dealer account'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      child: const Text('Forgot password?'),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/shop/login'),
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Shop Employee Login'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
