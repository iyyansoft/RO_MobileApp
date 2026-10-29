const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('phone release helper requires HTTPS and refuses local backend defaults', () => {
  const script = fs.readFileSync('scripts/build-phone-release.ps1', 'utf8');
  assert.match(script, /Parameter\(Mandatory\s*=\s*\$true\)[\s\S]*\[string\]\$ApiBaseUrl/);
  assert.match(script, /Release builds require an HTTPS production API URL/);
  assert.match(script, /localhost.*127\.0\.0\.1.*10\.0\.2\.2/);
  assert.match(script, /private LAN API hosts/);
  assert.match(script, /Supabase project root does not implement this app/);
  assert.doesNotMatch(script, /192\.168\.137\.233/);
});
