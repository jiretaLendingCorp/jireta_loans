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

// Matches lender_profiles.kyc_status CHECK constraint after migration 00006
// (adds 'not_submitted' and 'under_review' which were in types but missing from DB)
export type KycStatus =
  | 'not_submitted'
  | 'pending'
  | 'submitted'
  | 'under_review'
  | 'verified'
  | 'rejected';

export type AccountStatus = 'active' | 'inactive' | 'suspended' | 'archived';
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

export interface PaginatedResult<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}
