// supabase/functions/_shared/textbee.ts
// ─────────────────────────────────────────────────────────────────────────────
// TextBee SMS gateway (REST API v1).
//
//   POST https://api.textbee.dev/api/v1/gateway/send-sms
//   Header: x-api-key: <TEXTBEE_API_KEY>
//   Body:   { recipients: ["+639171234567"], message: "...", deviceId?: "..." }
//
// Docs: https://textbee.dev/docs/api-reference
//
// MAHALAGA:
//   * Ang API key ay galing LANG sa Edge Function secret (`TEXTBEE_API_KEY`).
//     Hindi ito kailanman isinusulat sa logs, sa client response, o sa DB.
//   * Ang `200` na sagot ay "queued/accepted" LANG — ang Android phone na
//     gateway (device) pa ang aktwal na nagpapadala. Kaya `pending` ang
//     naka-store na status, HINDI `sent`. Ang `delivered` ay hindi kailanman
//     inaangkin ng app.
//   * Ang OTP message body (at ang code sa loob nito) ay hindi nilo-log; ang
//     caller ang nagpapasa ng redacted na `logMessage` para sa `sms_logs`.
//   * Offline / disabled device, invalid key, at plan limit (429) ay failure
//     — hindi "sent" — para hindi sabihing naipadala ang code na wala naman.
// ─────────────────────────────────────────────────────────────────────────────
import type { SmsSendResult } from './sms.ts';

export const TEXTBEE_SEND_URL =
  'https://api.textbee.dev/api/v1/gateway/send-sms';

/**
 * Message history — ang TANGING paraan para malaman kung ano talaga ang
 * nangyari sa isang batch. `200` sa send ay "queued" lang; dito lumalabas ang
 * `sent` / `delivered` / `failed` at ang `errorCode` ng Android device.
 * Docs: “Delivery status and message states”.
 */
export const TEXTBEE_MESSAGES_URL =
  'https://api.textbee.dev/api/v1/gateway/messages';

const TEXTBEE_TIMEOUT_MS = 10_000;
const TEXTBEE_STATUS_TIMEOUT_MS = 5_000;
/** Agwat ng bounded na pagtingin sa status pagkatapos ng send (ms). */
const TEXTBEE_STATUS_POLL_INTERVAL_MS = 500;

/**
 * Inihahanda ang numero sa international format na kailangan ng TextBee.
 * Tinatanggap ang `0917...`, `+63917...`, `63917...`, at `917...`.
 */
export function normalizeTextBeeRecipient(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits === '') return '';

  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  if (digits.length === 10 && digits.startsWith('9')) return `+63${digits}`;
  return `+${digits}`;
}

export type TextBeePayload = {
  recipients: string[];
  message: string;
  deviceId?: string;
};

/**
 * Ang request body ng TextBee. Pure ito para masubukan nang walang network:
 * ang `deviceId` ay isinasama lang kapag may configured na value (kapag wala,
 * ang default device ng account ang gagamitin ng TextBee).
 */
export function buildTextBeePayload(params: {
  to: string;
  message: string;
  deviceId?: string | null;
}): TextBeePayload {
  const payload: TextBeePayload = {
    recipients: [normalizeTextBeeRecipient(params.to)],
    message: params.message,
  };
  const deviceId = (params.deviceId ?? '').trim();
  if (deviceId !== '') payload.deviceId = deviceId;
  return payload;
}

/**
 * `+639171234567` → `+6391*****567`. Ginagamit sa logs/status report para may
 * matukoy kung aling numero ang pumalya nang hindi nagsusulat ng buong numero.
 */
export function maskTextBeeNumber(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const digits = value.replace(/\D/g, '');
  if (digits.length < 8) return null;
  return `+${digits.slice(0, 4)}*****${digits.slice(-3)}`;
}

/** Tugma sa `redactSensitiveDigits` ng sms.ts; lokal para walang import cycle. */
function redactDigits(value: string, maxLength = 200): string {
  const redacted = value.replace(/\d{6,}/g, '******');
  return redacted.length > maxLength ? `${redacted.slice(0, maxLength)}…` : redacted;
}

