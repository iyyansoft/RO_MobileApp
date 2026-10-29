import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/brand_logo.dart';
import '../providers/registration_provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/utils/gstin.dart';

class DealerRegistrationScreen extends ConsumerStatefulWidget {
  const DealerRegistrationScreen({super.key});
  @override
  ConsumerState<DealerRegistrationScreen> createState() =>
      _DealerRegistrationScreenState();
}

class _DealerRegistrationScreenState
    extends ConsumerState<DealerRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _errorsInitialized = false;
  final _name = TextEditingController(),
      _mobile = TextEditingController(),
      _email = TextEditingController(),
      _address = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _company = TextEditingController(), _gst = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(registrationProvider.notifier).resetForNewPage();
      ref.read(authProvider.notifier).clearError();
      setState(() => _errorsInitialized = true);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _mobile,
      _email,
      _address,
      _password,
      _confirm,
      _company,
      _gst,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clearSignupErrors() {
    ref.read(registrationProvider.notifier).clearError();
    ref.read(authProvider.notifier).clearError();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final success = await ref
          .read(registrationProvider.notifier)
          .submitRegistration(
            businessName: _company.text.trim(),
            ownerName: _name.text.trim(),
            mobile: _mobile.text.trim(),
            email: _email.text.trim(),
            address: _address.text.trim(),
            city: '',
            stateName: '',
            pincode: '',
            gstNumber: _gst.text.trim().toUpperCase(),
            panNumber: '',
            businessType: '',
            dealerType: '',
            password: _password.text,
            confirmPassword: _confirm.text,
          );
      if (!success || !mounted) return;
      // Signup stores the account and returns to login. Email OTP remains an
      // explicit, separate login option on the sign-in screen.
      context.go('/login');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationProvider);
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Create dealer account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(width: 250, height: 90)),
                    const SizedBox(height: 18),
                    const Text(
                      'Register for wholesale access',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'After creating your account, sign in with your email and password. Email OTP is also available on the login page.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        counterText: '',
                      ),
                      onChanged: (_) => _clearSignupErrors(),
                      validator: (v) =>
                          RegExp(r'^\d{10}$').hasMatch((v ?? '').trim())
                          ? null
                          : 'Enter a 10-digit mobile number',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                      ),
                      onChanged: (_) => _clearSignupErrors(),
                      validator: (v) =>
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch((v ?? '').trim())
                          ? null
                          : 'Enter a valid email',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      maxLines: 2,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Business or delivery address (optional)',
                      ),
                      validator: (_) => null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _company,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Company Name (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _gst,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      maxLength: 15,
                      decoration: const InputDecoration(
                        labelText: 'GST Number (optional)',
                        counterText: '',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty || isValidGstin(value!)
                          ? null
                          : 'Enter a valid GST number',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: 'Use at least 8 characters',
                      ),
                      validator: (v) => (v ?? '').length >= 8
                          ? null
                          : 'Use at least 8 characters',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                      validator: (v) =>
                          v == _password.text ? null : 'Passwords do not match',
                    ),
                    if (_errorsInitialized &&
                        (state.errorMessage != null ||
                            auth.errorMessage != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          state.errorMessage ?? auth.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          _isSubmitting || state.isSubmitting || auth.isLoading
                          ? null
                          : _submit,
                      child:
                          _isSubmitting || state.isSubmitting || auth.isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.go('/login'),
                      child: const Text('Already have an account? Sign in'),
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
