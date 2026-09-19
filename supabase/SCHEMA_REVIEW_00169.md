# Schema / ERD Review — Jireta Loans (migration `00169_schema_integrity_audit.sql`)

Date: 2026-09-19
Scope: `supabase/migrations/00001` → `00168` inspected; fixes delivered **forward-only** in `00169`.
Constraint honoured: no redesign, no data deletion, no edits to already-applied migrations, no breaking changes to edge functions / Flutter / RLS / reports.

## Deployment status — APPLIED and verified (2026-09-19)

Applied to `jiretas_db` (`lcelzrvpqwlbeccrwpkp`, ap-northeast-1) via `supabase db push --linked --yes`.
Remote was at 00168 with 102 migrations applied, so `00169` was the only pending migration.

| Verification | Result |
|---|---|
| Recorded in `supabase_migrations.schema_migrations` | yes |
| `schema_integrity_findings` table | created |
| New unique indexes (3) | all created and enforcing |
| Superseded narrow indexes (2) | dropped, none left behind |
| `trg_payments_loan_consistency` | installed |
| Helper functions | 5 installed |
| **Open findings** | **0** (data was clean on every pre-flight check) |
| Deprecated varchar lookup columns still present | 12/12 intact — nothing dropped |
| Total FOREIGN KEY constraints | 183 |
| Critical FKs missing (21 sampled via `has_fk`) | 0 |

### Enforcement proven on the live database

Each new rule was exercised with a transaction-scoped fixture that was rolled back; nothing leaked
(probe row counts verified 0 afterwards):

| Probe | Attempt | Result |
|---|---|---|
| A | Payment on Loan A's schedule linked to Loan B's assignment | rejected `23514` by `enforce_payment_loan_consistency()` |
| B | Second active collection assignment for one schedule | rejected `23505` by `uq_collection_assignments_active_schedule` |
| C | Second active credit investigation for one loan | rejected `23505` by `uq_credit_investigations_active_loan` |
| D | Second disbursement for one loan | rejected `23505` by `uq_disbursements_one_per_loan` |

Note: probe B first tripped the pre-existing `collection_assignments_rider_required_unless_unassigned_request`
CHECK because `collection_assignments.status_id` has a column DEFAULT that the sync trigger lets override a
supplied `status` code on INSERT. That is existing behaviour the edge functions already work around by sending
`status_id: null`; re-running the probe CHECK-compliantly reached — and was blocked by — the new index.

At deploy time the project held 9 users / 7 lender profiles / 2 employee profiles and **no loan
transactions at all** (0 loans, 0 schedules, 0 payments, 0 disbursements, 0 CIs), i.e. it is a
development/staging database rather than live production data.

## How this was verified (read this first)

| Check | Status |
|---|---|
| Read the consolidated baseline (`00001`) + all 103 later migrations | done |
| Cross-checked real app usage in `lib/**/*.dart` and `supabase/functions/**/*.ts` | done |
| All 103 intended FK targets (table + column) exist in the migration-defined schema | **static check: PASS** |
| Migration structure (dollar-quote pairing, paren balance, DO/END, BEGIN/COMMIT) | **static check: PASS** |
| Executed against a live PostgreSQL | **NOT DONE — no Postgres/Docker in this environment** |

Docker is not running and `psql` is not installed, so the migration could not be applied here
(and I did not apply anything to the linked remote project `lcelzrvpqwlbeccrwpkp` — that needs your go-ahead).
Run it yourself with:

```bash
cd jireta_loans
npx supabase db reset                 # local: replays 00001..00169 from scratch
# or, against the linked project:
npx supabase migration up --linked    # applies only 00169
```

Then read the `NOTICE`/`WARNING` lines and inspect findings:

```sql
SELECT check_name, table_name, details FROM public.schema_integrity_findings WHERE resolved_at IS NULL;
```

Every statement in `00169` is `IF EXISTS` / catalog-guarded and idempotent, so re-running it is safe.

---

## A. Relationships fixed

