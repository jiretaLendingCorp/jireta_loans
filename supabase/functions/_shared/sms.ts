// supabase/functions/_shared/sms.ts
// ─────────────────────────────────────────────────────────────────────────────
// SMS sender — TextBee (primary) o Semaphore (fallback).
//
//   TextBee:  POST https://api.textbee.dev/api/v1/gateway/send-sms
//             header `x-api-key`, JSON `{ recipients, message, deviceId? }`
//   Semaphore: POST https://api.semaphore.co/api/v4/messages  → regular
//             POST https://api.semaphore.co/api/v4/otp       → OTP traffic
//             (dedicated route, `{otp}` placeholder)
//
// Docs: https://textbee.dev/docs/api-reference · https://semaphore.co/docs
//
// PINIPILI ANG PROVIDER:
//   * `SMS_PROVIDER=semaphore` → Semaphore lang (escape hatch).
//   * `TEXTBEE_API_KEY` naka-set → TextBee.
//   * Kung wala, Semaphore (backwards compatible sa lumang deployment).
// Walang automatic na paglipat sa dalawang provider sa isang send — kapag
// nag-fail ang TextBee, failure ito (hindi doble ang SMS).
//
// MAHALAGA:
//   * Ang API key ay galing LANG sa Edge Function secret (`TEXTBEE_API_KEY` /
//     `SEMAPHORE_API_KEY`). Hindi ito kailanman isinusulat sa logs, sa client
//     response, o sa DB.
//   * Ang `status` sa provider response ay QUEUED/PENDING pa lang sa simula —
//     acceptance ng API ay HINDI pa delivery. Kaya ang naka-store sa
//     `sms_logs` ay ang totoong provider status (queued → 'pending'), at ang
//     `accepted` flag ay "tinanggap ng API", hindi "na-deliver".
//   * Ang OTP message body ay hindi nilo-log; ang caller ang nagpapasa ng
//     redacted na `logMessage` para sa `sms_logs`.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';
import { sendTextBeeSms, waitForTextBeeBatchOutcome } from './textbee.ts';

const SEMAPHORE_MESSAGES_URL = 'https://api.semaphore.co/api/v4/messages';
const SEMAPHORE_OTP_URL = 'https://api.semaphore.co/api/v4/otp';
const SEMAPHORE_TIMEOUT_MS = 10_000;

/** Tugma sa `sms_statuses` codes (sent / pending / failed). */
export type SmsStatus = 'sent' | 'pending' | 'failed';

export type SmsSendResult = {
  /** Tinanggap ba ng Semaphore ang request? HINDI ito proof ng delivery. */
  accepted: boolean;

  /** Totoong provider status na naka-map sa sms_statuses. */
  status: SmsStatus;

  /** Semaphore `message_id` — para ma-trace ang delivery status. */
  gatewayReference: string | null;

  /** Internal na error code (para sa logs / caller), hindi para sa client. */
  errorCode?: string;

  /**
   * Ang `message` na ibinalik ng Semaphore kapag error-oriented ang body
   * (invalid key, unapproved sender name, walang credits). Redacted na —
   * puwede nang i-log. Wala ito kapag normal na message ang sagot.
   */
  providerDetail?: string;
};

export function isMockSmsEnabled(): boolean {
  return Deno.env.get('USE_MOCK_SMS') === 'true';
}

/**
 * Gaano katagal titingnan ang TUNAY na status ng batch pagkatapos ng send.
 *
 * Mahalaga ito dahil `200` ng TextBee ay "queued" lang: ang Android gateway
 * phone pa ang nagpapadala, at kapag ang SIM/device/carrier ang pumalya, dito
 * lang lumalabas ang `failed` + `errorCode`.
 *
 * Maikli ito (default 500ms, hard deadline) dahil ang sagot ay
 * hindi na kailangang hintayin ang `sent` ng carrier: kapag `pending` pa rin,
 * ang caller ay nag-uulat ng "on the way" — hindi "sent" — at hindi na
 * pinaghihintay ang user ng ilang segundo para sa parehong sagot. Ang unang
 * poll ay agad (walang 500ms na tulog bago ito), kaya ang 500ms na ito ay
 * tunay na budget para sa unang sagot, hindi karagdagang paghihintay.
 *
 * `0` = patayin ang pagtingin (bumalik sa dating behavior).
 */
