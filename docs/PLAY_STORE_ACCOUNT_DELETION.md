# Google Play Account Deletion — Jireta LMS

Last updated: 2026-11-01

This document covers the Google Play **account deletion** requirement:

* the public **Delete Account URL**,
* the in-app Delete Account flow,
* what is deleted versus retained,
* the Edge Function and database migration,
* deployment commands, secrets, testing, and the manual steps that remain.

The existing reviewer sign-in is documented separately in
`docs/PLAY_STORE_REVIEWER_ACCESS.md`.

---

## 1. Google Play Delete Account URL

**Use this exact URL in Play Console:**

```
https://www.jireta.com/delete-account
```

Where to enter it:

**Play Console → your app → App content → Data safety → Data deletion →
Delete account URL**

The same page is also reachable at
`https://jireta.vercel.app/delete-account` (preview origin), but Play Console
must use the production `www.jireta.com` URL.

The page:

* is public — no login, no app install, no JavaScript-only modal,
* works on desktop and mobile browsers,
* explains what is deleted and what is kept,
* collects the registered mobile number **or** email plus the full name,
* returns a reference number (`DEL-XXXXXXXXXX`) and a 7-business-day review
  window,
* never reveals whether the number/email belongs to an existing account
  (prevents account enumeration).

---

## 2. In-app deletion

**Lender:** Profile → General → **Delete Account**
**Rider:** Profile → General → **Delete Account**

The signed-in lender/rider can:

1. Read what will be deleted and what will be retained.
2. Type `DELETE` to confirm.
3. Tap **Delete my account**.

If the account has an **active or overdue loan**, the server returns
`409 OUTSTANDING_LOAN` and the account is not touched. The user must settle the
balance first. This is the only business block; pending/under-review/approved
applications are cancelled automatically.

Staff accounts (head manager / employee) see a notice that their account is
managed by HR and may submit a manual request instead.

---

## 3. What is deleted and what is retained

### Deleted

* `public.users` identity fields: name, email, mobile number, photo, FCM token
* `lender_profiles` / `rider_profiles` personal details (birth date, income,
  GCash number, employer, license, plate, address)
* `addresses`, `emergency_contacts`, `loan_emergency_contacts`
* `account_upgrade_documents` rows **and** their storage objects
* Profile photo in the `avatars` bucket
* `user_devices`, `notifications`, `user_mpins`
* `active_sessions`, `login_lockouts`, password history
* SMS notification logs, SMS/email OTP rows and lockouts, email-verification
  links, MPIN reset tokens
* Rider live location and location history
* GoTrue identity: `auth.identities`, `auth.sessions`, MFA factors; the
  `auth.users` row is anonymized, password cleared, and banned permanently

### Retained

* `loans`, `loan_schedules`
* `payments`, `payment_reversals`
* `disbursements`
* `collection_assignments`
* `credit_investigations` and CI documents
* Co-maker records attached to the retained loans
* `auth_logs` and `audit_logs`

These are financial, credit, and audit records that a Philippine lending
company must keep. They remain linked to the anonymized account id, not to the
person's name, number, or email. The retention period follows the company's
Data Retention Policy and applicable law.

> **Why `auth.users` is not deleted:** `auth.users.id` cascades to
> `public.users` → `lender_profiles` → `loans`. Hard-deleting the auth row
> would cascade-delete loan and payment history. The function therefore keeps
> the row, changes the email to a unique deleted placeholder, removes the
> phone, clears passwords/tokens/metadata, deletes identities/sessions, and
> sets `banned_until = infinity`.

---

## 4. Database migration

**New file:** `supabase/migrations/00195_account_deletion.sql`

It adds:

| Object | Purpose |
| --- | --- |
| `user_account_statuses` value `deleted` | Permanent account state |
| `users.account_deleted_at` | When the account was anonymized |
| `account_deletion_requests` | Public/manual request queue (service-role only, RLS with no policies) |
| `delete_user_account(uuid)` | One transaction: blockers, cancellation, cleanup, anonymization, auth scrub |

