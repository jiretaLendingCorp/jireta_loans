# Xendit Test (Sandbox) API — Integration, Testing & Deployment

Head Manager-only diagnostics for the Jireta lending system's Xendit integration.

- **Goal:** verify that `XENDIT_SECRET_KEY` (a **test** key) authenticates with Xendit,
  create a **sandbox** payment request as a *separate* step, and confirm the payment
  status from Xendit — without touching loan, payment, schedule, or disbursement records.
- **Architecture (unchanged):** Flutter → Dio → Supabase Edge Function REST API → Xendit API.
  The secret key lives **only** in the Edge Function secret store; it never reaches the
  Flutter app, its bundle, or any HTTP response.

---

## 1. Endpoints (added to the existing `payments-xendit-link` function)

| Action (query param) | Method | Who may call | Effect |
| --- | --- | --- | --- |
| `?fn=diagnostics` | POST | Head Manager | Read-only verification of the secret key. Creates nothing. |
| `?fn=create-test-payment` | POST | Head Manager | Creates a sandbox **payment request** (`POST /v3/payment_requests`). Requires `x-idempotency-key`. |
| `?fn=test-payment-status` | POST | Head Manager | Reads the Xendit payment-request status (`GET /v3/payment_requests/{id}`). |
| `?fn=simulate-test-payment` | POST | Head Manager | Test-mode-only completion (`POST /v3/payment_requests/{id}/simulate`). |
| `?fn=generate` | POST | Lender | **Existing** flow, untouched (`POST /v2/invoices`). |

Verified against the official docs (2026-10-17):

- <https://docs.xendit.co/apidocs/create-payment-request> → `POST /v3/payment_requests`
- <https://docs.xendit.co/apidocs/get-payment-request> → `GET /v3/payment_requests/{payment_request_id}`
- <https://docs.xendit.co/apidocs/simulate-payment-test-mode> → `POST /v3/payment_requests/{payment_request_id}/simulate`
- <https://docs.xendit.co/docs/api-keys> → Basic auth (secret key as username, empty password); test keys are `xnd_development_...`, live keys are `xnd_production_...`
- `api-version: 2024-11-11` is the only currently valid value of that header.

### How connectivity is verified (no payment created)

`GET /v3/payment_requests/pr-00000000-0000-0000-0000-000000000000` — a syntactically
valid id that **intentionally does not exist**:

| Xendit response | Verdict reported | Meaning |
| --- | --- | --- |
| `404 DATA_NOT_FOUND` | `connected` | Key authenticated, API answered. Our probe id simply does not exist. |
| `2xx` | `connected` | Key authenticated. |
| `401 UNAUTHORIZED` | `auth_failed` | Key invalid, revoked, or from another environment. |
| `403 FORBIDDEN` | `permission_denied` | Key is valid but lacks Payments-API permission. |
| `5xx`, `400`, network error, timeout | `unverified` | Could **not** be verified — never reported as success. |

We deliberately do **not** probe `/balance`: it requires Money-out permission, so a
Money-in-only key would look broken even though it can create payment requests.

---

## 2. Store the test secret key (PowerShell, VS Code terminal)

The value is never written to a file, never echoed, and never committed.

```powershell
# (once per machine)
npx supabase login
npx supabase link --project-ref <your-project-ref>

# Read the key as a masked SecureString (nothing is echoed to the terminal)
$secure = Read-Host -Prompt "Paste the XENDIT TEST secret key (xnd_development_...)" -AsSecureString
$plain  = [System.Net.NetworkCredential]::new("", $secure).Password

# Push it as an Edge Function secret (this is the ONLY place the value lives)
npx supabase secrets set "XENDIT_SECRET_KEY=$plain"

# Clean up the shell variables
Remove-Variable plain, secure

# Confirm it exists (shows NAME + digest only — never the value)
npx supabase secrets list
```

Existing webhook verification uses a separate secret (`XENDIT_WEBHOOK_TOKEN`) and is unchanged:

```powershell
$token = Read-Host -Prompt "Paste the Xendit callback token" -AsSecureString
$plainToken = [System.Net.NetworkCredential]::new("", $token).Password
npx supabase secrets set "XENDIT_WEBHOOK_TOKEN=$plainToken"
Remove-Variable plainToken, token
```

**Never** put `XENDIT_SECRET_KEY` in `assets/env/.env`, `web/`, GitHub secrets, or any
Flutter file. The client only needs `XENDIT_PUBLIC_KEY` (card tokenization), which is already configured.