| # | Relationship | Problem | Fix |
|---|---|---|---|
| 1 | `payments` ↔ `collection_assignments` ↔ `loan_schedules` | A payment could carry `loan_schedule_id` from Loan X while its `collection_assignment_id` belonged to Loan Y. Only "at least one link" (`payments_context_check`) was enforced. | New `trg_payments_loan_consistency` (BEFORE INSERT/UPDATE OF) raises `23514` unless both links resolve to the **same loan**. Existing violations are reported, never auto-moved. |
| 2 | `collection_assignments` — active/pending per schedule | Rule lived only in `collections-manage` (409 `ALREADY_IN_PROGRESS`). Two staff could race two different riders onto one schedule. | `uq_collection_assignments_active_schedule` — partial UNIQUE on `(loan_schedule_id)` for `requested, assigned, accepted, in_progress, pending_approval`. Supersedes the narrower `uq_collection_assignments_requested_schedule` (00018) and `uq_collection_assignments_active_schedule_rider` (00157). |
| 3 | `credit_investigations` — active per loan | `ci-manage` refuses a second active CI per loan in code only. | `uq_credit_investigations_active_loan` — partial UNIQUE on `(loan_id)` for `assigned, in_progress`. History rows are untouched. |
| 4 | `disbursements` — one per loan | `disbursements-gcash` / `-delivery` / `-select` / `-office` all refuse a 2nd row for a loan in code only; a race could double-release cash. | `uq_disbursements_one_per_loan` — UNIQUE on `(loan_id)`. Provider attempts/retries stay in `xendit_logs`. |
| 5 | Role ↔ profile combinations | No DB rule; `users-manage`'s profile drop is best-effort (errors swallowed), so an incompatible combination could persist silently. | `validate_profile_role_consistency()` (read-only) + findings. A hard trigger was deliberately **not** installed — see §H. |

## B. Foreign keys added / fixed

**All 103 intended relationships from the request were already enforced by real
`pg_constraint` FOREIGN KEYs** in the migration history (`00001`, `00110`, `00118`, `00128`, `00141`, `00157`),
including every `*_id` lookup pair, the `PK = FK` profile tables, and the newer tables
(`loan_emergency_contacts`, `rider_location_history`, `user_devices`, `active_sessions`, `email_reset_otps`,
`login_lockouts`, `password_history`, `password_reset_tokens`).

`00169` therefore adds an **enforcement + drift-protection** pass instead of guessing:

* ~103 relationships are re-checked with `has_fk(child, col, parent, col)` — a strict check that the FK exists
  *and* points at the stated parent column (not just a similarly-named column).
* Any that is missing (e.g. a DB where an incremental migration was skipped) is added
  `NOT VALID` → `VALIDATE` in its own subtransaction, so a single orphan row produces a
  `WARNING` + a finding instead of aborting the migration.
* Missing tables/columns are recorded as findings rather than crashing.
* A post-fix orphan scan runs on the hot FK columns (`payments`, `disbursements`,
  `credit_investigations`, `collection_assignments`).

## C. Unique constraints added

New in `00169`:

* `uq_credit_investigations_active_loan` — one active CI per loan (history stays 1:N)
* `uq_collection_assignments_active_schedule` — one active/pending assignment per schedule (history stays 1:N)
* `uq_disbursements_one_per_loan` — one disbursement per loan

Re-verified (already present, no change): `role_permissions(role_id, permission_id)`,
`loan_co_makers(loan_id, co_maker_id)`, `loan_schedules(loan_id, installment_number)`,
`application_personal_info/application_employment_info/application_loan_details(application_id)`,
`loan_disbursement_preferences(loan_id)` (PK), `rider_locations(rider_id)`,
`active_sessions(user_id)`, `payment_reversals(payment_id)`, `emergency_contacts(lender_id, phone_number)`,
`loan_emergency_contacts(loan_id, phone_number)`, `user_devices(user_id, fcm_token)`.

Indexes with no supporting constraint are impossible to add **silently**: if duplicate rows block a
UNIQUE, `00169` logs `duplicate_rows_block_unique` and skips it.

## D. Deprecated / legacy columns & tables (request item 11)

