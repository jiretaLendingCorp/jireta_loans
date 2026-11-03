// supabase/functions/account-delete/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNT DELETION — Google Play compliance.
//
//   ?fn=request          (PUBLIC, no JWT)  → creates a deletion request for the
//                                            public https://www.jireta.com/delete-account
//                                            page. Identity is verified by staff
//                                            out-of-band before processing.
//   ?fn=delete-self      (JWT)             → lender/rider deletes their own
//                                            account from Profile → Delete Account.
//   ?fn=list-requests    (head_manager)    → pending queue for staff.
//   ?fn=process-request  (head_manager)    → approve (run deletion) or reject.
//
// The database work is one SECURITY DEFINER transaction
// (`public.delete_user_account`, migration 00195). It keeps `auth.users` but
// anonymizes it, because deleting the auth row would cascade to
// users → lender_profiles → loans and destroy financial records.
//
// WHAT IS DELETED : profile, contact info, addresses, emergency contacts,
//                   KYC/account-upgrade documents + files, devices, FCM
//                   tokens, notifications, MPIN, OTPs, sessions, auth identity.
// WHAT IS KEPT    : loans, schedules, payments, disbursements, collections,
//                   credit investigations, auth/audit logs — required for the
//                   lending company's legal/accounting retention period.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { requireAuth } from '../_shared/auth.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import {
  buildDeletionReference,
  hashDeletionIdentifier,
  isDeletionReference,
  maskIdentifier,
  normalizeDeletionIdentifier,
  sanitizeDeletionReason,
  summarizeDeletionResult,
} from '../_shared/account_deletion.ts';
import {
  errorResponse,
  handleCors,
  jsonResponse,
} from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';

type Db = ReturnType<typeof getAdminClient>;

const DEFAULT_ACTION = 'request';
const MAX_BODY_BYTES = 16_384;
const PUBLIC_RATE_LIMIT = 5;
const PUBLIC_RATE_WINDOW_MS = 15 * 60 * 1000;
const REVIEW_WINDOW_DAYS = 7;

/** Local (per-isolate) abuse guard; the DB duplicate check is the real one. */
const publicHits = new Map<string, number[]>();

function clientIp(req: Request): string {
  const forwarded = req.headers.get('x-forwarded-for') ?? '';
  return forwarded.split(',')[0]?.trim() || 'unknown';
}

function rateLimited(ip: string, now = Date.now()): boolean {
  const recent = (publicHits.get(ip) ?? []).filter(
    (t) => now - t < PUBLIC_RATE_WINDOW_MS,
  );
  if (recent.length >= PUBLIC_RATE_LIMIT) {
    publicHits.set(ip, recent);
    return true;
  }
  recent.push(now);
  publicHits.set(ip, recent);
  return false;
}

async function readJsonBody(req: Request): Promise<Record<string, unknown> | null> {
  const declared = Number(req.headers.get('content-length') ?? '0');
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return null;
  try {
    const body = await req.json();
    if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
    return body as Record<string, unknown>;
  } catch {
    return null;
  }
}

function roleName(roles: unknown): string | null {
  if (Array.isArray(roles)) {
    const first = roles[0] as { name?: unknown } | undefined;
    return typeof first?.name === 'string' ? first.name : null;
  }
  if (roles && typeof roles === 'object') {
    const name = (roles as { name?: unknown }).name;
    return typeof name === 'string' ? name : null;
  }
  return null;
}

async function findUserByIdentifier(
  db: Db,
  identifier: NonNullable<ReturnType<typeof normalizeDeletionIdentifier>>,
) {
  const columns =
    'id, email, phone_number, profile_photo_url, account_status, account_deleted_at, roles!users_role_id_fkey(name)';

  if (identifier.type === 'email') {
    // ILIKE is case-insensitive, but `%`/`_` must be escaped so an email
    // containing them cannot turn into a wildcard that matches another user.
    const pattern = identifier.value.replace(/([\\%_])/g, '\\$1');
    const { data } = await db
      .from('users')
      .select(columns)
      .ilike('email', pattern)
      .maybeSingle();
    return data as Record<string, unknown> | null;
  }

  const { data } = await db
    .from('users')
    .select(columns)
    .in('phone_number', [identifier.value, identifier.e164])
    .maybeSingle();
  return data as Record<string, unknown> | null;
}

