# Authentication frontend integration

## Implemented flows
- Phone: phone + username, Firebase SMS verification, optional profile, existing initialization/Home.
- Email: email + password + username, mandatory email verification, optional profile, Home.
- Google: Firebase Google sign-in; existing backend profiles continue, new profiles confirm a suggested username then optional profile.
- Existing login uses the selected method and does not overwrite profile data. Phone sign-in can create a new Firebase identity; absent backend profiles are routed through username setup.
- Startup resumes unverified email and incomplete profiles. Only the backend's profile_not_found response starts registration; failures show retry.
- Username checks are advisory; final conflicts from server creation return to username confirmation.
- Optional profile uploads follow the current avatars/<random UUID> storage layout. Failed avatar saving can be retried or skipped after account creation.
- Authentication UI uses System by default, with persisted Light/Dark overrides, and the approved Opaque design.

## Runtime prerequisites and open dependencies
- Deploy the reviewed backend changes and apply its safe optional-phone/username migration first. Do not run the migration from the frontend.
- Resolve the backend review findings before calling this production-ready. Review notes: D:\DevTools\Opaque-Work\backend-auth-review.md.
- Firebase Phone, Email/Password and Google providers must be enabled. Android signing fingerprints, SMS region/billing settings and web authorized domains must match the deployment.
- Existing Firebase Storage rules must allow the authenticated user's avatar upload to the current avatars/ path; do not loosen access rules globally.
- AppConfig.baseUrl must point to the intended server. No deployment configuration or secrets were changed.
- Passkeys, reporting, account linking and new recovery workflows are outside this change.
- Legacy registration screen files remain unreferenced by the active entry flow; concurrent edits to those files were preserved.

## Validation scope
Targeted source/API review and Dart formatting only. No analyzer, automated tests, APK build, live signup, SMS request or database migration was run by this task, per the user's instruction. Device verification still needs the user's manual build and provider-backed checks.