The function is `SECURITY DEFINER`, revoked from `PUBLIC`/`anon`/`authenticated`,
and granted only to `service_role`. It cannot be called from the app.

---

## 5. Edge Function

**New function:** `supabase/functions/account-delete/index.ts`

| `?fn=` | Auth | Caller | Purpose |
| --- | --- | --- | --- |
| `request` | none | public page | Validate identifier, rate-limit, create a `DEL-…` request |
| `delete-self` | JWT | lender/rider | Immediate deletion; requires `{"confirmation":"DELETE"}` |
| `list-requests` | head_manager | staff | Queue (`?status=pending|processing|completed|rejected|all`) |
| `process-request` | head_manager | staff | `approve` (runs deletion) or `reject` |

Supporting pure helpers live in
`supabase/functions/_shared/account_deletion.ts`; tests in
`supabase/functions/_shared/account_deletion.test.ts`.

`supabase/config.toml` sets `verify_jwt = false` for this function because
`?fn=request` is public; every protected path calls `requireAuth()` inside the
function, exactly like `auth-email-verify`.

---

## 6. Required Supabase secrets

No **new required** secret — the function uses the standard values that
Supabase injects:

| Secret | Source |
| --- | --- |
| `SUPABASE_URL` | Automatic |
| `SUPABASE_SERVICE_ROLE_KEY` | Automatic |
| `SUPABASE_ANON_KEY` | Automatic |

**Recommended:**

```bash
supabase secrets set ACCOUNT_DELETION_PEPPER="$(openssl rand -hex 32)"
```

`ACCOUNT_DELETION_PEPPER` is used only to hash the identifier/IP stored in
`account_deletion_requests` (duplicate detection). If it is unset, the function
falls back to `SUPABASE_SERVICE_ROLE_KEY`. Changing it later does not break
anything; it only means older request hashes will no longer match duplicates.

Existing CORS configuration must allow the production origin. The code already
includes `https://www.jireta.com` and `https://jireta.com` as built-ins, but if
`CORS_ALLOWED_ORIGINS` is set, include:

```bash
supabase secrets set CORS_ALLOWED_ORIGINS="https://www.jireta.com,https://jireta.vercel.app"
```

---

## 7. Deployment commands

```bash
# 1. Apply the migration (adds status/table/function; changes no existing rows)
supabase db push

# 2. Optional but recommended: stable hash pepper
supabase secrets set ACCOUNT_DELETION_PEPPER="$(openssl rand -hex 32)"

# 3. Deploy the function
supabase functions deploy account-delete

# 4. Tail logs during the first tests
supabase functions logs account-delete --tail
```

Local development:

```bash
supabase db reset
supabase functions serve account-delete --env-file supabase/.env
```

---

## 8. API examples

Set:

```bash
REF="<project-ref>"
BASE="https://$REF.supabase.co/functions/v1"
ANON="<anon-key>"
```

### Public request (this is what the Delete Account page calls)

```bash
curl -s -X POST "$BASE/account-delete?fn=request" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "09171234567",
    "full_name": "Juan Dela Cruz",
    "reason": "I no longer use the service"
  }'
```

Response:

```json
{
  "message": "Your deletion request has been received...",
  "reference": "DEL-1A2B3C4D5E",
  "review_window_days": 7,
  "duplicate": false
}
```

### Self-deletion (lender/rider JWT)

```bash
curl -s -X POST "$BASE/account-delete?fn=delete-self" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"confirmation":"DELETE","reason":"No longer needed"}'
```

Expected blockers:

| HTTP | Code | Meaning |
| --- | --- | --- |
| 409 | `OUTSTANDING_LOAN` | Active/overdue loan — settle first |
| 409 | `ALREADY_DELETED` | Account already deleted |
| 409 | `OPEN_COLLECTIONS` / `OPEN_CREDIT_INVESTIGATIONS` / `OPEN_DISBURSEMENTS` | Rider has open work |
| 403 | `ROLE_NOT_DELETABLE` | Staff account |
| 403 | `REVIEWER_NOT_ALLOWED` | Play reviewer account |

### Head Manager: list and process

