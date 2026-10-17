// supabase/functions/_shared/xendit.ts
//
// Server-side Xendit integration. ANG SECRET KEY AY HINDI Kailanman lumalabas
// sa response, log, o client bundle — `XENDIT_SECRET_KEY` env var lang.
//
// Dalawang bahagi:
//   1. LEGACY (existing, huwag baguhin ang behavior): `createInvoice`
//      (`POST /v2/invoices`) at `createDisbursement` (`POST /disbursements`) —
//      ginagamit ng payments-xendit-link?fn=generate at ng
//      disbursements-gcash / disbursements-select.
//   2. SANDBOX DIAGNOSTICS + PAYMENTS API v3 (bagong, test-only): read-only
//      connectivity probe, `POST /v3/payment_requests`, status fetch at ang
//      documented test-mode simulate endpoint.
//
// Sanggunian (verified 2026-10-17):
//   • https://docs.xendit.co/apidocs/create-payment-request  → POST /v3/payment_requests
//   • https://docs.xendit.co/apidocs/get-payment-request     → GET  /v3/payment_requests/{id}
//   • https://docs.xendit.co/apidocs/simulate-payment-test-mode
//       → POST /v3/payment_requests/{payment_request_id}/simulate  (test mode only)
//   • https://docs.xendit.co/docs/api-keys  → Basic auth, secret key as
//     username + walang password; test keys ay `xnd_development_...`,
//     live keys ay `xnd_production_...`.
//   • `api-version: 2024-11-11` ang tanging valid na value ng header ngayon.
const XENDIT_BASE = 'https://api.xendit.co';

/** Ang tanging sinusuportahang value ng `api-version` header (docs, Oct 2026). */
export const XENDIT_API_VERSION = '2024-11-11';

/** Test (sandbox) secret keys — ito LANG ang dapat gamitin sa diagnostics. */
export const XENDIT_TEST_KEY_PREFIX = 'xnd_development_';
/** Live (production) secret keys — hindi kailanman dapat tumakbo sa test paths. */
export const XENDIT_LIVE_KEY_PREFIX = 'xnd_production_';

/** Default timeout ng bawat Xendit call — hindi dapat mag-hang ang function. */
export const XENDIT_TIMEOUT_MS = 10_000;

export type XenditEnvironment = 'test' | 'live' | 'unknown';

/**
 * Ang probe id: 39 characters (`pr-` + 36-char UUID) para pumasa sa
 * documented `minLength/maxLength: 39` ng `payment_request_id` path param —
 * kung mali ang haba, 400 API_VALIDATION_ERROR ang isasagot ng Xendit at hindi
 * natin makikita ang 404 na senyales ng matagumpay na authentication.
 * Sinadya itong HINDI umiiral para laging 404 DATA_NOT_FOUND ang sagot.
 */
export const XENDIT_PROBE_PAYMENT_REQUEST_ID = 'pr-00000000-0000-0000-0000-000000000000';

// ════════════════════════════════════════════════════════════════════════════
// LEGACY — invoices + disbursements (ginagamit pa rin ng existing flows)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Maikli at UNIQUE na `external_id` para sa Xendit invoice — hal.
 * `JR-K3M9X2P1A4B`.
 *
 * DATI (sa `payments-xendit-link?fn=generate`):
 * `${loan_number}-SCHED-${loan_schedule_id}-${Date.now()}` — ~100 characters.
 * Iyon mismo ang lumalabas na "Reference No." sa receipt at ang
 * "Your order #..." sa Xendit checkout, kaya mahirap basahin.
 *
 * Ang base36 timestamp (ms) ang nagsisiguro ng uniqueness sa paglipas ng
 * oras; ang maikling random na suffix ay para hindi magbangga ang dalawang
 * invoice na nagawa sa parehong millisecond.
 */
export function shortInvoiceReference(
  prefix = 'JR',
  now: number = Date.now(),
): string {
  const ts = now.toString(36).toUpperCase();
  const rnd = new Uint8Array(2);
  crypto.getRandomValues(rnd);
  const suffix = Array.from(rnd)
    .map((b) => (b % 36).toString(36).toUpperCase())
    .join('');
  return `${prefix}-${ts}${suffix}`;
}

function getXenditHeaders(): HeadersInit {
  const secretKey = Deno.env.get('XENDIT_SECRET_KEY')!;
  const encoded = btoa(`${secretKey}:`);
  return {
    Authorization: `Basic ${encoded}`,
    'Content-Type': 'application/json',
  };
}