function firstString(...values: unknown[]): string {
  for (const value of values) {
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
  }
  return '';
}

/** Kinukuha ang `data` object ng TextBee sagot (`{ data: {...} }`). */
function textBeeData(body: unknown): Record<string, unknown> | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const data = (body as Record<string, unknown>).data;
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    return null;
  }
  return data as Record<string, unknown>;
}

/**
 * Isinasalin ang HTTP response ng TextBee sa isang `SmsSendResult`.
 *
 * Pure function (walang network/DB) para masubukan. Mga panuntunan:
 *   * non-2xx (401 invalid key, 429 plan limit, 400 walang enabled/offline
 *     device) → failure, may redacted na `providerDetail`.
 *   * `success: false`, o `successCount: 0` na may `failureCount > 0` →
 *     failure — hindi tinanggap ang message.
 *   * `success: true` / may `smsBatchId` / `successCount > 0` → tinanggap
 *     (`accepted: true`) pero `status: 'pending'` — nasa queue pa lang.
 *   * `warning` (hal. `SMS_PERMISSION_MISSING`) → tinanggap pero may
 *     `errorCode` na pang-log; hindi ito "delivered".
 */
export function parseTextBeeSendResponse(
  httpStatus: number,
  body: unknown,
): SmsSendResult {
  if (httpStatus < 200 || httpStatus >= 300) {
    const record = body !== null && typeof body === 'object' && !Array.isArray(body)
      ? body as Record<string, unknown>
      : {};
    const data = textBeeData(body) ?? {};
    const detail = firstString(
      data.message,
      data.error,
      record.message,
      record.error,
    );
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: `TEXTBEE_HTTP_${httpStatus}`,
      ...(detail !== '' ? { providerDetail: redactDigits(detail) } : {}),
    };
  }

  const data = textBeeData(body);
  if (!data) {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_INVALID_RESPONSE',
    };
  }

  const smsBatchId = firstString(data.smsBatchId);
  const success = data.success;
  const successCount = typeof data.successCount === 'number'
    ? data.successCount
    : null;
  const failureCount = typeof data.failureCount === 'number'
    ? data.failureCount
    : null;
  const warning = data.warning !== null && typeof data.warning === 'object' &&
      !Array.isArray(data.warning)
    ? data.warning as Record<string, unknown>
    : null;
  const warningCode = firstString(warning?.code);
  const warningMessage = firstString(warning?.message);

  const acceptedByCount = successCount !== null &&
    successCount > 0 &&
    (failureCount ?? 0) === 0;
  const rejectedByCount = failureCount !== null && failureCount > 0 &&
    (successCount ?? 0) === 0 && smsBatchId === '';

  if (success === false || rejectedByCount) {
    const detail = firstString(
      data.message,
      warningMessage,
      data.error,
    );
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: smsBatchId !== '' ? smsBatchId : null,
      errorCode: warningCode !== '' ? warningCode : 'TEXTBEE_REJECTED',
      ...(detail !== '' ? { providerDetail: redactDigits(detail) } : {}),
    };
  }

  const queued = success === true || smsBatchId !== '' || acceptedByCount;
  if (!queued) {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_INVALID_RESPONSE',
    };
  }

  return {
    accepted: true,
    // Tinanggap ng API — nasa queue pa lang para sa Android device.
    status: 'pending',
    gatewayReference: smsBatchId !== '' ? smsBatchId : null,
    ...(warningCode !== ''
      ? {
        errorCode: warningCode,
        ...(warningMessage !== ''
          ? { providerDetail: redactDigits(warningMessage) }
          : {}),
      }
      : {}),
  };
}

export type TextBeeMessageState = {
  status: string;
  errorCode: string | null;
  errorMessage: string | null;
  /** Naka-mask — hindi buong numero sa logs. */
  recipient: string | null;
  simSubscriptionId: string | null;
};

