import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_auth_adapter.dart';
import 'package:ro_wholesale_dealer_app/core/supabase/supabase_password_change_policy.dart';
import 'package:ro_wholesale_dealer_app/features/profile/presentation/screens/profile_screen.dart';

void main() {
  test(
    'Supabase Auth adapter and Profile screen compile for the password path',
    () {
      expect(const SupabaseAuthAdapter(), isA<SupabaseAuthAdapter>());
      expect(const ProfileScreen(), isA<ProfileScreen>());
    },
  );

  group('changePasswordAfterReauthentication', () {
    test('normalizes email and updates only after the same identity reauthenticates', () async {
      final calls = <String>[];
      await changePasswordAfterReauthentication(
        email: ' Dealer@Example.com ',
        expectedUserId: 'dealer-1',
        currentPassword: 'current-password',
        newPassword: 'replacement-password',
        reauthenticate: (email, _) async {
          calls.add('reauth:$email');
          return 'dealer-1';
        },
        updatePassword: (_) async {
          calls.add('update');
        },
      );

      expect(calls, ['reauth:dealer@example.com', 'update']);
    });

    test(
      'does not update if reauthentication resolves to another identity',
      () async {
        var updated = false;
        await expectLater(
          changePasswordAfterReauthentication(
            email: 'dealer@example.com',
            expectedUserId: 'dealer-1',
            currentPassword: 'current-password',
            newPassword: 'replacement-password',
            reauthenticate: (_, __) async => 'dealer-2',
            updatePassword: (_) async {
              updated = true;
            },
          ),
          throwsA(isA<StateError>()),
        );
        expect(updated, isFalse);
      },
    );

    test('does not update when reauthentication fails', () async {
      var updated = false;
      await expectLater(
        changePasswordAfterReauthentication(
          email: 'dealer@example.com',
          expectedUserId: 'dealer-1',
          currentPassword: 'wrong-password',
          newPassword: 'replacement-password',
          reauthenticate: (_, __) async => throw StateError('invalid login'),
          updatePassword: (_) async {
            updated = true;
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(updated, isFalse);
    });

    test(
      'rejects weak or missing credentials before reauthentication',
      () async {
        var reauthenticated = false;
        await expectLater(
          changePasswordAfterReauthentication(
            email: 'dealer@example.com',
            expectedUserId: 'dealer-1',
            currentPassword: '',
            newPassword: 'short',
            reauthenticate: (_, __) async {
              reauthenticated = true;
              return 'dealer-1';
            },
            updatePassword: (_) async {},
          ),
          throwsA(isA<StateError>()),
        );
        expect(reauthenticated, isFalse);
      },
    );
  });
}
