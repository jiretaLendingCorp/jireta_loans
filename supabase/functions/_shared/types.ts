// supabase/functions/_shared/types.ts

export type Role = 'head_manager' | 'employee' | 'rider' | 'lender';

// Matches loans.status CHECK constraint after migration 00006
// (renames schema value kyc_required → ci_required to match application code)
export type LoanStatus =
  | 'pending'
  | 'under_review'
  | 'ci_required'
  | 'ci_assigned'
  | 'ci_completed'
  | 'approved'
  | 'active'
  | 'completed'
  | 'overdue'
  | 'rejected'
  | 'cancelled';

// Matches lender_profiles.account_upgrade_status CHECK constraint after migration 00006
// (adds 'not_submitted' and 'under_review' which were in types but missing from DB)
export type AccountUpgradeStatus =
  | 'not_submitted'
  | 'pending'
  | 'submitted'
  | 'under_review'
  | 'verified'
  | 'rejected';

export type AccountStatus = 'active' | 'inactive' | 'archived';
export type PaymentMethod = 'gcash' | 'office_cash' | 'rider_collection';
export type PaymentStatus = 'pending' | 'verified' | 'reversed' | 'failed';
export type Frequency = 'daily' | 'weekly' | 'monthly';
export type CiStatus =
  | 'pending'
  | 'accepted'
  | 'declined'
  | 'in_progress'
  | 'completed';
export type CollectionStatus =
  | 'assigned'
  | 'accepted'
  | 'declined'
  | 'in_progress'
  | 'completed'
  | 'failed';
export type DisbursementMethod = 'gcash' | 'office_cash' | 'rider_delivery';

// The service-role Supabase client returned by getAdminClient().
export type DbClient = ReturnType<typeof import('./db.ts').getAdminClient>;

export interface PaginatedResult<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// PostgREST returns a single object for to-one embeds (FK relationships), but
// supabase-js's generic inference models every embed as an array. These types
// re-shape inferred rows so embeds can be accessed as objects, matching the
// runtime shape. They are type-level only and never change runtime values.

type UnwrapEmbed<V> = V extends null | undefined
  ? (NonNullable<V> extends readonly (infer U)[] ? U | null : V)
  : (V extends readonly (infer U)[] ? U : V);

export type RowWithObjectEmbeds<T> = {
  [K in keyof T]: UnwrapEmbed<T[K]>;
};

export type RowsWithObjectEmbeds<T extends readonly unknown[] | null | undefined> =
  NonNullable<T> extends readonly (infer E)[] ? RowWithObjectEmbeds<E>[] | null : never;

/** Re-type a multi-row query result so to-one embeds are objects. No runtime change. */
export function rowsWithObjectEmbeds<T extends readonly unknown[] | null | undefined>(
  rows: T,
): RowsWithObjectEmbeds<T> {
  return rows as unknown as RowsWithObjectEmbeds<T>;
}

/** Re-type a single-row query result so to-one embeds are objects. No runtime change. */
export function singleWithObjectEmbeds<T>(row: T): RowWithObjectEmbeds<NonNullable<T>> | null {
  return (row ?? null) as unknown as RowWithObjectEmbeds<NonNullable<T>> | null;
}

// PostgREST to-one embeds are objects at runtime; supabase-js types them as
// arrays. This unwraps either shape to the object form (arrays → first
// element) so nested embeds can be accessed as objects.
export type EmbedSource<T> = T | T[] | null | undefined;

export function embedAsObject<T>(v: EmbedSource<T>): T | null {
  if (Array.isArray(v)) return v[0] ?? null;
  return (v as T | null) ?? null;
}
