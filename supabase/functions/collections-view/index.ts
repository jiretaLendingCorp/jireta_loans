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
import { ROLES, requireRole } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination, validateUUID } from '../_shared/validators.ts';
import { getLoanFinancialsBatch } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';
import { dispatchPendingPushNotifications } from '../_shared/notifications.ts';
import { searchScheduleIds, NO_MATCH_ID } from '../_shared/search.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

// NOTE: `!inner` on loan_schedules/loans is REQUIRED, not cosmetic. PostgREST
// applies embedded filters to the embedded rows ONLY (left join semantics), so
// `scopeQueryToUser`'s `loan_schedule.loan.lender_id` filter alone returned
// EVERY lender's assignments — a brand-new lender account saw the previous
// account's collections in Recent Activity. `!inner` makes the join inner so
// the nested filter also restricts the top-level collection_assignments rows
// (same pattern as payments-view / kpi-view). collection_assignments.
// loan_schedule_id is NOT NULL, so no legitimate row is dropped by the inner
// join for rider / employee / head_manager callers.
const COLLECTION_SELECT = `id, loan_schedule_id, status, collection_type, rider_id, assigned_by, requested_by, requested_at, assigned_at, amount_collected, requested_amount, collection_schedule, response_at, completed_at, reviewed_by, reviewed_at, rejection_reason, created_at,
  notes:collection_notes,
  proof_photo, borrower_signature, collection_photo,
  loan_schedule:loan_schedules!inner(id, installment_number, due_date, amount_due, loan:loans!inner(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, gcash_number, users!lender_profiles_id_fkey(first_name, last_name, phone_number, addresses:addresses(address_type, street, barangay, city, province, zip_code, latitude, longitude, is_primary))))),
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
      case 'rider-monitoring':
        // Head Manager / Employee: per-rider monitoring table + summary cards.
        return await handleRiderMonitoring(req);
      case 'rider-monitoring-detail':
        // Head Manager / Employee: isang rider — accounts, payments, history.
        return await handleRiderMonitoringDetail(req);
      case 'my-collection-summary':
        // Rider: sariling totals lang. Hindi pwedeng mag-request ng ibang rider.
        return await handleMyCollectionSummary(req);
      case 'rider-quotas':
        // Head Manager / Employee: quota table + summary cards (read-only).
        return await handleRiderQuotas(req);
      case 'rider-quota-riders':
        // Head Manager / Employee: active riders para sa assign form.
        return await handleRiderQuotaRiders(req);
      case 'my-quota':
        // Rider: sariling quota lang — rider id galing sa token.
        return await handleMyQuota(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('collections-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// "All Pending Payment": lahat ng koleksyon na HINDI pa bayad/na-kolekta. Ang
// `status=pending` sa query ay hindi isang tunay na status ng assignment, kaya
// hindi ito sumasagasa sa `status` filter — ginagamit ito ng Collections screen
// (HM/Employee) para sa "All Pending Payment" pill.
const OPEN_COLLECTION_STATUSES = [
  'requested',
  'assigned',
  'accepted',
  'in_progress',
  'pending_approval',
];

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
  const search = url.searchParams.get('search');
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const offset = (page - 1) * limit;
  const db = getAdminClient();
  // Auto-expire overdue before listing so overdue assignments disappear
  // from rider's active tabs and a overdue notification is inserted.
  try { await (db as any).rpc('expire_overdue_assignments'); } catch (_) {}
  // Dispatch any notifications created by that expiry as device pushes
  // (claim-based — each notification is pushed at most once). Non-fatal.
  try { await dispatchPendingPushNotifications(); } catch (_) {}
  let query = db.from('collection_assignments')
    .select(COLLECTION_SELECT, { count: 'exact' });
  query = scopeQueryToUser(query, user, riderId);
  if (status === 'pending') {
    query = query.in('status', OPEN_COLLECTION_STATUSES);
  } else if (status) {
    query = query.eq('status', status);
  }
  if (search) {
    // PostgREST's `.or()` cannot parse embedded paths like
    // `loan_schedule.loan.lender_profiles.users.first_name.ilike` (throws
    // PGRST100, 500s the whole list). Resolve matches to loan_schedule IDs
    // first (loan_number ilike OR lender name via top-level `users` query),
    // then filter by `loan_schedule_id` — a plain top-level column.
    const scheduleIds = await searchScheduleIds(db, search);
    if (scheduleIds.length > 0) {
      query = query.in('loan_schedule_id', scheduleIds);
    } else {
      query = query.eq('loan_schedule_id', NO_MATCH_ID);
    }
  }
  if (dateFrom) query = query.gte('created_at', dateFrom);
  if (dateTo) query = query.lte('created_at', dateTo);
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

// ══════════════════════════════════════════════════════════════════════════
// RIDER COLLECTION MONITORING
//
// Lahat ng numero ay galing sa `rider_collection_monitoring` RPC (migration
// 00186), na binuo mula sa collection_assignments + loan_schedules +
// v_loan_schedules + verified payments. Read-only ang buong feature — walang
// payment na naitala, walang penalty, at walang loan status na binabago.
// ══════════════════════════════════════════════════════════════════════════

const MONITORING_STATUSES = new Set([
  'all',
  'active',
  'overdue',
  'has_collection',
  'no_collection',
]);

const MONITORING_SORT_KEYS = new Set([
  'rider_name',
  'assigned_accounts',
  'expected_collection',
  'confirmed_collection',
  'remaining_due',
  'overdue_accounts',
  'last_activity_at',
  'collection_performance',
]);

/** `YYYY-MM-DD` lang ang tinatanggap; walang implicit na timezone/date parse. */
function validDateOnly(value: string | null): string | null {
  if (!value) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const year = Number(value.slice(0, 4));
  if (year < 2000 || year > 2100) return null;
  const dt = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(dt.getTime())) return null;
  // Reject impossible dates like 2026-02-31 (JS rolls them over).
  if (dt.toISOString().slice(0, 10) !== value) return null;
  return value;
}

function parseDateRange(url: URL):
  | { from: string | null; to: string | null }
  | { error: Response } {
  const rawFrom = url.searchParams.get('date_from');
  const rawTo = url.searchParams.get('date_to');
  const from = rawFrom ? validDateOnly(rawFrom) : null;
  const to = rawTo ? validDateOnly(rawTo) : null;
  if (rawFrom && !from) {
    return { error: errorResponse('date_from must be a valid YYYY-MM-DD date', 400, 'VALIDATION_ERROR') };
  }
  if (rawTo && !to) {
    return { error: errorResponse('date_to must be a valid YYYY-MM-DD date', 400, 'VALIDATION_ERROR') };
  }
  if (from && to && from > to) {
    return { error: errorResponse('date_from must not be after date_to', 400, 'VALIDATION_ERROR') };
  }
  return { from, to };
}

/** Manila calendar day ng isang timestamp (YYYY-MM-DD). */
function manilaDay(value: unknown): string | null {
  if (value == null || value === '') return null;
  const ms = Date.parse(String(value));
  if (Number.isNaN(ms)) return String(value).slice(0, 10) || null;
  return new Date(ms + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

function inRange(day: string | null, from: string | null, to: string | null): boolean {
  if (!day) return !from && !to;
  if (from && day < from) return false;
  if (to && day > to) return false;
  return true;
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

function performance(confirmed: number, expected: number): number | null {
  if (!(expected > 0)) return null;
  return round1((confirmed / expected) * 100);
}

function sortMonitoringRows(rows: Array<Record<string, any>>, sort: string | null, dir: string | null) {
  const key = sort && MONITORING_SORT_KEYS.has(sort) ? sort : 'rider_name';
  const asc = (dir ?? 'asc').toLowerCase() !== 'desc';
  const copy = [...rows];
  copy.sort((a, b) => {
    const av = a[key];
    const bv = b[key];
    if (av == null && bv == null) return 0;
    if (av == null) return 1; // nulls last
    if (bv == null) return -1;
    let cmp: number;
    if (typeof av === 'number' && typeof bv === 'number') {
      cmp = av - bv;
    } else {
      cmp = String(av).localeCompare(String(bv));
    }
    return asc ? cmp : -cmp;
  });
  return copy;
}

async function handleRiderMonitoring(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const forbidden = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (forbidden) return forbidden;

  const url = new URL(req.url);
  const range = parseDateRange(url);
  if ('error' in range) return range.error;

  const rawStatus = (url.searchParams.get('status') ?? 'all').trim();
  const status = MONITORING_STATUSES.has(rawStatus) ? rawStatus : 'all';
  const search = (url.searchParams.get('search') ?? '').trim().slice(0, 100);
  const riderId = url.searchParams.get('rider_id');
  if (riderId && !validateUUID(riderId)) {
    return errorResponse('Invalid rider_id', 400, 'VALIDATION_ERROR');
  }
  const { page, limit } = validatePagination(
    url.searchParams.get('page'),
    url.searchParams.get('limit'),
  );

  const db = getAdminClient();
  const { data, error } = await db.rpc('rider_collection_monitoring', {
    p_rider_id: riderId ?? null,
    p_date_from: range.from,
    p_date_to: range.to,
    p_search: search || null,
    p_status: status,
  });
  if (error) {
    console.error('rider-monitoring rpc failed:', error.message);
    return errorResponse('Failed to load rider collection monitoring', 500, 'SERVER_ERROR');
  }

  const payload = (data ?? {}) as {
    rows?: Array<Record<string, any>>;
    summary?: Record<string, any>;
    generated_at?: string;
  };
  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  const sorted = sortMonitoringRows(rows, url.searchParams.get('sort'), url.searchParams.get('dir'));
  const total = sorted.length;
  const offset = (page - 1) * limit;
  const summaryRaw = payload.summary ?? {};
  const summary = {
    ...summaryRaw,
    collection_performance: performance(
      Number(summaryRaw.confirmed_collection ?? 0),
      Number(summaryRaw.expected_collection ?? 0),
    ),
  };

  return jsonResponse({
    data: sorted.slice(offset, offset + limit),
    summary,
    total,
    page,
    limit,
    totalPages: total === 0 ? 1 : Math.ceil(total / limit),
    generated_at: payload.generated_at ?? new Date().toISOString(),
    range: { date_from: range.from, date_to: range.to },
  });
}

function riderName(first?: unknown, last?: unknown): string {
  return [first, last]
    .map((v) => (typeof v === 'string' ? v.trim() : ''))
    .filter(Boolean)
    .join(' ');
}

async function handleRiderMonitoringDetail(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const forbidden = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (forbidden) return forbidden;

  const url = new URL(req.url);
  const riderId = url.searchParams.get('rider_id');
  if (!riderId || !validateUUID(riderId)) {
    return errorResponse('rider_id is required', 400, 'VALIDATION_ERROR');
  }
  const range = parseDateRange(url);
  if ('error' in range) return range.error;

  const db = getAdminClient();
  const { data: aggregate, error: aggError } = await db.rpc('rider_collection_monitoring', {
    p_rider_id: riderId,
    p_date_from: range.from,
    p_date_to: range.to,
    p_search: null,
    p_status: 'all',
  });
  if (aggError) {
    console.error('rider-monitoring-detail rpc failed:', aggError.message);
    return errorResponse('Failed to load rider monitoring', 500, 'SERVER_ERROR');
  }
  const aggregateRows = ((aggregate ?? {}) as { rows?: Array<Record<string, any>> }).rows ?? [];
  const monitoringRow = aggregateRows[0];
  if (!monitoringRow) {
    return errorResponse('Rider not found', 404, 'NOT_FOUND');
  }
  const summaryRaw = ((aggregate ?? {}) as { summary?: Record<string, any> }).summary ?? {};
  const summary = {
    ...summaryRaw,
    collection_performance: performance(
      Number(summaryRaw.confirmed_collection ?? 0),
      Number(summaryRaw.expected_collection ?? 0),
    ),
  };

  // ── Profile — limited to what the monitoring page actually displays. ──
  const { data: profileRow } = await db
    .from('users')
    .select(`id, first_name, last_name, phone_number, account_status, created_at, profile_photo_url,
      rider_profiles!rider_profiles_id_fkey(plate_number, vehicle_type, vehicle_brand, is_available),
      addresses(address_type, street, barangay, city, province, zip_code, is_primary)`)
    .eq('id', riderId)
    .maybeSingle();
  if (!profileRow) return errorResponse('Rider not found', 404, 'NOT_FOUND');
  const riderProfile = embedAsObject((profileRow as any).rider_profiles);
  const addresses = Array.isArray((profileRow as any).addresses) ? (profileRow as any).addresses : [];
  const primaryAddress = addresses.find((a: any) => a?.is_primary === true) ?? addresses[0] ?? null;
  const rider = {
    rider_id: riderId,
    rider_name: riderName((profileRow as any).first_name, (profileRow as any).last_name),
    first_name: (profileRow as any).first_name ?? null,
    last_name: (profileRow as any).last_name ?? null,
    phone_number: (profileRow as any).phone_number ?? null,
    account_status: (profileRow as any).account_status ?? null,
    joined_at: (profileRow as any).created_at ?? null,
    profile_photo_url: (profileRow as any).profile_photo_url ?? null,
    plate_number: riderProfile?.plate_number ?? null,
    vehicle_type: riderProfile?.vehicle_type ?? null,
    vehicle_brand: riderProfile?.vehicle_brand ?? null,
    is_available: riderProfile?.is_available ?? null,
    address: primaryAddress
      ? [primaryAddress.street, primaryAddress.barangay, primaryAddress.city, primaryAddress.province]
          .filter(Boolean)
          .join(', ')
      : null,
  };

  // ── Assignments (bounded — isang rider lang at may date filter). ──
  // `payments` embed ay hindi ini-join sa verified lang dito; kino-classify sa
  // TS para makita rin ang pending/rejected sa history nang walang ekstrang
  // query. Isang bayad = isang `collection_assignment_id`, kaya dedupe by id.
  const { data: assignmentRows, error: assignmentError } = await db
    .from('collection_assignments')
    .select(`id, loan_schedule_id, status, collection_type, collection_schedule,
      amount_collected, completed_at, created_at, rejection_reason, collection_notes,
      loan_schedule:loan_schedules!inner(id, installment_number, due_date, amount_due, loan_id,
        loan:loans!inner(id, loan_number, status, lender_id,
          lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name, phone_number)))),
      payments(id, amount, status, payment_method, paid_at)`)
    .eq('rider_id', riderId)
    .order('created_at', { ascending: false })
    .limit(1000);
  if (assignmentError) {
    console.error('rider monitoring assignments failed:', assignmentError.message);
    return errorResponse('Failed to load rider collections', 500, 'SERVER_ERROR');
  }
  const assignments = ((assignmentRows ?? []) as Array<Record<string, any>>);

  // Schedule-level paid/status mula sa canonical na v_loan_schedules.
  const scheduleIds = [...new Set(assignments.map((a) => a.loan_schedule_id).filter(Boolean))] as string[];
  const scheduleInfo: Record<string, { amount_paid: number; status: string | null }> = {};
  for (let i = 0; i < scheduleIds.length; i += 200) {
    const chunk = scheduleIds.slice(i, i + 200);
    const { data: scheduleRows } = await db
      .from('v_loan_schedules')
      .select('id, amount_paid, status')
      .in('id', chunk);
    for (const row of (scheduleRows ?? []) as Array<Record<string, any>>) {
      scheduleInfo[String(row.id)] = {
        amount_paid: Number(row.amount_paid ?? 0),
        status: row.status ?? null,
      };
    }
  }

  // Verified payments — deduped by payment id (isang bayad, isang bilihan).
  const paymentById = new Map<string, Record<string, any>>();
  const confirmedBySchedule = new Map<string, number>();
  for (const a of assignments) {
    const schedule = embedAsObject(a.loan_schedule);
    const loan = schedule ? embedAsObject(schedule.loan) : null;
    const lenderProfile = loan ? embedAsObject(loan.lender_profiles) : null;
    const lenderUser = lenderProfile ? embedAsObject(lenderProfile.users) : null;
    const payments = Array.isArray(a.payments) ? a.payments : [];
    for (const p of payments) {
      if (p?.status !== 'verified') continue;
      const id = String(p.id);
      if (!paymentById.has(id)) {
        paymentById.set(id, {
          id,
          amount: Number(p.amount ?? 0),
          method: p.payment_method ?? null,
          paid_at: p.paid_at ?? null,
          loan_number: loan?.loan_number ?? null,
          lender_name: riderName(lenderUser?.first_name, lenderUser?.last_name),
          installment_number: schedule?.installment_number ?? null,
          due_date: schedule?.due_date ?? null,
          scheduled_amount_due: schedule ? Number(schedule.amount_due ?? 0) : null,
        });
        // Isang bayad → isang schedule. Ang pagsama nito sa `if` ay
        // nagpapatunay na hindi ito madodoble kahit lumitaw ang parehong
        // payment id sa dalawang assignment embed.
        const key = String(a.loan_schedule_id ?? '');
        confirmedBySchedule.set(key, round1((confirmedBySchedule.get(key) ?? 0) + Number(p.amount ?? 0)));
      }
    }
  }

  // ── Accounts grouped by loan (installments deduped per schedule). ──
  const accountMap = new Map<string, Record<string, any>>();
  const seenSchedule = new Set<string>();
  for (const a of assignments) {
    const schedule = embedAsObject(a.loan_schedule);
    if (!schedule) continue;
    const loan = embedAsObject(schedule.loan);
    if (!loan) continue;
    const dueDay = typeof schedule.due_date === 'string' ? schedule.due_date.slice(0, 10) : null;
    if (!inRange(dueDay, range.from, range.to)) continue;

    const loanId = String(loan.id);
    let account = accountMap.get(loanId);
    if (!account) {
      const lenderProfile = embedAsObject(loan.lender_profiles);
      const lenderUser = lenderProfile ? embedAsObject(lenderProfile.users) : null;
      account = {
        loan_number: loan.loan_number ?? null,
        loan_status: loan.status ?? null,
        lender_name: riderName(lenderUser?.first_name, lenderUser?.last_name) || null,
        lender_phone: lenderUser?.phone_number ?? null,
        outstanding_balance: null,
        assigned_installments: 0,
        expected_collection: 0,
        confirmed_collection: 0,
        remaining_due: 0,
        overdue_installments: 0,
        schedules: [] as Array<Record<string, any>>,
      };
      accountMap.set(loanId, account);
    }

    const scheduleId = String(schedule.id);
    const info = scheduleInfo[scheduleId];
    const amountDue = Number(schedule.amount_due ?? 0);
    const amountPaid = Number(info?.amount_paid ?? 0);
    const remaining = Math.max(0, Math.round((amountDue - amountPaid) * 100) / 100);
    const scheduleStatus = info?.status ??
      (remaining <= 0 ? 'paid' : amountPaid > 0 ? 'partial' : 'pending');

    if (seenSchedule.has(scheduleId)) {
      // Isang installment pero maraming assignment — pagsamahin ang rider
      // confirmed para hindi mawala ang bayad na naitala sa ibang assignment.
      continue;
    }
    seenSchedule.add(scheduleId);

    account.schedules.push({
      installment_number: schedule.installment_number ?? null,
      due_date: dueDay,
      amount_due: amountDue,
      amount_paid: amountPaid,
      remaining_due: remaining,
      status: scheduleStatus,
      confirmed_collection: confirmedBySchedule.get(scheduleId) ?? 0,
      last_assignment_status: a.status ?? null,
    });
    account.assigned_installments += 1;
    account.expected_collection = round1(account.expected_collection + amountDue);
    account.confirmed_collection = round1(account.confirmed_collection + (confirmedBySchedule.get(scheduleId) ?? 0));
    account.remaining_due = round1(account.remaining_due + remaining);
    if (scheduleStatus === 'overdue') account.overdue_installments += 1;
  }

  const loanIds = [...accountMap.keys()];
  const financials = await getLoanFinancialsBatch(db, loanIds);
  for (const [loanId, account] of accountMap) {
    account.outstanding_balance = financials[loanId]?.outstanding_balance ?? null;
    account.schedules.sort((x: any, y: any) => String(x.due_date ?? '').localeCompare(String(y.due_date ?? '')));
    account.next_due_date = account.schedules.find((s: any) => s.status !== 'paid')?.due_date ?? null;
  }

  // ── Payment activity (verified only) at collection history. ──
  const payments = [...paymentById.values()]
    .filter((p) => inRange(manilaDay(p.paid_at), range.from, range.to))
    .sort((a, b) => String(b.paid_at ?? '').localeCompare(String(a.paid_at ?? '')))
    .slice(0, 200);

  const history = assignments
    .map((a) => {
      const schedule = embedAsObject(a.loan_schedule);
      const loan = schedule ? embedAsObject(schedule.loan) : null;
      const lenderProfile = loan ? embedAsObject(loan.lender_profiles) : null;
      const lenderUser = lenderProfile ? embedAsObject(lenderProfile.users) : null;
      const activityAt = a.completed_at ?? a.created_at ?? null;
      return {
        assignment_id: a.id,
        loan_number: loan?.loan_number ?? null,
        lender_name: riderName(lenderUser?.first_name, lenderUser?.last_name) || null,
        installment_number: schedule?.installment_number ?? null,
        due_date: schedule?.due_date ?? null,
        status: a.status ?? null,
        collection_type: a.collection_type ?? null,
        amount_collected: a.amount_collected == null ? null : Number(a.amount_collected),
        scheduled_amount_due: schedule ? Number(schedule.amount_due ?? 0) : null,
        scheduled_at: a.collection_schedule ?? null,
        activity_at: activityAt,
        completed_at: a.completed_at ?? null,
        rejection_reason: a.rejection_reason ?? null,
        // System note ng auto-expiry ('expired: no action within 48h' o
        // '[auto-expired: overdue]') — ito ang ipinapaliwanag ng History kung
        // bakit na-`failed` ang isang assignment.
        notes: a.collection_notes ?? null,
      };
    })
    .filter((h) => inRange(manilaDay(h.activity_at), range.from, range.to))
    .sort((a, b) => String(b.activity_at ?? '').localeCompare(String(a.activity_at ?? '')))
    .slice(0, 200);

  const accounts = [...accountMap.values()]
    .sort((a, b) => String(a.lender_name ?? '').localeCompare(String(b.lender_name ?? '')));

  return jsonResponse({
    data: {
      rider,
      summary,
      monitoring: monitoringRow,
      accounts,
      payments,
      history,
    },
    range: { date_from: range.from, date_to: range.to },
    generated_at: new Date().toISOString(),
  });
}

async function handleMyCollectionSummary(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  if (authResult.role !== ROLES.RIDER) {
    return errorResponse('Access denied', 403, 'FORBIDDEN');
  }
  const range = parseDateRange(new URL(req.url));
  if ('error' in range) return range.error;

  const db = getAdminClient();
  // Rider id ay LAGING galing sa token — hindi kailanman sa query string.
  const { data, error } = await db.rpc('rider_collection_monitoring', {
    p_rider_id: authResult.id,
    p_date_from: range.from,
    p_date_to: range.to,
    p_search: null,
    p_status: 'all',
  });
  if (error) {
    console.error('my-collection-summary rpc failed:', error.message);
    return errorResponse('Failed to load collection summary', 500, 'SERVER_ERROR');
  }
  const payload = (data ?? {}) as { rows?: Array<Record<string, any>>; summary?: Record<string, any> };
  const summaryRaw = payload.summary ?? {};
  const summary = {
    ...summaryRaw,
    collection_performance: performance(
      Number(summaryRaw.confirmed_collection ?? 0),
      Number(summaryRaw.expected_collection ?? 0),
    ),
  };
  return jsonResponse({
    data: {
      summary,
      rider: (payload.rows ?? [])[0] ?? null,
    },
    range: { date_from: range.from, date_to: range.to },
    generated_at: new Date().toISOString(),
  });
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

// ══════════════════════════════════════════════════════════════════════════
// RIDER QUOTA MANAGEMENT (migration 00187)
//
// Confirmed collections = verified payments LANG na naka-link sa assignment
// ng rider at pumapasok sa [start_date, end_date] ng quota (Asia/Manila).
// Status ay derived sa RPC mula sa dates at sa result — hindi free-text.
// Read-only ang function na ito; ang create/update/close ay nasa
// `collections-manage` at Head-Manager-only.
// ══════════════════════════════════════════════════════════════════════════

const QUOTA_PERIODS = new Set(['daily', 'weekly', 'monthly']);
const QUOTA_STATUSES = new Set([
  'all',
  'upcoming',
  'active',
  'completed',
  'expired',
  'inactive',
]);

const QUOTA_SORT_KEYS = new Set([
  'rider_name',
  'start_date',
  'end_date',
  'target_amount',
  'confirmed_collection',
  'remaining_target',
  'completion_percentage',
]);

function sortQuotaRows(
  rows: Array<Record<string, any>>,
  sort: string | null,
  dir: string | null,
) {
  const key = sort && QUOTA_SORT_KEYS.has(sort) ? sort : 'start_date';
  const asc = (dir ?? (key === 'start_date' ? 'desc' : 'asc')).toLowerCase() !== 'desc';
  const copy = [...rows];
  copy.sort((a, b) => {
    const av = a[key];
    const bv = b[key];
    if (av == null && bv == null) return 0;
    if (av == null) return 1; // nulls last
    if (bv == null) return -1;
    const cmp =
      typeof av === 'number' && typeof bv === 'number'
        ? av - bv
        : String(av).localeCompare(String(bv));
    return asc ? cmp : -cmp;
  });
  return copy;
}

async function handleRiderQuotas(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const forbidden = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (forbidden) return forbidden;

  const url = new URL(req.url);
  const range = parseDateRange(url);
  if ('error' in range) return range.error;

  const riderId = url.searchParams.get('rider_id');
  if (riderId && !validateUUID(riderId)) {
    return errorResponse('Invalid rider_id', 400, 'VALIDATION_ERROR');
  }
  const rawPeriod = (url.searchParams.get('period') ?? '').trim().toLowerCase();
  if (rawPeriod && !QUOTA_PERIODS.has(rawPeriod)) {
    return errorResponse('period must be daily, weekly or monthly', 400, 'VALIDATION_ERROR');
  }
  const rawStatus = (url.searchParams.get('status') ?? 'all').trim().toLowerCase();
  const status = QUOTA_STATUSES.has(rawStatus) ? rawStatus : 'all';
  const search = (url.searchParams.get('search') ?? '').trim().slice(0, 100);
  const { page, limit } = validatePagination(
    url.searchParams.get('page'),
    url.searchParams.get('limit'),
  );

  const db = getAdminClient();
  const { data, error } = await db.rpc('rider_quota_monitoring', {
    p_rider_id: riderId ?? null,
    p_period: rawPeriod || null,
    p_status: status,
    p_date_from: range.from,
    p_date_to: range.to,
    p_search: search || null,
  });
  if (error) {
    console.error('rider-quotas rpc failed:', error.message);
    return errorResponse('Failed to load rider quotas', 500, 'SERVER_ERROR');
  }

  const payload = (data ?? {}) as {
    rows?: Array<Record<string, any>>;
    summary?: Record<string, any>;
    generated_at?: string;
  };
  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  const sorted = sortQuotaRows(
    rows,
    url.searchParams.get('sort'),
    url.searchParams.get('dir'),
  );
  const total = sorted.length;
  const offset = (page - 1) * limit;

  return jsonResponse({
    data: sorted.slice(offset, offset + limit),
    summary: payload.summary ?? {},
    total,
    page,
    limit,
    totalPages: total === 0 ? 1 : Math.ceil(total / limit),
    generated_at: payload.generated_at ?? new Date().toISOString(),
    range: { date_from: range.from, date_to: range.to },
  });
}

async function handleRiderQuotaRiders(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const forbidden = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (forbidden) return forbidden;

  const db = getAdminClient();
  const { data: roleRow } = await db
    .from('roles')
    .select('id')
    .eq('name', ROLES.RIDER)
    .maybeSingle();
  if (!roleRow) return jsonResponse({ data: [] });

  const { data, error } = await db
    .from('users')
    .select(
      'id, first_name, last_name, phone_number, account_status, rider_profiles!rider_profiles_id_fkey(is_available)',
    )
    .eq('role_id', (roleRow as { id: string }).id)
    .eq('account_status', 'active')
    .order('first_name', { ascending: true });
  if (error) {
    console.error('rider-quota-riders failed:', error.message);
    return errorResponse('Failed to load riders', 500, 'SERVER_ERROR');
  }

  const riders = (data ?? []).map((row: any) => {
    const profile = embedAsObject(row.rider_profiles);
    return {
      rider_id: row.id,
      rider_name: riderName(row.first_name, row.last_name) || null,
      phone_number: row.phone_number ?? null,
      is_available: profile?.is_available ?? null,
    };
  });

  return jsonResponse({ data: riders });
}

async function handleMyQuota(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const forbidden = requireRole(authResult, ROLES.RIDER);
  if (forbidden) return forbidden;

  const db = getAdminClient();
  // Rider id ay LAGING galing sa token — hindi kailanman sa query string.
  const { data, error } = await db.rpc('rider_quota_self', {
    p_rider_id: authResult.id,
  });
  if (error) {
    console.error('my-quota rpc failed:', error.message);
    return errorResponse('Failed to load your quota', 500, 'SERVER_ERROR');
  }

  return jsonResponse({ data: data ?? {} });
}
