# Google Play Reviewer Access — Jireta LMS

Last updated: 2026-11-01

This document covers the dedicated Google Play Store reviewer accounts, the
server-side reviewer sign-in flow, the exact Play Console details, and the
security guarantees.

---

## 1. What this adds

| Piece | Purpose |
| --- | --- |
| `supabase/functions/auth-reviewer` | `POST auth-reviewer?fn=login` — password-based reviewer sign-in. No SMS, no OTP, no expiry. Disabled by default. |
| `supabase/functions/_shared/reviewer.ts` | Server-side allowlist, constant-time password check, reviewer session flag, `requireNonReviewer` financial guard. |
| `scripts/setup_reviewer_accounts.ts` | Idempotent provisioning of the two reviewer `auth.users` + `public.users` + profile + MPIN. |
| `supabase/migrations/00194_reviewer_login.sql` | Allows `reviewer_login` / `reviewer_login_failed` in `auth_logs`. |
| `lib/presentation/features/auth/screens/reviewer_login_screen.dart` | Reviewer sign-in form (phone + password). Reachable only through a hidden 7-tap gesture on the login footer. |
| Money-moving Edge Functions | Return `403 REVIEWER_NOT_ALLOWED` for reviewer sessions. |

**Blast radius:** when `REVIEWER_LOGIN_ENABLED` is unset/false, `auth-otp`,
`auth-mpin`, and the financial functions behave exactly as before. The new
checks only match the configured reviewer phone numbers or the
`app_metadata.reviewer` flag.

---

## 2. Reviewer accounts

Two dedicated accounts are provisioned. The phone numbers are synthetic test
numbers — **no SMS is ever sent to them**.

| Role | Mobile number | Password | MPIN |
| --- | --- | --- | --- |
| Lender (borrower) | `09000000101` | value of `REVIEWER_LENDER_PASSWORD` (set by you, see §3) | `2468` |
| Rider | `09000000102` | value of `REVIEWER_RIDER_PASSWORD` (set by you, see §3) | `2468` |

> **Why the password is not written here:** committing a live reviewer password
> to the repository would defeat the requirement that reviewer credentials live
> only in Supabase Edge Function secrets. The "exact" password is the one you
> generate in §3 and paste into both the Supabase secret and Play Console. It is
> reusable for the whole review period — nothing expires.
>
> If you change a reviewer password later, update the Supabase secret **and**
> Play Console, then re-run the setup script (§3, step 4).

---

## 3. One-time setup

### Step 1 — generate two strong passwords

```bash
openssl rand -base64 18   # lender password
openssl rand -base64 18   # rider password
```

Use 16+ characters. Do not reuse an app user password.

### Step 2 — store the reviewer configuration in Supabase secrets

```bash
supabase secrets set \
  REVIEWER_LOGIN_ENABLED=true \
  REVIEWER_LENDER_PHONE=09000000101 \
  REVIEWER_LENDER_PASSWORD='<lender password from step 1>' \
  REVIEWER_RIDER_PHONE=09000000102 \
  REVIEWER_RIDER_PASSWORD='<rider password from step 1>'
```

The function fails closed: without all four values **and**
`REVIEWER_LOGIN_ENABLED=true`, the endpoint returns `404 Not found` and the
reviewer screen cannot sign in.

### Step 3 — apply the database migration

```bash
supabase db push
```

This applies `00194_reviewer_login.sql`. It only widens the `auth_logs`
`event_type` CHECK constraint; it does not touch users, loans, or payments.

### Step 4 — provision the two accounts

Dry-run first (prints what it would do, writes nothing):

```bash
SUPABASE_URL="https://<project-ref>.supabase.co" \
SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
REVIEWER_LENDER_PHONE="09000000101" \
REVIEWER_LENDER_PASSWORD="<lender password>" \
REVIEWER_LENDER_NAME="Google Play Reviewer Lender" \
REVIEWER_RIDER_PHONE="09000000102" \
REVIEWER_RIDER_PASSWORD="<rider password>" \
REVIEWER_RIDER_NAME="Google Play Reviewer Rider" \
REVIEWER_MPIN="2468" \
deno run --allow-net --allow-env scripts/setup_reviewer_accounts.ts
```

Then run the same command with `--apply` at the end.

The script is idempotent and:

* creates/updates the Supabase Auth user (phone + `@jireta.temp` credential),
* sets `app_metadata.reviewer = true` and `reviewer_role` (service-role only),
* creates the `public.users`, `lender_profiles`/`rider_profiles` rows,
* sets MPIN `2468` in `user_mpins`,
* clears stale sessions/OTP lockouts for those numbers.

### Step 5 — deploy

```bash
supabase functions deploy auth-reviewer
supabase functions deploy auth-otp auth-mpin \
  payments-xendit-link payments-manage collections-manage \
  disbursements-gcash disbursements-select disbursements-delivery
```

