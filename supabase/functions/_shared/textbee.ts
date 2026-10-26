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

/** Gateway devices — dito nakikita kung BAKIT naka-queue ang mensahe. */
export const TEXTBEE_DEVICES_URL =
  'https://api.textbee.dev/api/v1/gateway/devices';

const TEXTBEE_TIMEOUT_MS = 10_000;
const TEXTBEE_STATUS_TIMEOUT_MS = 5_000;
/** Agwat ng bounded na pagtingin sa status pagkatapos ng send (ms). */
const TEXTBEE_STATUS_POLL_INTERVAL_MS = 500;

/**
 * Inihahanda ang numero sa E.164 na eksaktong kailangan ng TextBee.
 *
 * Tinatanggap ang `0917...`, `+63917...`, `63917...`, `917...`, at ang
 * nagkakamaling `+63 0917...` (natitirang trunk zero). Ang TextBee ay HINDI
 * nagdadagdag ng country code — ipapasa nito sa carrier ang numero "as
 * written" — kaya ang normalization ay responsibilidad ng app.
 *
 * `''` kapag hindi ito valid na numero: mas mabuting mabigo agad nang malinaw
 * (`TEXTBEE_INVALID_RECIPIENT`) kaysa magpadala sa `+6309...` o sa isang
 * putol na numero na "tinatanggap" ng API pero hindi kayang i-deliver. Ang
 * explicit na international na numero (`+<country code>...`) ay pinapasa
 * kung E.164-shaped, para walang mabagong ibang gumagamit ng `sms.ts`.
 */
export function normalizeTextBeeRecipient(phone: string): string {
  const raw = (phone ?? '').trim();
  if (raw === '') return '';

  // Explicit international input: iwan ang country code, tanggalin lang ang
  // spaces/punctuation. Ang `+63 09XX...` ay inaayos pa rin (trunk zero).
  if (raw.startsWith('+')) {
    const intl = raw.replace(/[^\d+]/g, '');
    if (!/^\+\d{8,15}$/.test(intl)) return '';
    return intl.replace(/^\+630(?=9\d{9}$)/, '+63');
  }

  const digits = raw.replace(/\D/g, '');
  if (digits === '') return '';

  // `63 09XX...` (country code + natitirang trunk zero).
  if (/^6309\d{9}$/.test(digits)) return `+63${digits.slice(3)}`;
  // `639XXXXXXXXX` (international, walang plus).
  if (/^639\d{9}$/.test(digits)) return `+${digits}`;
  // `09XXXXXXXXX` (local trunk prefix).
  if (/^09\d{9}$/.test(digits)) return `+63${digits.slice(1)}`;
  // `9XXXXXXXXX` (10 digits, walang trunk zero at walang country code).
  if (/^9\d{9}$/.test(digits)) return `+63${digits}`;

  // Hindi PH mobile (o kulang/sobra ang digit) — walang recipient.
  return '';
}

export type TextBeePayload = {
  recipients: string[];
  message: string;
  deviceId?: string;
  simSubscriptionId?: number;
};

/**
 * Ang request body ng TextBee. Pure ito para masubukan nang walang network:
 * ang `deviceId` ay isinasama lang kapag may configured na value (kapag wala,
 * ang default device ng account ang gagamitin ng TextBee).
 *
 * Ang `recipients[0]` ay LAGING ang numero na inilagay ng lender/rider —
 * kailanman hindi ang numero ng gateway phone. Ang `deviceId` lang ang
 * tumutukoy sa Android phone na magpapadala.
 *
 * `simSubscriptionId` (optional): ang SIM na ipapadala. Kapag wala, ang
 * **default SMS SIM ng gateway phone** ang gagamitin — kaya sa phone
 * (Settings → SIMs → SMS) dapat naka-set ang SIM na may regular SMS load.
 * Kapag naka-pin ito, hindi na tahimik na lumilipat ang Android sa ibang SIM
 * (hal. data-only) kapag nagbago ang SIM id.
 */
export function buildTextBeePayload(params: {
  to: string;
  message: string;
  deviceId?: string | null;
  simSubscriptionId?: number | null;
}): TextBeePayload {
  const payload: TextBeePayload = {
    recipients: [normalizeTextBeeRecipient(params.to)],
    message: params.message,
  };
  const deviceId = (params.deviceId ?? '').trim();
  if (deviceId !== '') payload.deviceId = deviceId;
  const sim = typeof params.simSubscriptionId === 'number' &&
      Number.isInteger(params.simSubscriptionId) &&
      params.simSubscriptionId >= 0
    ? params.simSubscriptionId
    : null;
  if (sim !== null) payload.simSubscriptionId = sim;
  return payload;
}