| Table | Column | Replacement | Replacement lookup | Still used by app code? | Safe to remove? |
|---|---|---|---|---|---|
| `users` | `account_status` | `account_status_id` | `user_account_statuses.id` | **yes** (Dart + edge) | No — drop only after app dual-write |
| `lender_profiles` | `gender`, `civil_status`, `employment_type`, `account_upgrade_status` | `*_id` | `gender_types`, `civil_statuses`, `employment_types`, `account_upgrade_statuses` | **yes** | No |
| `employee_profiles` | `gender`, `civil_status` | `*_id` | `gender_types`, `civil_statuses` | **yes** | No |
| `rider_profiles` | `vehicle_type` | `vehicle_type_id` | `vehicle_types` | **yes** | No |
| `loans` | `payment_frequency`, `status`, `employment_type` | `*_id` | `payment_frequencies`, `loan_statuses`, `employment_types` | **yes** | No |
| `collection_assignments` | `status` | `status_id` | `collection_assignment_statuses` | **yes** | No |
| `disbursements` | `method`, `status` | `*_id` | `disbursement_methods`, `disbursement_statuses` | **yes** | No |
| `payments` | `payment_method`, `status` | `*_id` | `payment_methods`, `payment_statuses` | **yes** | No |
| `addresses` / `application_addresses` | `address_type` | `address_type_id` | `address_types` | **yes** | No |
| `emergency_contacts` / `loan_co_makers` / `application_*` | `relationship` | `relationship_id` | `relationship_types` | **yes** | No |
| `loan_documents`, `ci_documents`, `co_maker_documents`, `application_documents`, `account_upgrade_documents` | `document_type` | `document_type_id` | `document_types` | **yes** | No |
| `credit_investigations`, `in_office_applications`, `notifications`, `sms_logs` | `status` / `type` | `status_id` / `type_id` | `credit_investigation_statuses`, `in_office_application_statuses`, `notification_types`, `sms_statuses` | **yes** | No |
| `terms_consent_logs` | `platform` | `platform_id` | `platform_types.id` | yes | No |
| `loan_disbursement_preferences` | `method` | `method_id` | `disbursement_methods.id` | yes | No |
| `account_upgrade_documents` | `status` | `status_id` | `document_review_statuses.id` | yes | No |
| `lender_profiles` | `employment_type(_id)`, `employer_name`, `monthly_income`, `source_of_funds` | `loans.*` (per-loan snapshot) | same lookups | partly (still written by `users-manage`) | No |
| `emergency_contacts` (**table**) | — | `loan_emergency_contacts` | — | **yes** — read by `kyc-view` L514/L752, `users-manage` L565; written by `in-office-view` L525/L594 | No |
| `application_emergency_contacts` (**table**) | — | `loan_emergency_contacts` on conversion | — | **yes** — wizard/draft stage (`in-office-create` L259, `in-office-view` L389, `kyc-view` L138) | No — it is the draft-stage store, not legacy |
| `otp_codes`, `email_reset_otps`, `email_register_otps`, `email_otp_lockouts`, `email_register_lockouts` | — | — | — | yes | N/A — pre-auth, correctly keyed by phone/email (no `user_id` available yet). `login_lockouts`, `password_history`, `password_reset_tokens`, `active_sessions` all FK to `users`. |

**Why the varchar aliases are still here.** `00110–00112` already made the UUID column canonical
(`NOT NULL`, FK-validated, trigger-synced). An app audit on 2026-09-19 counts **123** Dart writes and
**261** edge-function writes still using the varchar names, versus 23 / 24 using `*_id`. Dropping the
varchar column now would produce `42703 column "status" does not exist` on every insert — a SEV-1.
The `DROP COLUMN` block already exists, commented, at the bottom of `00112`; it becomes safe once the
app dual-writes then writes `*_id` only.

## E. Data migration performed

| Action | Data touched | Why it is safe |
|---|---|---|
| `role_permissions` de-dup (keep earliest row per `(role_id, permission_id)`) | identical junction rows only | No business payload; required to add/keep the UNIQUE. Count logged + recorded as a finding. |
| `loan_co_makers` de-dup (keep earliest per `(loan_id, co_maker_id)`) | identical junction rows only | Same reasoning. |
| Orphan scan on `payments.*`, `disbursements.loan_id`, `credit_investigations.loan_id`, `collection_assignments.loan_schedule_id` | **none** | Rows are reported as findings, not modified. |