---

## 3. Deploy (PowerShell, VS Code terminal)

```powershell
# Apply the idempotency index migration (additive only)
npx supabase db push

# Deploy the Edge Function (verify_jwt = true comes from supabase/config.toml)
npx supabase functions deploy payments-xendit-link

# Optional: tail the logs while testing
npx supabase functions logs payments-xendit-link --tail
```

Local development (no cloud project) — note the env-file name:

```powershell
# Create supabase/.env (this path IS git-ignored by `*.env`)
"XENDIT_SECRET_KEY=xnd_development_..." | Set-Content -Path supabase\.env

# Sanity check that it is ignored before you write anything
git check-ignore -v supabase\.env     # -> .gitignore:49:*.env

npx supabase functions serve payments-xendit-link --env-file supabase/.env
# NOTE: supabase/.env.local is NOT covered by this repo's .gitignore — do not use it.
```

---

## 4. Test connectivity first

```powershell
$anon   = "<SUPABASE_ANON_KEY>"
$base   = "https://<project-ref>.supabase.co/functions/v1/payments-xendit-link"

# Log in as a HEAD MANAGER and reuse the access token for the diagnostics calls.
# (Logging in claims the active session, so the token-derived session id matches.)
$loginBody = @{
  identifier = Read-Host "Head Manager email / phone"
  password   = Read-Host "Password" -AsSecureString | ConvertFrom-SecureString -AsPlainText
} | ConvertTo-Json

$login = Invoke-RestMethod -Method Post -Uri "$base.Replace('payments-xendit-link','auth-login')?fn=login" `
  -Headers @{ apikey = $anon; "Content-Type" = "application/json" } -Body $loginBody

$headers = @{
  apikey        = $anon
  Authorization = "Bearer $($login.access_token)"
  "Content-Type" = "application/json"
}

# 1) Connectivity check (read-only — no payment is created)
Invoke-RestMethod -Method Post -Uri "$base?fn=diagnostics" -Headers $headers | ConvertTo-Json -Depth 6
```

Expected (success — sanitized, no secret):

```json
{
  "check": "xendit_connectivity",
  "status": "connected",
  "authenticated": true,
  "key_present": true,
  "key_preview": "xnd_development_***4f60",
  "environment": "test",
  "api_version": "2024-11-11",
  "endpoint": "GET /v3/payment_requests/pr-00000000-0000-0000-0000-000000000000",
  "http_status": 404,
  "error_code": "DATA_NOT_FOUND",
  "latency_ms": 143,
  "message": "Authenticated with Xendit (probe payment request intentionally does not exist).",
  "warning": null,
  "checked_at": "2026-10-17T04:15:22.918Z",
  "sandbox_test_ready": true
}
```

Expected (invalid key — HTTP 200 because the *diagnostic* succeeded; the verdict is `auth_failed`):

```json
{
  "check": "xendit_connectivity",
  "status": "auth_failed",
  "authenticated": false,
  "key_present": true,
  "key_preview": "xnd_development_***0000",
  "environment": "test",
  "http_status": 401,
  "error_code": "UNAUTHORIZED",
  "latency_ms": 121,
  "message": "Xendit rejected the credentials (401). The secret key is invalid, revoked, or from the wrong environment.",
  "sandbox_test_ready": false
}
```

Expected (missing secret):

```json
{
  "status": "unverified",
  "authenticated": false,
  "key_present": false,
  "key_preview": null,
  "environment": "unknown",
  "http_status": null,
  "message": "XENDIT_SECRET_KEY is not set. Add it with `supabase secrets set XENDIT_SECRET_KEY=...`.",
  "sandbox_test_ready": false
}
```

Expected (network / timeout — reported as unverified, **not** as success):

```json
{
  "status": "unverified",
  "authenticated": false,
  "http_status": null,
  "message": "Could not verify — the Edge Function could not reach api.xendit.co (network error).",
  "sandbox_test_ready": false
}
```

> A `warning` is added (and `sandbox_test_ready` forced to `false`) when the configured key is a
> **live** key (`xnd_production_...`) or an unrecognised prefix. Live keys are refused by the
> sandbox endpoints.

---

## 5. Create a sandbox payment request (separate step)

```powershell
$idem = [guid]::NewGuid().ToString()          # idempotency key (also supports "replay")
$body = @{ amount = 100; channel_code = "GCASH" } | ConvertTo-Json
$payHeaders = $headers + @{ "x-idempotency-key" = $idem }