/** Hugis ng TextBee device id (Mongo ObjectId: 24 hex characters). */
const TEXTBEE_DEVICE_ID_PATTERN = /^[a-f0-9]{24}$/i;

/**
 * Sinusuri ang `TEXTBEE_DEVICE_ID`.
 *
 * Ito ay dapat ang ID ng ANDROID PHONE na nagpapadala (`GET /gateway/devices`
 * → `_id`, o Settings → Device ID sa textbee app) — HINDI ang numero ng SIM
 * at HINDI ang numero ng lender. Kapag may 9+ digit na run ang value, malamang
 * numero ng telepono ang naipaste: ibinabalik ito bilang error para hindi
 * maipadala ang OTP sa `TEXTBEE_HTTP_400` na walang paliwanag.
 *
 * Ibang hugis (hal. id sa test/fixture) ay pinapasa pa rin — ang TextBee ang
 * huling magsasabi kung `400 Invalid device id` ito.
 */
export function validateTextBeeDeviceId(raw: string | null | undefined): {
  deviceId: string | null;
  error: 'TEXTBEE_DEVICE_ID_INVALID' | null;
} {
  const value = (raw ?? '').trim();
  if (value === '') return { deviceId: null, error: null };
  if (TEXTBEE_DEVICE_ID_PATTERN.test(value)) {
    return { deviceId: value, error: null };
  }
  if (value.replace(/\D/g, '').length >= 9) {
    return { deviceId: null, error: 'TEXTBEE_DEVICE_ID_INVALID' };
  }
  return { deviceId: value, error: null };
}

/**
 * Ang naka-pin na SIM (`TEXTBEE_SIM_SUBSCRIPTION_ID`), galing sa `simInfo` ng
 * device (`subscriptionId`). `null` kapag wala/invalid — ang device default
 * SIM ang gagamitin.
 */
export function parseTextBeeSimSubscriptionId(
  raw: string | null | undefined,
): number | null {
  const value = (raw ?? '').trim();
  if (value === '') return null;
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
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
 * Failure body na TOP-LEVEL ang dahilan (`{ success: false, error: "..." }`) —
 * ganito ang hugis ng 400 (walang enabled/offline device, unverified email)
 * at ng ilang 200 na tinanggihan. `null` kapag hindi ito rejection body.
 */
function topLevelRejection(body: unknown): SmsSendResult | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const record = body as Record<string, unknown>;
  const detail = firstString(record.error, record.message);
  if (record.success !== false && detail === '') return null;
  return {
    accepted: false,
    status: 'failed',
    gatewayReference: null,
    errorCode: 'TEXTBEE_REJECTED',
    ...(detail !== '' ? { providerDetail: redactDigits(detail) } : {}),
  };
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
    // Rejection na nasa labas ng `data` (hal. `{ success: false, error: ... }`)
    // ay may totoong dahilan — mas kapaki-pakinabang kaysa INVALID_RESPONSE.
    const rejection = topLevelRejection(body);
    if (rejection) return rejection;
    return {
      accepted: false,
      status: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_INVALID_RESPONSE',
    };
  }

  // Ang 400/200 na failure body ay maaaring top-level `error` (hal.
  // `{ "success": false, "error": "No enabled device found..." }`) — kailangan
  // ito para may dahilan sa logs kung bakit tinanggihan ang send.
  const record = body !== null && typeof body === 'object' && !Array.isArray(body)
    ? body as Record<string, unknown>
    : {};

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
      record.error,
      record.message,
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
  /** SIM na HINILING sa send request (wala na ito ngayon). */
  simSubscriptionId: string | null;
  /**
   * SIM na TUNAY na ginamit ng phone (`simUsed.subscriptionId`). Ito ang
   * ebidensya kung aling SIM ang nagpadala — mahalaga sa dual-SIM (data-only
   * ang isang SIM).
   */
  simUsedSubscriptionId: number | null;
};