function textBeeStatusCheckMs(): number {
  const raw = (Deno.env.get('TEXTBEE_STATUS_CHECK_MS') ?? '').trim();
  const parsed = parseInt(raw, 10);
  if (raw === '') return 500;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 500;
}

/**
 * Tinatanggal ang anumang 6+ digit na run (OTP code, phone number) bago ito
 * ma-log, at pinuputol sa `maxLength` para hindi bumaha ang function logs.
 */
export function redactSensitiveDigits(value: string, maxLength = 200): string {
  const redacted = value.replace(/\d{6,}/g, '******');
  return redacted.length > maxLength ? `${redacted.slice(0, maxLength)}…` : redacted;
}

/**
 * Allowlisted na diagnostics ng isang Failed/Refunded na message — HINDI
 * kasama ang `message` field dahil sa `/api/v4/otp` ay may OTP iyon.
 * Dito makikita kung aling sender name / network ang tumanggi.
 */
function rejectedMessageDetail(record: Record<string, unknown>): string {
  const pick = (key: string) => {
    const value = record[key];
    return typeof value === 'string' && value.trim() !== ''
      ? value.trim()
      : '';
  };
  const parts = [
    `provider_status=${pick('status') || 'unknown'}`,
    `network=${pick('network') || 'unknown'}`,
    `sender=${pick('sender_name') || 'account-default'}`,
    `type=${pick('type') || 'unknown'}`,
  ];
  return redactSensitiveDigits(parts.join(', '));
}

function mapSemaphoreStatus(raw: unknown): SmsStatus {
  const value = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
  switch (value) {
    case 'sent':
      return 'sent';
    case 'failed':
    case 'refunded':
      return 'failed';
    case 'queued':
    case 'pending':
      return 'pending';
    default:
      return 'pending';
  }
}

/**
 * Isinasalin ang HTTP response ng Semaphore sa isang result.
 *
 * Pure function (walang network/DB) para masubukan. Tinatanggap ang 2xx na
 * may `message_id`, sa DALAWANG hugis na ginagamit ng Semaphore:
 *   * array — ang dokumentadong shape ng `/api/v4/messages` at `/api/v4/otp`, at
 *   * single object — ang isang-message na sagot na nakikita sa live na
 *     `/api/v4/otp` (dati itong nagiging `SEMAPHORE_INVALID_RESPONSE` kahit
 *     200 ang HTTP kaya bumagsak ang OTP delivery).
 *
 * Ang `Failed`/`Refunded` na status ay failure; ang non-2xx ay failure na may
 * error code. Kapag object na walang `message_id` (error body: invalid key,
 * hindi aprubadong sender name, walang credits) ang `message` ay ibinabalik
 * bilang `providerDetail` — redacted, para may maipakita sa logs.
 */
export function parseSemaphoreSendResponse(
  httpStatus: number,
  body: unknown,
): SmsSendResult {
  if (httpStatus < 200 || httpStatus >= 300) {
    // Ang non-2xx body ay palaging `[{ message: "..." }]` o `{ message }` —
    // kunin ang paliwanag (redacted) para may dahilan sa logs kung bakit 500
    // (hal. hindi aprubadong sender name, walang credits, invalid number).
    const errorRecord = Array.isArray(body) ? body[0] : body;
    const errorMessage = errorRecord && typeof errorRecord === 'object'
      ? (errorRecord as Record<string, unknown>).message
      : undefined;
    const detail = typeof errorMessage === 'string' ? errorMessage.trim() : '';

    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: `SEMAPHORE_HTTP_${httpStatus}`,
      ...(detail !== '' ? { providerDetail: redactSensitiveDigits(detail) } : {}),
    };
  }

  if (Array.isArray(body) && body.length === 0) {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'SEMAPHORE_EMPTY_RESPONSE',
    };
  }

  const first: unknown = Array.isArray(body) ? body[0] : body;
  if (first === null || first === undefined || typeof first !== 'object') {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'SEMAPHORE_INVALID_RESPONSE',
    };
  }

  const record = first as Record<string, unknown>;
  const messageId = record.message_id;
  const hasId = messageId !== undefined && messageId !== null &&
    `${messageId}` !== '';

  if (!hasId) {
    const detail = typeof record.message === 'string'
      ? record.message.trim()
      : '';

    // Error body (`{ "message": "..." }`) — hindi ito laging 4xx ang HTTP
    // status, kaya kinikilala ito dito imbes na iwanang INVALID_RESPONSE.
    // Ang `message_id` na wala sa ARRAY ay totoong rejection ng message,
    // kaya mananatili itong SEMAPHORE_REJECTED.
    if (!Array.isArray(body) && detail !== '') {
      return {
        accepted: false,
        status: 'failed',
        gatewayReference: null,
        errorCode: 'SEMAPHORE_ERROR',
        providerDetail: redactSensitiveDigits(detail),
      };
    }

    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'SEMAPHORE_REJECTED',
    };
  }

  const providerStatus = mapSemaphoreStatus(record.status);

  if (providerStatus === 'failed') {
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: String(messageId),
      errorCode: 'SEMAPHORE_REJECTED',
      providerDetail: rejectedMessageDetail(record),
    };
  }

  return {
    accepted: true,
    status: providerStatus,
    gatewayReference: String(messageId),
  };
}