**No** financial row is rewritten. Cross-loan payment mismatches, duplicate active CIs, duplicate active
collections and duplicate disbursements are all **reported only** — moving money between installments or
deleting a disbursement is a business decision, not a migration's.

## F. Relationships intentionally left 1:N (business history)

* `loans 1:N credit_investigations` — re-investigation history; `ci-manage` marks superseded rows
  `reassigned` and inserts a fresh one. Only the **active** row is unique.
* `loan_schedules 1:N collection_assignments` — declined / rejected / reassigned / retried assignments
  are history. Only **one active/pending** row per schedule is allowed.
* `loans 1:N loan_schedules`, `loans 1:N loan_documents`, `loans 1:N loan_emergency_contacts`,
  `users 1:N addresses`, `users 1:N notifications`, `users 1:N user_devices` — all genuinely 1:N.
* `loans 1:N payments` (one collected amount is allocated across several installments of the same loan),
  `collection_assignments 1:N payments` — allocations plus split payments.
* `loans 1:0..1 loan_disbursement_preferences` (`loan_id` is PK), `users 1:0..1 lender_profiles /
  rider_profiles / employee_profiles` (PK = FK), `rider_profiles 1:0..1 rider_locations`
  (UNIQUE), `payments 1:0..1 payment_reversals` (UNIQUE) — all confirmed 1:0..1.

## G. Remaining ERD issues (honest list)

1. **Duplicate varchar + UUID lookup columns remain** (two storage columns for one fact). They cannot be
   removed until the Flutter/edge dual-write migration lands; until then the UUID column is the declared
   single source of truth and the varchar is a trigger-synced alias.
2. **`loans` ↔ `in_office_applications` is still a two-way pair**: `loans.in_office_application_id`
   (canonical FK) plus the historical reverse FK on `in_office_applications`. Documented as load-bearing
   by `00034`/`00035` (`in-office-view` embeds through it). Not changed.
3. **Role ↔ profile combinations are not hard-enforced.** Asymmetric ordering in `users-manage`
   (profile insert *then* `users.role_id` update) means any trigger would reject legitimate role changes.
   Safe fix (app change, then a follow-up migration): write `role_id` first, re-shape profiles, then
   enable the trigger on `users BEFORE UPDATE OF role_id`. Until then use
   `SELECT * FROM public.validate_profile_role_consistency();`.
4. **`emergency_contacts` (per-lender) is duplicated data** versus `loan_emergency_contacts`
   (per-loan). New code should read the per-loan table; `in-office-view` still fans contacts out to both.
5. **`lender` = borrower** naming is retained (`lender_profiles`, `loans.lender_id`) for realtime/API
   stability; the alias views introduced by `00109/00111` were removed again in `00168`.
6. **`uq_disbursements_one_per_loan` assumes no partial disbursements.** If partial or multi-tranche
   releases are ever required, drop this index and reintroduce `xendit_logs`-based attempt history.
7. Findings recorded by `00169` (duplicates, orphans, mismatches) stay open until a human reviews them —
   the migration intentionally does not "fix" financial data by guessing.

## Blast radius of 00169 (what it can possibly change)

`00169` contains **no** `DROP TABLE`, `DROP COLUMN`, `ALTER COLUMN`, `SET NOT NULL`, `DROP CONSTRAINT` or
`TRUNCATE`. The complete list of destructive statements is:

| Statement | Target | Guard |
|---|---|---|
| `DROP FUNCTION` ×1 | `ensure_unique_constraint(...)` — a helper this same migration created | own helper, not used by the app |
| `DROP INDEX` ×2 | `uq_collection_assignments_requested_schedule`, `uq_collection_assignments_active_schedule_rider` | only executes when the replacement `uq_collection_assignments_active_schedule` exists |
| `DROP TRIGGER` ×1 | `trg_payments_loan_consistency` | immediately recreated (idempotency) |
| `DELETE FROM` ×2 | exact-duplicate rows in `role_permissions` / `loan_co_makers` | identical junction rows only; count logged as a finding |

