const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const adapter = fs.readFileSync(
  path.join(root, 'lib/core/supabase/supabase_auth_adapter.dart'),
  'utf8',
);
const policy = fs.readFileSync(
  path.join(root, 'lib/core/supabase/supabase_password_change_policy.dart'),
  'utf8',
);
const profile = fs.readFileSync(
  path.join(root, 'lib/features/profile/presentation/screens/profile_screen.dart'),
  'utf8',
);

test('password change requires a verified Supabase session and reauthenticates its identity', () => {
  const start = adapter.indexOf('Future<void> changePassword({');
  const end = adapter.indexOf('Future<Map<String, dynamic>> restoreDealerSession()', start);
  assert.ok(start >= 0 && end > start, 'Supabase password change adapter exists');
  const method = adapter.slice(start, end);
  assert.match(method, /currentSession/);
  assert.match(method, /emailConfirmedAt/);
  assert.match(method, /expectedEmail\.trim\(\)\.toLowerCase\(\)/);
  assert.match(method, /signInWithPassword/);
  assert.match(method, /expectedUserId:\s*user\.id/);
  assert.match(method, /updateUser\(UserAttributes\(password:\s*password\)\)/);
});

test('password update occurs only after successful same-user reauthentication', () => {
  const reauth = policy.indexOf('final authenticatedUserId = await reauthenticate(');
  const identityCheck = policy.indexOf('if (authenticatedUserId != expectedUserId)', reauth);
  const update = policy.indexOf('await updatePassword(newPassword)', identityCheck);
  assert.ok(reauth >= 0 && identityCheck > reauth && update > identityCheck);
  assert.match(policy, /currentPassword\.isEmpty \|\| newPassword\.length < 8/);
});

test('Profile uses Supabase password change only with the opt-in Auth session and retains Express fallback', () => {
  const start = profile.indexOf('Future<void> _changePassword(UserModel user)');
  const end = profile.indexOf('Future<void> _supportTicket(UserModel user)', start);
  assert.ok(start >= 0 && end > start);
  const method = profile.slice(start, end);
  assert.match(method, /SupabaseConfig\.authEnabled/);
  assert.match(method, /currentSession != null/);
  assert.match(method, /SupabaseAuthAdapter\(\)\.changePassword/);
  assert.match(method, /_post\('user\/change-password', result\)/);
});