`config.toml` already sets `verify_jwt = false` for `auth-reviewer` (it is the
login endpoint; the function verifies credentials itself).

> If you changed secrets **after** deploying, redeploy `auth-reviewer` so warm
> isolates pick up the new environment values.

### Step 6 — verify the provisioned accounts

```bash
SUPABASE_URL="https://<project-ref>.supabase.co" \
SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
SUPABASE_ANON_KEY="<anon-key>" \
REVIEWER_LENDER_PHONE="09000000101" \
REVIEWER_LENDER_PASSWORD="<lender password>" \
REVIEWER_RIDER_PHONE="09000000102" \
REVIEWER_RIDER_PASSWORD="<rider password>" \
 deno run --allow-net --allow-env scripts/check_reviewer_accounts.ts
```

Every line must say `OK`; exit code `1` means a check failed. This is the
fastest way to see whether the account is missing, not flagged as a reviewer,
or the secret password differs from the GoTrue credential.

### Step 7 — smoke test (optional but recommended)

Replace `<anon-key>` and `<project-ref>`. Disabled state first:

```bash
# With REVIEWER_LOGIN_ENABLED unset -> 404
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  "https://<project-ref>.supabase.co/functions/v1/auth-reviewer?fn=login" \
  -H "apikey: <anon-key>" -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"phone":"09000000101","password":"whatever"}'
```

With the secrets set:

```bash
# Wrong password -> 401 REVIEWER_LOGIN_FAILED
curl -s -X POST \
  "https://<project-ref>.supabase.co/functions/v1/auth-reviewer?fn=login" \
  -H "apikey: <anon-key>" -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"phone":"09000000101","password":"wrong"}'

# Correct credentials -> 200 with access_token + refresh_token + reviewer:true
curl -s -X POST \
  "https://<project-ref>.supabase.co/functions/v1/auth-reviewer?fn=login" \
  -H "apikey: <anon-key>" -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"phone":"09000000101","password":"<lender password>"}'
```

An ordinary user's phone must always return `401 REVIEWER_LOGIN_FAILED`.

---

## 4. Exact Google Play Console sign-in details

Play Console accepts one username/password per instruction set, so add **two**
instruction sets (one per role):

**Play Console → your app → App content → App access → Manage →**
**"All or some functionality is restricted" → Add new instructions.**

### Instruction set 1 — Lender

| Field | Value |
| --- | --- |
| Name | `Jireta Loans — Lender reviewer` |
| Username | `09000000101` |
| Password | the value of `REVIEWER_LENDER_PASSWORD` |
| Instructions | see below |

### Instruction set 2 — Rider

| Field | Value |
| --- | --- |
| Name | `Jireta Loans — Rider reviewer` |
| Username | `09000000102` |
| Password | the value of `REVIEWER_RIDER_PASSWORD` |

### Instructions text (English, paste into Play Console)

```text
JIRETA LOANS — LENDER REVIEWER ACCOUNT

1. Open the Jireta Loans app.
2. On the sign-in screen, tap the copyright line at the bottom
   ("© 1966 Jireta Loans & Credit Corp") 7 times in a row.
   A "Reviewer Sign-In" screen opens.
3. Enter the username (mobile number) and password shown above.
4. Tap "Sign in as reviewer".
5. Enter MPIN 2468 when the MPIN screen appears.
6. If the Terms & Conditions screen appears, tap Accept to continue.
7. You are signed in as the lender (borrower) reviewer account.

RIDER REVIEWER ACCOUNT

1. In Profile, tap Log out. The app shows the MPIN screen
   (logging out locks the app rather than signing it out).
2. Tap "Use another number" to return to the sign-in form.
3. Tap the copyright line 7 times in a row and enter the rider
   username/password above.
4. Tap "Sign in as reviewer".
5. Enter MPIN 2468.
6. If the Terms & Conditions screen appears, tap Accept to continue.
7. You are signed in as the rider reviewer account.

NOTES
- No SMS code is required. Reviewer accounts never receive or use SMS OTP.
- The credentials do not expire and can be reused for the entire review.
- Payments, disbursements, and cash collections are intentionally
  disabled for reviewer accounts. All other screens are available.
```

The same procedure applies to the app's internal QA team.

---

## 5. Authentication flow (reviewer)