function hashPepper(): string {
  return (Deno.env.get('ACCOUNT_DELETION_PEPPER') ?? '').trim() ||
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ||
    'jireta-account-deletion';
}

function deletionError(message: string): {
  status: number;
  code: string;
  message: string;
} {
  const text = message ?? '';
  if (text.includes('OPEN_LOANS')) {
    const match = text.match(/OPEN_LOANS:([a-z_,]+)/i);
    const statuses = match?.[1] ?? 'active,overdue';
    return {
      status: 409,
      code: 'OUTSTANDING_LOAN',
      message:
        `This account still has an outstanding loan (${statuses}). Settle the balance first, then request deletion again.`,
    };
  }
  if (text.includes('OPEN_COLLECTIONS')) {
    return {
      status: 409,
      code: 'OPEN_COLLECTIONS',
      message:
        'This rider account still has open collection assignments. Complete or return them first.',
    };
  }
  if (text.includes('OPEN_CREDIT_INVESTIGATIONS')) {
    return {
      status: 409,
      code: 'OPEN_CREDIT_INVESTIGATIONS',
      message:
        'This rider account still has open credit investigations. Complete them first.',
    };
  }
  if (text.includes('OPEN_DISBURSEMENTS')) {
    return {
      status: 409,
      code: 'OPEN_DISBURSEMENTS',
      message:
        'This rider account still has an in-progress disbursement. Complete it first.',
    };
  }
  if (text.includes('ALREADY_DELETED')) {
    return {
      status: 409,
      code: 'ALREADY_DELETED',
      message: 'This account has already been deleted.',
    };
  }
  if (text.includes('ROLE_NOT_DELETABLE')) {
    return {
      status: 403,
      code: 'ROLE_NOT_DELETABLE',
      message:
        'Staff accounts (head manager / employee) cannot be deleted here. Contact HR or the system administrator.',
    };
  }
  if (text.includes('ACCOUNT_NOT_FOUND')) {
    return {
      status: 404,
      code: 'ACCOUNT_NOT_FOUND',
      message: 'No account matched that number or email.',
    };
  }
  console.error('[account-delete] unexpected RPC error:', text);
  return {
    status: 500,
    code: 'DELETION_FAILED',
    message: 'Account deletion failed. Please try again or contact support.',
  };
}

/** Removes profile photo + KYC files. Best effort; the DB scrub already ran. */
async function cleanupStorage(
  db: Db,
  userId: string,
  profilePhotoUrl: string | null,
): Promise<{ avatar_removed: boolean; document_objects_removed: number; warnings: string[] }> {
  const warnings: string[] = [];
  let avatarRemoved = false;
  let docsRemoved = 0;

  if (profilePhotoUrl) {
    const marker = '/storage/v1/object/public/avatars/';
    const index = profilePhotoUrl.indexOf(marker);
    if (index >= 0) {
      try {
        const path = decodeURIComponent(
          profilePhotoUrl.slice(index + marker.length).split('?')[0],
        );
        if (path) {
          const { error } = await db.storage.from('avatars').remove([path]);
          if (error) warnings.push(`avatar: ${error.message}`);
          else avatarRemoved = true;
        }
      } catch (err) {
        warnings.push(`avatar: ${String(err)}`);
      }
    }
  }

  const prefix = `account-upgrade/${userId}`;
  const { data, error } = await db.storage
    .from('account-upgrade-documents')
    .list(prefix, { limit: 1000 });

  if (error) {
    // A missing folder is normal (user never submitted KYC).
    if (!error.message.toLowerCase().includes('not found')) {
      warnings.push(`account-upgrade-documents: ${error.message}`);
    }
  } else if (data && data.length > 0) {
    const paths = data.map((entry) => `${prefix}/${entry.name}`);
    const { error: removeError } = await db.storage
      .from('account-upgrade-documents')
      .remove(paths);
    if (removeError) warnings.push(`account-upgrade-documents: ${removeError.message}`);
    else docsRemoved = paths.length;
  }

  return {
    avatar_removed: avatarRemoved,
    document_objects_removed: docsRemoved,
    warnings,
  };
}

interface DeletionOutcome {
  ok: boolean;
  status: number;
  code?: string;
  message: string;
  summary?: ReturnType<typeof summarizeDeletionResult>;
  storage?: Awaited<ReturnType<typeof cleanupStorage>>;
}

