# Android release signing (company-owned key)

The signing key proves every future update comes from the company. Google Play only
accepts updates signed with the same (upload) key, so it must be **owned by the company,
backed up, and never stored in this repository or sent anywhere**.

What the project does (`android/app/build.gradle.kts`):

* Reads `key.properties` from the path in `NEEROPLUS_KEY_PROPERTIES` (outside the
  repository) or `android/key.properties` (git-ignored, like `*.jks` / `*.keystore`).
* The keystore password comes from `NEEROPLUS_KEYSTORE_PASSWORD`, set only for the
  build by `scripts/build-release-aab.ps1`, so `key.properties` contains **no password**.
* `flutter build appbundle --release` **refuses** to build without the company key, so a
  debug-signed bundle can never reach Play. Test APKs without the key stay debug-signed.

Verified 2026-11-21 with a throw-away TEST key (deleted afterwards): key created in a
private folder, `key.properties` without password, second run and in-repo folder refused,
AAB refused without a key and for a non-HTTPS/emulator API, AAB signed by the new key
with matching fingerprint, nothing uploaded.

## 1. Before you start

* A trusted company Windows PC, signed in with the owner's own account.
* The company password manager open (e.g. Bitwarden/1Password business vault owned by
  the company account, not a personal account).
* An encrypted USB drive (BitLocker To Go) for the offline copy.

## 2. Create the key (once)

1. In the password manager, create an entry **"NeeroPlus Android upload key"** and let it
   generate a password of 24+ random characters. Save the entry.
2. In PowerShell in the project folder run:

   ```
   powershell -ExecutionPolicy Bypass -File scripts\create-signing-key.ps1 -CompanyName "<Company legal name>" -City "<City>"
   ```

   Paste the password twice when asked (it is never shown or saved to disk). The script:
   * creates `C:\NeeroPlusSigning\` readable only by you, SYSTEM and Administrators
     (it refuses a folder inside any Git repository and never overwrites an existing key);
   * creates `neeroplus-upload.jks` (RSA 2048, ~27 years) and `key.properties` (no password);
   * prints the certificate **SHA256** fingerprint.
3. Copy the SHA256 fingerprint into the password-manager entry.

## 3. Back it up (same day)

1. Attach `C:\NeeroPlusSigning\neeroplus-upload.jks` to the password-manager entry.
2. Copy the `.jks` to the encrypted USB drive; keep it locked away (not with the PC).
   Check the copy opens: `keytool -list -keystore E:\neeroplus-upload.jks -alias upload`
   (asks for the password; the fingerprint must match).
3. Share the entry only with the people who publish releases. Never email, WhatsApp,
   Drive-share or commit the `.jks`, `key.properties` or the password.
4. If the PC is replaced: restore the `.jks` from the vault into a new private folder and
   create `key.properties` with `keyAlias=upload` and `storeFile=<path to .jks>`.

## 4. Google Play App Signing (recommended)

Create the app in Play Console and enrol in **Play App Signing**: Google keeps the
app-signing key; our key is the *upload key*. If it is ever lost or leaked, the account
owner can ask Google for an upload-key reset instead of losing the app.

## 5. Build the bundle (only after approval)

```
powershell -ExecutionPolicy Bypass -File scripts\build-release-aab.ps1
```

It asks for the password, builds with the production API
(`https://ro-mobileapp.onrender.com`, refuses anything else), checks the bundle is signed
by the company certificate (refuses the debug key), copies it to
`%USERPROFILE%\ro_mobile_build\release\NeeroPlus-<version>.aab` and prints the signer,
fingerprint and file SHA-256. It uploads nothing.

* Before each Play upload raise `version:` in `pubspec.yaml` (e.g. `1.0.1+2`; the number
  after `+` must always increase).
* Package name `com.rowholesale.ro_wholesale_dealer_app` is permanent once published.
* Target API 36. Play Console will ask for declarations for the NFC and phone-state
  permissions added by plugins.
* Anyone with a debug-signed test APK must uninstall it before installing a
  company-signed build (different signatures cannot update each other).