/** Kalagayan ng isang batch, galing sa `GET /gateway/messages`. */
export type TextBeeBatchOutcome = {
  total: number;
  /** `sent` + `delivered` — tinanggap ng carrier. */
  sentCount: number;
  /** `delivered` lang — may delivery report na galing sa carrier. */
  deliveredCount: number;
  failedCount: number;
  pendingCount: number;
  /**
   * `unknown` — walang kumpirmadong state (hindi nag-report ang phone sa loob
   * ng 20 minuto). HINDI ito "pending" at HINDI rin "sent"; ito ang dahilan
   * kung bakit may "unable to confirm delivery" na sagot.
   */
  unknownCount: number;
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
    const simUsed = record.simUsed !== null &&
        typeof record.simUsed === 'object' &&
        !Array.isArray(record.simUsed)
      ? record.simUsed as Record<string, unknown>
      : null;
    messages.push({
      status: status === '' ? 'unknown' : status,
      errorCode: firstString(record.errorCode) || null,
      errorMessage: errorMessage === '' ? null : redactDigits(errorMessage),
      recipient: maskTextBeeNumber(record.recipient),
      simSubscriptionId: record.simSubscriptionId === undefined ||
          record.simSubscriptionId === null
        ? null
        : String(record.simSubscriptionId),
      simUsedSubscriptionId: typeof simUsed?.subscriptionId === 'number'
        ? simUsed.subscriptionId as number
        : null,
    });
  }

  const count = (wanted: string[]) =>
    messages.filter((m) => wanted.includes(m.status)).length;
  const sentCount = count(['sent', 'delivered']);
  const deliveredCount = count(['delivered']);
  // `delivery_failed` (rare) = negative delivery report galing sa carrier;
  // `failed` = hindi naipadala ng phone. Parehong hindi tagumpay.
  const failedCount = count(['failed', 'delivery_failed']);
  const pendingCount = count(['pending', 'dispatched']);
  const unknownCount = count(['unknown']);

  return {
    total: messages.length,
    sentCount,
    deliveredCount,
    failedCount,
    pendingCount,
    unknownCount,
    allSent: messages.length > 0 && sentCount === messages.length,
    anyFailed: failedCount > 0,
    messages,
  };
}

/** Estado ng DELIVERY (hindi lang acceptance ng API). */
export type TextBeeDeliveryState =
  | 'confirmed'
  | 'carrier_accepted'
  | 'queued'
  | 'unconfirmed'
  | 'failed';

/**
 * Isinasalin ang batch report sa estado ng delivery ayon sa dokumentadong
 * message states (pending → dispatched → sent → delivered / failed / unknown).
 *
 * Mahalaga: `sent` = tinanggap ng CARRIER, hindi pa kumpirmadong natanggap ng
 * telepono — kaya `carrier_accepted`, hindi `confirmed`. `delivered` lang ang
 * may delivery report. Ang `unknown`/walang report ay `unconfirmed` — hinding
 * hindi nagiging `confirmed` kapag walang ebidensya.
 */
export function textBeeDeliveryState(
  report: TextBeeBatchOutcome | null,
): TextBeeDeliveryState {
  if (!report || report.total === 0) return 'unconfirmed';
  if (report.anyFailed && report.sentCount === 0) return 'failed';
  if (report.deliveredCount === report.total) return 'confirmed';
  if (report.sentCount === report.total) return 'carrier_accepted';
  if (report.pendingCount > 0) return 'queued';
  // `dispatched`/`unknown` lang — nasa phone na o nawalan ng report, pero
  // walang resulta: hindi ito maipapakitang "sent".
  return 'unconfirmed';
}

/**
 * Paghahambing ng RECIPIENT na aktwal na iniulat ng TextBee sa batch laban sa
 * numerong inilagay ng lender/rider.
 *
 * Ito ang huling tsek ng "naipadala ba talaga sa tamang numero?": kung iba
 * ang `recipient` na nakatala sa message (`GET /gateway/messages`), hindi
 * dumating ang OTP sa lender kahit `delivered` ang status ng gateway. Naka-mask
 * lahat ng numero — sapat ang 7 visible digits para mahuli ang maling numero
 * nang hindi nagsusulat ng buong numero sa logs.
 *
 * `recipient` na wala sa sagot (lumang app) ay HINDI mismatch — hindi ito
 * maipapakitang mali.
 */