export async function createInvoice(params: {
  externalId: string;
  amount: number;
  payerEmail?: string;
  description: string;
  successRedirectUrl?: string;
}): Promise<{ invoiceUrl: string; id: string; status: string }> {
  const res = await fetch(`${XENDIT_BASE}/v2/invoices`, {
    method: 'POST',
    headers: getXenditHeaders(),
    body: JSON.stringify({
      external_id: params.externalId,
      amount: params.amount,
      payer_email: params.payerEmail,
      description: params.description,
      success_redirect_url: params.successRedirectUrl,
      currency: 'PHP',
      payment_methods: ['GCASH'],
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Xendit invoice error: ${JSON.stringify(err)}`);
  }

  const data = await res.json();
  return { invoiceUrl: data.invoice_url, id: data.id, status: data.status };
}

/**
 * `GET /v2/invoices/{id}` — status ng legacy invoice (read-only).
 *
 * Ginagamit ito ng reconciliation (`payments-xendit-link?fn=sync-payment`):
 * kapag hindi umabot ang webhook callback, dito tinatanong mismo sa Xendit kung
 * bayad na ang invoice bago i-verify ang `payments` row.
 */
export async function getInvoice(
  invoiceId: string,
  secretKey?: string | null,
): Promise<XenditCallResult> {
  return await xenditRequest(`/v2/invoices/${encodeURIComponent(invoiceId)}`, {
    method: 'GET',
    secretKey,
  });
}

/**
 * Ang halagang binayad kapag ang invoice ay PAID/SETTLED na — `null` kapag
 * hindi pa bayad (PENDING/EXPIRED) o walang valid na amount sa sagot.
 *
 * Prefers `paid_amount` (aktwal na natanggap) bago ang `amount` (invoice
 * amount), at tinatanggap din ang `SETTLED` dahil may mga channel na iyon ang
 * huling status na ipinapadala.
 */
export function paidInvoiceAmount(
  data: Record<string, unknown> | null,
): number | null {
  if (!data) return null;
  const status = typeof data.status === 'string'
    ? data.status.trim().toUpperCase()
    : '';
  if (status !== 'PAID' && status !== 'SETTLED') return null;
  const raw = data.paid_amount ?? data.amount;
  const amount = Number(raw);
  return Number.isFinite(amount) ? amount : null;
}

export async function createDisbursement(params: {
  externalId: string;
  bankCode: string;
  accountHolderName: string;
  accountNumber: string;
  amount: number;
  description: string;
}): Promise<{ id: string; status: string }> {
  const res = await fetch(`${XENDIT_BASE}/disbursements`, {
    method: 'POST',
    headers: getXenditHeaders(),
    body: JSON.stringify({
      external_id: params.externalId,
      bank_code: params.bankCode,
      account_holder_name: params.accountHolderName,
      account_number: params.accountNumber,
      amount: params.amount,
      description: params.description,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Xendit disbursement error: ${JSON.stringify(err)}`);
  }

  const data = await res.json();
  return { id: data.id, status: data.status };
}

export function verifyWebhookToken(req: Request): boolean {
  const callbackToken = req.headers.get('x-callback-token');
  const expectedToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN');
  if (!expectedToken || !callbackToken) return false;
  return timingSafeEqual(callbackToken, expectedToken);
}

// Constant-time string comparison (avoids leaking byte-by-byte timing which a
// naive `===` comparison is vulnerable to when used against secret tokens).
export function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const bufA = enc.encode(a);
  const bufB = enc.encode(b);
  if (bufA.length !== bufB.length) return false;
  let diff = 0;
  for (let i = 0; i < bufA.length; i++) diff |= bufA[i] ^ bufB[i];
  return diff === 0;
}

// ════════════════════════════════════════════════════════════════════════════
// SECRET KEY PLUMBING — environment detection + redaction
// ════════════════════════════════════════════════════════════════════════════

/** Ang secret key mula sa Edge Function secret, o `null` kapag hindi naka-set. */
export function getXenditSecretKey(): string | null {
  const raw = Deno.env.get('XENDIT_SECRET_KEY');
  if (raw == null) return null;
  const trimmed = raw.trim();
  return trimmed === '' ? null : trimmed;
}

/**
 * Kung TEST (sandbox) o LIVE (production) ang key — prefix-based lang ito
 * (walang network call), kaya hindi ito humihinto sa Xendit dashboard.
 * Ang `unknown` ay hindi nangangahulugang invalid: maaaring ibang format ng
 * key (hal. restricted/xenPlatform key) — sapat na ito para malaman na HINDI
 * natin ito dapat ipadala sa test-only endpoints.
 */
export function xenditEnvironmentOf(key: string | null | undefined): XenditEnvironment {
  const value = (key ?? '').trim();
  if (value.startsWith(XENDIT_TEST_KEY_PREFIX)) return 'test';
  if (value.startsWith(XENDIT_LIVE_KEY_PREFIX)) return 'live';
  return 'unknown';
}

/** True lang kapag malinaw na test/sandbox key ang nasa secret store. */
export function isTestSecretKey(key: string | null | undefined): boolean {
  return xenditEnvironmentOf(key) === 'test';
}

/**
 * Record ng key na safe i-log o ipakita sa UI: prefix + huling 4 na character
 * lang. Kapag maikli/malabo ang key, `***` na lang — hinding-hindi ang buong
 * value.
 */
export function maskSecretKey(key: string | null | undefined): string | null {
  const value = (key ?? '').trim();
  if (value === '') return null;
  const prefix = value.startsWith(XENDIT_TEST_KEY_PREFIX)
    ? XENDIT_TEST_KEY_PREFIX
    : value.startsWith(XENDIT_LIVE_KEY_PREFIX)
      ? XENDIT_LIVE_KEY_PREFIX
      : '';
  const tail = value.slice(-4);
  if (prefix === '' && value.length < 8) return '***';
  return `${prefix}***${tail}`;
}

// ════════════════════════════════════════════════════════════════════════════
// TIMEOUT-SAFE REQUEST WRAPPER
// ════════════════════════════════════════════════════════════════════════════

export type XenditFailureReason = 'timeout' | 'unreachable' | 'not_configured';

export interface XenditCallResult {
  /** HTTP response na naabot (2xx man o hindi). */
  ok: boolean;
  /** 0 kapag HINDI umabot sa Xendit (network/timeout). */
  httpStatus: number;
  /** Parsed JSON body (o `null` kapag blanko/`text` ang sagot). */
  data: Record<string, unknown> | null;
  /** `null` kapag may HTTP response; kung wala, ang dahilan. */
  failure: XenditFailureReason | null;
  /** Bilang ng millisecond bago ang sagot (0 kapag hindi umabot). */
  latencyMs: number;
}

/**
 * Isang Xendit call na hindi kailanman nag-hang nang lampas `timeoutMs` at
 * hindi kailanman naghahagis ng raw error (kaya hindi nabubunyag ang
 * Authorization header o ang upstream body sa error path).
 */
export async function xenditRequest(
  path: string,
  init: {
    method: string;
    body?: unknown;
    timeoutMs?: number;
    secretKey?: string | null;
  },
): Promise<XenditCallResult> {
  const started = Date.now();
  const secretKey = init.secretKey === undefined ? getXenditSecretKey() : init.secretKey;
  if (!secretKey) {
    return { ok: false, httpStatus: 0, data: null, failure: 'not_configured', latencyMs: 0 };
  }

  const headers: Record<string, string> = {
    Authorization: `Basic ${btoa(`${secretKey}:`)}`,
    Accept: 'application/json',
    'api-version': XENDIT_API_VERSION,
  };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';

  try {
    const res = await fetch(`${XENDIT_BASE}${path}`, {
      method: init.method,
      headers,
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      signal: AbortSignal.timeout(init.timeoutMs ?? XENDIT_TIMEOUT_MS),
    });
    const latencyMs = Date.now() - started;
    let data: Record<string, unknown> | null = null;
    try {
      const parsed = await res.json();
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        data = parsed as Record<string, unknown>;
      }
    } catch (_) {
      data = null;
    }
    return { ok: res.ok, httpStatus: res.status, data, failure: null, latencyMs };
  } catch (err) {
    const latencyMs = Date.now() - started;
    const name = (err as { name?: string })?.name ?? '';
    const isTimeout = name === 'TimeoutError' || name === 'AbortError';
    return {
      ok: false,
      httpStatus: 0,
      data: null,
      failure: isTimeout ? 'timeout' : 'unreachable',
      latencyMs,
    };
  }
}

