// supabase/functions/payments-xendit-link/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   payments-generate-xendit-link  →  ?fn=generate
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser, type AuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import {
  createInvoice,
  createPaymentRequest,
  getPaymentRequest,
  getXenditSecretKey,
  isTerminalPaymentRequestStatus,
  isTestSecretKey,
  isValidPaymentRequestId,
  normalizeIdempotencyKey,
  probeXenditConnectivity,
  sanitizePaymentRequest,
  simulatePaymentRequest,
  xenditEnvironmentOf,
  xenditErrorCode,
  xenditErrorMessage,
  XENDIT_TEST_DEFAULT_AMOUNT,
  XENDIT_TEST_MAX_AMOUNT,
} from '../_shared/xendit.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { getSchedulePayment, scheduleStatus } from '../_shared/loan_financials.ts';
import {
  checkBlock,
  checkRateLimit,
  guardRateLimit,
  type BlockInfo,
} from '../_shared/rate_limiter.ts';

// Abuse detection: at most 3 GCash links generated per lender per loan
// schedule per 15 minutes. Repeated generation beyond that is treated as
// suspicious activity and temporarily blocked for review.
//
// Mahalaga: ang bilang na ito ay para sa MGA TOTOONG invoice generation lang
// (tingnan ang pagkakalagay ng `guardRateLimit` sa `handleGenerate`). Dating
// nakalagay ito BAGO ang lahat ng validation, kaya ang bawat pagtanggi na
// hindi kasalanan ng lender — "Loan is not in a payable status",
// "Installment already paid" — ay binibilang pa rin bilang attempt at
// nag-ti-trigger ng 30-minutong block. Kaya ang lender na nag-retry habang
// sira ang status check ay na-lockout sa 429 sa halip na makita ang tunay na
// dahilan.
const PAYMENT_ATTEMPT_MAX = 3;
const PAYMENT_ATTEMPT_WINDOW_MINUTES = 15;
const PAYMENT_BLOCK_MINUTES = 30;

/**
 * Ang iisang 429 response para sa na-block na installment. May kasamang
 * "ano ang susunod na gawin" para hindi dead-end ang lender na gusto lang
 * magbayad, at isang mensahe lang ang pinagmulan nito (blocked-early man o
 * bagong block) kaya hindi nagkakaiba ang sinasabi ng UI.
 */
