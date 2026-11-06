# RO Wholesale Flutter app

The Flutter client in `lib/` covers dealer registration, email OTP/password login,
catalog search/filter/sort, cart, checkout, order history, profile, addresses,
password changes, rewards, GST invoice information, support tickets, and admin
catalog/dealer/order management. The existing Node/MySQL service remains the
backend. `web_preview/` preserves the original web client.

## Development

Use Flutter 3.47.6 or newer. This workstation's SDK is installed at
`%LOCALAPPDATA%\FlutterSDK\source`; its `bin` directory is on the user PATH.
Open a new terminal to pick up PATH changes. Android SDK and emulator commands
are also on the user PATH. Java 21 is installed in `%LOCALAPPDATA%\ROAndroidJava`.

Run:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=https://ro-mobileapp.onrender.com
```

To use the local backend on an Android emulator:

```powershell
npm start
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/
```

Check the server's configured port before running; the emulator's `10.0.2.2`
address reaches the Windows host. Backend secrets belong in `.env`, never in Dart
defines or app assets. Do not bundle Node, MySQL, or database backups in the app.

`scripts/setup-android.ps1` installs Android SDK packages and creates the
`RO_Dealer_API_36` virtual device after Java and command-line tools
are installed. `scripts/run-android.ps1` starts it and runs the app against the
deployed backend at `https://ro-mobileapp.onrender.com` by default. Pass
`-ApiBaseUrl http://10.0.2.2:8080/api/` only when you explicitly run a local
backend on port 8080. Hardware virtualization and Windows
Hypervisor Platform must be available for acceleration.

Dealer and admin sessions are stored with Flutter Secure Storage. Admin tokens
are verified against the backend on restart. Spreadsheet import/export accepts
XLSX; product/category images can be picked from the device.

Native Google sign-in requires an Android OAuth client configured for the final
application ID and signing certificate. Checkout offers Cash on Delivery and
Razorpay. Set `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` in the server `.env`;
the secret never goes to Flutter. The server validates signatures and checks or
captures the matching payment with Razorpay before saving a paid order.

Configure the server-only `SUPABASE_DB_URL` and verified PostgreSQL TLS settings
from `.env.example`. Signup and OTP verification require confirmed PostgreSQL
writes. OTPs expire after five minutes, allow five attempts, and are stored as
HMAC hashes. Successful verification preserves the password sign-in flow.

Dealer sign-in flow: create account, verify the email OTP, then sign in with the
registered email and password to open Home. `status=pending` and
`is_approved=false` do not block this login. The server compares the password
against the saved PostgreSQL bcrypt hash; unverified and rejected accounts stay
blocked. Dealer tokens do not grant admin or shop employee permissions.
Deploy the updated `server.js` to Render as well as distributing the rebuilt
APK: an APK update alone cannot remove an approval gate in an older backend.
Deploy the complete reviewed backend commit, including `email_provider.js`,
`package.json`, and `package-lock.json`; retain existing Render secrets and
database settings. Use Render's deployment branch, build with `npm ci`, and
start with `npm start`. No approval backfill or database migration is needed.
After deployment, `GET /api/auth/config` must report
`dealerPasswordLogin.requiresAdminApproval=false` and
`dealerPasswordLogin.requiresEmailVerification=true`. A missing field means
this diagnostic is not deployed; it does not establish the older policy.

To debug existing dealer login locally, first run `$env:PORT='8081'` and
`npm start` in a terminal at the project root. In a second terminal run
`./scripts/run-android.ps1 -LocalBackend`. This starts a debug app against
`http://10.0.2.2:8081/api/` and refuses to proceed if the local backend is absent
or its policy still requires approval. Enter the existing credentials directly
in the emulator. Verify the backend's sanitized `[DEALER LOGIN]` result and that
Home opens before building a release. Existing email verification and rejected
account checks remain enforced; do not change database flags to make a test pass.

On Render Free, outbound SMTP ports 25, 465 and 587 are blocked. Configure
`BREVO_API_KEY`, `BREVO_SENDER_EMAIL` (a verified sender/domain), and optionally
`BREVO_SENDER_NAME` in Render Environment to send through HTTPS. Existing SMTP
support remains available on hosts that allow SMTP, with certificate validation.
See [Render restrictions](https://render.com/docs/free).

After deployment, run `node test_smtp.js` in Render Shell for a configuration-only
check; it prints provider/configuration status without secrets or sending mail.
To explicitly send a non-login smoke-test email to a test inbox, run
`node test_smtp.js --send-to <test-recipient>`. Provider acceptance does not prove
inbox delivery: check the provider's delivery events, sender verification,
suppression list, and the recipient's spam folder.

When `USE_SUPABASE_AUTH=true`, Auth sends mail using **Supabase's** email settings,
independently of Render's email provider. Configure its custom email delivery and
put `{{ .Token }}` in the Confirm Signup and Magic Link email templates to match
the app's six-digit form. Signup reuses the confirmation already sent by Auth
instead of immediately sending a second email. See
[Supabase email templates](https://supabase.com/docs/guides/auth/auth-email-templates).

Home and Product Details display Dealer Price. Native shared image cards and
their accompanying text display MRP only. Checkout supports With GST (GSTIN
format/checksum required and prefilled from signup) and Without GST (zero GST).

The fresh local catalog contains six categories with three sample products each.
The active RO database is `ro_wholesale_db` in the isolated Docker container
`ro-wholesale-mysql-20261009-133949`, bound to `127.0.0.1:3307`. Its persistent
volume is `ro-wholesale-data-20261009-133949`; do not remove that volume. Windows
MySQL80 on port 3306 and its databases were left unchanged. Start Docker Desktop
before the backend; the container restarts automatically, or start it explicitly:

```powershell
docker start ro-wholesale-mysql-20261009-133949
npm start
```

Original app data and configuration were copied and SHA-256 verified before
replacement in `C:\Users\priya\AppData\Local\ROMySQLRecovery\fresh-reset-20261009-133949`.
This protected folder contains secrets and historical data; do not commit or
share it. Active dealers and orders start empty, and cached dealer sessions are
validated against the current backend before restoring a profile. Existing admin
credentials are preserved. Register a new dealer through Signup to use checkout.
