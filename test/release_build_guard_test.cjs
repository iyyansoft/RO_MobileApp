const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('phone release helper requires HTTPS and refuses local backend defaults', () => {
  const script = fs.readFileSync('scripts/build-phone-release.ps1', 'utf8');
  // The default (when no -ApiBaseUrl is given) is the HTTPS Production API;
  // any value passed is still checked by the guards below.
  const defaultUrl = (script.match(/\[string\]\$ApiBaseUrl\s*=\s*'([^']*)'/) || [])[1];
  assert.equal(defaultUrl, 'https://ro-mobileapp.onrender.com');
  assert.match(script, /Release builds require an HTTPS production API URL/);
  assert.match(script, /localhost.*127\.0\.0\.1.*10\.0\.2\.2/);
  assert.match(script, /private LAN API hosts/);
  assert.match(script, /Supabase project root does not implement this app/);
  assert.doesNotMatch(script, /192\.168\.137\.233/);
});

test('phone release helper accepts the current dealer login policy and refuses older ones', () => {
  const script = fs.readFileSync('scripts/build-phone-release.ps1', 'utf8');
  // Must match /api/auth/config today: no admin approval, no email-verification step.
  assert.match(script, /\$policy\.requiresAdminApproval -ne \$false -or \$policy\.requiresEmailVerification -ne \$false/);
  assert.doesNotMatch(script, /requiresEmailVerification -ne \$true/);
  const server = fs.readFileSync('server.js', 'utf8');
  assert.match(server, /dealerPasswordLogin:\s*\{\s*requiresAdminApproval:\s*false,\s*requiresEmailVerification:\s*false\s*\}/);
});