function paymentAttemptBlockedResponse(block?: BlockInfo): Response {
  const waitMinutes = block?.retryAfterSeconds
    ? Math.max(1, Math.ceil(block.retryAfterSeconds / 60))
    : PAYMENT_BLOCK_MINUTES;
  return errorResponse(
    `You've reached the limit of ${PAYMENT_ATTEMPT_MAX} GCash links for this installment. Please try again in about ${waitMinutes} minute(s) — or pay via Cash on Delivery in the meantime.`,
    429,
    'PAYMENT_ATTEMPT_BLOCKED',
  );
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'generate';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'generate':
        // ── [moved from functions/payments-generate-xendit-link/index.ts] ─
        return await handleGenerate(req);
      // ── Sandbox (test) diagnostics — HEAD MANAGER lang ──────────────────
      // Test-only surface: WALANG binabago sa `payments`, `loans`,
      // `loan_schedules` o `disbursements`; hindi rin nagpapalabas ng pondo.
      case 'diagnostics':
        return await handleDiagnostics(req);
      case 'create-test-payment':
        return await handleCreateTestPayment(req);
      case 'test-payment-status':
        return await handleTestPaymentStatus(req);
      case 'simulate-test-payment':
        return await handleSimulateTestPayment(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('payments-xendit-link error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/payments-generate-xendit-link/index.ts] ────────────
async function handleGenerate(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.LENDER);
  if (roleCheck) return roleCheck;
  const { loan_id, loan_schedule_id } = await req.json();
  if (!loan_id || !loan_schedule_id) return errorResponse('loan_id and loan_schedule_id required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';

  // Kung aktibo ang block, dito pa lang hihinto na — WALANG bagong attempt na
  // itinatala at walang validation work. Ang pagbilang mismo ay nasa ibaba,
  // katabi na ng tunay na Xendit invoice generation.
  const attemptKey = `payment:${user.id}:${loan_schedule_id}`;
  const activeBlock = await checkBlock(attemptKey);
  if (activeBlock.blocked) {
    try {
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'payment_attempt_blocked',
        ip_address: ip,
      });
    } catch (_) {}
    return paymentAttemptBlockedResponse(activeBlock);
  }

  const { data: loan } = await db.from('loans').select('id, loan_number, lender_id, status').eq('id', loan_id).eq('lender_id', user.id).single();
  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  // PAYABLE STATUSES: active O overdue. Ang `overdue` ay HINDI dapat harangin —
  // iyon mismo ang sandali na kailangang makabayad ng lender, at iyon ang
  // tugma ng lahat ng ibang bayaran na landas:
  //   • `payments-manage` (office cash)  → ['active','overdue']
  //   • `collections-manage` (COD/rider) → ['active','overdue']
  //   • `_shared/loan_schedules`         → active/overdue/completed
  // Dati, ang GCash lang (`payments-xendit-link?fn=generate`) ang humihingi ng
  // STRICTLY 'active', kaya "Loan is not active" ang nakikita ng lender na
  // overdue na — hindi siya makakabayad via GCash kahit gustuhin niya.
  // (Hindi rin kasama ang 'completed': bayad na ang loan at walang dapat
  // kolektahin.)
  if (!['active', 'overdue'].includes(loan.status)) {
    return errorResponse('Loan is not in a payable status', 400, 'INVALID_STATUS');
  }
  const { data: schedule } = await db.from('loan_schedules').select('id, amount_due, due_date').eq('id', loan_schedule_id).eq('loan_id', loan_id).single();
  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  const schedulePayment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(schedulePayment.amount_paid, schedule.amount_due, schedule.due_date) === 'paid') return errorResponse('Installment already paid', 400, 'PAYMENT_ALREADY_MADE');
  // Abuse detection: dito lang binibilang ang attempt — pagkatapos ng lahat ng
  // validation at katabi na ng totoong invoice generation. Mahalaga ito:
  // ang isang lender na tumatanggap ng 400 (hindi pa payable / bayad na) ay
  // HINDI dapat maubusan ng quota ni ma-block, dahil wala namang na-generate
  // na invoice. Ang pumasa sa validation lang ang bumabayad ng attempt.
  const attemptGuard = await guardRateLimit({
    key: attemptKey,
    maxAttempts: PAYMENT_ATTEMPT_MAX,
    windowMinutes: PAYMENT_ATTEMPT_WINDOW_MINUTES,
    blockMinutes: PAYMENT_BLOCK_MINUTES,
    blockReason: 'Multiple payment attempts on same installment',
    eventType: 'payment_attempt_blocked',
    userId: user.id,
    ipAddress: ip,
  });
  if (!attemptGuard.allowed) {
    try {
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'payment_attempt_blocked',
        ip_address: ip,
      });
    } catch (_) {}
    return paymentAttemptBlockedResponse(attemptGuard.block);
  }

  // Kapag hindi naka-set ang XENDIT_SECRET_KEY, ang legacy na `createInvoice` ay
  // mag-e-401 sa Xendit at maghahagis — generic 500 "Internal server error" ang
  // dating nakikita ng lender. Isang malinaw na 503 na lang ito, at WALA pang
  // `payments` row na naiiwan.
  const secretKey = getXenditSecretKey();
  if (!secretKey) {
    return errorResponse(
      'GCash payments are not configured for this project right now. Please pay via Cash on Delivery, or contact the office.',
      503,
      'XENDIT_NOT_CONFIGURED',
    );
  }

  const { data: userInfo } = await db.from('users').select('email, first_name, last_name').eq('id', user.id).single();
  const externalId = `${loan.loan_number}-SCHED-${loan_schedule_id}-${Date.now()}`;
  // Ang `createInvoice` (legacy /v2/invoices) ay naghahagis kapag hindi 2xx ang
  // Xendit — hindi dapat maging generic 500 iyon, at hindi rin dapat lumabas
  // ang raw upstream body sa client. 502 lang na may sanitized na mensahe.
  let invoice: { invoiceUrl: string; id: string; status: string };
  try {
    invoice = await createInvoice({ externalId, amount: schedule.amount_due, payerEmail: userInfo?.email ?? undefined, description: `Payment for ${loan.loan_number} installment due ${schedule.due_date}` });
  } catch (err) {
    console.error(
      '[payments-xendit-link] createInvoice failed:',
      (err as Error)?.message ?? err,
    );
    return errorResponse(
      'Xendit could not create the GCash payment link just now. Please try again in a moment, or pay via Cash on Delivery.',
      502,
      'XENDIT_INVOICE_FAILED',
    );
  }
  const { data: payment } = await db.from('payments').insert({ loan_schedule_id, amount: schedule.amount_due, payment_method: 'gcash_xendit', status: 'pending', xendit_payment_id: invoice.id, xendit_reference: externalId }).select('id').single();
  if (!payment) return errorResponse('Failed to create payment record', 500, 'DB_ERROR');
  await db.from('xendit_logs').insert({ loan_id, payment_id: payment.id, event_type: 'payment', xendit_id: invoice.id, payload: invoice, status: 'created' });
  await writeAuditLog({ performedBy: user.id, action: 'generate_gcash_link', tableName: 'payments', recordId: payment.id, ipAddress: ip });
  return jsonResponse({ invoice_url: invoice.invoiceUrl, xendit_invoice_id: invoice.id, payment_id: payment.id });
}