$payment = Invoke-RestMethod -Method Post -Uri "$base?fn=create-test-payment" `
  -Headers $payHeaders -Body $body

$payment | ConvertTo-Json -Depth 6
```

Expected (HTTP 201):

```json
{
  "payment_request_id": "pr-8877c08a-740d-4153-9816-3d744ed197a5",
  "reference_id": "JR-TEST-<idempotency-key>",
  "status": "REQUIRES_ACTION",
  "type": "PAY",
  "country": "PH",
  "currency": "PHP",
  "request_amount": 100,
  "channel_code": "GCASH",
  "description": "Jireta sandbox test payment JR-TEST-<idempotency-key>",
  "actions": [
    { "type": "REDIRECT_CUSTOMER", "descriptor": "WEB_URL", "value": "https://checkout.xendit.co/web/..." }
  ],
  "created": "2026-10-17T04:16:05.371Z",
  "amount": 100,
  "idempotency_key": "5f0c…",
  "sandbox": true,
  "source": "jireta-test",
  "duplicate": false,
  "note": "SANDBOX TEST ONLY — no loan, schedule, payment, or disbursement record was created or modified."
}
```

Duplicate protection — **the same** `x-idempotency-key` returns the same payment request
(HTTP 200, `"duplicate": true`, no new Xendit call):

```powershell
Invoke-RestMethod -Method Post -Uri "$base?fn=create-test-payment" -Headers $payHeaders -Body $body |
  Select-Object payment_request_id, duplicate
```

---

## 6. Verify the payment (Xendit-confirmed)

```powershell
# a) Ask Xendit for the current status
Invoke-RestMethod -Method Post -Uri "$base?fn=test-payment-status" -Headers $headers `
  -Body (@{ payment_request_id = $payment.payment_request_id } | ConvertTo-Json) | ConvertTo-Json -Depth 6

# b) (optional, TEST MODE ONLY) complete the sandbox payment, then re-check the status
Invoke-RestMethod -Method Post -Uri "$base?fn=simulate-test-payment" -Headers $headers `
  -Body (@{ payment_request_id = $payment.payment_request_id; amount = 100 } | ConvertTo-Json) | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -Uri "$base?fn=test-payment-status" -Headers $headers `
  -Body (@{ payment_request_id = $payment.payment_request_id } | ConvertTo-Json) | ConvertTo-Json -Depth 6
