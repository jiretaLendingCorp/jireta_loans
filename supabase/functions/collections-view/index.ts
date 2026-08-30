// supabase/functions/collections-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes actions through ONE deployable function using
// the `?fn=<action>` query parameter.
//
//   collections-get-list  →  ?fn=get-list
//   collections-get       →  ?fn=get&id=<assignment_id>
//
// The original action logic is preserved verbatim below.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser, AuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLoanFinancialsBatch } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

const COLLECTION_SELECT = `id, loan_schedule_id, status, collection_type, rider_id, assigned_by, requested_by, amount_collected, requested_amount, collection_schedule, response_at, completed_at, created_at,
  notes:collection_notes,
  proof_photo, borrower_signature, collection_photo,
  loan_schedule:loan_schedules(id, installment_number, due_date, amount_due, loan:loans(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, gcash_number, users!lender_profiles_id_fkey(first_name, last_name, phone_number, addresses:addresses(address_type, street, barangay, city, province, zip_code, latitude, longitude, is_primary))))),
  rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name)),
  assigned_by_user:users!collection_assignments_assigned_by_fkey(id, first_name, last_name)`;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/collections-get-list/index.ts] ─────────
        return await handleCollectionGetList(req);
      case 'get':
        // Single assignment by id (role-scoped), same shape as list rows.
        return await handleCollectionGet(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('collections-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

function scopeQueryToUser(query: any, user: AuthUser, riderId?: string | null) {
  if (user.role === ROLES.RIDER) return query.eq('rider_id', user.id);
  if (user.role === ROLES.LENDER) return query.eq('loan_schedule.loan.lender_id', user.id);
  if (riderId) return query.eq('rider_id', riderId);
  return query;
}

// Proof columns hold STORAGE PATHS (short, permanent). Convert them to
// fresh signed URLs here so every consumer (HM/employee/rider/lender
// screens) always receives a viewable link and old rows keep working.
const PROOF_FIELDS = ['proof_photo', 'borrower_signature', 'collection_photo'] as const;
async function signProof(db: ReturnType<typeof getAdminClient>, value: unknown): Promise<unknown> {
  if (typeof value !== 'string' || value.length === 0) return value;
  if (value.startsWith('http') || value.startsWith('data:')) return value;
  const { data: signed } = await db.storage.from('collection-proofs').createSignedUrl(value, 3600 * 24 * 7);
  return signed?.signedUrl ?? value;
}

async function mapRows(
  db: ReturnType<typeof getAdminClient>,
  data: Array<Record<string, any>>,
): Promise<Array<Record<string, any>>> {
  const loanIds = data.map((r) => embedAsObject(embedAsObject(r.loan_schedule)?.loan)?.id).filter(Boolean);
  const financials = await getLoanFinancialsBatch(db, loanIds);
  return Promise.all(data.map(async (r) => {
    const schedule = embedAsObject(r.loan_schedule);
    const loanEmbed = schedule ? embedAsObject(schedule.loan) : null;
    const lenderProf = loanEmbed ? embedAsObject(loanEmbed.lender_profiles) : null;
    const lenderUser = lenderProf ? embedAsObject(lenderProf.users) : null;
    const lenderAddresses = lenderUser && Array.isArray(lenderUser.addresses)
      ? lenderUser.addresses
      : [];
    const rider = embedAsObject(r.rider);
    const riderUser = rider ? embedAsObject(rider.users) : null;
    const loan = loanEmbed
      ? { ...loanEmbed, outstanding_balance: financials[loanEmbed.id]?.outstanding_balance ?? null }
      : null;
    const proofs: Record<string, unknown> = {};
    for (const field of PROOF_FIELDS) {
      proofs[field] = await signProof(db, r[field]);
    }
    return {
      ...r,
      ...proofs,
      loans: loan,
      // Flat convenience fields so every consumer (employee/HM/rider screens)
      // can render correctly regardless of which nested keys it reads.
      loan_number: loanEmbed?.loan_number ?? null,
      lender_name: [lenderUser?.first_name, lenderUser?.last_name].filter(Boolean).join(' ') || null,
      lender_phone: lenderUser?.phone_number ?? null,
      lender_gcash: lenderProf?.gcash_number ?? null,
      lender_addresses: lenderAddresses,
      rider_name: [riderUser?.first_name, riderUser?.last_name].filter(Boolean).join(' ') || null,
      amount_due: schedule?.amount_due ?? null,
      period_number: schedule?.installment_number ?? null,
      due_date: schedule?.due_date ?? null,
    };
  }));
}

// ── [moved from functions/collections-get-list/index.ts] ────────────────────
async function handleCollectionGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const url = new URL(req.url);
  const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
  const status = url.searchParams.get('status');
  const riderId = url.searchParams.get('rider_id');
  const offset = (page - 1) * limit;
  const db = getAdminClient();
  // Auto-expire overdue before listing so overdue assignments disappear
  // from rider's active tabs and a overdue notification is inserted.
  try { await (db as any).rpc('expire_overdue_assignments'); } catch (_) {}
  let query = db.from('collection_assignments')
    .select(COLLECTION_SELECT, { count: 'exact' });
  query = scopeQueryToUser(query, user, riderId);
  if (status) query = query.eq('status', status);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  // The deeply-nested renamed embeds in the select string trip supabase-js's
  // type-level PostgREST parser (ParserError), so the row type is re-typed
  // here. Runtime behavior is unchanged — PostgREST parses the query itself.
  const { data, error, count } = await query as unknown as {
    data: Array<Record<string, any>> | null;
    error: { message?: string } | null;
    count: number | null;
  };
  if (error) return errorResponse('Failed to fetch collections', 500, 'SERVER_ERROR');

  const mapped = await mapRows(db, data ?? []);
  return jsonResponse({ data: mapped, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
}

// ── [new] single assignment by id, role-scoped, identical row shape ─────────
async function handleCollectionGet(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const id = new URL(req.url).searchParams.get('id');
  if (!id) return errorResponse('id is required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  let query = db.from('collection_assignments').select(COLLECTION_SELECT);
  query = scopeQueryToUser(query, user);
  const { data, error } = await query.eq('id', id).maybeSingle() as unknown as {
    data: Record<string, any> | null;
    error: { message?: string } | null;
  };
  if (error) return errorResponse('Failed to fetch collection', 500, 'SERVER_ERROR');
  if (!data) return errorResponse('Collection not found', 404, 'NOT_FOUND');
  const [mapped] = await mapRows(db, [data]);
  return jsonResponse({ data: mapped });
}