Every other change is additive (`CREATE TABLE/FUNCTION/TRIGGER/INDEX`, `ADD CONSTRAINT`, `COMMENT ON`), and
every failure path records a finding + `WARNING` instead of aborting. RLS policies and grants on existing
tables are untouched.

## Rollback (if the deploy must be undone)

The whole file runs in one transaction, so a failure rolls back completely. To undo it after a successful
apply:

```sql
BEGIN;
DROP TRIGGER  IF EXISTS trg_payments_loan_consistency ON public.payments;
DROP FUNCTION IF EXISTS public.enforce_payment_loan_consistency();
DROP INDEX    IF EXISTS public.uq_credit_investigations_active_loan;
DROP INDEX    IF EXISTS public.uq_disbursements_one_per_loan;
DROP INDEX    IF EXISTS public.uq_collection_assignments_active_schedule;
-- restore the narrower partial indexes that 00169 replaced
CREATE UNIQUE INDEX IF NOT EXISTS uq_collection_assignments_requested_schedule
  ON public.collection_assignments (loan_schedule_id) WHERE status = 'requested';
CREATE UNIQUE INDEX IF NOT EXISTS uq_collection_assignments_active_schedule_rider
  ON public.collection_assignments (loan_schedule_id, rider_id)
  WHERE status IN ('assigned','accepted','in_progress','pending_approval');
DROP FUNCTION IF EXISTS public.validate_profile_role_consistency();
DROP TABLE    IF EXISTS public.schema_integrity_findings;   -- audit output only
DROP FUNCTION IF EXISTS public.has_fk(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.has_unique_on(TEXT, TEXT[]);
DROP FUNCTION IF EXISTS public.record_integrity_finding(TEXT, TEXT, UUID, JSONB);
-- FK constraints 00169 added (only on a drifted DB) would need dropping individually;
-- check: SELECT conname FROM pg_constraint WHERE conname LIKE 'fk\_%' AND contype='f';
COMMIT;
```

A deduped `role_permissions` / `loan_co_makers` row cannot be restored — it carried no data beyond the pair
it duplicated.

## Verification checklist (request item 6)

| Verification | Result |
|---|---|
| Migration applies / SQL structure valid | static PASS; **needs your `db reset` for runtime confirmation** |
| Every intended relationship enforced by a real FK | PASS (static, 103/103 already enforced; `00169` re-asserts) |
| Unique constraints enforced | PASS for existing ones; 3 new ones added (skipped + reported if data blocks them) |
| No orphan records | orphan scan included in `00169` (reports, never deletes) |
| RLS still works | untouched — no policy, grant or table-visibility change. New table is `service_role` only |
| Edge functions still work | verified by reading each affected handler (see §A/§E evidence) |
| API insert/update paths | `payments`, `collection_assignments`, `credit_investigations`, `disbursements` handlers read and confirmed compatible |
| Flutter app depends on no removed column | nothing removed |
| Loan application / approval / CI assignment / disbursement / payment recording / payment reversal / notifications / reports | not executed — run the flow tests after `db reset`; Dart unit tests are unaffected |

### Flows checked against the new enforcement (code evidence)

| Flow | File | Why it still passes |
|---|---|---|
| Office payment | `payments-manage` L154 | inserts `loan_schedule_id`, no assignment → trigger returns early |
| Rider collection | `collections-manage` L886 | `allocatePayment(db, loanId, …)` only returns schedules of `loan.id` derived from `assignment.loan_schedule_id` (L832) → same loan |
| Payment→assignment link repair | `collections-manage` L62–118 | matches the payment by the assignment's own schedule → same loan |
| Payment→schedule link repair | `collections-manage` L142–160 | copies the assignment's schedule when the payment's is NULL → same loan |
| Payment reversal | `payments-manage` L298 | only `status` is updated → trigger does not fire |
| CI assignment | `ci-manage` L88–145 | already rejects a 2nd active CI and marks superseded rows `reassigned` |
| Collection assign / request | `collections-manage` L441, L470 | already 409s when an active assignment exists |
| Disbursement (4 handlers) | `disbursements-*` | each refuses a 2nd row per loan (`400 DUPLICATE`) |
