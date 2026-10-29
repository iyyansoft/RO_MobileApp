import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class ApprovalStatusScreen extends ConsumerWidget {
  const ApprovalStatusScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Account status')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                user == null ? Icons.lock_outline : Icons.verified_user,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                user == null
                    ? 'Sign in to view your account'
                    : 'Status: ${user.status}',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (user != null) Text(user.email),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    context.go(user == null ? '/login' : '/profile'),
                child: Text(user == null ? 'Sign in' : 'Back to profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
