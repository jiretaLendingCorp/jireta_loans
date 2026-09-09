// supabase/functions/_shared/search.ts
// ─────────────────────────────────────────────────────────────────────────────
// Free-text search helpers for the merged list endpoints.
//
// PostgREST's `.or()` logic tree CANNOT parse embedded resource paths — a
// filter like `lender_profiles.users.first_name.ilike.%x%` throws PGRST100
// ("unexpected 'u' expecting 'not' or operator"), which turns every name
// search into a 500. The workaround: resolve the term against the `users`
// table first (top-level `or()` parses fine there), collect matching IDs,
// then apply a plain `in(...)` filter on the caller's top-level columns.
// ─────────────────────────────────────────────────────────────────────────────
import type { DbClient } from './types.ts';

// Strip PostgREST filter metacharacters so user input can't break `.or()`.
function stripFilterMeta(raw: unknown): string {
  return String(raw ?? '').replace(/[(),.%*[\].]/g, '');
}

/** Sentinel UUID that never matches — used to force an empty result set. */
export const NO_MATCH_ID = '00000000-0000-0000-0000-000000000000';

/**
 * User (lender) IDs whose first/last name contains the term.
 * `users` is queried directly so `.or()` only touches top-level columns.
 */
export async function searchUserIdsByName(
  db: DbClient,
  raw: unknown,
): Promise<string[]> {
  const term = stripFilterMeta(raw);
  if (!term) return [];
  const { data } = await db
    .from('users')
    .select('id')
    .or(`first_name.ilike.%${term}%,last_name.ilike.%${term}%`);
  return (data ?? []).map((u) => u.id);
}

/**
 * Loan IDs whose loan_number OR lender name matches the term.
 * Used by list endpoints that search "loan number + borrower name".
 */
export async function searchLoanIds(
  db: DbClient,
  raw: unknown,
): Promise<string[]> {
  const term = stripFilterMeta(raw);
  if (!term) return [];
  const lenderIds = await searchUserIdsByName(db, term);
  let q = db.from('loans').select('id');
  if (lenderIds.length > 0) {
    q = q.or(`loan_number.ilike.%${term}%,lender_id.in.(${lenderIds.join(',')})`);
  } else {
    q = q.ilike('loan_number', `%${term}%`);
  }
  const { data } = await q;
  return (data ?? []).map((l) => l.id);
}

/**
 * loan_schedule IDs belonging to loans that match the term.
 * Used by endpoints that filter on `loan_schedule_id` (collections, payments).
 */
export async function searchScheduleIds(
  db: DbClient,
  raw: unknown,
): Promise<string[]> {
  const loanIds = await searchLoanIds(db, raw);
  if (loanIds.length === 0) return [];
  const { data } = await db
    .from('loan_schedules')
    .select('id')
    .in('loan_id', loanIds);
  return (data ?? []).map((s) => s.id);
}