// ════════════════════════════════════════════════════════════════════════════
// XENDIT SANDBOX DIAGNOSTICS (?fn=diagnostics | create-test-payment |
// test-payment-status | simulate-test-payment)
//
// Layunin: mapatunayang gumagana ang `XENDIT_SECRET_KEY` at makagawa ng
// TEST payment request (Payments API v3) NANG HINDI hinahawakan ang loan /
// payment / disbursement records. Lahat ng action dito ay HEAD MANAGER lang.
//
// Sanggunian (verified 2026-10-17):
//   • POST /v3/payment_requests                     — create payment request
//   • GET  /v3/payment_requests/{id}                — payment request status
//   • POST /v3/payment_requests/{id}/simulate       — test-mode only
//   • Basic auth: secret key bilang username, blangko ang password
//     (https://docs.xendit.co/docs/api-keys)
// ════════════════════════════════════════════════════════════════════════════

/** Status ng `xendit_logs` row para sa test payment request na ginawa. */
const TEST_STATUS_CREATED = 'test_created';
/** Status na itinatala kapag na-simulate ang sandbox payment. */
const TEST_STATUS_SIMULATED = 'test_simulated';
/** Prefix ng `reference_id` — kitang-kita sa Xendit dashboard na test ito. */
const TEST_REFERENCE_PREFIX = 'JR-TEST-';
/** PH e-wallet channel codes na sinusuportahan ng test payment request. */
const TEST_CHANNEL_CODES = new Set(['GCASH', 'MAYA', 'GRABPAY', 'SHOPEEPAY']);
/** Paalala na nasa lahat ng test response — hindi ito totoong bayad. */
const TEST_NOTE =
  'SANDBOX TEST ONLY — no loan, schedule, payment, or disbursement record was created or modified.';

/** IP ng caller para sa audit/security rows (best-effort). */
function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