/** Kalagayan ng isang batch, galing sa `GET /gateway/messages`. */
export type TextBeeBatchOutcome = {
  total: number;
  /** `sent` + `delivered` — tinanggap ng carrier. */
  sentCount: number;
  failedCount: number;
  pendingCount: number;
  /** Lahat ng mensahe ay `sent`/`delivered`. */
  allSent: boolean;
  /** May kahit isang `failed` — hindi ito delivery failure ng app, failure ito
   * ng device/carrier, at ito ang mahalagang ebidensya. */
  anyFailed: boolean;
  messages: TextBeeMessageState[];
};

/**
 * Isinasalin ang `GET /gateway/messages?smsBatchId=...` na sagot sa kalagayan
 * ng batch. Pure function: walang network, at naka-mask ang mga numero.
 * `null` kapag hindi kilala ang hugis ng sagot.
 */
export function parseTextBeeMessageReport(
  body: unknown,
): TextBeeBatchOutcome | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const data = (body as Record<string, unknown>).data;
  if (!Array.isArray(data)) return null;

  const messages: TextBeeMessageState[] = [];
  for (const item of data) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      return null;
    }
    const record = item as Record<string, unknown>;
    const status = firstString(record.status).toLowerCase();
    const errorMessage = firstString(record.errorMessage);
    messages.push({
      status: status === '' ? 'unknown' : status,
      errorCode: firstString(record.errorCode) || null,
      errorMessage: errorMessage === '' ? null : redactDigits(errorMessage),
      recipient: maskTextBeeNumber(record.recipient),
      simSubscriptionId: record.simSubscriptionId === undefined ||
          record.simSubscriptionId === null
        ? null
        : String(record.simSubscriptionId),
    });
  }

  const count = (wanted: string[]) =>
    messages.filter((m) => wanted.includes(m.status)).length;
  const sentCount = count(['sent', 'delivered']);
  const failedCount = count(['failed']);
  const pendingCount = count(['pending', 'dispatched']);

  return {
    total: messages.length,
    sentCount,
    failedCount,
    pendingCount,
    allSent: messages.length > 0 && sentCount === messages.length,
    anyFailed: failedCount > 0,
    messages,
  };
}

/**
 * Binabasa ang tunay na status ng isang batch. `null` kapag hindi mabasa
 * (404, hindi 2xx, network) — fail-open: hindi nito gagawing "failed" ang
 * isang send na tinanggap ng API.
 *
 * `timeoutMs` — kapag tinatawag mula sa bounded na paghihintay, ito ang
 * natitirang budget ng buong request (hindi na lalampas pa sa 5s na default).
 */
export async function fetchTextBeeMessageReport(params: {
  apiKey: string;
  smsBatchId: string;
  timeoutMs?: number;
}): Promise<TextBeeBatchOutcome | null> {
  const batch = params.smsBatchId.trim();
  if (batch === '') return null;

  try {
    const url = `${TEXTBEE_MESSAGES_URL}?smsBatchId=${
      encodeURIComponent(batch)
    }&limit=100`;
    const res = await fetch(url, {
      method: 'GET',
      headers: { 'x-api-key': params.apiKey },
      signal: AbortSignal.timeout(
        Math.max(1, params.timeoutMs ?? TEXTBEE_STATUS_TIMEOUT_MS),
      ),
    });
    if (!res.ok) {
      // 404 = wala sa account/history ang batch. Hindi ito delivery failure.
      console.warn(
        `[sms] TextBee status check unavailable (http=${res.status}, batch=${batch})`,
      );
      return null;
    }
    const body = await res.json().catch(() => null);
    return parseTextBeeMessageReport(body);
  } catch (_) {
    console.warn('[sms] TextBee status check failed: network error');
    return null;
  }
}

/**
 * Bounded na paghihintay sa resulta ng batch — humihinto agad kapag
 * `sent`/`delivered` ang lahat o may `failed`, o kapag naubos ang `timeoutMs`.
 *
 * Ito ang nagsasabi kung ang problema ay (a) nasa device/SIM/carrier (`failed`
 * + `errorCode`) o (b) nasa daan pa lang (`pending`) — bagay na hindi
 * maipapakita ng `200` ng send.
 *
 * PERF: ang UNANG poll ay agad (walang tulog bago ito). Dating laging may
 * fixed na 500ms na tulog muna, kaya ang bawat OTP request ay may 500ms na
 * dagdag na paghihintay kahit `sent`/`failed` na ang batch bago pa tayo
 * tumingin — halatang-halata sa login (at sa mga test na ~500ms tumatagal).
 * Sa pagitan lang ng mga poll natutulog, at hindi lumalampas sa `timeoutMs`.
 */