/** Ang machine-readable error code mula sa Xendit error body (kung mayroon). */
export function xenditErrorCode(data: Record<string, unknown> | null): string | null {
  if (!data) return null;
  const direct = data.error_code;
  if (typeof direct === 'string' && direct.trim() !== '') return direct.trim();
  const nested = data.error;
  if (nested && typeof nested === 'object') {
    const code = (nested as Record<string, unknown>).code;
    if (typeof code === 'string' && code.trim() !== '') return code.trim();
  }
  return null;
}

/**
 * Maikling, sanitized na mensahe para sa client — error code lang mula sa
 * Xendit, WALANG raw body, WALANG header, WALANG key.
 */
export function xenditErrorMessage(
  result: Pick<XenditCallResult, 'httpStatus' | 'failure' | 'data'>,
): string {
  if (result.failure === 'not_configured') {
    return 'XENDIT_SECRET_KEY is not configured for this project.';
  }
  if (result.failure === 'timeout') {
    return `Xendit did not respond within ${Math.round(XENDIT_TIMEOUT_MS / 1000)}s (timeout).`;
  }
  if (result.failure === 'unreachable') {
    return 'Xendit could not be reached from the Edge Function (network error).';
  }
  const code = xenditErrorCode(result.data);
  if (result.httpStatus === 401) {
    return 'Xendit rejected the credentials (401 UNAUTHORIZED). The secret key is invalid, revoked, or from another environment.';
  }
  if (result.httpStatus === 403) {
    return `The key is valid but lacks permission for this endpoint${code ? ` (${code})` : ''}.`;
  }
  if (result.httpStatus >= 500) {
    return `Xendit returned a server error (${result.httpStatus}${code ? ` ${code}` : ''}). Retry later.`;
  }
  return `Xendit rejected the request (${result.httpStatus}${code ? ` ${code}` : ''}).`;
}