async function performDeletion(
  db: Db,
  userId: string,
  actorId: string | null,
  req: Request,
  source: 'in_app' | 'web',
  reason: string,
): Promise<DeletionOutcome> {
  // Reviewer accounts keep Play Console access working — never delete them.
  const { data: authRow } = await db.auth.admin.getUserById(userId);
  if (authRow?.user?.app_metadata?.reviewer === true) {
    return {
      ok: false,
      status: 403,
      code: 'REVIEWER_NOT_ALLOWED',
      message: 'Reviewer accounts cannot be deleted.',
    };
  }

  const { data: before } = await db
    .from('users')
    .select('id, email, phone_number, profile_photo_url, account_status')
    .eq('id', userId)
    .maybeSingle();

  if (!before) {
    return {
      ok: false,
      status: 404,
      code: 'ACCOUNT_NOT_FOUND',
      message: 'No account matched that number or email.',
    };
  }

  const { data, error } = await db.rpc('delete_user_account', {
    p_user_id: userId,
  });

  if (error) {
    const mapped = deletionError(error.message ?? '');
    return { ok: false, status: mapped.status, code: mapped.code, message: mapped.message };
  }

  const summary = summarizeDeletionResult(data);
  // The DB scrub already committed. A storage hiccup must NOT turn a
  // successful deletion into a 500 — report it as a warning instead.
  let storage: Awaited<ReturnType<typeof cleanupStorage>>;
  try {
    storage = await cleanupStorage(
      db,
      userId,
      typeof before.profile_photo_url === 'string' ? before.profile_photo_url : null,
    );
  } catch (err) {
    console.error('[account-delete] storage cleanup failed:', err);
    storage = {
      avatar_removed: false,
      document_objects_removed: 0,
      warnings: [`storage cleanup failed: ${String(err)}`],
    };
  }

  // Close any pending public requests for this account. Best effort: the
  // deletion already committed, so a queue-update failure is not fatal.
  try {
    await db
      .from('account_deletion_requests')
      .update({
        status: 'completed',
        processed_at: new Date().toISOString(),
        processed_by: actorId,
        identifier: null,
        full_name: null,
        notes: reason || null,
      })
      .eq('user_id', userId)
      .in('status', ['pending', 'processing']);
  } catch (err) {
    console.error('[account-delete] request close failed:', err);
  }

  await writeAuditLog({
    performedBy: actorId,
    action: 'account_deleted',
    tableName: 'users',
    recordId: userId,
    oldValues: {
      email: maskIdentifier('email', String(before.email ?? 'unknown@unknown')),
      phone: before.phone_number
        ? maskIdentifier('phone', String(before.phone_number))
        : null,
      account_status: before.account_status,
    },
    newValues: {
      source,
      cancelled_loans: summary.cancelled_loans,
      storage_warnings: storage.warnings,
    },
    ipAddress: clientIp(req),
  });

  return { ok: true, status: 200, message: 'Account deleted.', summary, storage };
}