export type TextBeeRecipientAudit = {
  ok: boolean;
  /** Naka-mask na numero na hiniling (`+6391*****567`). */
  expected: string | null;
  /** Naka-mask na numero na iniulat ng gateway (bawat message). */
  reported: string[];
  /** Unang naiibang recipient na iniulat, kung mayroon. */
  mismatched: string | null;
};

export function textBeeRecipientAudit(
  report: TextBeeBatchOutcome | null,
  expectedRecipient: string,
): TextBeeRecipientAudit {
  const expected = maskTextBeeNumber(
    normalizeTextBeeRecipient(expectedRecipient),
  ) ?? maskTextBeeNumber(expectedRecipient);

  const reported: string[] = [];
  let mismatched: string | null = null;
  for (const message of report?.messages ?? []) {
    if (message.recipient === null) continue;
    reported.push(message.recipient);
    if (expected !== null && message.recipient !== expected && mismatched === null) {
      mismatched = message.recipient;
    }
  }

  // Isang recipient lang ang dapat mayroon ang isang OTP request.
  const tooManyRecipients = (report?.total ?? 0) > 1;
  return {
    ok: mismatched === null && !tooManyRecipients,
    expected,
    reported,
    mismatched: mismatched ??
      (tooManyRecipients ? `${reported.length} recipients` : null),
  };
}

/**
 * `true` kapag ang recipient ay ang numero ng gateway SIM mismo (self-send).
 *
 * Sa self-send, "Delivered" ang lalabas sa TextBee Activity pero nasa gateway
 * phone lang ang SMS — walang IBA pang telepono ang makakatanggap nito. Ito ang
 * klaseng pagkakamali ng "device number vs recipient number".
 */
export function isTextBeeSelfSend(
  recipient: string,
  gatewayNumber: string | null | undefined,
): boolean {
  const to = normalizeTextBeeRecipient(recipient);
  const gateway = normalizeTextBeeRecipient(gatewayNumber ?? '');
  return to !== '' && gateway !== '' && to === gateway;
}

/**
 * Isang linyang buod ng kalusugan ng gateway phone — para sa logs.
 *
 * Ito ang linyang sumasagot sa "bakit `queued` ang OTP ko?" nang hindi
 * binubuksan ang dashboard: sariwa ba ang heartbeat, naka-Doze ba, pinapatay
 * ba ng battery optimization, at nasa network ba ang SIM.
 */
export function textBeeGatewaySummary(health: TextBeeGatewayHealth): string {
  return `device=${health.deviceId ?? 'default'} enabled=${health.enabled} ` +
    `heartbeat_min=${health.heartbeatAgeMinutes ?? 'n/a'} ` +
    `doze=${health.doze} ` +
    `battery_opt_ignored=${health.batteryOptimizationsIgnored} ` +
    `sims=${health.simSubscriptionIds.join('/') || 'none'} ` +
    `sim_service=${
      health.sims.map((sim) => sim.serviceState ?? 'unknown').join('/') ||
      'unknown'
    } ` +
    `sms_send_delay_s=${health.smsSendDelaySeconds ?? 'n/a'} ` +
    `issue=${health.issue ?? 'none'}`;
}

export type TextBeeGatewayIssue =
  | 'NO_DEVICE'
  | 'DEVICE_DISABLED'
  | 'DEVICE_OFFLINE'
  | 'SIM_NOT_IN_SERVICE'
  | 'DEVICE_DOZE'
  | 'BATTERY_OPTIMIZED';

/** Isang SIM ng gateway phone, galing sa `simInfo.sims` ng device. */
export type TextBeeSimState = {
  subscriptionId: number | null;
  /** `simSlotIndex` sa docs ng devices; `slotIndex` sa ibang bersyon. */
  slotIndex: number | null;
  /** `IN_SERVICE`, `OUT_OF_SERVICE`, `EMERGENCY_ONLY`, `POWER_OFF`. */
  serviceState: string | null;
  signalLevel: number | null;
};

/** `true` kapag sinasabi ng SIM na wala ito sa network — walang SMS na aalis. */
export function textBeeSimOutOfService(state: string | null): boolean {
  if (state === null) return false;
  return ['OUT_OF_SERVICE', 'EMERGENCY_ONLY', 'POWER_OFF'].includes(
    state.trim().toUpperCase(),
  );
}