// ════════════════════════════════════════════════════════════════════════════
// CONNECTIVITY PROBE (read-only — walang payment na nagagawa)
// ════════════════════════════════════════════════════════════════════════════

export type XenditProbeStatus =
  | 'connected'
  | 'auth_failed'
  | 'permission_denied'
  | 'unverified';

export interface XenditProbeClassification {
  status: XenditProbeStatus;
  authenticated: boolean;
  message: string;
}

/**
 * PURONG function (walang I/O) para ma-test ang clasipikasyon ng probe.
 *
 * Semantics:
 *   • 401 → HINDI pumasa ang authentication (`auth_failed`).
 *   • 403 → pumasa ang authentication pero kulang ang permission ng key.
 *   • 404 → `DATA_NOT_FOUND` para sa KNOWN-nonexistent probe id: pumasa ang
 *     authentication at tumugon ang API → `connected`.
 *   • 2xx → `connected`.
 *   • 400 / 5xx / network / timeout → `unverified` — hindi sapat ang sagot
 *     para sabihing konektado ("never report success unless the API response
 *     confirms it").
 */
export function classifyXenditProbe(input: {
  keyPresent: boolean;
  httpStatus: number;
  failure: XenditFailureReason | null;
  errorCode?: string | null;
}): XenditProbeClassification {
  const { keyPresent, httpStatus, failure, errorCode } = input;

  if (!keyPresent || failure === 'not_configured') {
    return {
      status: 'unverified',
      authenticated: false,
      message: 'XENDIT_SECRET_KEY is not set. Add it with `supabase secrets set XENDIT_SECRET_KEY=...`.',
    };
  }
  if (failure === 'timeout') {
    return {
      status: 'unverified',
      authenticated: false,
      message: `Xendit did not respond within ${Math.round(XENDIT_TIMEOUT_MS / 1000)}s. Could not verify (timeout).`,
    };
  }
  if (failure === 'unreachable') {
    return {
      status: 'unverified',
      authenticated: false,
      message: 'Could not verify — the Edge Function could not reach api.xendit.co (network error).',
    };
  }
  if (httpStatus === 401) {
    return {
      status: 'auth_failed',
      authenticated: false,
      message: 'Xendit rejected the credentials (401). The secret key is invalid, revoked, or from the wrong environment.',
    };
  }
  if (httpStatus === 403) {
    return {
      status: 'permission_denied',
      authenticated: true,
      message: `The key is valid but has no permission for this endpoint${errorCode ? ` (${errorCode})` : ''}. Grant Money-in write/read for the Payments API.`,
    };
  }
  if (httpStatus >= 200 && httpStatus < 300) {
    return { status: 'connected', authenticated: true, message: 'Authenticated with Xendit.' };
  }
  if (httpStatus === 404) {
    return {
      status: 'connected',
      authenticated: true,
      message: 'Authenticated with Xendit (probe payment request intentionally does not exist).',
    };
  }
  if (httpStatus >= 500) {
    return {
      status: 'unverified',
      authenticated: false,
      message: `Could not verify — Xendit returned a server error (${httpStatus}). Retry later.`,
    };
  }
  return {
    status: 'unverified',
    authenticated: false,
    message: `Could not verify — unexpected response from Xendit (${httpStatus}${errorCode ? ` ${errorCode}` : ''}).`,
  };
}

