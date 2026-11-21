# Android release signing (company-owned key)

The signing key proves every future update comes from the company. Google Play
only accepts updates signed by the same key, so it must be **owned by the company,
backed up, and never stored in this repository**.

What the project already does (`android/app/build.gradle.kts`):

* Reads the key from a `key.properties` file at the path in the environment variable
  `NEEROPLUS_KEY_PROPERTIES` (recommended: a folder outside the repository), or from
  `android/key.properties` (git-ignored, with `*.jks` / `*.keystore`).
* `flutter build appbundle --release` **refuses to build** without that key, so a
  debug-signed bundle can never be uploaded by mistake.
* Without the key, `flutter build apk --release` still works for emulator/internal
  testing and prints a warning; such APKs are signed with the Android debug key.

Verified 2026-11-21 with a throw-away test key (deleted afterwards): AAB refused
without a key; AAB signed by the key from `key.properties`; APK without a key is
debug-signed; `git status` shows no signing files.

## 1. Create the upload key (company owner, once)

Do this on a trusted company computer, signed in as the owner (not a shared account).

1. Create a private folder outside the repository, e.g. `C:\NeeroPlusSigning\`
   (right-click > Properties > Security: only the owner and Administrators).
2. Generate two strong random passwords (password manager). PKCS12 keystores use one
   password for the store and the key, so use the same value for both.
3. Run (JDK `keytool`, e.g. `C:\Users\<you>\AppData\Local\ROAndroidJava\jdk-21...\bin\keytool.exe`):

   ```
   keytool -genkeypair -v -keystore C:\NeeroPlusSigning\neeroplus-upload.jks ^
     -storetype PKCS12 -alias upload -keyalg RSA -keysize 2048 -validity 10000 ^
     -dname "CN=<Company legal name>, O=<Company legal name>, L=<City>, ST=Tamil Nadu, C=IN"
   ```

   Enter the password when asked (do not put it on the command line).
4. Create `C:\NeeroPlusSigning\key.properties`:

   ```
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=C:/NeeroPlusSigning/neeroplus-upload.jks
   ```

5. Record the certificate fingerprint (safe to share, used to confirm the right key):
   `keytool -list -v -keystore C:\NeeroPlusSigning\neeroplus-upload.jks -alias upload`

## 2. Back it up

* Store `neeroplus-upload.jks` **and** its password in the company password manager
  (attachment + password entry), owned by the company account, shared only with the
  people who publish releases.
* Keep one offline copy (encrypted USB drive) in a locked place. Test the backup once
  by listing the key from the copy (step 1.5).
* Never email it, never put it in GitHub, Google Drive shared folders, WhatsApp or the
  project folder.

## 3. Google Play App Signing (recommended)

In Play Console create the app, then enrol in **Play App Signing**: Google keeps the
app-signing key and our keystore becomes the *upload key*. If the upload key is ever
lost or leaked, the account owner can request an upload-key reset from Google instead
of losing the ability to update the app.

## 4. Build the release bundle (after approval only)

```
set NEEROPLUS_KEY_PROPERTIES=C:\NeeroPlusSigning\key.properties
flutter build appbundle --release --dart-define=API_BASE_URL=https://ro-mobileapp.onrender.com
```

Output: `build\app\outputs\bundle\release\app-release.aab`. Check the signer:
`keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab`
(must show the company certificate, not "Android Debug").

* Raise `version:` in `pubspec.yaml` for every upload (e.g. `1.0.1+2`; the number after
  `+` must always increase).
* Package name `com.rowholesale.ro_wholesale_dealer_app` is permanent once published.
* The app targets Android API 36. Play Console will ask for declarations for the NFC
  and phone-state permissions added by plugins.
* Anyone who installed a debug-signed test APK must uninstall it before installing a
  company-signed build (different signatures cannot update each other).