/**
 * Kalusugan ng gateway phone, galing sa `GET /gateway/devices`.
 *
 * Ito ang sumasagot sa "bakit `queued`/`pending` pa rin?" — hindi ito makikita
 * sa send response (200 = tinanggap lang). `issue` ang UNANG hadlang na
 * nakita, para may isang salita ang log: offline ba, disabled ba, naka-Doze,
 * o pinapatay ng battery optimization.
 */
export type TextBeeGatewayHealth = {
  deviceId: string | null;
  name: string | null;
  enabled: boolean | null;
  isDefault: boolean | null;
  /** Ilang minuto ang nakalipas mula sa `lastHeartbeat`. */
  heartbeatAgeMinutes: number | null;
  /** `powerInfo.isDeviceIdleMode` — naka-Doze. */
  doze: boolean | null;
  /** `powerInfo.isIgnoringBatteryOptimizations` — `false` = pwedeng antalahin. */
  batteryOptimizationsIgnored: boolean | null;
  /** Agwat ng bawat message sa batch (`smsSendDelaySeconds`). */
  smsSendDelaySeconds: number | null;
  simSubscriptionIds: number[];
  sims: TextBeeSimState[];
  issue: TextBeeGatewayIssue | null;
};

function numberOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function booleanOrNull(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null;
}

function emptyGatewayHealth(
  overrides: Partial<TextBeeGatewayHealth> = {},
): TextBeeGatewayHealth {
  return {
    deviceId: null,
    name: null,
    enabled: null,
    isDefault: null,
    heartbeatAgeMinutes: null,
    doze: null,
    batteryOptimizationsIgnored: null,
    smsSendDelaySeconds: null,
    simSubscriptionIds: [],
    sims: [],
    issue: null,
    ...overrides,
  };
}

/**
 * Isinasalin ang `GET /gateway/devices` na sagot sa kalusugan ng gateway.
 * Pure function (walang network) para masubukan.
 *
 * Pinipili ang device na: (a) ang `deviceId` na naka-configure, (b) ang
 * `isDefault`, (c) ang unang enabled — parehong panuntunan ng TextBee kapag
 * walang `deviceId` sa send. `null` kapag hindi kilala ang hugis ng sagot.
 */
export function parseTextBeeGatewayHealth(
  body: unknown,
  params: { deviceId?: string | null; nowMs?: number } = {},
): TextBeeGatewayHealth | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const data = (body as Record<string, unknown>).data;
  if (!Array.isArray(data)) return null;

  const devices = data.filter((item): item is Record<string, unknown> =>
    item !== null && typeof item === 'object' && !Array.isArray(item)
  );
  if (devices.length === 0) return emptyGatewayHealth({ issue: 'NO_DEVICE' });

  const wanted = (params.deviceId ?? '').trim();
  const selected = wanted !== ''
    ? devices.find((device) => firstString(device._id) === wanted) ?? null
    : devices.find((device) => device.isDefault === true) ??
      devices.find((device) => device.enabled === true) ??
      devices[0];

  if (!selected) {
    // Naka-configure ang deviceId pero wala ito sa account: 404 ang send.
    return emptyGatewayHealth({ deviceId: wanted, issue: 'NO_DEVICE' });
  }

  const interval = numberOrNull(selected.heartbeatIntervalMinutes) ?? 30;
  const lastHeartbeat = firstString(selected.lastHeartbeat);
  const lastMs = lastHeartbeat === '' ? NaN : new Date(lastHeartbeat).getTime();
  const nowMs = params.nowMs ?? Date.now();
  const heartbeatAgeMinutes = Number.isFinite(lastMs)
    ? Math.max(0, Math.round((nowMs - lastMs) / 60000))
    : null;
  // Docs: sariwa ang device kapag may heartbeat loob ng interval (30 min).
  const stale = heartbeatAgeMinutes === null ||
    heartbeatAgeMinutes > Math.max(interval, 5);

  const power = selected.powerInfo !== null &&
      typeof selected.powerInfo === 'object' &&
      !Array.isArray(selected.powerInfo)
    ? selected.powerInfo as Record<string, unknown>
    : null;
  const simInfo = selected.simInfo !== null &&
      typeof selected.simInfo === 'object' &&
      !Array.isArray(selected.simInfo)
    ? selected.simInfo as Record<string, unknown>
    : null;
  const simList = Array.isArray(simInfo?.sims) ? simInfo.sims : [];
  const sims: TextBeeSimState[] = simList.map((sim) => {
    const record = sim !== null && typeof sim === 'object' && !Array.isArray(sim)
      ? sim as Record<string, unknown>
      : {};
    return {
      subscriptionId: numberOrNull(record.subscriptionId),
      slotIndex: numberOrNull(record.simSlotIndex) ??
        numberOrNull(record.slotIndex),
      serviceState: firstString(record.serviceState) || null,
      signalLevel: numberOrNull(record.signalLevel),
    };
  });
  const simSubscriptionIds = sims
    .map((sim) => sim.subscriptionId)
    .filter((id): id is number => id !== null);

  const enabled = booleanOrNull(selected.enabled);
  const doze = booleanOrNull(power?.isDeviceIdleMode);
  const batteryIgnored = booleanOrNull(power?.isIgnoringBatteryOptimizations);

  // Ang SIM na wala sa network (`OUT_OF_SERVICE`/`POWER_OFF`) ay hindi
  // makakapagpadala kahit gising ang phone at may load — dapat itong sabihin
  // bago pa hintayin ang naka-queue na OTP.
  const reportedServiceStates = sims
    .map((sim) => sim.serviceState)
    .filter((state): state is string => state !== null);
  const noSimInService = reportedServiceStates.length > 0 &&
    reportedServiceStates.every((state) => textBeeSimOutOfService(state));

  let issue: TextBeeGatewayIssue | null = null;
  if (enabled === false) issue = 'DEVICE_DISABLED';
  else if (stale) issue = 'DEVICE_OFFLINE';
  else if (noSimInService) issue = 'SIM_NOT_IN_SERVICE';
  else if (doze === true) issue = 'DEVICE_DOZE';
  else if (batteryIgnored === false) issue = 'BATTERY_OPTIMIZED';

  return {
    deviceId: firstString(selected._id) || null,
    name: firstString(selected.name) || null,
    enabled,
    isDefault: booleanOrNull(selected.isDefault),
    heartbeatAgeMinutes,
    doze,
    batteryOptimizationsIgnored: batteryIgnored,
    smsSendDelaySeconds: numberOrNull(selected.smsSendDelaySeconds),
    simSubscriptionIds,
    sims,
    issue,
  };
}