// ── PUBLIC: request deletion ────────────────────────────────────────────────
async function handlePublicRequest(req: Request): Promise<Response> {
  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse('Invalid request body.', 400, 'VALIDATION_ERROR', undefined, req);
  }

  const ip = clientIp(req);
  if (rateLimited(ip)) {
    return errorResponse(
      'Too many deletion requests. Please wait 15 minutes and try again.',
      429,
      'RATE_LIMITED',
      undefined,
      req,
    );
  }

  const identifier = normalizeDeletionIdentifier(body.identifier ?? body.phone ?? body.email);
  if (!identifier) {
    return errorResponse(
      'Enter the mobile number or email registered to your Jireta Loans account.',
      400,
      'INVALID_IDENTIFIER',
      undefined,
      req,
    );
  }

  const fullName = sanitizeString(body.full_name);
  if (fullName.length < 2 || fullName.length > 200) {
    return errorResponse(
      'Enter the full name on the account.',
      400,
      'INVALID_NAME',
      undefined,
      req,
    );
  }

  const reason = sanitizeDeletionReason(body.reason);
  const pepper = hashPepper();
  const identifierHash = await hashDeletionIdentifier(pepper, identifier.value);
  const ipHash = await hashDeletionIdentifier(pepper, ip);
  const db = getAdminClient();

  // Duplicate request within 24h → return the existing reference. This is
  // also what makes double-tapping Submit harmless.
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: existing } = await db
    .from('account_deletion_requests')
    .select('reference, status, requested_at')
    .eq('identifier_hash', identifierHash)
    .in('status', ['pending', 'processing'])
    .gte('requested_at', since)
    .order('requested_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing?.reference) {
    return jsonResponse({
      message:
        'A deletion request for these details is already waiting for review.',
      reference: existing.reference,
      review_window_days: REVIEW_WINDOW_DAYS,
      duplicate: true,
    }, 200, req);
  }

  const user = await findUserByIdentifier(db, identifier);

  let reference = buildDeletionReference();
  let insertError: { message?: string; code?: string } | null = null;
  let requestRowId: string | null = null;

  for (let attempt = 0; attempt < 3; attempt++) {
    const { data: inserted, error } = await db
      .from('account_deletion_requests')
      .insert({
        reference,
        user_id: user?.id ?? null,
        role: roleName(user?.roles),
        identifier: identifier.value,
        identifier_type: identifier.type,
        identifier_hash: identifierHash,
        full_name: fullName,
        reason: reason || null,
        source: 'web',
        status: 'pending',
        ip_hash: ipHash,
        user_agent: (req.headers.get('user-agent') ?? '').slice(0, 300) || null,
      })
      .select('id')
      .single();

    if (!error) {
      insertError = null;
      requestRowId = String(inserted?.id ?? '');
      break;
    }
    insertError = error;
    if (error.code !== '23505') break; // only retry reference collisions
    reference = buildDeletionReference();
  }

  if (insertError || !requestRowId) {
    console.error(
      '[account-delete] request insert failed:',
      insertError?.message ?? 'missing inserted id',
    );
    return errorResponse(
      'Could not save your request. Please try again or contact support.',
      500,
      'REQUEST_FAILED',
      undefined,
      req,
    );
  }

  await writeAuditLog({
    performedBy: null,
    action: 'account_deletion_requested',
    tableName: 'account_deletion_requests',
    recordId: requestRowId,
    newValues: {
      reference,
      source: 'web',
      identifier_type: identifier.type,
      account_matched: Boolean(user?.id),
    },
    ipAddress: ip,
  });

  return jsonResponse({
    message:
      'Your deletion request has been received. We will verify your identity and process it within 7 business days.',
    reference,
    review_window_days: REVIEW_WINDOW_DAYS,
    duplicate: false,
    what_happens_next: [
      'Our team verifies that the request came from the account owner.',
      'The account, profile, contact details, uploaded KYC files, and login access are deleted.',
      'Loan, payment, disbursement, and audit records are retained for the period required by law.',
    ],
  }, 200, req);
}

// ── AUTHENTICATED: delete my own account ────────────────────────────────────
async function handleDeleteSelf(req: Request): Promise<Response> {
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  if (auth.role !== 'lender' && auth.role !== 'rider') {
    return errorResponse(
      'Staff accounts cannot be deleted from the app. Contact HR or the system administrator.',
      403,
      'ROLE_NOT_DELETABLE',
      undefined,
      req,
    );
  }
  if (auth.isReviewer) {
    return errorResponse(
      'Reviewer accounts cannot be deleted.',
      403,
      'REVIEWER_NOT_ALLOWED',
      undefined,
      req,
    );
  }

  const body = await readJsonBody(req);
  if (!body || sanitizeString(body.confirmation).toUpperCase() !== 'DELETE') {
    return errorResponse(
      'Type DELETE to confirm account deletion.',
      400,
      'CONFIRMATION_REQUIRED',
      undefined,
      req,
    );
  }

  const db = getAdminClient();
  const outcome = await performDeletion(
    db,
    auth.id,
    auth.id,
    req,
    'in_app',
    sanitizeDeletionReason(body.reason),
  );

  if (!outcome.ok) {
    return errorResponse(outcome.message, outcome.status, outcome.code, undefined, req);
  }

  return jsonResponse({
    message: 'Your account has been deleted.',
    deletion: outcome.summary,
    files: outcome.storage,
    retained_notice:
      'Loan, payment, disbursement, collection, and audit records are retained for the period required by law.',
  }, 200, req);
}

// ── HEAD MANAGER: queue ─────────────────────────────────────────────────────
async function requireHeadManager(req: Request) {
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;
  if (auth.role !== 'head_manager') {
    return errorResponse(
      'Only the Head Manager can review deletion requests.',
      403,
      'FORBIDDEN',
      undefined,
      req,
    );
  }
  return auth;
}