```bash
curl -s -X POST "$BASE/account-delete?fn=list-requests&status=pending" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $HM_JWT"

curl -s -X POST "$BASE/account-delete?fn=process-request" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $HM_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "reference": "DEL-1A2B3C4D5E",
    "action": "approve",
    "notes": "Identity verified by calling the registered number"
  }'
```

Use `"action": "reject"` with `notes` when identity cannot be verified. A
rejected request is closed; the user must submit a new one.

---

## 9. Staff procedure for public requests

The page only **records** a request; it does not prove identity. Before
approving:

1. Open **Head Manager → Account Deletion** (or call
   `?fn=list-requests&status=pending`; the function is POST-only).
2. Compare the submitted full name with the account (`user_id` is already
   attached when the identifier matched).
3. Verify identity out-of-band — call the registered mobile number or reply to
   the registered email. Do not rely on the form alone.
4. Approve with a note describing the verification method, or reject.
5. If the account has an active/overdue loan, tell the user to settle it and
   leave the request pending (the endpoint returns `409 OUTSTANDING_LOAN`).

Useful SQL:

```sql
-- Pending queue
select reference, user_id, role, identifier_type, status, requested_at
from public.account_deletion_requests
where status in ('pending','processing')
order by requested_at;

-- Deleted accounts
select id, first_name, last_name, email, phone_number,
       account_status, account_deleted_at
from public.users
where account_status = 'deleted'
order by account_deleted_at desc;

-- Confirm PII is gone
select u.id, u.phone_number, u.email, lp.gcash_number, lp.monthly_income
from public.users u
left join public.lender_profiles lp on lp.id = u.id
where u.account_status = 'deleted';
```

The `phone_number` column must be `NULL`, `email` must be
`deleted+<uuid>@deleted.invalid`, and profile PII must be `NULL`.

---

## 10. Files created and modified

### Created

* `supabase/migrations/00195_account_deletion.sql`
* `supabase/functions/account-delete/index.ts`
* `supabase/functions/_shared/account_deletion.ts`
* `supabase/functions/_shared/account_deletion.test.ts`
* `lib/data/datasources/remote/account_deletion_remote_datasource.dart`
* `lib/presentation/features/account/screens/delete_account_screen.dart`
* `test/delete_account_screen_test.dart`
* `docs/PLAY_STORE_ACCOUNT_DELETION.md` (this file)

### Modified

* `supabase/config.toml` — `account-delete` function entry
* `lib/core/network/api_endpoints.dart` — `accountDeleteRequest`, `accountDeleteSelf`
* `lib/core/constants/route_constants.dart` — `/delete-account`
* `lib/core/router/app_router.dart` — public route + signed-in whitelist
* `lib/core/di/injection.dart` — datasource registration
* `lib/presentation/features/lender/profile/screens/lender_profile_screen.dart` — menu item
* `lib/presentation/features/rider/profile/screens/rider_profile_screen.dart` — menu item

---

## 11. Testing results

Run from the repository root unless noted.

| Check | Command | Result |
| --- | --- | --- |
| Deno type-check | `cd supabase && deno check functions/account-delete/index.ts functions/_shared/account_deletion.ts functions/_shared/account_deletion.test.ts` | **Passed** (only the pre-existing `allowJs` config warning) |
| Deno unit tests | `cd supabase && deno test --allow-read --allow-env functions/_shared/account_deletion.test.ts` | **10 passed, 0 failed** |
| Dart analyze | `dart analyze` on the changed Flutter files + test | **No issues found** |
| Flutter widget/source test | `flutter test test/delete_account_screen_test.dart` | **4 passed** |

Covered by the Deno tests: outstanding vs cancellable loan statuses, PH mobile
normalization (`09…`, `+63…`, `63…`, `9…`), email normalization, rejection of
landline/blank input, masking, reference format, reason sanitization, hash
determinism, RPC result defaults.

Covered by the Flutter test: the page renders publicly without a session, the
request form validates, a signed-in lender sees instant deletion, and the
route/endpoint/router wiring is present.