export async function waitForTextBeeBatchOutcome(params: {
  apiKey: string;
  smsBatchId: string;
  timeoutMs: number;
}): Promise<TextBeeBatchOutcome | null> {
  if (params.timeoutMs <= 0) return null;

  // HARD DEADLINE: kasama sa `timeoutMs` ang sleep at ang bawat fetch. Dating
  // tig-5s ang timeout ng fetch at pagkatapos lang nito sinusuri ang oras, kaya
  // ang 1500ms na budget ay nagiging ~6.5s sa OTP request — dagdag na
  // paghihintay sa user na wala namang nakukuhang bagong impormasyon kapag
  // naka-queue lang ang mensahe sa gateway phone.
  const deadline = Date.now() + params.timeoutMs;
  let last: TextBeeBatchOutcome | null = null;

  while (true) {
    const budget = deadline - Date.now();
    if (budget <= 0) return last;

    const report = await fetchTextBeeMessageReport({
      apiKey: params.apiKey,
      smsBatchId: params.smsBatchId,
      timeoutMs: budget,
    });
    if (report && report.total > 0) {
      last = report;
      if (report.allSent || report.anyFailed) return report;
    }

    const remaining = deadline - Date.now();
    if (remaining <= 0) return last;
    await new Promise((resolve) =>
      setTimeout(resolve, Math.min(TEXTBEE_STATUS_POLL_INTERVAL_MS, remaining))
    );
  }
}

/**
 * Ipinapadala ang SMS sa TextBee. Hindi ito nagbabato — isang
 * `SmsSendResult` ang isinasagot para pareho ang handling ng Semaphore.
 */
export async function sendTextBeeSms(params: {
  apiKey: string;
  to: string;
  message: string;
  deviceId?: string | null;
}): Promise<SmsSendResult> {
  const payload = buildTextBeePayload({
    to: params.to,
    message: params.message,
    deviceId: params.deviceId,
  });

  if (payload.recipients[0] === '') {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_INVALID_RECIPIENT',
    };
  }

  try {
    const res = await fetch(TEXTBEE_SEND_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Secret: hindi ito nilo-log at hindi lumalabas sa response.
        'x-api-key': params.apiKey,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(TEXTBEE_TIMEOUT_MS),
    });

    const body = await res.json().catch(() => null);
    const result = parseTextBeeSendResponse(res.status, body);

    if (result.accepted) {
      // Ebidensya ng bawat send, walang key/numero/code: HTTP status, batch id
      // at bilang ng recipient. Ito ang hinahanap kapag may "hindi dumating".
      const data = textBeeData(body);
      const recipientCount = typeof data?.recipientCount === 'number'
        ? data.recipientCount
        : 1;
      console.info(
        `[sms] TextBee accepted (http=${res.status}, batch=${
          result.gatewayReference ?? 'none'
        }, recipients=${recipientCount})`,
      );
    }

    if (!result.accepted) {
      // Walang API key, walang recipient, at walang OTP sa log.
      const detail = result.providerDetail ? `, detail="${result.providerDetail}"` : '';
      console.error(
        `[sms] TextBee did not accept the message (http=${res.status}, code=${
          result.errorCode ?? 'unknown'
        }${detail})`,
      );
    } else if (result.errorCode) {
      console.warn(`[sms] TextBee accepted with warning ${result.errorCode}`);
    }

    return result;
  } catch (err) {
    const isTimeout = err instanceof DOMException && err.name === 'TimeoutError';
    console.error(
      `[sms] TextBee request failed: ${isTimeout ? 'timeout' : 'network error'}`,
    );
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: isTimeout ? 'TEXTBEE_TIMEOUT' : 'TEXTBEE_NETWORK_ERROR',
    };
  }
}
