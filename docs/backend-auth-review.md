# Backend review: registration/login integration

Reviewed current uncommitted code in E:\Opaque\opaque-backend. No tests or migrations run.

Required corrections before deployment:
1. main.go getTrustedIdentity: VerifyIDTokenAndCheckRevoked errors fall back to VerifyIDToken. This accepts revoked but otherwise valid tokens. Fail closed; distinguish temporary verification outages from invalid credentials without bypassing revocation. Apply the intended revocation/disabled-account policy consistently to profile retrieval and authenticated HTTP/WebSocket entry points.
2. createProfileHandler existing-UID path updates display_name even when omitted (it defaults to the submitted username). Registration retries must return the existing profile without modifying it; keep profile edits separate.
3. getClientIP trusts any X-Forwarded-For/X-Real-IP. Accept forwarded addresses only from configured trusted proxies, otherwise use RemoteAddr. Add a verified-UID limit on profile creation where appropriate.
4. Same-UID concurrent creation can return username_taken/phone_taken from the prechecks or constraint handling before reaching the profiles_pkey branch. Reconcile conflicts against the authenticated UID and return that existing profile consistently.
5. Migration 002 is not transactional and adding the lower(username) index fails if existing case-colliding usernames exist. Add a non-destructive collision preflight and transactional migration. The fresh schema also needs the same case-insensitive uniqueness index.
6. Existing display_name is read into string in creation/retry paths although profile retrieval treats it as nullable. Use sql.NullString consistently. Truncate/validate display names by Unicode characters, not slicing UTF-8 bytes.

API contract used by the frontend:
- POST /profiles/check-username: {username}; 200 {available, reason?}; 429 for throttling.
- GET /profiles/me: 200 existing profile; 404 ONLY for missing profile; all other failures must not be treated as incomplete signup.
- POST /profiles/create: {username, displayName?}; verified identity/optional number are derived from Firebase. 201 created / 200 existing; JSON {error,message} on failures.
- POST /profile/avatar/update: {avatarUrl} after profile creation.

Keep current accounts and identifiers; no automatic cross-UID merges. Supply deployment/configuration notes. Frontend integration cannot make these backend issues safe.