export interface XenditProbeResult extends XenditProbeClassification {
  keyPresent: boolean;
  keyPreview: string | null;
  environment: XenditEnvironment;
  apiVersion: string;
  endpoint: string;
  httpStatus: number | null;
  errorCode: string | null;
  latencyMs: number | null;
  checkedAt: string;
}

/**
 * Read-only connectivity check. `GET /v3/payment_requests/{probe id}`:
 *   • HINDI nagagawa ng payment,
 *   • HINDI gumagalaw ng pondo,
 *   • hindi umaasa sa Balance API (na nangangailangan ng Money-out permission).
 */
export async function probeXenditConnectivity(): Promise<XenditProbeResult> {
  const secretKey = getXenditSecretKey();
  const keyPresent = secretKey !== null;
  const path = `/v3/payment_requests/${XENDIT_PROBE_PAYMENT_REQUEST_ID}`;

  if (!keyPresent) {
    const classification = classifyXenditProbe({
      keyPresent: false,
      httpStatus: 0,
      failure: 'not_configured',
    });
    return {
      ...classification,
      keyPresent: false,
      keyPreview: null,
      environment: 'unknown',
      apiVersion: XENDIT_API_VERSION,
      endpoint: `GET ${path}`,
      httpStatus: null,
      errorCode: null,
      latencyMs: null,
      checkedAt: new Date().toISOString(),
    };
  }

  const result = await xenditRequest(path, { method: 'GET', secretKey });
  const classification = classifyXenditProbe({
    keyPresent: true,
    httpStatus: result.httpStatus,
    failure: result.failure,
    errorCode: xenditErrorCode(result.data),
  });

  return {
    ...classification,
    keyPresent: true,
    keyPreview: maskSecretKey(secretKey),
    environment: xenditEnvironmentOf(secretKey),
    apiVersion: XENDIT_API_VERSION,
    endpoint: `GET ${path}`,
    httpStatus: result.failure === null ? result.httpStatus : null,
    errorCode: xenditErrorCode(result.data),
    latencyMs: result.failure === null ? result.latencyMs : null,
    checkedAt: new Date().toISOString(),
  };
}

// ════════════════════════════════════════════════════════════════════════════
// PAYMENTS API v3 — sandbox test payments
// ════════════════════════════════════════════════════════════════════════════

/** Ang default na halaga ng test payment request (PHP). */
export const XENDIT_TEST_DEFAULT_AMOUNT = 100;
/** Pinakamataas na halaga ng test payment — maliit lang, sinadyang test-only. */
export const XENDIT_TEST_MAX_AMOUNT = 100_000;

/**
 * Body ng `POST /v3/payment_requests` para sa isang test/sandbox na bayad.
 * Ang `reference_id` at `metadata` ay laging may `JR-TEST` marker para
 * makilala agad sa Xendit dashboard na test transaction ito.
 */
export interface XenditPaymentRequestInput {
  referenceId: string;
  amount: number;
  channelCode: string;
  description: string;
  successReturnUrl?: string;
  failureReturnUrl?: string;
  metadata?: Record<string, string>;
}

export function buildPaymentRequestBody(input: XenditPaymentRequestInput) {
  return {
    reference_id: input.referenceId,
    type: 'PAY',
    country: 'PH',
    currency: 'PHP',
    request_amount: input.amount,
    capture_method: 'AUTOMATIC',
    channel_code: input.channelCode,
    ...(input.successReturnUrl || input.failureReturnUrl
      ? {
        channel_properties: {
          ...(input.successReturnUrl ? { success_return_url: input.successReturnUrl } : {}),
          ...(input.failureReturnUrl ? { failure_return_url: input.failureReturnUrl } : {}),
        },
      }
      : {}),
    description: input.description,
    metadata: { env: 'sandbox', source: 'jireta-test', ...(input.metadata ?? {}) },
  };
}