async function handleListRequests(req: Request): Promise<Response> {
  const auth = await requireHeadManager(req);
  if (auth instanceof Response) return auth;

  const url = new URL(req.url);
  const status = url.searchParams.get('status') ?? 'pending';
  if (!['pending', 'processing', 'completed', 'rejected', 'all'].includes(status)) {
    return errorResponse('Invalid status filter.', 400, 'INVALID_STATUS', undefined, req);
  }

  const db = getAdminClient();
  let query = db
    .from('account_deletion_requests')
    .select(
      'id, reference, user_id, role, identifier, identifier_type, full_name, reason, source, status, requested_at, processed_at, processed_by, notes',
    )
    // Pinakabago muna — may 100-row cap, kaya dapat hindi maitago ng lumang
    // requests ang bagong pumasok.
    .order('requested_at', { ascending: false })
    .limit(100);

  if (status !== 'all') query = query.eq('status', status);

  const { data, error } = await query;
  if (error) {
    console.error('[account-delete] list failed:', error.message);
    return errorResponse('Could not load deletion requests.', 500, 'SERVER_ERROR', undefined, req);
  }

  const rows = ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    ...row,
  }));

  // A rejection closes the request but leaves the account alive. Older builds
  // wiped `identifier` / `full_name` on reject anyway, so backfill them from
  // the live account. Rejected rows only — completed requests were really
  // anonymized and must stay that way.
  const backfillIds = [
    ...new Set(
      rows
        .filter((row) => {
          const status = String(row.status ?? '');
          return (
            status === 'rejected' &&
            Boolean(row.user_id) &&
            (!row.identifier || !row.full_name)
          );
        })
        .map((row) => String(row.user_id)),
    ),
  ];

  if (backfillIds.length > 0) {
    const { data: users } = await db
      .from('users')
      .select('id, first_name, last_name, email, phone_number')
      .in('id', backfillIds);
    const usersById = new Map((users ?? []).map((user) => [String(user.id), user]));

    for (const row of rows) {
      if (String(row.status ?? '') !== 'rejected') continue;
      const user = row.user_id
        ? usersById.get(String(row.user_id))
        : undefined;
      if (!user) continue;

      if (!row.identifier) {
        const phone =
          typeof user.phone_number === 'string' ? user.phone_number.trim() : '';
        const email =
          typeof user.email === 'string' ? user.email.trim() : '';
        if (phone) {
          row.identifier = phone;
          row.identifier_type = 'phone';
        } else if (email && !email.endsWith('@deleted.invalid')) {
          row.identifier = email;
          row.identifier_type = 'email';
        }
      }

      if (!row.full_name) {
        const name = [user.first_name, user.last_name]
          .filter((part) => typeof part === 'string' && part.trim().length > 0)
          .join(' ')
          .trim();
        if (name) row.full_name = name;
      }
    }
  }

  return jsonResponse({
    requests: rows,
    count: rows.length,
    status,
  }, 200, req);
}

