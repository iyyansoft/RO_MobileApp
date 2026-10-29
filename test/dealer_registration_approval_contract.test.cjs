const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

test('successful client signup keeps the submitted dealer pending until admin approval', () => {
  const provider = fs.readFileSync(
    path.join(root, 'lib/features/auth/presentation/providers/registration_provider.dart'),
    'utf8',
  );
  const submittedScreen = fs.readFileSync(
    path.join(root, 'lib/features/auth/presentation/screens/registration_submitted_screen.dart'),
    'utf8',
  );
  assert.match(provider, /status:\s*ApprovalStatus\.pending/);
  assert.doesNotMatch(provider, /status:\s*ApprovalStatus\.approved/);
  assert.match(submittedScreen, /pending administrator approval/i);
  assert.doesNotMatch(submittedScreen, /is approved for dealer access/i);
});
