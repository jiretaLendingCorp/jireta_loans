// supabase/functions/_shared/sms.ts
// ─────────────────────────────────────────────────────────────────────────────
// SMS sender — TextBee lamang (walang ibang provider).
//
//   POST https://api.textbee.dev/api/v1/gateway/send-sms
//   header `x-api-key`, JSON `{ recipients, message, deviceId? }`
//   status: GET https://api.textbee.dev/api/v1/gateway/messages?smsBatchId=...
//
// Docs: https://textbee.dev/docs/api-reference
//
// MAHALAGA:
//   * Ang TextBee ang TANGING provider. Walang Semaphore fallback at walang
//     `SMS_PROVIDER` override — kapag kulang o mali ang `TEXTBEE_API_KEY`,
//     malinaw na failure (`TEXTBEE_NOT_CONFIGURED`), hindi tahimik na
//     paglipat sa ibang gateway.
//   * Ang API key ay galing LANG sa Edge Function secret (`TEXTBEE_API_KEY`).
//     Hindi ito kailanman isinusulat sa logs, sa client response, o sa DB.
//   * Ang `status` sa provider response ay QUEUED/PENDING pa lang sa simula —
//     acceptance ng API ay HINDI pa delivery. Kaya ang naka-store sa
//     `sms_logs` ay ang totoong provider status (queued → 'pending'), at ang
//     `accepted` flag ay "tinanggap ng API", hindi "na-deliver".
//   * Ang OTP message body ay hindi nilo-log; ang caller ang nagpapasa ng
//     redacted na `logMessage` para sa `sms_logs`.
// ─────────────────────────────────────────────────────────────────────────────
import { getAdminClient } from './db.ts';
import {
  fetchTextBeeGatewayHealth,
  fetchTextBeeMessageReport,
  isTextBeeSelfSend,
  maskTextBeeNumber,
  normalizeTextBeeRecipient,
  parseTextBeeSimSubscriptionId,
  sendTextBeeSms,
  textBeeDeliveryState,
  textBeeGatewaySummary,
  textBeeRecipientAudit,
  validateTextBeeDeviceId,
  waitForTextBeeBatchOutcome,
  type TextBeeGatewayHealth,
} from './textbee.ts';

/** Tugma sa `sms_statuses` codes (sent / pending / failed). */
export type SmsStatus = 'sent' | 'pending' | 'failed';

/**
 * Ebidensya ng aktwal na delivery — hiwalay sa `SmsStatus` na naka-store sa
 * `sms_logs` (sent/pending/failed lang doon):
 *
 *   confirmed        — may delivery report galing sa carrier (TextBee
 *                      `delivered`): kumpirmadong natanggap ng telepono.
 *   carrier_accepted — tinanggap ng carrier (TextBee `sent`). Karaniwang
 *                      huling estado sa PH: maraming carrier ang walang
 *                      delivery report, kaya HINDI ito "delivered".
 *   queued           — nasa queue/gateway phone pa (`pending`/`dispatched`).
 *   unconfirmed      — tinanggap ng API pero walang nabasang status
 *                      (`unknown`, offline ang device, o hindi mabasa ang
 *                      batch). "OTP request accepted; delivery not yet
 *                      confirmed."
 *   failed           — pumalya ang API, device, SIM, o carrier.
 */
export type SmsDelivery =
  | 'confirmed'
  | 'carrier_accepted'
  | 'queued'
  | 'unconfirmed'
  | 'failed';