/**
 * Bumubuo ng Semaphore form body. Pure ito para masubukan nang walang
 * network: ang `sendername` ay ISINASAMA lang kapag may configured na value.
 * Ang puwersahang paggamit ng hindi aprubadong sender name ay nagdudulot ng
 * `Failed` (network rejection) kaya umaasa na lang sa default na aprubadong
 * sender name ng account kapag walang naka-set.
 */
export function buildSemaphoreForm(params: {
  apiKey: string;
  to: string;
  message: string;
  senderName?: string | null;
  otpCode?: string;
}): URLSearchParams {
  const form = new URLSearchParams();
  form.set('apikey', params.apiKey);
  form.set('number', params.to.replace(/\s+/g, ''));
  form.set('message', params.message);

  const senderName = (params.senderName ?? '').trim();
  if (senderName !== '') form.set('sendername', senderName);
  if (params.otpCode) form.set('code', params.otpCode);

  return form;
}

export async function sendSms(params: {
  to: string;
  /** Message para sa Semaphore. Sa OTP route, may `{otp}` placeholder. */
  message: string;
  /**
   * Ang isusulat sa `sms_logs` (dapat redacted sa OTP). Kapag wala, ang
   * `message` ang gagamitin — huwag itong iwanang blangko sa OTP flow.
   */
  logMessage?: string;
  /**
   * Kapag may value, gagamitin ang `/api/v4/otp` endpoint at ipapasa ang code
   * bilang `code` param. Ang `message` ay dapat may `{otp}` placeholder.
   */
  otpCode?: string;
  userId?: string;
  loanScheduleId?: string;
}): Promise<SmsSendResult> {
  const logMessage = params.logMessage ?? params.message;

  // DEV MOCK: hindi tumatawag sa Semaphore. `pending` ang status — hindi
  // "sent" — para hindi magkunwari na na-deliver. Tanging sa mock mode lang
  // isinusulat ang buong message (kasama ang OTP) sa sms_logs para may
  // makuhang code ang developer sa Supabase Studio; sa totoong send,
  // redacted ang `logMessage` na ipinapasa ng caller.
  if (isMockSmsEnabled()) {
    console.log('[sms] MOCK_MODE: skipped Semaphore request');
    await recordSmsLog({
      ...params,
      status: 'pending',
      gatewayReference: null,
      logMessage,
    });
    return {
      accepted: true,
      status: 'pending',
      gatewayReference: null,
      errorCode: 'MOCK_MODE',
    };
  }

  // ── TextBee (primary kapag naka-set ang secret) ────────────────────────
  // Ang TextBee ay walang `{otp}` placeholder, kaya ang code ay pinalitan na
  // dito sa message bago ipadala. Ang ipapasa sa `sms_logs` ay ang redacted
  // na `logMessage` pa rin — walang code na naka-store o naka-log.
  const textBeeApiKey = (Deno.env.get('TEXTBEE_API_KEY') ?? '').trim();
  const providerOverride = (Deno.env.get('SMS_PROVIDER') ?? '').trim().toLowerCase();
  if (textBeeApiKey !== '' && providerOverride !== 'semaphore') {
    const message = params.otpCode
      ? params.message.replace('{otp}', params.otpCode)
      : params.message;

    const smsStartedAt = Date.now();
    const accepted = await sendTextBeeSms({
      apiKey: textBeeApiKey,
      to: params.to,
      message,
      deviceId: Deno.env.get('TEXTBEE_DEVICE_ID'),
    });
    const sendMs = Date.now() - smsStartedAt;

    // ── Tunay na status ng batch ─────────────────────────────────────────
    // Tinanggap ng API ≠ naipadala ng phone. Kapag `failed` ang mensahe sa
    // device (walang load ang SIM, sarado ang radio, naabot ang carrier/device
    // limit, kulang ang SMS permission), HINDI ito ipapasa bilang "sent" —
    // failure ito para ma-retry ng user at makita sa logs ang errorCode.
    let result = accepted;
    let statusCheckMs = 0;
    if (accepted.accepted && accepted.gatewayReference) {
      const checkStartedAt = Date.now();
      const report = await waitForTextBeeBatchOutcome({
        apiKey: textBeeApiKey,
        smsBatchId: accepted.gatewayReference,
        timeoutMs: textBeeStatusCheckMs(),
      });
      statusCheckMs = Date.now() - checkStartedAt;
      if (report && report.total > 0) {
        const failure = report.messages.find((m) => m.status === 'failed');
        if (report.anyFailed && report.sentCount === 0) {
          const detail = [
            failure?.errorCode ? `device_error_code=${failure.errorCode}` : '',
            failure?.errorMessage ?? '',
          ].filter((part) => part !== '').join(', ');
          console.error(
            `[sms] TextBee batch ${accepted.gatewayReference} failed on the gateway phone (${
              detail || 'no detail'
            })`,
          );
          result = {
            accepted: false,
            status: 'failed',
            gatewayReference: accepted.gatewayReference,
            errorCode: 'TEXTBEE_SEND_FAILED',
            providerDetail: redactSensitiveDigits(
              detail || 'message failed on the gateway phone',
            ),
          };
        } else if (report.allSent) {
          // Carrier accepted it — mas matibay na katotohanan kaysa `pending`.
          result = { ...accepted, status: 'sent' };
        } else if (report.pendingCount > 0) {
          // Nasa queue pa lang: hindi pa naipadala ng gateway phone (offline,
          // tulog, o naantala ang push). HINDI natin ito sasabihing "sent" —
          // `pending` ang ibabalik, at ito ang ebidensya sa logs kung gaano
          // katagal nang naka-queue ang OTP.
          console.info(
            `[sms] TextBee batch ${accepted.gatewayReference} still pending (${
              report.pendingCount}/${report.total}) — queued on the gateway phone`,
          );
        }
      }
    }

    const logStartedAt = Date.now();
    await recordSmsLog({
      ...params,
      status: result.status,
      gatewayReference: result.gatewayReference,
      logMessage,
    });

    // Timing ng bawat yugto para may ebidensya kapag "mabagal ang OTP": send =
    // TextBee API, status_check = gateway phone, log = sms_logs insert. Walang
    // numero o code sa linyang ito.
    console.info(
      `[sms] TextBee result=${result.status} send_ms=${sendMs} ` +
        `status_check_ms=${statusCheckMs} log_ms=${Date.now() - logStartedAt} ` +
        `total_ms=${Date.now() - smsStartedAt}`,
    );

    return result;
  }

  const apiKey = Deno.env.get('SEMAPHORE_API_KEY');
  // Walang hardcoded na fallback: ang sender name na hindi aprubado sa
  // Semaphore account ay network rejection (status `Failed`). Kapag walang
  // naka-set, ang approved default sender name ng account ang gagamitin.
  const senderName = Deno.env.get('SEMAPHORE_SENDER_NAME');

  if (!apiKey) {
    console.error('[sms] SEMAPHORE_API_KEY is not configured');
    await recordSmsLog({
      ...params,
      status: 'failed',
      gatewayReference: null,
      logMessage,
    });
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'SMS_NOT_CONFIGURED',
    };
  }

  const form = buildSemaphoreForm({
    apiKey,
    to: params.to,
    message: params.message,
    senderName,
    otpCode: params.otpCode,
  });

  let endpoint = params.otpCode ? SEMAPHORE_OTP_URL : SEMAPHORE_MESSAGES_URL;

  try {
    let res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
      signal: AbortSignal.timeout(SEMAPHORE_TIMEOUT_MS),
    });

    let body = await res.json().catch(() => null);
    let result = parseSemaphoreSendResponse(res.status, body);

    // FALLBACK: kapag 5xx ang dedicated OTP route (hindi ito naka-enable /
    // aprubado sa account, o pansamantalang down si Semaphore), ipadala ang
    // parehong OTP sa dating `/api/v4/messages` route na may aktwal na code sa
    // message — ito ang gumaganang daan bago ang paglipat sa `/api/v4/otp`.
    // Ang `sms_logs` ay redacted pa rin (logMessage), walang code na nilo-log.
    const otpRouteDown = params.otpCode !== undefined &&
      (result.errorCode?.startsWith('SEMAPHORE_HTTP_5') ?? false);
    if (otpRouteDown) {
      console.warn(
        `[sms] OTP route failed (${result.errorCode}) — retrying via /api/v4/messages`,
      );
      const fallbackForm = buildSemaphoreForm({
        apiKey,
        to: params.to,
        message: params.message.replace('{otp}', params.otpCode as string),
        senderName,
      });
      endpoint = SEMAPHORE_MESSAGES_URL;
      res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: fallbackForm.toString(),
        signal: AbortSignal.timeout(SEMAPHORE_TIMEOUT_MS),
      });
      body = await res.json().catch(() => null);
      result = parseSemaphoreSendResponse(res.status, body);
    }

    if (!result.accepted) {
      // Status, error code, hugis ng sagot, at ang REDACTED na body para makita
      // kung aling field ang tinanggihan (sendername / number / apikey / ...).
      // Walang API key at walang OTP sa log — 6+ digit runs ay pinapalitan.
      const shape = body === null
        ? 'non-json'
        : Array.isArray(body)
        ? 'array'
        : typeof body;
      const contentType = res.headers.get('content-type') ?? 'unknown';
      const detail = result.providerDetail
        ? `, detail="${result.providerDetail}"`
        : '';
      const bodySnippet = body === null
        ? ''
        : redactSensitiveDigits(JSON.stringify(body) ?? '', 400);
      console.error(
        `[sms] Semaphore rejected the request (http=${res.status}, code=${result.errorCode ?? 'unknown'}, endpoint=${endpoint},
         sender=${(senderName ?? '').trim() || 'account-default'}, shape=${shape}, content_type=${contentType}${detail}, body=${bodySnippet})`
          .replace(/\s+/g, ' '),
      );
    }

    await recordSmsLog({
      ...params,
      status: result.status,
      gatewayReference: result.gatewayReference,
      logMessage,
    });

    return result;
  } catch (err) {
    const isTimeout = err instanceof DOMException && err.name === 'TimeoutError';
    console.error(
      `[sms] Semaphore request failed: ${isTimeout ? 'timeout' : 'network error'}`,
    );
    await recordSmsLog({
      ...params,
      status: 'failed',
      gatewayReference: null,
      logMessage,
    });
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: isTimeout ? 'SMS_TIMEOUT' : 'SMS_NETWORK_ERROR',
    };
  }
}

/**
 * `sms_logs` ay may NOT NULL na `user_id`, kaya ang mga OTP para sa
 * hindi pa rehistradong numero ay hindi naka-log dito (walang user pa).
 * Never throws — a logging failure must not fail the SMS path.
 */
async function recordSmsLog(params: {
  to: string;
  userId?: string;
  loanScheduleId?: string;
  status: SmsStatus;
  gatewayReference: string | null;
  logMessage: string;
}): Promise<void> {
  if (!params.userId) return;
  try {
    const db = getAdminClient();
    await db.from('sms_logs').insert({
      user_id: params.userId,
      loan_schedule_id: params.loanScheduleId ?? null,
      phone_number: params.to,
      message: params.logMessage,
      status: params.status,
      gateway_reference: params.gatewayReference,
    });
  } catch (err) {
    console.error(
      '[sms] failed to write sms_logs:',
      (err as Error)?.message ?? err,
    );
  }
}