The migration and `delete_user_account` were also executed against an
in-memory Postgres (PGlite) with a representative schema. Assertions passed
for: lender PII/auth scrub, active-loan and open-collection blockers,
pending-loan cancellation, rider plate/license/address scrub, staff-role
rejection, and double-delete rejection. The temporary harness was removed
after the run because the repository has no database-test harness.

**Not run in this environment:**

* The SQL migration against a real Postgres/Supabase instance. Docker was not
  running (`docker ps` could not reach the daemon) and no project credentials
  were available, so the migration was **not executed** here.
* Live calls to the deployed Edge Function.
* End-to-end deletion of a disposable account.

These must be run after `supabase db push` / `supabase functions deploy` using
the smoke tests in §8. Do not claim the production flow is verified until
those pass.

---

## 12. Manual steps still required

1. **Apply the migration**: `supabase db push`.
2. **Deploy** `account-delete`: `supabase functions deploy account-delete`.
3. **Set the pepper** (recommended): `supabase secrets set ACCOUNT_DELETION_PEPPER=...`,
   then redeploy so warm isolates pick it up.
4. **Smoke-test the public endpoint** with a disposable identifier (curl in
   §8). Confirm a `DEL-…` reference is returned and a row appears in
   `account_deletion_requests`.
5. **Smoke-test in-app deletion** with a disposable lender account that has no
   loan. Confirm: success response, row becomes `account_status='deleted'`,
   phone/email are anonymized, `auth.identities`/sessions are gone, and the old
   number can be used to register a new account.
6. **Test the blocker**: create a disposable account with an `active` loan and
   confirm `409 OUTSTANDING_LOAN` (no PII is removed).
7. **Check storage**: `avatars` profile photo and
   `account-upgrade-documents/account-upgrade/<userId>/…` objects are removed;
   inspect the `files` field in the response.
8. **Play Console**: enter `https://www.jireta.com/delete-account` under
   **App content → Data safety → Data deletion**, and complete the Data safety
   form consistently (account + data deletion, retained financial records).
9. **Check the live page** in a private browser window at
   `https://www.jireta.com/delete-account` (no login) and on a phone. Vercel
   already rewrites unknown paths to `index.html`, so the Flutter route loads
   directly.
10. **Operational process**: assign someone to review **Head Manager →
    Account Deletion** at least weekly. The screen lists pending requests,
    lets staff approve (after the identity-verification checkbox) or reject,
    and shows completed/rejected history. The documented
    `?fn=list-requests` / `?fn=process-request` API remains available for
    automation.
11. **Retention review**: confirm the company's Data Retention Policy matches
    §3 (financial records kept, identity removed) and that support staff know
    not to promise immediate deletion of loan records.

---

## 13. Rollback / disable

* Remove the Play Console Delete Account URL and change the Data safety answer
  if the page must be taken down.
* Remove the in-app menu items / `/delete-account` route if the feature must be
  hidden.
* Deleting the Edge Function and dropping
  `public.account_deletion_requests` + `public.delete_user_account` stops new
  processing. It **cannot restore** accounts already deleted.
* Do **not** drop the `deleted` lookup value or `users.account_deleted_at` while
  deleted accounts exist; `users.account_status` references the lookup.

---

## 14. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Public page returns `404` on Vercel | Check the rewrite in `vercel.json` and that the build contains the route; open `/privacy-policy` as a control. |
| `401 UNAUTHORIZED_ANON_TOKEN` on `delete-self` | The request was sent without a user JWT. Sign in again. |
| `400 CONFIRMATION_REQUIRED` | The confirmation field was not exactly `DELETE`. |
| `409 OUTSTANDING_LOAN` | Expected. Settle/reverse the active or overdue loan first. |
| `500 DELETION_FAILED` | Check `supabase functions logs account-delete` and the Postgres error. The transaction rolls back, so no partial deletion. |
| Public request never processed | There is no automatic worker; staff must approve it. See §9. |
| Storage warning after success | DB deletion succeeded; remove the listed object manually with the Storage API/dashboard and investigate the bucket policy. |
| Reviewer account cannot be deleted | Intentional — keeps Play Console credentials working. |
