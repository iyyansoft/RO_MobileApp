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
flutter run --dart-define=API_BASE_URL=https://romobileapp-production.up.railway.app/api/
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
local backend at `http://10.0.2.2:8080/api/` by default. Pass
`-ApiBaseUrl https://romobileapp-production.up.railway.app/api/` when you
explicitly want the production API. Hardware virtualization and Windows
Hypervisor Platform must be available for acceleration.

Dealer and admin sessions are stored with Flutter Secure Storage. Admin tokens
are verified against the backend on restart. Spreadsheet import/export accepts
XLSX; product/category images can be picked from the device.

Native Google sign-in requires an Android OAuth client configured for the final
application ID and signing certificate. Checkout offers Cash on Delivery and
Razorpay. Set `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` in the server `.env`;
the secret never goes to Flutter. The server validates signatures and checks or
captures the matching payment with Razorpay before saving a paid order.

Configure `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME` for the
existing MySQL database. `AUTO_APPLY_SCHEMA=true` applies the additional GST,
OTP-attempt, and payment-session columns/tables on startup. Signup and checkout
require confirmed MySQL writes. Configure real `SMTP_*` credentials for email
OTP; failed email delivery never logs a user in. Codes expire in five minutes,
allow five attempts and are stored as hashes.

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
