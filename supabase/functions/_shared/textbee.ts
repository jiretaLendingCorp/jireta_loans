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

const TEXTBEE_TIMEOUT_MS = 10_000;

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