```
Flutter reviewer screen
   │  phone + password  (typed by reviewer; nothing hardcoded)
   ▼
Dio  →  POST auth-reviewer?fn=login          (Supabase Edge Function)
   │
   ├─ enabled?            REVIEWER_LOGIN_ENABLED === "true"       else 404
   ├─ rate limit?         per IP + per account (30/20 per 15 min)
   ├─ allowlisted?        phone === REVIEWER_*_PHONE              else generic 401
   ├─ provisioned?        auth user app_metadata.reviewer === true
   │                      and reviewer_role === role              else generic 401
   ├─ phone match?        auth.users.phone === +63…               else generic 401
   ├─ password match?     constant-time vs REVIEWER_*_PASSWORD    else generic 401
   ├─ GoTrue sign-in      signInWithPassword(phone/email, secret)
   ├─ single-session      claim_active_session
   └─ audit               auth_logs + security_events + users.last_login_at
   ▼
Same session response shape as auth-otp?fn=verify-otp
   ▼
Flutter stores the session → normal MPIN gate (2468) → role dashboard
```

Reviewer sessions carry `reviewer: true` in the response (UI only) and
`auth.users.app_metadata.reviewer = true` (trusted server-side).

---

## 6. What reviewers can and cannot do

| Area | Reviewer access |
| --- | --- |
| Lender dashboard, loan application, account upgrade, profile, notifications | ✅ |
| Rider dashboard, CI, collections **list/detail**, profile, notifications | ✅ |
| Payment history / disbursement history (read) | ✅ |
| MPIN unlock (enter `2468`) | ✅ |
| Change/reset MPIN | ❌ `403 REVIEWER_NOT_ALLOWED` (keeps Play credentials valid) |
| Create Xendit payment link, sync payment | ❌ |
| Record/reverse office payment | ❌ |
| Record/upload/approve/reject collections | ❌ (collections are read-only) |
| Select disbursement method, GCash payout, office cash release | ❌ |
| Rider delivery / proof upload for a real disbursement | ❌ |
| SMS OTP send/verify on reviewer numbers | Blocked (generic response, no SMS) |

Submitting a loan **application** is allowed (it moves no money); approving and
disbursing require staff accounts, which reviewers do not have.

---

## 7. Security controls map

| Requirement | Control |
| --- | --- |
| No reviewer credentials/OTPs/bypass secrets in Flutter | The client sends only typed phone + password. Reviewed by `test/reviewer_login_screen_test.dart` source scan. |
| Configuration in Edge Function secrets | `REVIEWER_LOGIN_ENABLED`, `REVIEWER_*_PHONE`, `REVIEWER_*_PASSWORD`. No defaults in `reviewer.ts`. |
| Server-side validation | Every check happens in `auth-reviewer`; the client is never trusted. |
| Not exposed to ordinary users | Hidden 7-tap entry; endpoint returns 404 unless enabled; Play Console instructions only. |
| No global OTP disable | `auth-otp` is untouched for normal accounts. Reviewer numbers get a generic "sent" response and no SMS. |
| No access to other accounts | Two-layer allowlist: configured phone **and** `app_metadata.reviewer` + matching phone/role. |
| No financial transactions/disbursements | `requireNonReviewer` in payments, disbursements, and collections functions. |
| Log reviewer activity | `auth_logs.event_type = reviewer_login / reviewer_login_failed`, plus `security_events` and `console.info` (no credentials). |
| Reviewer mode not client-activatable | No flag is read from the client. Enablement is an env secret + provisioned `app_metadata`; the password is compared server-side. |
| Reusable Play credentials | Fixed phone + password + MPIN; MPIN changes are blocked; no OTP expiry. |

Additional hardening: per-IP and per-account rate limit, constant-time password
comparison, generic `401 REVIEWER_LOGIN_FAILED` for unknown phone/wrong
password, request body size cap, POST only, and debug-log redaction of
passwords/OTP/MPIN/tokens.

---

## 8. Files changed

### New

* `supabase/functions/auth-reviewer/index.ts`
* `supabase/functions/_shared/reviewer.ts`
* `supabase/functions/_shared/reviewer.test.ts`
* `supabase/migrations/00194_reviewer_login.sql`
* `scripts/setup_reviewer_accounts.ts`
* `scripts/check_reviewer_accounts.ts` — read-only diagnostics (checks env config, `public.users`, `app_metadata.reviewer`, profile, MPIN, and a live GoTrue sign-in).
* `lib/presentation/features/auth/screens/reviewer_login_screen.dart`
* `test/reviewer_login_screen_test.dart`
* `docs/PLAY_STORE_REVIEWER_ACCESS.md` (this file)

### Modified