async function handleProcessRequest(req: Request): Promise<Response> {
  const auth = await requireHeadManager(req);
  if (auth instanceof Response) return auth;

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse('Invalid request body.', 400, 'VALIDATION_ERROR', undefined, req);
  }

  const requestId = sanitizeString(body.request_id);
  const reference = sanitizeString(body.reference);
  if (!requestId && !isDeletionReference(reference)) {
    return errorResponse(
      'Provide the request id (or DEL-XXXXXXXXXX reference).',
      400,
      'REQUEST_ID_REQUIRED',
      undefined,
      req,
    );
  }

  const action = sanitizeString(body.action).toLowerCase();
  if (action !== 'approve' && action !== 'reject') {
    return errorResponse('action must be "approve" or "reject".', 400, 'INVALID_ACTION', undefined, req);
  }

  const notes = sanitizeDeletionReason(body.notes);
  const db = getAdminClient();

  let lookup = db
    .from('account_deletion_requests')
    .select('id, reference, user_id, identifier, identifier_type, full_name, status, source, reason');
  lookup = requestId
    ? lookup.eq('id', requestId)
    : lookup.eq('reference', reference.toUpperCase());

  const { data: deletionRequest, error: lookupError } = await lookup.maybeSingle();
  if (lookupError || !deletionRequest) {
    return errorResponse('Deletion request not found.', 404, 'REQUEST_NOT_FOUND', undefined, req);
  }

  if (!['pending', 'processing'].includes(String(deletionRequest.status))) {
    return errorResponse(
      `Request is already ${deletionRequest.status}.`,
      409,
      'REQUEST_ALREADY_PROCESSED',
      undefined,
      req,
    );
  }

  if (action === 'reject') {
    // A rejection does NOT delete the account, so keep `identifier` and
    // `full_name` — kailangan pa ito para sa audit trail at sa susunod na
    // review. Dati binubura ang dalawa kaya "Deleted account" at walang
    // contact ang lumalabas sa history kahit buhay pa ang account.
    const { error } = await db
      .from('account_deletion_requests')
      .update({
        status: 'rejected',
        processed_at: new Date().toISOString(),
        processed_by: auth.id,
        notes: notes || 'Rejected by staff.',
      })
      .eq('id', deletionRequest.id);

    if (error) {
      console.error('[account-delete] reject failed:', error.message);
      return errorResponse('Could not update the request.', 500, 'SERVER_ERROR', undefined, req);
    }

    await writeAuditLog({
      performedBy: auth.id,
      action: 'account_deletion_request_rejected',
      tableName: 'account_deletion_requests',
      recordId: String(deletionRequest.id),
      newValues: { reference: deletionRequest.reference, notes: notes || null },
      ipAddress: clientIp(req),
    });

    return jsonResponse({ message: 'Deletion request rejected.', reference: deletionRequest.reference }, 200, req);
  }

  if (!deletionRequest.user_id) {
    // Walang na-delete na account dito (hindi nahanap), kaya panatilihin ang
    // requester details para may ma-cross-check ang staff sa susunod.
    await db
      .from('account_deletion_requests')
      .update({
        status: 'rejected',
        processed_at: new Date().toISOString(),
        processed_by: auth.id,
        notes: notes || 'No matching active account found.',
      })
      .eq('id', deletionRequest.id);

    return errorResponse(
      'No matching account was found for this request. The request has been closed.',
      404,
      'ACCOUNT_NOT_FOUND',
      undefined,
      req,
    );
  }

  await db
    .from('account_deletion_requests')
    .update({ status: 'processing', processed_by: auth.id })
    .eq('id', deletionRequest.id);

  const outcome = await performDeletion(
    db,
    String(deletionRequest.user_id),
    auth.id,
    req,
    'web',
    notes,
  );

  if (!outcome.ok) {
    // Put the request back in the queue so staff can retry after the user
    // settles the loan / completes assignments.
    await db
      .from('account_deletion_requests')
      .update({ status: 'pending', processed_by: null })
      .eq('id', deletionRequest.id)
      .eq('status', 'processing');

    return errorResponse(outcome.message, outcome.status, outcome.code, undefined, req);
  }

  try {
    await db
      .from('account_deletion_requests')
      .update({
        status: 'completed',
        processed_at: new Date().toISOString(),
        processed_by: auth.id,
        identifier: null,
        full_name: null,
        notes: notes || null,
      })
      .eq('id', deletionRequest.id);
  } catch (err) {
    console.error('[account-delete] final request update failed:', err);
  }

  return jsonResponse({
    message: 'Account deleted and request closed.',
    reference: deletionRequest.reference,
    deletion: outcome.summary,
    files: outcome.storage,
  }, 200, req);
}

serve(async (req: Request) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  if (req.method !== 'POST') {
    return errorResponse('Method not allowed.', 405, 'METHOD_NOT_ALLOWED', undefined, req);
  }

  const url = new URL(req.url);
  const fn = url.searchParams.get('fn') ?? DEFAULT_ACTION;

  try {
    switch (fn) {
      case 'request':
        return await handlePublicRequest(req);
      case 'delete-self':
        return await handleDeleteSelf(req);
      case 'list-requests':
        return await handleListRequests(req);
      case 'process-request':
        return await handleProcessRequest(req);
      default:
        return errorResponse('Unknown action.', 404, 'UNKNOWN_ACTION', undefined, req);
    }
  } catch (err) {
    console.error('[account-delete] unhandled error:', err);
    return errorResponse(
      'Account deletion failed. Please try again or contact support.',
      500,
      'SERVER_ERROR',
      undefined,
      req,
    );
  }
});
