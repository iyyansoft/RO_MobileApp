# Dealer password login verification — 2026-10-31

## Root cause

The running Android emulator used `https://ro-mobileapp.onrender.com/api/`.
Its actual `POST /api/auth/login` response was HTTP 403 with:

```text
Your dealer account is awaiting admin approval.
```

The deployed `/api/auth/config` returned only `googleClientId`, without the
current `dealerPasswordLogin` policy. Render is serving an older backend;
changing Flutter alone cannot fix this server rejection.

## Successful emulator test

Attached Flutter to the existing debug app and hot reloaded it. No APK was built.
Temporarily pointed its password request to `http://10.0.2.2:8081/api/`, serving
this workspace's Express backend with the configured PostgreSQL database.
Submitted the same email and password already entered in the emulator, without
reading or logging the password or changing database approval flags.

The backend logged:

```json
{"outcome":"authenticated","status":"pending","isApproved":false}
```

The emulator opened Home, showing Categories, Featured Wholesale Deals, and the
Home/Catalog/Orders/Profile navigation. Local evidence is saved in
`scratch/dealer-login-result.xml` and `scratch/dealer-login-home.png`.
The temporary login URL was removed from the source after this test. Production
remains the default; local debug runs use `scripts/run-android.ps1 -LocalBackend`.

## Regression checks

- 14 focused Node tests passed: account creation, saved bcrypt password,
  one-time email verification, pending dealer login/session restoration,
  invalid passwords, rejected/unverified accounts, and rejection of dealer
  tokens by admin and employee authorization.
- 14 additional Node tests passed: deployment configuration, Supabase session
  exchange, and Google identity verification.
- 19 Flutter tests passed: signup → email verification → password login → Home,
  wrong password rejection, OTP behavior, API URL normalization, and employee
  login/API handling.

## Production completion

Deploy the reviewed backend changes to the Render service while retaining its
existing production secrets. No approval backfill is needed. Confirm that
`/api/auth/config` reports `requiresAdminApproval: false` and
`requiresEmailVerification: true`, then repeat emulator login against Render.
`scripts/build-phone-release.ps1` now refuses to build against a backend that
does not expose this policy. The policy check is a deployment prerequisite;
it does not replace the actual production login test.

Production deployment and production login are still outstanding. The current
workspace has no Render deployment configuration or authenticated Render CLI.