export async function createPaymentRequest(
  input: XenditPaymentRequestInput,
  secretKey?: string | null,
): Promise<XenditCallResult> {
  return await xenditRequest('/v3/payment_requests', {
    method: 'POST',
    body: buildPaymentRequestBody(input),
    secretKey,
  });
}

/** `GET /v3/payment_requests/{id}` — status ng payment request (read-only). */
export async function getPaymentRequest(
  paymentRequestId: string,
  secretKey?: string | null,
): Promise<XenditCallResult> {
  return await xenditRequest(
    `/v3/payment_requests/${encodeURIComponent(paymentRequestId)}`,
    { method: 'GET', secretKey },
  );
}

/**
 * `POST /v3/payment_requests/{id}/simulate` — DOCUMENTED test-mode-only
 * endpoint. Sinasabayan nito ang pag-complete ng payment sa sandbox; hindi ito
 * gumagana sa live key (at hindi natin ito sinasadyang subukan).
 */
export async function simulatePaymentRequest(
  paymentRequestId: string,
  amount: number,
  secretKey?: string | null,
): Promise<XenditCallResult> {
  return await xenditRequest(
    `/v3/payment_requests/${encodeURIComponent(paymentRequestId)}/simulate`,
    { method: 'POST', body: { amount }, secretKey },
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SANITIZATION — para sa responses/logs (walang key, walang card data)
// ════════════════════════════════════════════════════════════════════════════

export interface SanitizedPaymentRequest {
  payment_request_id: string | null;
  reference_id: string | null;
  status: string | null;
  type: string | null;
  country: string | null;
  currency: string | null;
  request_amount: number | null;
  channel_code: string | null;
  description: string | null;
  actions: Array<{ type: string; descriptor?: string; value?: string }>;
  created: string | null;
  updated: string | null;
}

/**
 * Pili lang na fields ang ipinapasa sa client: walang card data, walang
 * business id, walang anumang credential. Ang `value` ng action ay ang
 * checkout URL / QR na kailangan ng tao para tapusin ang sandbox payment.
 */
export function sanitizePaymentRequest(
  data: Record<string, unknown> | null,
): SanitizedPaymentRequest | null {
  if (!data || typeof data !== 'object') return null;
  const actionsRaw = Array.isArray(data.actions) ? data.actions : [];
  const actions = actionsRaw
    .filter((a): a is Record<string, unknown> => !!a && typeof a === 'object')
    .map((a) => {
      const action: { type: string; descriptor?: string; value?: string } = {
        type: String(a.type ?? ''),
      };
      if (typeof a.descriptor === 'string') action.descriptor = a.descriptor;
      if (typeof a.value === 'string') action.value = a.value;
      return action;
    })
    .filter((a) => a.type !== '');

  const num = (v: unknown): number | null =>
    typeof v === 'number' && Number.isFinite(v) ? v : null;
  const str = (v: unknown): string | null =>
    typeof v === 'string' && v.trim() !== '' ? v : null;

  return {
    payment_request_id: str(data.payment_request_id),
    reference_id: str(data.reference_id),
    status: str(data.status),
    type: str(data.type),
    country: str(data.country),
    currency: str(data.currency),
    request_amount: num(data.request_amount),
    channel_code: str(data.channel_code),
    description: str(data.description),
    actions,
    created: str(data.created),
    updated: str(data.updated),
  };
}

/** Status ng payment request na itinuturing na tapos na (terminal). */
export function isTerminalPaymentRequestStatus(status: string | null): boolean {
  return status === 'SUCCEEDED' || status === 'FAILED' || status === 'EXPIRED' ||
    status === 'CANCELED' || status === 'CANCELLED';
}

/** Validation ng client-supplied idempotency key (UUID-gaya, safe sa JSONB key). */
export function normalizeIdempotencyKey(raw: string | null): string | null {
  if (raw == null) return null;
  const value = raw.trim();
  if (value.length < 8 || value.length > 100) return null;
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return null;
  return value;
}

/** Ang `payment_request_id` ay `pr-` + UUID (39 chars) — ayon sa docs. */
export function isValidPaymentRequestId(raw: unknown): raw is string {
  if (typeof raw !== 'string') return false;
  return /^pr-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
    .test(raw.trim());
}