/**
 * Binabasa ang kalusugan ng gateway phone. `null` kapag hindi mabasa (401/404/
 * network) — diagnosis lang ito, hindi ito nagpapabagsak ng send.
 */
export async function fetchTextBeeGatewayHealth(params: {
  apiKey: string;
  deviceId?: string | null;
  timeoutMs?: number;
}): Promise<TextBeeGatewayHealth | null> {
  try {
    const res = await fetch(TEXTBEE_DEVICES_URL, {
      method: 'GET',
      headers: { 'x-api-key': params.apiKey },
      signal: AbortSignal.timeout(Math.max(1, params.timeoutMs ?? 2_500)),
    });
    if (!res.ok) {
      console.warn(
        `[sms] TextBee device check unavailable (http=${res.status})`,
      );
      return null;
    }
    return parseTextBeeGatewayHealth(await res.json().catch(() => null), {
      deviceId: params.deviceId,
    });
  } catch (_) {
    console.warn('[sms] TextBee device check failed: network error');
    return null;
  }
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
 * `SmsSendResult` ang isinasagot para pareho ang handling sa lahat ng tawag.
 */
export async function sendTextBeeSms(params: {
  apiKey: string;
  to: string;
  message: string;
  deviceId?: string | null;
  simSubscriptionId?: number | null;
}): Promise<SmsSendResult> {
  const payload = buildTextBeePayload({
    to: params.to,
    message: params.message,
    deviceId: params.deviceId,
    simSubscriptionId: params.simSubscriptionId,
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
      // Ang recipient at ang device/SIM ay naka-log para may ebidensya sa
      // BAWAT send: ito ang numerong pinadalhan, at ito ang phone na
      // nagpadala. Naka-mask ang numero; walang API key at walang OTP.
      console.info(
        `[sms] TextBee accepted (http=${res.status}, batch=${
          result.gatewayReference ?? 'none'
        }, recipient=${maskTextBeeNumber(payload.recipients[0]) ?? 'invalid'}, ` +
          `device=${payload.deviceId ?? 'default'}, ` +
          `sim=${payload.simSubscriptionId ?? 'device-default'}, ` +
          `recipients=${recipientCount})`,
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
