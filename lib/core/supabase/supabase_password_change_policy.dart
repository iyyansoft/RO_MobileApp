/// Applies a password change only after re-authenticating the same identity.
///
/// Keeping the callbacks injectable lets this security-sensitive sequencing be
/// tested without a live Supabase project or real credentials.
Future<void> changePasswordAfterReauthentication({
  required String email,
  required String expectedUserId,
  required String currentPassword,
  required String newPassword,
  required Future<String?> Function(String email, String password)
  reauthenticate,
  required Future<void> Function(String password) updatePassword,
}) async {
  final normalizedEmail = email.trim().toLowerCase();
  if (normalizedEmail.isEmpty || expectedUserId.isEmpty) {
    throw StateError('A signed-in account is required to change the password.');
  }
  if (currentPassword.isEmpty || newPassword.length < 8) {
    throw StateError(
      'Enter the current password and a new password of at least 8 characters.',
    );
  }

  final authenticatedUserId = await reauthenticate(
    normalizedEmail,
    currentPassword,
  );
  if (authenticatedUserId != expectedUserId) {
    throw StateError('The signed-in account changed. Sign in again and retry.');
  }

  await updatePassword(newPassword);
}