```

Expected status response (`SUCCEEDED` after a successful simulation):

```json
{
  "check": "xendit_test_payment_status",
  "test_payment": true,
  "payment_request_id": "pr-8877c08a-740d-4153-9816-3d744ed197a5",
  "reference_id": "JR-TEST-<idempotency-key>",
  "status": "SUCCEEDED",
  "currency": "PHP",
  "request_amount": 100,
  "channel_code": "GCASH",
  "terminal": true,
  "payment_confirmed": true,
  "recorded": true,
  "note": "SANDBOX TEST ONLY — no loan, schedule, payment, or disbursement record was created or modified."
}
```

**Distinction that must not be blurred:**

| Concept | How it is proven | Effect on the database |
| --- | --- | --- |
| API connectivity | `?fn=diagnostics` verdict `connected` | none (no writes at all) |
| Payment request created | `?fn=create-test-payment` returns a `payment_request_id` | one `xendit_logs` row (`status = 'test_created'`, no `loan_id`/`payment_id`) |
| Payment confirmed/paid | `?fn=test-payment-status` → `payment_confirmed: true` (or the validated webhook) | one `xendit_logs` row for the terminal status |
| Disbursement / payout | **out of scope here** — the existing `disbursements-*` functions and their webhook are unchanged | — |

Creating a test payment request **never** approves a loan, marks an installment paid, or
changes `payments`/`loans`/`disbursements`.

Webhooks: the production receiver (`payments-xendit-webhook`) still verifies the
`x-callback-token` header (`XENDIT_WEBHOOK_TOKEN`), rejects replays whose payment row is
already `verified`, and rejects amount mismatches. A simulated sandbox payment that fires
`payment.succeeded` for a `pr-…` id does not match any `payments.xendit_payment_id`, so it is
recorded as an `unmatched` `xendit_logs` row and nothing else changes.

---

## 7. Error / status codes

| HTTP | Code | When |
| --- | --- | --- |
| 200 | — | Diagnostics verdict (including `auth_failed` / `unverified`), idempotent replay |
| 201 | — | Test payment request created |
| 400 | `VALIDATION_ERROR` | Bad/missing `x-idempotency-key`, invalid `amount`, unsupported `channel_code`, malformed `payment_request_id` |
| 400 | `XENDIT_TEST_KEY_REQUIRED` | The configured key is not a test key (`xnd_development_...`) |
| 401 | `UNAUTHORIZED*` | Missing / invalid / expired user session (from `requireAuth`) |
| 403 | `FORBIDDEN` | Caller is not a Head Manager |
| 404 | `NOT_FOUND` | Unknown action, or Xendit reports no such payment request |
| 422 | `XENDIT_ERROR` (e.g. `CHANNEL_NOT_AVAILABLE`) | Xendit rejected the request |
| 429 | `RATE_LIMITED` | 20 diagnostics / 5 min, or 10 test payments or simulations / 15 min per user |
| 502 | `XENDIT_UNREACHABLE` / `XENDIT_TIMEOUT` / auth error from Xendit | Network, timeout, or upstream authentication failure |
| 503 | `XENDIT_NOT_CONFIGURED` | `XENDIT_SECRET_KEY` is not set |

---

## 8. Test matrix

| Scenario | How to reproduce | Expected result |
| --- | --- | --- |
| Valid test credentials | `?fn=diagnostics` with a correct `xnd_development_...` key | `connected`, `authenticated: true`, `environment: "test"`, `sandbox_test_ready: true` |
| Invalid credentials | temporarily set `XENDIT_SECRET_KEY=xnd_development_invalid`, run diagnostics, then re-set the real key | `auth_failed`, `authenticated: false`, `http_status: 401` |
| Missing secret | `npx supabase secrets unset XENDIT_SECRET_KEY`, run diagnostics / create | diagnostics `unverified` + `HTTP 503 XENDIT_NOT_CONFIGURED` on create |
| Live key configured | set an `xnd_production_...` key and run diagnostics / create | `environment: "live"` + `warning`, `sandbox_test_ready: false`; create → `400 XENDIT_TEST_KEY_REQUIRED` |
| Network failure / timeout | run while Xendit is unreachable (or on an offline environment) | `unverified` + `XENDIT_UNREACHABLE` / `XENDIT_TIMEOUT` (never a success) |
| Invalid amounts | `@{ amount = 0 }`, `@{ amount = -5 }`, `@{ amount = 9999999 }`, `@{ amount = "abc" }` | `400 VALIDATION_ERROR`, no Xendit call |
| Unauthorized request | call without `Authorization`, or with a **lender** token | `401 UNAUTHORIZED_*` / `403 FORBIDDEN` |
| Duplicate request | send the same `x-idempotency-key` twice (concurrently is fine) | second call returns `duplicate: true` with the **same** `payment_request_id`; one `xendit_logs` row (partial unique index `uq_xendit_logs_test_idempotency`) |
| Webhook verification | `POST payments-xendit-webhook` without `x-callback-token` (or with a wrong one) | `401 UNAUTHORIZED`, no DB write |
| Duplicate webhook | replay a `PAID` callback for an already `verified` payment | `{ "already_processed": true }`, no double credit |
| Amount mismatch | callback `amount` ≠ installment `amount_due` | `422 AMOUNT_MISMATCH`, logged as `amount_mismatch` |
| Never marks a payment paid | inspect `payments`, `loans`, `loan_schedules` after create/simulate/status | unchanged |

---

## 9. Database & security notes

- **No schema change.** Migration `00183_xendit_test_payment_idempotency.sql` only adds a
  partial unique index on `xendit_logs ((payload ->> 'idempotency_key'))` for rows with
  `status = 'test_created'`. No columns, tables, RLS policies, or production rows are touched.
- All test rows go to `xendit_logs` (service-role only; RLS enabled with no policies) with
  `loan_id`, `payment_id`, `disbursement_id` left `NULL` and a `JR-TEST-…` reference plus
  `sandbox`/`source` markers.
- Test payment creation and simulation are written to `audit_logs`
  (`xendit_test_payment_created`, `xendit_test_payment_simulated`) and appear in the
  Head Manager audit log.
- The client can never set a payment to successful: only `test-payment-status` (Xendit API)
  or the token-verified webhook reports `payment_confirmed`.
- The secret key is never returned: responses expose only a masked `key_preview`
  (`xnd_development_***4f60`). Xendit error bodies are reduced to an `error_code` + a fixed
  sentence; raw upstream bodies and headers are never forwarded.

---

## 10. Flutter usage

The Head Manager **Settings** screen now shows a *Xendit Sandbox Diagnostics* card with three
clearly separated steps: **1. API connectivity** → **2. Sandbox payment request** →
**3. Confirmed payment**. Buttons: `Test API Connectivity`, `Create Test Payment`,
`Replay (same idempotency key)`, `Check Payment Status`, `Simulate Sandbox Payment`.

It works on Flutter Web and Android (no platform-specific code), uses the existing Dio client
(`DioClient` + interceptors, including the `x-idempotency-key` helper), and reads the
datasource through the existing GetIt registration. No secret key, no card fields, and no
platform channels are involved.

---

## 11. Files changed

| File | Change |
| --- | --- |
| `supabase/functions/_shared/xendit.ts` | Added the v3 Payments API client (`POST /v3/payment_requests`, `GET /v3/payment_requests/{id}`, test-mode `simulate`), the timeout-safe `xenditRequest` wrapper, secret-key environment detection/redaction, the read-only connectivity probe + pure `classifyXenditProbe`, PH currency constants, and response sanitization. Legacy `createInvoice` / `createDisbursement` are unchanged. |
| `supabase/functions/payments-xendit-link/index.ts` | Added the `?fn=diagnostics`, `?fn=create-test-payment`, `?fn=test-payment-status`, `?fn=simulate-test-payment` handlers behind a Head-Manager gate, with HMAC-free input validation, test-key enforcement, rate limits, `x-idempotency-key` idempotency, `xendit_logs` test markers, and audit writes. The existing `?fn=generate` handler is untouched. |
| `supabase/migrations/00183_xendit_test_payment_idempotency.sql` | New partial unique index enforcing one test payment request per idempotency key. |
| `supabase/functions/_shared/xendit.test.ts` | New Deno unit tests for probe classification, redaction, request bodies, sanitization, validation, and error messages (23 tests). |
| `lib/core/network/api_endpoints.dart` | New endpoint constants for the four diagnostics actions. |
| `lib/data/datasources/remote/payment_remote_datasource.dart` | New methods: `checkXenditConnectivity`, `createXenditTestPayment`, `getXenditTestPaymentStatus`, `simulateXenditTestPayment`. |
| `lib/presentation/features/head_manager/settings/providers/xendit_diagnostics_provider.dart` | New Riverpod state/notifier for the card (connectivity, test payment, idempotent replay, status, simulation, sanitized errors). |
| `lib/presentation/features/head_manager/settings/widgets/xendit_diagnostics_card.dart` | New Head-Manager-only UI card separating connectivity / payment request / confirmed payment. |
| `lib/presentation/features/head_manager/settings/screens/hm_settings_screen.dart` | Mounts the diagnostics card under System Config. |
| `lib/presentation/features/head_manager/audit/audit_action_catalog.dart` | Registered the two new audit actions (`xendit_test_payment_created`, `xendit_test_payment_simulated`). |
| `test/xendit_diagnostics_test.dart` | New Flutter tests: endpoints, datasource payloads/idempotency header, the card's three-step UI, sanitized error display, and source scans proving the secret key is absent from the client and that the Edge Function keeps its HM gate, test-key guard, idempotency check, and webhook verification. |
| `test/features/head_manager/audit/audit_action_catalog_test.dart` | Synced the expected action set with the catalog (it had drifted out of date). |
| `lib/presentation/features/lender/payments/screens/lender_payment_method_screen.dart` | The GCash option is now selectable (no "Coming Soon" badge); selecting it routes to the existing GCash/Xendit screen, and the Pay button follows the selection. |
| `lib/presentation/features/lender/payments/screens/lender_pay_via_gcash_screen.dart` | Shows the server's sanitized reason (e.g. `Loan is not in a payable status`, rate-limit message) instead of a generic "Failed to generate payment link". |
| `supabase/functions/payments-xendit-link/index.ts` (`?fn=generate`) | **Bug fix:** the GCash generator accepted only `active` loans, so an **overdue** loan could never pay via GCash — inconsistent with office cash (`payments-manage`) and COD (`collections-manage`), which both accept `active`/`overdue`. Now `['active','overdue']` (still not `completed`). |
| `test/lender_payment_method_amount_test.dart` | New tests: GCash is selectable with no "Coming Soon" badge, and "Pay via GCash" navigates to `/lender/pay-gcash`. |
| `test/xendit_diagnostics_test.dart` | Added a regression guard that the GCash generator keeps `overdue` payable (and never the strict `active`-only check). |
| `supabase/functions/payments-xendit-link/index.ts` (`?fn=generate`) | **Bug fix (429 lockout):** the abuse guard ran *before* validation, so every 400 — "not in a payable status", "already paid" — consumed one of the 3 attempts and, on the 4th try, placed a 30-minute `security_blocks` entry. A lender retrying against a rejected request was locked out with `429 PAYMENT_ATTEMPT_BLOCKED` even though no invoice was ever created. The count is now taken immediately before the real Xendit invoice generation (invalid requests cost nothing), while an *existing* block is still detected up front via `checkBlock` (cheap, no new attempt recorded). The 429 message now names the limit and suggests Cash on Delivery. Also: a missing `XENDIT_SECRET_KEY` returns `503 XENDIT_NOT_CONFIGURED` and a failing `createInvoice` returns `502 XENDIT_INVOICE_FAILED` instead of an opaque 500. |
| `docs/XENDIT_TEST_API.md` | This document. |

---

## 12. Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `auth_failed` (401) | Wrong/revoked key, or a **live** key used against a test environment. Regenerate the test key in Xendit Dashboard → Settings → API Keys and re-run `npx supabase secrets set`. |
| `permission_denied` (403) | The key has no Payments-API permission. Grant money-in read/write for the API key. |
| `unverified` with a 400 / 5xx | Xendit answered but not conclusively (e.g. a server error). Retry; check `npx supabase functions logs payments-xendit-link`. |
| `unverified` with no `http_status` | Network/timeout between the Edge Function and `api.xendit.co`, or the function is not deployed. |
| `XENDIT_NOT_CONFIGURED` (503) | `XENDIT_SECRET_KEY` missing in that project. Re-run `npx supabase secrets set` and redeploy. |
| `403 FORBIDDEN` on every action | The caller is not a Head Manager. |
| `429 RATE_LIMITED` | Wait for the window (5 min for diagnostics, 15 min for create/simulate) — rows live in `rate_limit_logs`/`security_blocks`. |
| `429 PAYMENT_ATTEMPT_BLOCKED` on `?fn=generate` | 3 GCash links for the same installment were generated inside 15 minutes, so the key was blocked for 30 minutes (`security_blocks`, key `payment:<user>:<schedule>`; the event is in `security_events`). Wait out the block, or clear it in the SQL editor: `delete from security_blocks where key like 'payment:%';` and `delete from rate_limit_logs where key like 'payment:%';`. Only attempts that reach invoice generation are counted — a request rejected for status/paid reasons never triggers this. |
| Card shows "Create Test Payment" disabled | Connectivity was not yet verified with a test key (`sandbox_test_ready: false`). |
| Lender GCash screen: `Loan is not in a payable status` | The loan is neither `active` nor `overdue` (e.g. `approved` — not released yet, or already `completed`). Payable statuses for GCash are `active` and `overdue`, matching office cash and COD. |
| Browser blocks the request | `CORS_ALLOWED_ORIGINS` must include your web origin (existing behaviour; `x-idempotency-key` is already an allowed header). |

## 13. Honest limitations

1. Connectivity is proven with **one** read-only probe. A key that can hit Xendit's Payments
   API but lacks permission for the specific channel you pick will only fail at
   `?fn=create-test-payment` — that failure is reported verbatim (sanitized) rather than guessed.
2. `?fn=simulate-test-payment` uses Xendit's documented **test-mode-only** endpoint; it
   completes sandbox payments only and is refused for live keys. Xendit may not support
   simulation for every channel (e.g. some direct-debit flows) — those errors are surfaced
   as-is.
3. Legacy `POST /v2/invoices` (used by the existing lender GCash flow) is Xendit's legacy
   product and is not used by any new code here; migrating that production flow is a separate
   task and was intentionally left untouched.
4. `deno lint` in this repository is not a clean gate (pre-existing `no-import-prefix`,
   `no-explicit-any`, and `no-empty` findings across many untouched functions). The new files
   add no new lint categories; `deno check` and `deno test` are green.