/** JSON body na hindi kailanman naghahagis (blangko → `{}`). */
async function readJsonBody(req: Request): Promise<Record<string, unknown>> {
  try {
    const parsed = await req.json();
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch (_) {
    // blangko o invalid JSON — ituring na walang body
  }
  return {};
}

/** HEAD MANAGER-only gate para sa lahat ng Xendit diagnostics actions. */
async function requireHeadManager(
  req: Request,
): Promise<{ user: AuthUser } | Response> {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;
  return { user: authResult };
}

/** Ang halaga ng test payment — malaki lang kapag malinaw na 2 decimals. */
function parseTestAmount(raw: unknown): number | null {
  if (raw === undefined || raw === null || raw === '') return XENDIT_TEST_DEFAULT_AMOUNT;
  const value = typeof raw === 'string' ? Number(raw) : raw;
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  if (value <= 0 || value > XENDIT_TEST_MAX_AMOUNT) return null;
  return Math.round(value * 100) / 100;
}

/**
 * Idempotency lookup: ang test payment request ay nakalista sa `xendit_logs`
 * (`payload->>'idempotency_key'`, status `test_created`). Hinahanap ito BAGO
 * tumawag sa Xendit, at ang partial unique index mula sa migration 00183 ang
 * humaharang sa sabay-sabay na duplicate (23505).
 */
async function findExistingTestPayment(
  db: ReturnType<typeof getAdminClient>,
  idempotencyKey: string,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await db
    .from('xendit_logs')
    .select('xendit_id, payload')
    .eq('event_type', 'payment')
    .eq('status', TEST_STATUS_CREATED)
    .eq('payload->>idempotency_key', idempotencyKey)
    .maybeSingle();
  if (error) {
    console.error('[payments-xendit-link] xendit_logs idempotency lookup failed:', error.message);
    return null;
  }
  if (!data) return null;
  const row = data as { xendit_id: string; payload: Record<string, unknown> | null };
  const payload = row.payload ?? {};
  return { ...payload, payment_request_id: payload.payment_request_id ?? row.xendit_id };
}

/** `?fn=diagnostics` — read-only connectivity check ng `XENDIT_SECRET_KEY`. */
async function handleDiagnostics(req: Request) {
  const guard = await requireHeadManager(req);
  if (guard instanceof Response) return guard;
  const { user } = guard;

  // Hindi ito nagdudulot ng pondo, pero hindi rin dapat maging libreng
  // paulit-ulit na Xendit call ang isang account.
  const rate = await checkRateLimit({
    key: `xendit:diagnostics:${user.id}`,
    maxAttempts: 20,
    windowMinutes: 5,
  });
  if (!rate.allowed) {
    return errorResponse(
      'Too many connectivity checks. Please wait a few minutes and try again.',
      429,
      'RATE_LIMITED',
    );
  }

  const probe = await probeXenditConnectivity();
  const environment = probe.environment;
  // Ang LIVE key ay "valid", pero HINDI dapat gamitin sa test paths.
  const warning = environment === 'live'
    ? 'The configured XENDIT_SECRET_KEY is a LIVE (production) key. Sandbox test payments are refused — set a test key (xnd_development_...) instead.'
    : environment === 'unknown'
    ? 'The key prefix is not a recognised Xendit test key (xnd_development_...). Sandbox test payments are refused.'
    : null;

  // 200 ang status kahit hindi pumasa ang key: ang "result" ng diagnostic na
  // ito ay ang verdict sa loob ng body (auth_failed / unverified), hindi isang
  // API failure. Walang DB write — purong read-only ito.
  return jsonResponse({
    check: 'xendit_connectivity',
    status: probe.status,
    authenticated: probe.authenticated,
    key_present: probe.keyPresent,
    key_preview: probe.keyPreview,
    environment,
    api_version: probe.apiVersion,
    endpoint: probe.endpoint,
    http_status: probe.httpStatus,
    error_code: probe.errorCode,
    latency_ms: probe.latencyMs,
    message: probe.message,
    warning,
    checked_at: probe.checkedAt,
    sandbox_test_ready: probe.status === 'connected' && environment === 'test',
  });
}

/** `?fn=create-test-payment` — sandbox payment request (Payments API v3). */
async function handleCreateTestPayment(req: Request) {
  const guard = await requireHeadManager(req);
  if (guard instanceof Response) return guard;
  const { user } = guard;
  const db = getAdminClient();
  const ip = clientIp(req);

  const idempotencyKey = normalizeIdempotencyKey(req.headers.get('x-idempotency-key'));
  if (!idempotencyKey) {
    return errorResponse(
      'A valid x-idempotency-key header is required (8-100 chars, A-Z a-z 0-9 _ -).',
      400,
      'VALIDATION_ERROR',
    );
  }

  const secretKey = getXenditSecretKey();
  if (!secretKey) {
    return errorResponse(
      'XENDIT_SECRET_KEY is not configured for this project. Add it with `supabase secrets set XENDIT_SECRET_KEY=...`.',
      503,
      'XENDIT_NOT_CONFIGURED',
    );
  }
  // Mahigpit na sandbox-only: ang live key ay tumatanggi bago pa makatawag.
  if (!isTestSecretKey(secretKey)) {
    return errorResponse(
      'Test payments require a Xendit TEST secret key (xnd_development_...). The configured key is refused.',
      400,
      'XENDIT_TEST_KEY_REQUIRED',
    );
  }

  const body = await readJsonBody(req);
  const amount = parseTestAmount(body.amount ?? body.request_amount);
  if (amount === null) {
    return errorResponse(
      `amount must be a number greater than 0 and at most ${XENDIT_TEST_MAX_AMOUNT}`,
      400,
      'VALIDATION_ERROR',
    );
  }
  const channelCode = String(body.channel_code ?? 'GCASH').trim().toUpperCase();
  if (!TEST_CHANNEL_CODES.has(channelCode)) {
    return errorResponse(
      `Unsupported channel_code. Allowed test channels: ${[...TEST_CHANNEL_CODES].join(', ')}`,
      400,
      'VALIDATION_ERROR',
    );
  }

  const attemptGuard = await guardRateLimit({
    key: `xendit:test-payment:${user.id}`,
    maxAttempts: 10,
    windowMinutes: 15,
    blockMinutes: 15,
    blockReason: 'Repeated Xendit sandbox test payment creation',
    eventType: 'xendit_test_payment_blocked',
    userId: user.id,
    ipAddress: ip,
  });
  if (!attemptGuard.allowed) {
    return errorResponse(
      'Too many test payment attempts. Please wait before trying again.',
      429,
      'RATE_LIMITED',
    );
  }

  // Duplicate-request protection (idempotent replay): kaparehong key →
  // kaparehong payment request id, WALANG bagong Xendit call.
  const existing = await findExistingTestPayment(db, idempotencyKey);
  if (existing) {
    return jsonResponse({ ...existing, duplicate: true, note: TEST_NOTE }, 200);
  }

  const referenceId = `${TEST_REFERENCE_PREFIX}${idempotencyKey}`;
  const result = await createPaymentRequest({
    referenceId,
    amount,
    channelCode,
    description: `Jireta sandbox test payment ${referenceId}`,
  }, secretKey);

  if (result.failure) {
    return errorResponse(
      xenditErrorMessage(result),
      502,
      result.failure === 'timeout' ? 'XENDIT_TIMEOUT' : 'XENDIT_UNREACHABLE',
    );
  }
  if (!result.ok) {
    const status = result.httpStatus === 401 || result.httpStatus === 403 ? 502 : 422;
    return errorResponse(
      xenditErrorMessage(result),
      status,
      xenditErrorCode(result.data) ?? 'XENDIT_ERROR',
    );
  }

  const sanitized = sanitizePaymentRequest(result.data);
  if (!sanitized || !sanitized.payment_request_id) {
    return errorResponse(
      'Xendit did not return a payment_request_id for the test payment.',
      502,
      'XENDIT_UNEXPECTED_RESPONSE',
    );
  }

  const payload: Record<string, unknown> = {
    ...sanitized,
    amount,
    currency: 'PHP',
    idempotency_key: idempotencyKey,
    reference_id: referenceId,
    created_by: user.id,
    sandbox: true,
    source: 'jireta-test',
    note: TEST_NOTE,
  };

  // `loan_id` / `payment_id` / `disbursement_id` ay SINADYANG null: ang test
  // payment ay hindi kailanman naka-link sa isang tunay na loan o bayad.
  const { error: logError } = await db.from('xendit_logs').insert({
    event_type: 'payment',
    xendit_id: sanitized.payment_request_id,
    status: TEST_STATUS_CREATED,
    payload,
  });
  if (logError) {
    // 23505 → nauna nang naitala ng sabay na request (partial unique index).
    const raced = await findExistingTestPayment(db, idempotencyKey);
    if (raced) {
      return jsonResponse({ ...raced, duplicate: true, note: TEST_NOTE }, 200);
    }
    console.error(
      '[payments-xendit-link] xendit_logs insert failed for test payment:',
      logError.message,
    );
  }

  await writeAuditLog({
    performedBy: user.id,
    action: 'xendit_test_payment_created',
    tableName: 'xendit_logs',
    recordId: sanitized.payment_request_id,
    newValues: {
      reference_id: referenceId,
      amount,
      currency: 'PHP',
      channel_code: channelCode,
      environment: 'test',
    },
    ipAddress: ip,
  });

  return jsonResponse({ ...payload, duplicate: false }, 201);
}

/** `?fn=test-payment-status` — status ng test payment request (read-only). */
async function handleTestPaymentStatus(req: Request) {
  const guard = await requireHeadManager(req);
  if (guard instanceof Response) return guard;
  const db = getAdminClient();

  const url = new URL(req.url);
  const body = await readJsonBody(req);
  const rawId = body.payment_request_id ?? url.searchParams.get('payment_request_id');
  if (!isValidPaymentRequestId(rawId)) {
    return errorResponse(
      'A valid payment_request_id (pr-<uuid>) is required.',
      400,
      'VALIDATION_ERROR',
    );
  }
  const paymentRequestId = rawId.trim();

  const secretKey = getXenditSecretKey();
  if (!secretKey) {
    return errorResponse(
      'XENDIT_SECRET_KEY is not configured for this project.',
      503,
      'XENDIT_NOT_CONFIGURED',
    );
  }

  const result = await getPaymentRequest(paymentRequestId, secretKey);
  if (result.failure) {
    return errorResponse(
      xenditErrorMessage(result),
      502,
      result.failure === 'timeout' ? 'XENDIT_TIMEOUT' : 'XENDIT_UNREACHABLE',
    );
  }
  if (!result.ok) {
    if (result.httpStatus === 404) {
      return errorResponse('No such payment request on Xendit.', 404, 'NOT_FOUND');
    }
    const status = result.httpStatus === 401 || result.httpStatus === 403 ? 502 : 422;
    return errorResponse(
      xenditErrorMessage(result),
      status,
      xenditErrorCode(result.data) ?? 'XENDIT_ERROR',
    );
  }

  const sanitized = sanitizePaymentRequest(result.data);
  const terminal = isTerminalPaymentRequestStatus(sanitized?.status ?? null);

  // Terminal statuses lang ang itinatala, at isang beses lang bawat status —
  // hindi dumodoble ang DB row kahit paulit-ulit mag-poll ang UI.
  let recorded = false;
  if (terminal && sanitized?.status) {
    const logStatus = `test_${sanitized.status.toLowerCase()}`;
    const { data: existingLog } = await db
      .from('xendit_logs')
      .select('id')
      .eq('event_type', 'payment')
      .eq('xendit_id', paymentRequestId)
      .eq('status', logStatus)
      .maybeSingle();
    if (!existingLog) {
      const { error } = await db.from('xendit_logs').insert({
        event_type: 'payment',
        xendit_id: paymentRequestId,
        status: logStatus,
        payload: { ...sanitized, source: 'jireta-test', note: TEST_NOTE },
      });
      if (error) {
        console.error('[payments-xendit-link] terminal status log failed:', error.message);
      } else {
        recorded = true;
      }
    }
  }

  return jsonResponse({
    check: 'xendit_test_payment_status',
    test_payment: true,
    ...(sanitized ?? { payment_request_id: paymentRequestId, status: null }),
    terminal,
    // Tanging ang Xendit API (o validated webhook) ang pinagmumulan ng
    // "bayad na" — HINDI ito nag-a-approve ng loan o nagmamarka ng payment.
    payment_confirmed: sanitized?.status === 'SUCCEEDED',
    recorded,
    note: TEST_NOTE,
  });
}

/** `?fn=simulate-test-payment` — documented TEST-MODE-ONLY completion. */
async function handleSimulateTestPayment(req: Request) {
  const guard = await requireHeadManager(req);
  if (guard instanceof Response) return guard;
  const { user } = guard;
  const db = getAdminClient();
  const ip = clientIp(req);

  const secretKey = getXenditSecretKey();
  if (!secretKey) {
    return errorResponse(
      'XENDIT_SECRET_KEY is not configured for this project.',
      503,
      'XENDIT_NOT_CONFIGURED',
    );
  }
  if (!isTestSecretKey(secretKey)) {
    return errorResponse(
      'Payment simulation is available in test mode only. The configured key is refused.',
      400,
      'XENDIT_TEST_KEY_REQUIRED',
    );
  }

  const url = new URL(req.url);
  const body = await readJsonBody(req);
  const rawId = body.payment_request_id ?? url.searchParams.get('payment_request_id');
  if (!isValidPaymentRequestId(rawId)) {
    return errorResponse(
      'A valid payment_request_id (pr-<uuid>) is required.',
      400,
      'VALIDATION_ERROR',
    );
  }
  const paymentRequestId = rawId.trim();

  // Ang amount ay dapat kapareho ng request_amount ng payment request; kapag
  // hindi ipinasa, kunin mula sa naitalang test row (o default).
  let amount = parseTestAmount(body.amount);
  if (amount === null) {
    return errorResponse(
      `amount must be a number greater than 0 and at most ${XENDIT_TEST_MAX_AMOUNT}`,
      400,
      'VALIDATION_ERROR',
    );
  }
  if (body.amount === undefined || body.amount === null || body.amount === '') {
    const { data: stored } = await db
      .from('xendit_logs')
      .select('payload')
      .eq('event_type', 'payment')
      .eq('xendit_id', paymentRequestId)
      .eq('status', TEST_STATUS_CREATED)
      .maybeSingle();
    const storedAmount = (stored?.payload as Record<string, unknown> | null)?.amount;
    if (typeof storedAmount === 'number' && storedAmount > 0) {
      amount = Math.round(storedAmount * 100) / 100;
    }
  }

  const attemptGuard = await guardRateLimit({
    key: `xendit:test-simulate:${user.id}`,
    maxAttempts: 10,
    windowMinutes: 15,
    blockMinutes: 15,
    blockReason: 'Repeated Xendit sandbox payment simulation',
    eventType: 'xendit_test_payment_blocked',
    userId: user.id,
    ipAddress: ip,
  });
  if (!attemptGuard.allowed) {
    return errorResponse(
      'Too many simulation attempts. Please wait before trying again.',
      429,
      'RATE_LIMITED',
    );
  }

  const result = await simulatePaymentRequest(paymentRequestId, amount, secretKey);
  if (result.failure) {
    return errorResponse(
      xenditErrorMessage(result),
      502,
      result.failure === 'timeout' ? 'XENDIT_TIMEOUT' : 'XENDIT_UNREACHABLE',
    );
  }
  if (!result.ok) {
    const status = result.httpStatus === 401 || result.httpStatus === 403 ? 502 : 422;
    return errorResponse(
      xenditErrorMessage(result),
      status,
      xenditErrorCode(result.data) ?? 'XENDIT_ERROR',
    );
  }

  const { data: existingLog } = await db
    .from('xendit_logs')
    .select('id')
    .eq('event_type', 'payment')
    .eq('xendit_id', paymentRequestId)
    .eq('status', TEST_STATUS_SIMULATED)
    .maybeSingle();
  if (!existingLog) {
    const { error } = await db.from('xendit_logs').insert({
      event_type: 'payment',
      xendit_id: paymentRequestId,
      status: TEST_STATUS_SIMULATED,
      payload: {
        payment_request_id: paymentRequestId,
        amount,
        currency: 'PHP',
        response_status: typeof result.data?.status === 'string' ? result.data.status : null,
        requested_by: user.id,
        source: 'jireta-test',
        note: TEST_NOTE,
      },
    });
    if (error) {
      console.error('[payments-xendit-link] simulation log failed:', error.message);
    }
  }

  await writeAuditLog({
    performedBy: user.id,
    action: 'xendit_test_payment_simulated',
    tableName: 'xendit_logs',
    recordId: paymentRequestId,
    newValues: { amount, currency: 'PHP', environment: 'test' },
    ipAddress: ip,
  });

  return jsonResponse({
    check: 'xendit_test_payment_simulation',
    test_payment: true,
    payment_request_id: paymentRequestId,
    amount,
    currency: 'PHP',
    status: typeof result.data?.status === 'string' ? result.data.status : 'PENDING',
    message: typeof result.data?.message === 'string' ? result.data.message : null,
    // Ang simulate ay nag-uudyok lang ng sandbox payment. Ang "confirmed"
    // status ay kailangan pa ring kumpirmahin sa ?fn=test-payment-status (o sa
    // validated webhook).
    payment_confirmed: false,
    next_step: 'Call ?fn=test-payment-status for the Xendit-confirmed status.',
    note: TEST_NOTE,
    environment: xenditEnvironmentOf(secretKey),
  });
}