export type SmsSendResult = {
  /** Tinanggap ba ng TextBee ang request? HINDI ito proof ng delivery. */
  accepted: boolean;

  /** Totoong provider status na naka-map sa sms_statuses. */
  status: SmsStatus;

  /**
   * Gaano kalayo ang alam natin tungkol sa PAGDATING ng mensahe. `confirmed`
   * lang kapag may delivery report — hindi kailanman hinuhulaan. Ang `sendSms`
   * ang laging naglalagay nito.
   */
  delivery?: SmsDelivery;

  /** TextBee `smsBatchId` — para ma-trace ang delivery status. */
  gatewayReference: string | null;

  /** Internal na error code (para sa logs / caller), hindi para sa client. */
  errorCode?: string;

  /**
   * Ang `message`/`error` na ibinalik ng TextBee kapag error-oriented ang body
   * (invalid key, walang enabled device, plan limit). Redacted na — puwede
   * nang i-log. Wala ito kapag normal na send ang sagot.
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
 * Humihinto AGAD ang paghihintay kapag `sent`/`delivered`/`failed` na ang
 * batch. Default 2500ms: sapat para mahuli ang `sent` o `failed` (mabilis
 * mag-report ang gateway phone kapag may load ang SIM), pero hindi
 * pinaghihintay ang user nang 6s bago lumipat sa Verify OTP screen. Kapag
 * `pending` pa rin sa budget, "on its way" ang sagot — hindi "sent".
 *
 * Ang NATITIRANG status pagkatapos ng sagot ay nilo-log sa background kapag
 * `TEXTBEE_GATEWAY_DIAGNOSTICS=true` (walang dagdag na paghihintay).
 *
 * `0` = patayin ang pagtingin.
 */
function textBeeStatusCheckMs(): number {
  const raw = (Deno.env.get('TEXTBEE_STATUS_CHECK_MS') ?? '').trim();
  const parsed = parseInt(raw, 10);
  if (raw === '') return 2500;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 2500;
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
 * Opt-in (`TEXTBEE_GATEWAY_DIAGNOSTICS=true`): kapag naka-queue ang OTP,
 * mag-log ng kalusugan ng gateway phone. Default OFF para walang dagdag na
 * API call sa bawat login; nakukuha rin ito sa
 * `scripts/textbee_sms_diagnose.ts` at sa TextBee dashboard.
 */
function textBeeGatewayDiagnosticsEnabled(): boolean {
  return (Deno.env.get('TEXTBEE_GATEWAY_DIAGNOSTICS') ?? '').trim().toLowerCase() ===
    'true';
}

/**
 * Kapag naka-queue pa ang OTP, ang natitirang tanong ay nasa GATEWAY phone:
 * offline ba ito, naka-Doze, o pinapatay ng battery optimization? Isang
 * bounded na tingin sa `GET /gateway/devices` ang sumasagot — pero PAGKATAPOS
 * ng sagot sa app, para walang dagdag na paghihintay sa login.
 *
 * `EdgeRuntime.waitUntil` ang nagpapanatili sa isolate pagkatapos ng response
 * (kaparehong pattern sa ibang functions sa repo). Walang numero, walang code,
 * walang API key sa log.
 */
/**
 * `EdgeRuntime.waitUntil` — huwag i-await ang background na gawain.
 *
 * May factory ang task para hindi ito MASIMULAN kapag walang `waitUntil`
 * (local `deno run` / tests): kung hindi, may naiiwang timer na mag-fetch pa ng
 * tunay na API pagkatapos ng test at magpapatagal sa process.
 */
function runInBackground(task: () => Promise<unknown>): void {
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (!runtime?.waitUntil) return;
  runtime.waitUntil(task().catch(() => {}));
}

/**
 * Pagkatapos ng sagot sa app, ituloy ang pagtingin sa batch sa BACKGROUND
 * (3 bounded na GET lang, walang dagdag na paghihintay sa login).
 *
 * Ito ang ebidensya sa "ano talaga ang nangyari sa OTP na pinindot ko?":
 *   sent/delivered sa +8s   → umalis agad ang SMS; nasa recipient na
 *   failed                  → tinanggihan ng phone/SIM/carrier (`errorCode`)
 *   pending pa rin sa +50s   → HINDI pa naipapadala ng gateway phone (offline,
 *                             Doze, walang SMS permission, walang load, o
 *                             hindi ito ang phone na tinitingnan mo)
 *
 * Laging naka-on — ito ang tanging paraan para malaman kung ang isang
 * "accepted" na batch ay talagang umalis. Walang numero at walang OTP sa log.
 */
const TEXTBEE_FOLLOW_UP_DELAYS_MS = [8_000, 25_000, 50_000];

function scheduleTextBeeBatchFollowUp(params: {
  apiKey: string;
  smsBatchId: string;
  recipient: string;
  deviceId: string | null;
}): void {
  runInBackground(async () => {
    let waitedMs = 0;
    for (let index = 0; index < TEXTBEE_FOLLOW_UP_DELAYS_MS.length; index++) {
      const delayMs = TEXTBEE_FOLLOW_UP_DELAYS_MS[index];
      await new Promise((resolve) =>
        setTimeout(resolve, Math.max(0, delayMs - waitedMs))
      );
      waitedMs = delayMs;

      const report = await fetchTextBeeMessageReport({
        apiKey: params.apiKey,
        smsBatchId: params.smsBatchId,
        timeoutMs: 5_000,
      });
      if (!report || report.total === 0) continue;

      const failure = report.messages.find((m) => m.status === 'failed');
      const lastDelaySeconds = Math.round(
        TEXTBEE_FOLLOW_UP_DELAYS_MS[TEXTBEE_FOLLOW_UP_DELAYS_MS.length - 1] /
          1000,
      );
      console.info(
        `[sms] TextBee batch ${params.smsBatchId} follow-up +${
          Math.round(delayMs / 1000)
        }s: delivery=${textBeeDeliveryState(report)} ` +
          `sent=${report.sentCount} delivered=${report.deliveredCount} ` +
          `failed=${report.failedCount} pending=${report.pendingCount} ` +
          `unknown=${report.unknownCount}/${report.total} ` +
          `recipient=${maskTextBeeNumber(params.recipient) ?? 'invalid'} ` +
          `device=${params.deviceId ?? 'default'}` +
          (failure?.errorCode ? ` errorCode=${failure.errorCode}` : '') +
          (failure?.errorMessage
            ? ` errorMessage="${failure.errorMessage}"`
            : ''),
      );

      if (report.allSent || report.anyFailed) return;

      if (index === TEXTBEE_FOLLOW_UP_DELAYS_MS.length - 1) {
        console.warn(
          `[sms] TextBee batch ${params.smsBatchId} has NOT been sent ${lastDelaySeconds}s ` +
            'after acceptance — the gateway phone never handed it to the radio. ' +
            'Check on the phone: textbee app running with SMS permission, battery ' +
            'usage Unrestricted (not Doze), a SIM in service with SMS load, and that ' +
            `device ${params.deviceId ?? 'default'} is the phone you are looking at.`,
        );
      }
    }
  });
}

// ── Gateway phone / SIM resolution ─────────────────────────────────────────
// Ang `TEXTBEE_DEVICE_ID` ay ID ng Android phone na nagpapadala, at ang
// `TEXTBEE_SIM_SUBSCRIPTION_ID` (optional) ang SIM nito. Ang `recipients` ng
// bawat request ay LAGING ang numero ng lender/rider — kailanman hindi ang
// numero ng gateway phone. Ito ang dalawang magkaibang bagay na madaling
// mapagkamalan kapag "hindi dumarating ang OTP": ang Activity log ay nagpapakita
// ng recipient, at kapag iyon pala ang numero mismo ng gateway SIM, "Delivered"
// ito agad pero wala na itong ibang teleponong mararating.
const TEXTBEE_DEVICE_CACHE_MS = 5 * 60 * 1000;

type TextBeeSenderResolution = {
  deviceId: string | null;
  simSubscriptionId: number | null;
  errorCode: string | null;
  providerDetail?: string;
  /** Kalusugan ng device sa preflight — para may ebidensya sa log. */
  health: TextBeeGatewayHealth | null;
};

let textBeeDeviceCache:
  | { key: string; at: number; health: TextBeeGatewayHealth | null }
  | null = null;

/** Para sa tests: huwag mag-reuse ng device health sa pagitan ng mga test. */
export function resetTextBeeGatewayCache(): void {
  textBeeDeviceCache = null;
}

async function cachedTextBeeGatewayHealth(params: {
  apiKey: string;
  deviceId: string | null;
}): Promise<TextBeeGatewayHealth | null> {
  const key = params.deviceId ?? 'default';
  const now = Date.now();
  if (
    textBeeDeviceCache !== null && textBeeDeviceCache.key === key &&
    now - textBeeDeviceCache.at < TEXTBEE_DEVICE_CACHE_MS
  ) {
    return textBeeDeviceCache.health;
  }
  const health = await fetchTextBeeGatewayHealth({
    apiKey: params.apiKey,
    deviceId: params.deviceId,
    // Bounded para hindi mabigo nang mabagal ang login kapag hung ang
    // devices endpoint: ang send pa rin ang mahalaga.
    timeoutMs: 1_200,
  });
  // Ang NABASANG health lang ang i-cache — ang "hindi mabasa" (network/401) ay
  // hindi dapat mag-stick nang 5 minuto at mag-block ng send.
  if (health !== null) {
    textBeeDeviceCache = { key, at: now, health };
  }
  return health;
}

/**
 * Sinusuri BAGO mag-send na ang naka-configure na `deviceId` ay ang konektadong
 * Android phone, at (kapag naka-pin) ang SIM ay umiiral at nasa network.
 *
 * Fail-open kapag hindi mabasa ang device list (network/401): hindi ito dapat
 * magpabagsak ng OTP. Fail-fast lang sa malinaw na hindi makakapagpadala:
 *   TEXTBEE_DEVICE_ID_INVALID  — numero ng telepono ang nakalagay, hindi ID
 *   TEXTBEE_DEVICE_UNKNOWN     — wala sa account ang device id
 *   TEXTBEE_DEVICE_DISABLED    — naka-disable ang gateway app sa phone
 *   TEXTBEE_SIM_NOT_IN_SERVICE — walang SIM sa phone na nasa network
 *   TEXTBEE_SIM_NOT_CONFIGURED — naka-pin na SIM id ay wala sa device
 *
 * Ang `DEVICE_OFFLINE`/`DEVICE_DOZE`/`BATTERY_OPTIMIZED` ay HINDI failure: ang
 * mensahe ay naka-queue lang at ipapadala paggising ng phone.
 */
async function resolveTextBeeSender(params: {
  apiKey: string;
}): Promise<TextBeeSenderResolution> {
  const parsed = validateTextBeeDeviceId(Deno.env.get('TEXTBEE_DEVICE_ID'));
  const sim = parseTextBeeSimSubscriptionId(
    Deno.env.get('TEXTBEE_SIM_SUBSCRIPTION_ID'),
  );
  if (parsed.error) {
    return {
      deviceId: null,
      simSubscriptionId: null,
      errorCode: parsed.error,
      providerDetail:
        'TEXTBEE_DEVICE_ID must be the TextBee device id of the Android gateway phone, not its phone number',
      health: null,
    };
  }

  const health = await cachedTextBeeGatewayHealth({
    apiKey: params.apiKey,
    deviceId: parsed.deviceId,
  });
  if (!health) {
    // Hindi mabasa — huwag hadlangan ang send; ang TextBee pa rin ang sasagot.
    return {
      deviceId: parsed.deviceId,
      simSubscriptionId: sim,
      errorCode: null,
      health: null,
    };
  }

  const failure = (
    errorCode: string,
    providerDetail: string,
  ): TextBeeSenderResolution => ({
    deviceId: null,
    simSubscriptionId: null,
    errorCode,
    providerDetail,
    health,
  });

  if (health.issue === 'NO_DEVICE') {
    return failure(
      'TEXTBEE_DEVICE_UNKNOWN',
      parsed.deviceId === null
        ? 'no enabled device on the TextBee account'
        : `device ${parsed.deviceId} is not on the TextBee account`,
    );
  }
  if (health.issue === 'DEVICE_DISABLED') {
    return failure(
      'TEXTBEE_DEVICE_DISABLED',
      'the TextBee gateway app is disabled on the phone',
    );
  }
  if (health.issue === 'SIM_NOT_IN_SERVICE') {
    return failure(
      'TEXTBEE_SIM_NOT_IN_SERVICE',
      'no SIM in the gateway phone is in service',
    );
  }
  if (
    sim !== null && health.simSubscriptionIds.length > 0 &&
    !health.simSubscriptionIds.includes(sim)
  ) {
    return failure(
      'TEXTBEE_SIM_NOT_CONFIGURED',
      `SIM subscriptionId ${sim} is not installed in the gateway phone (found: ${
        health.simSubscriptionIds.join(', ')
      })`,
    );
  }

  // Kapag walang naka-configure na device id, i-pin ang na-resolve na device
  // para hindi tahimik na lumipat ang TextBee sa ibang phone kapag nagbago ang
  // default sa dashboard.
  return {
    deviceId: parsed.deviceId ?? health.deviceId,
    simSubscriptionId: sim,
    errorCode: null,
    health,
  };
}

function scheduleTextBeeGatewayDiagnosis(params: {
  apiKey: string;
  deviceId: string | null;
  batchId: string | null;
}): void {
  runInBackground(async () => {
    const health = await fetchTextBeeGatewayHealth({
      apiKey: params.apiKey,
      deviceId: params.deviceId,
      timeoutMs: 2_500,
    });
    if (!health) return;
    console.info(
      `[sms] TextBee gateway diagnosis (batch=${params.batchId ?? 'none'}) ` +
        `${textBeeGatewaySummary(health)} is_default=${health.isDefault}`,
    );
  });
}

export async function sendSms(params: {
  to: string;
  /** Message para sa TextBee. Sa OTP, may `{otp}` placeholder. */
  message: string;
  /**
   * Ang isusulat sa `sms_logs` (dapat redacted sa OTP). Kapag wala, ang
   * `message` ang gagamitin — huwag itong iwanang blangko sa OTP flow.
   */
  logMessage?: string;
  /**
   * Kapag may value, ang code ang ipapalit sa `{otp}` ng `message` bago
   * ipadala. Ang naka-log pa rin ay ang redacted na `logMessage`.
   */
  otpCode?: string;
  userId?: string;
  loanScheduleId?: string;
}): Promise<SmsSendResult> {
  const logMessage = params.logMessage ?? params.message;

  // DEV MOCK: hindi tumatawag sa TextBee. `pending` ang status — hindi "sent"
  // — para hindi magkunwari na na-deliver. Tanging sa mock mode lang
  // isinusulat ang buong message (kasama ang OTP) sa sms_logs para may
  // makuhang code ang developer sa Supabase Studio; sa totoong send,
  // redacted ang `logMessage` na ipinapasa ng caller.
  if (isMockSmsEnabled()) {
    console.log('[sms] MOCK_MODE: skipped TextBee request');
    await recordSmsLog({
      ...params,
      status: 'pending',
      gatewayReference: null,
      logMessage,
    });
    return {
      accepted: true,
      status: 'pending',
      // Walang tunay na provider — walang delivery evidence.
      delivery: 'unconfirmed',
      gatewayReference: null,
      errorCode: 'MOCK_MODE',
    };
  }

  // ── TextBee (ang tanging provider) ─────────────────────────────────────
  // Ang TextBee ay walang `{otp}` placeholder, kaya ang code ay pinalitan na
  // dito sa message bago ipadala. Ang ipapasa sa `sms_logs` ay ang redacted
  // na `logMessage` pa rin — walang code na naka-store o naka-log.
  const textBeeApiKey = (Deno.env.get('TEXTBEE_API_KEY') ?? '').trim();
  if (textBeeApiKey === '') {
    // Walang fallback sa ibang provider: mabigo nang malinaw kung kulang ang
    // secret, para hindi maging "tahimik na ibang gateway" ang OTP.
    console.error(
      '[sms] TEXTBEE_API_KEY is not configured — TextBee is the only SMS provider',
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
      delivery: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_NOT_CONFIGURED',
    };
  }

  const message = params.otpCode
    ? params.message.replace('{otp}', params.otpCode)
    : params.message;

  // Ang recipient ay ang numero ng LENDER/RIDER sa E.164 (`+639XXXXXXXXX`) —
  // hindi ang numero ng gateway phone. Kapag hindi valid na PH mobile, walang
  // network call: hindi ito kayang i-deliver kahit "accepted" ang API.
  const recipient = normalizeTextBeeRecipient(params.to);
  if (recipient === '') {
    console.error(
      '[sms] TextBee recipient rejected: not a valid Philippine mobile number',
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
      delivery: 'failed',
      gatewayReference: null,
      errorCode: 'TEXTBEE_INVALID_RECIPIENT',
    };
  }

  // Gateway phone / SIM — para may ebidensya kung SAAN galing ang SMS at hindi
  // mapagkamalan ang numero ng gateway bilang recipient.
  const sender = await resolveTextBeeSender({ apiKey: textBeeApiKey });
  if (sender.errorCode) {
    console.error(
      `[sms] TextBee gateway not usable (${sender.errorCode}): ${
        sender.providerDetail ?? 'no detail'
      }`,
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
      delivery: 'failed',
      gatewayReference: null,
      errorCode: sender.errorCode,
      ...(sender.providerDetail
        ? { providerDetail: redactSensitiveDigits(sender.providerDetail) }
        : {}),
    };
  }

  // Self-send: kapag ang recipient ay ang gateway SIM mismo, "Delivered" ang
  // lalabas sa Activity pero nasa gateway phone lang ang SMS. Wala itong ibang
  // teleponong mararating — kaya sinasabi ito nang malinaw sa log bago pa
  // hintayin ang code.
  if (isTextBeeSelfSend(recipient, Deno.env.get('TEXTBEE_GATEWAY_NUMBER'))) {
    console.warn(
      `[sms] TextBee recipient ${maskTextBeeNumber(recipient)} is the configured ` +
        'gateway number (TEXTBEE_GATEWAY_NUMBER): the OTP is sent to the gateway ' +
        "SIM itself, so only that phone can receive it. Enter the lender's own number.",
    );
  }

  const smsStartedAt = Date.now();
  const accepted = await sendTextBeeSms({
    apiKey: textBeeApiKey,
    to: recipient,
    message,
    deviceId: sender.deviceId,
    simSubscriptionId: sender.simSubscriptionId,
  });
  const sendMs = Date.now() - smsStartedAt;

  // ── Tunay na status ng batch ───────────────────────────────────────────
  // Tinanggap ng API ≠ naipadala ng phone. Kapag `failed` ang mensahe sa
  // device (walang load ang SIM, sarado ang radio, naabot ang carrier/device
  // limit, kulang ang SMS permission), HINDI ito ipapasa bilang "sent" —
  // failure ito para ma-retry ng user at makita sa logs ang errorCode.
  let result = accepted;
  // Simula sa `unconfirmed`: kapag hindi natin nabasa ang batch (offline ang
  // phone, hindi API-readable ang status), wala tayong ebidensyang umalis ang
  // mensahe — "OTP request accepted; delivery not yet confirmed."
  let delivery: SmsDelivery = accepted.accepted ? 'unconfirmed' : 'failed';
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
      // `sent` lang = tinanggap ng carrier; `delivered` lang ang may
      // delivery report. Maraming PH carrier ang HINDI nagdadala ng
      // delivery report, kaya normal ang `sent` na walang `delivered`.
      console.info(
        `[sms] TextBee batch ${accepted.gatewayReference} status: ` +
          `sent=${report.sentCount} delivered=${report.deliveredCount} ` +
          `failed=${report.failedCount} pending=${report.pendingCount} ` +
          `unknown=${report.unknownCount}/${report.total}`,
      );
      // Aling SIM talaga ang nagpadala (`simUsed`)? Mahalaga ito sa dual-SIM
      // gateway: ang "device default" SMS SIM ang pumipili, at kapag iba ito
      // sa SIM na sinubukan ng tester (hal. ang may load), dumarating ang
      // manual text pero hindi ang OTP — "Delivered" pa rin sa Activity.
      const simUsed = report.messages.find((m) =>
        m.simUsedSubscriptionId !== null
      )?.simUsedSubscriptionId ?? null;
      if (simUsed !== null) {
        const installedSims = sender.health?.simSubscriptionIds ?? [];
        if (sender.simSubscriptionId !== null && simUsed !== sender.simSubscriptionId) {
          console.warn(
            `[sms] TextBee batch ${accepted.gatewayReference} went out from SIM ` +
              `subscriptionId=${simUsed}, NOT the pinned ` +
              `${sender.simSubscriptionId} — the phone changed SIM, kaya ibang ` +
              'numero ang lumalabas bilang sender. I-pin muli ang tamang SIM ' +
              '(textbee app → SIM Cards).',
          );
        } else if (
          sender.simSubscriptionId === null && installedSims.length > 1
        ) {
          console.warn(
            `[sms] TextBee dual-SIM: the OTP went out from subscriptionId=` +
              `${simUsed} (installed: ${installedSims.join('/')}). Kung ibang ` +
              'SIM ang ginamit mo sa manual test (ang may SMS load), i-pin ito: ' +
              `TEXTBEE_SIM_SUBSCRIPTION_ID=${simUsed}`,
          );
        }
      }
      const failure = report.messages.find((m) => m.status === 'failed');
      // Huling tsek: ang `recipient` na nakatala sa TextBee ba ay ANG numerong
      // hiniling? Kapag iba, hindi dumating ang OTP sa lender kahit `delivered`
      // pa ang gateway — hindi natin ito sasabihing tagumpay.
      const audit = textBeeRecipientAudit(report, recipient);
      if (!audit.ok) {
        console.error(
          `[sms] TextBee batch ${accepted.gatewayReference} went to a DIFFERENT ` +
            `recipient (expected ${audit.expected ?? 'unknown'}, gateway reported ` +
            `${audit.mismatched ?? 'multiple recipients'}) — the OTP was not ` +
            'delivered to the requested number',
        );
        delivery = 'failed';
        result = {
          accepted: false,
          status: 'failed',
          gatewayReference: accepted.gatewayReference,
          errorCode: 'TEXTBEE_RECIPIENT_MISMATCH',
          providerDetail: redactSensitiveDigits(
            `expected ${audit.expected ?? 'unknown'}, gateway sent to ${
              audit.mismatched ?? 'multiple recipients'
            }`,
          ),
        };
      } else if (report.anyFailed && report.sentCount === 0) {
        const detail = [
          failure?.errorCode ? `device_error_code=${failure.errorCode}` : '',
          failure?.errorMessage ?? '',
        ].filter((part) => part !== '').join(', ');
        console.error(
          `[sms] TextBee batch ${accepted.gatewayReference} failed on the gateway phone (${
            detail || 'no detail'
          })`,
        );
        delivery = 'failed';
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
        // `delivered` lang (delivery report) ang `confirmed`.
        result = { ...accepted, status: 'sent' };
        delivery = report.deliveredCount === report.total
          ? 'confirmed'
          : 'carrier_accepted';
      } else if (report.pendingCount > 0) {
        delivery = 'queued';
        // Nasa queue pa lang: hindi pa naipadala ng gateway phone (offline,
        // tulog, o naantala ang push). HINDI natin ito sasabihing "sent" —
        // `pending` ang ibabalik, at ito ang ebidensya sa logs kung gaano
        // katagal nang naka-queue ang OTP.
        console.info(
          `[sms] TextBee batch ${accepted.gatewayReference} still pending (${
            report.pendingCount}/${report.total}) — queued on the gateway phone`,
        );
      } else {
        // `dispatched`/`unknown`: nasa phone na o wala nang report, pero
        // walang resulta. Hindi ito "sent" at hindi rin "pending".
        console.warn(
          `[sms] TextBee batch ${accepted.gatewayReference} has no result ` +
            `(unknown=${report.unknownCount}/${report.total}) — delivery ` +
            `cannot be confirmed`,
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
    `[sms] TextBee result=${result.status} delivery=${delivery} ` +
      `recipient=${maskTextBeeNumber(recipient) ?? 'invalid'} ` +
      `device=${sender.deviceId ?? 'default'} ` +
      `sim=${sender.simSubscriptionId ?? 'device-default'} ` +
      (result.errorCode ? `error=${result.errorCode} ` : '') +
      `send_ms=${sendMs} status_check_ms=${statusCheckMs} ` +
      `log_ms=${Date.now() - logStartedAt} ` +
      `total_ms=${Date.now() - smsStartedAt}`,
  );

  // Kalusugan ng gateway phone sa Bawat send (galing sa preflight — libre):
  // ito ang linya na nagsasabi kung sariwa ang heartbeat, naka-Doze ba, o may
  // SIM na wala sa network — ang mga dahilan kung bakit naka-queue lang ang OTP.
  if (sender.health) {
    console.info(`[sms] TextBee gateway ${textBeeGatewaySummary(sender.health)}`);
    if (sender.health.issue === 'DEVICE_OFFLINE') {
      console.warn(
        `[sms] TextBee gateway phone has not reported a heartbeat for ${
          sender.health.heartbeatAgeMinutes ?? 'many'
        } min — messages stay queued until it reconnects. Verify that ` +
          `TEXTBEE_DEVICE_ID (${sender.deviceId ?? 'default'}) is the phone you ` +
          'are looking at, and keep the textbee app running with battery usage ' +
          'set to Unrestricted.',
      );
    }
  }

  // Naka-queue o walang resulta? Ituloy sa BACKGROUND ang huling estado ng
  // batch (laging on) para may ebidensya kung naipadala pagkalipas ng ilang
  // segundo, o kung hindi talaga umalis / pumalya sa phone o SIM.
  if (
    result.accepted && result.gatewayReference &&
    (delivery === 'queued' || delivery === 'unconfirmed')
  ) {
    scheduleTextBeeBatchFollowUp({
      apiKey: textBeeApiKey,
      smsBatchId: result.gatewayReference,
      recipient,
      deviceId: sender.deviceId,
    });
    // Dagdag na device health sa background — opt-in lang (extra API call).
    if (textBeeGatewayDiagnosticsEnabled()) {
      scheduleTextBeeGatewayDiagnosis({
        apiKey: textBeeApiKey,
        deviceId: sender.deviceId,
        batchId: result.gatewayReference,
      });
    }
  }

  return { ...result, delivery };
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