* `supabase/functions/_shared/auth.ts` — exposes `isReviewer` from `app_metadata`.
* `supabase/functions/auth-otp/index.ts` — blocks reviewer numbers from SMS OTP.
* `supabase/functions/auth-mpin/index.ts` — blocks reviewer MPIN change/reset.
* `supabase/functions/payments-xendit-link/index.ts`
* `supabase/functions/payments-manage/index.ts`
* `supabase/functions/collections-manage/index.ts`
* `supabase/functions/disbursements-gcash/index.ts`
* `supabase/functions/disbursements-delivery/index.ts`
* `supabase/functions/disbursements-select/index.ts`
* `supabase/config.toml` — `auth-reviewer` function entry.
* `lib/core/network/api_endpoints.dart`
* `lib/core/network/interceptors/auth_interceptor.dart`
* `lib/core/network/interceptors/logging_interceptor.dart` — redacts passwords/OTP/MPIN/tokens from debug logs.
* `lib/data/datasources/remote/auth_remote_datasource.dart`
* `lib/presentation/features/auth/providers/auth_provider.dart`
* `lib/presentation/features/auth/screens/mobile_login_screen.dart`

---

## 9. Test results (this change)

Run from the repository root unless noted.

| Check | Result |
| --- | --- |
| `cd supabase && deno test --allow-read --allow-env functions/_shared/reviewer.test.ts` | **10 passed, 0 failed** |
| `cd supabase && deno check functions/auth-reviewer/index.ts functions/auth-otp/index.ts functions/auth-mpin/index.ts functions/_shared/reviewer.ts functions/_shared/auth.ts` | **passed** |
| `cd supabase && deno check` on the six guarded financial functions | **passed** |
| `deno check scripts/setup_reviewer_accounts.ts` | **passed** |
| `dart analyze` on the changed Flutter files + test | **No issues found** |
| `flutter test test/reviewer_login_screen_test.dart` | **2 passed** |

Covered by the Deno tests: disabled-by-default, fail-closed missing/short
secrets, phone normalization, duplicate phone rejection, allowlist matching,
exact password match, constant-time compare, `app_metadata` reviewer flag,
`403 REVIEWER_NOT_ALLOWED`, generic failure response, masked logging.

**Not run here:** live end-to-end sign-in against a Supabase project, because
this environment has no project URL/service-role key. After §3, run the curl
smoke tests in step 6 and one device sign-in per role.

---

## 10. Rotation and disable

* **Disable reviewer access immediately:** `REVIEWER_LOGIN_ENABLED=false`
  (or delete it), then redeploy `auth-reviewer`. New logins get `404`; existing
  reviewer sessions live until their token/session expires.
* **Rotate a password:** update the Supabase secret, update Play Console,
  re-run the setup script with `--apply` using the new value. Existing sessions
  are cleared by the script (`active_sessions`).
* **Remove reviewer accounts entirely:** delete the two auth users
  (`auth.users`), their `public.users` rows, profiles, and `user_mpins`, then
  remove the secrets.
* **Audit:** `select * from auth_logs where event_type like 'reviewer_login%'
  order by created_at desc;` and `select * from security_events where
  event_type like 'reviewer_login%' order by created_at desc;`.

---

## 11. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Reviewer screen shows "not available in this app build" | Server returned 404: `REVIEWER_LOGIN_ENABLED` is not `true`, secrets are missing/short, or `auth-reviewer` was not deployed. |
| `401 Invalid reviewer credentials` | One of the server checks failed. The exact reason is in `security_events`: `select created_at, detail from security_events where event_type = 'reviewer_login_failed' order by created_at desc limit 10;` (`not_allowlisted`, `missing_public_user`, `not_provisioned_as_reviewer`, `phone_mismatch`, `role_mismatch`, `bad_password`, `sign_in_failed`). Or run `scripts/check_reviewer_accounts.ts`. |
| `phone_mismatch` | Inspect the auth identity:<br>`select u.phone_number as public_phone, r.name as role, a.phone as auth_phone, a.email as auth_email, a.raw_app_meta_data->>'reviewer' as reviewer, a.raw_app_meta_data->>'reviewer_role' as reviewer_role from public.users u join roles r on r.id = u.role_id left join auth.users a on a.id = u.id where u.phone_number in ('09000000101','09000000102');`<br>If `auth_phone` is NULL/different **and** `auth_email` is not `<phone>@jireta.temp`, re-run the setup script `--apply`. If `auth_phone` is NULL but `auth_email` is the temp email, the current function version accepts it. |
| `429 Too many sign-in attempts` | Per-IP/account rate limit (30 per IP / 20 per account per 15 min). Wait 15 minutes. |
| `403 ACCOUNT_ARCHIVED` / `ACCOUNT_INACTIVE` | The reviewer `public.users` row is not active. Re-run the setup script. |
| MPIN screen says `Too many wrong MPIN attempts` | 3 wrong MPINs lock for 60 seconds. Wait and enter `2468`. |
| Payment button returns `REVIEWER_NOT_ALLOWED` | Expected — reviewer accounts cannot move money. |
| Setup script fails on `rider_profiles` | The `vehicle_types` lookup seed is missing in a non-standard database. Run the seed migrations first. |
