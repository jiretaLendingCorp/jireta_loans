// scripts/textbee_sms_diagnose.ts
// ─────────────────────────────────────────────────────────────────────────────
// TextBee OTP delivery diagnostic — ginagamit ito para malaman KUNG SAAN
// talaga pumapalya ang OTP: recipient formatting, TextBee API, gateway phone,
// o SIM/carrier. Hindi ito nagbabago ng app logic.
//
//   deno run --allow-env --allow-net scripts/textbee_sms_diagnose.ts \
//     09171234567 09281234567            # dry run (walang SMS)
//
//   deno run --allow-env --allow-net scripts/textbee_sms_diagnose.ts \
//     09171234567 09281234567 --send     # aktwal na send sa DALAWANG numero
//
// MGA PANUNTUNAN:
//   * API key ay galing LANG sa `TEXTBEE_API_KEY` env var — hindi ito
//     ipinapakita, hindi isinusulat sa file.
//   * Ang mga numero ay naka-mask sa output (`+6391*****567`).
//   * Gumagamit ng placeholder na code (`000000`) — HINDI totoong OTP, kaya
//     walang valid na code na lumalabas sa logs o sa telepono ng tester.
//   * Kailangan ng PAHINTULOT ng may-ari ng dalawang numero bago mag-`--send`.
// ─────────────────────────────────────────────────────────────────────────────
import {
  buildTextBeePayload,
  fetchTextBeeGatewayHealth,
  fetchTextBeeMessageReport,
  isTextBeeSelfSend,
  maskTextBeeNumber,
  parseTextBeeSendResponse,
  parseTextBeeSimSubscriptionId,
  textBeeDeliveryState,
  textBeeRecipientAudit,
  validateTextBeeDeviceId,
  TEXTBEE_SEND_URL,
  type TextBeeBatchOutcome,
} from '../supabase/functions/_shared/textbee.ts';
import { otpSmsBodyTemplate } from '../supabase/functions/_shared/otp.ts';

const API_BASE = 'https://api.textbee.dev/api/v1';
const STATUS_POLL_MS = 3_000;
const STATUS_WAIT_SECONDS = 45;

/** Parehong body na ipinapadala ng auth-otp/sms-send — placeholder lang ang
 * code. Galing ito sa `OTP_SMS_TEMPLATE` para eksakto ang sinusubukan. */
const OTP_TEMPLATE = otpSmsBodyTemplate(
  5,
  Deno.env.get('OTP_SMS_TEMPLATE'),
).replace('{otp}', '000000');

const args = Deno.args;
const shouldSend = args.includes('--send');
const numbers = args.filter((arg) => !arg.startsWith('--'));

function usage(exitCode = 1): never {
  console.error(
    [
      'Usage:',
      '  deno run --allow-env --allow-net scripts/textbee_sms_diagnose.ts <phone1> <phone2> [--send]',
      '',
      'Hindi kasama ang `--send`: dry run lang (walang SMS na ipapadala).',
      'Kailangan ng pahintulot ng may-ari ng numero bago mag-send.',
    ].join('\n'),
  );
  Deno.exit(exitCode);
}

const apiKey = (Deno.env.get('TEXTBEE_API_KEY') ?? '').trim();
const deviceIdEnv = (Deno.env.get('TEXTBEE_DEVICE_ID') ?? '').trim();
const deviceIdCheck = validateTextBeeDeviceId(deviceIdEnv);
const deviceId = deviceIdCheck.deviceId ?? '';
const simSubscriptionId = parseTextBeeSimSubscriptionId(
  Deno.env.get('TEXTBEE_SIM_SUBSCRIPTION_ID'),
);
const gatewayNumber = (Deno.env.get('TEXTBEE_GATEWAY_NUMBER') ?? '').trim();
if (apiKey === '') {
  console.error(
    'TEXTBEE_API_KEY is not set. Kunin ito sa TextBee dashboard → API keys, ' +
      'at i-set lamang sa environment ng script (hindi sa git):\n' +
      '  TEXTBEE_API_KEY=... deno run --allow-env --allow-net ' +
      'scripts/textbee_sms_diagnose.ts 0917... 0928... --send',
  );
  Deno.exit(1);
}
if (numbers.length !== 2) usage();

type Recipient = { raw: string; e164: string; masked: string };

const recipients: Recipient[] = numbers.map((raw) => {
  const payload = buildTextBeePayload({ to: raw, message: 'x' });
  const e164 = payload.recipients[0];
  if (e164 === '') {
    console.error(`Hindi ma-normalize ang numero: ${raw}`);
    Deno.exit(1);
  }
  return { raw, e164, masked: maskTextBeeNumber(e164) ?? '(masked)' };
});

function line(label: string, value: unknown): void {
  console.log(`  ${label.padEnd(22)} ${String(value)}`);
}

async function listDevices(): Promise<void> {
  console.log('\n[1] Gateway devices (GET /gateway/devices)');
  let res: Response;
  try {
    res = await fetch(`${API_BASE}/gateway/devices`, {
      headers: { 'x-api-key': apiKey },
      signal: AbortSignal.timeout(10_000),
    });
  } catch (_) {
    console.log('  network error — hindi maabot ang TextBee API');
    return;
  }
  line('http_status', res.status);
  const body = await res.json().catch(() => null) as { data?: unknown } | null;
  if (res.status !== 200 || !Array.isArray(body?.data)) {
    line('body', JSON.stringify(body)?.slice(0, 300) ?? '(non-json)');
    return;
  }
  const devices = body.data as Record<string, unknown>[];
  if (devices.length === 0) {
    console.log('  WALANG device sa account — walang magpapadala ng SMS.');
    return;
  }
  for (const device of devices) {
    const sims = device.simInfo as { sims?: unknown[] } | undefined;
    console.log(
      `  • ${String(device._id)} enabled=${String(device.enabled)} ` +
        `isDefault=${String(device.isDefault)} name=${String(device.name ?? '-')}`,
    );
    const simList = Array.isArray(sims?.sims) ? sims.sims : [];
    const heartbeatMs = Date.parse(String(device.lastHeartbeat ?? ''));
    const heartbeatMinutes = Number.isFinite(heartbeatMs)
      ? Math.max(0, Math.round((Date.now() - heartbeatMs) / 60000))
      : null;
    console.log(
      `    lastHeartbeat=${String(device.lastHeartbeat ?? 'never')} ` +
        `(${heartbeatMinutes === null ? 'walang heartbeat' : `${heartbeatMinutes} min ago`}) ` +
        `sims=${simList.length} ` +
        `receiveSMSEnabled=${String(device.receiveSMSEnabled)} ` +
        `app=${String(device.appVersionName ?? '?')} ` +
        `sentSMSCount=${String(device.sentSMSCount ?? '?')}`,
    );
    if (heartbeatMinutes === null || heartbeatMinutes > 30) {
      console.log(
        '      ⚠ Matagal nang walang heartbeat — malamang offline/asleep/Doze ang ' +
          'phone na ito. Ang mga send dito ay mananatiling naka-queue.',
      );
    }
    // Walang phone number sa output — slot/carrier/label lang. Ang DEFAULT
    // SMS SIM ng phone ang ginagamit ng TextBee (walang simSubscriptionId sa
    // request), kaya dito makikita kung aling SIM ang naka-install at kung
    // alin ang dapat maging default para sa SMS.
    for (const [index, sim] of simList.entries()) {
      const record = sim !== null && typeof sim === 'object'
        ? sim as Record<string, unknown>
        : {};
      const id = record.subscriptionId;
      const slot = record.simSlotIndex ?? record.slotIndex;
      const carrier = String(record.carrierName ?? '-');
      const label = String(record.displayName ?? '-');
      const serviceState = String(record.serviceState ?? 'unknown');
      const signalLevel = record.signalLevel;
      console.log(
        `      SIM ${typeof slot === 'number' ? slot + 1 : index + 1}: ` +
          `subscriptionId=${id === undefined ? '(wala)' : String(id)} ` +
          `carrier=${carrier} label=${label} ` +
          `serviceState=${serviceState} ` +
          `signalLevel=${signalLevel === undefined ? '?' : String(signalLevel)}`,
      );
      if (serviceState.toUpperCase() !== 'IN_SERVICE') {
        console.log(
          '        ⚠ Wala ang SIM na ito sa network — hindi ito makakapagpadala.',
        );
      }
      if (simSubscriptionId !== null && id === simSubscriptionId) {
        console.log('        ^ ito ang naka-pin na TEXTBEE_SIM_SUBSCRIPTION_ID');
      }
    }
    if (simList.length > 1) {
      console.log(
        '      ⚠ Dual-SIM: ang DEFAULT SMS SIM ng phone ang gagamitin. Sa ' +
          'Android: Settings → Network & internet → SIMs → SMS → piliin ang ' +
          'SIM na may regular SMS load (hindi data-only tulad ng GOMO).',
      );
    }
    if (deviceId !== '' && String(device._id) === deviceId) {
      console.log('    ^ ito ang TEXTBEE_DEVICE_ID (gateway na nagpapadala)');
    }
  }
  if (deviceId !== '' && !devices.some((d) => String(d._id) === deviceId)) {
    console.log(
      `  ⚠ TEXTBEE_DEVICE_ID=${deviceId} ay WALA sa account na ito — ` +
        'magre-404/400 ang send.',
    );
  }

  // Pinaka-mahalagang tsek: ang NAKA-CONFIGURE na device ba ang pinaka-buhay?
  // Ang send na may `deviceId` ay HINDI lumilipat sa ibang phone. Kapag ang
  // naka-configure ay lumang device (naka-enable pa pero patay ang phone),
  // naka-queue lang ang OTP habang ang TOTOONG gateway phone ay tahimik.
  const enabled = devices.filter((device) => device.enabled === true);
  const freshest = enabled
    .map((device) => ({
      device,
      at: Date.parse(String(device.lastHeartbeat ?? '')),
    }))
    .filter((entry) => Number.isFinite(entry.at))
    .sort((a, b) => b.at - a.at)[0];
  const configured = devices.find((device) => String(device._id) === deviceId);
  if (configured && freshest && configured !== freshest.device) {
    const configuredAt = Date.parse(String(configured.lastHeartbeat ?? ''));
    if (!Number.isFinite(configuredAt) || freshest.at - configuredAt > 600_000) {
      console.log(
        `  ⚠ Ang TEXTBEE_DEVICE_ID ay ${String(configured._id)}\n` +
          `    ${Number.isFinite(configuredAt) ? new Date(configuredAt).toISOString() : 'walang heartbeat'}` +
          `\n    pero ang pinaka-buhay na enabled device ay ${String(freshest.device._id)} ` +
          `(${new Date(freshest.at).toISOString()}).\n` +
          '    Ibig sabihin: posibleng HINDI ito ang konektadong gateway phone — ' +
          'naka-queue lang ang mga OTP sa lumang device.',
      );
    }
  }
}

/**
 * Per-message timestamps — dito makikita kung SAAN nakaantala ang mensahe
 * (server queue → push → phone → radio → carrier), hindi lang ang status:
 *   dispatchedAt   empty → wala pa sa push service (nasa server queue)
 *   pushReceivedAt empty → hindi naabot ng push ang phone (offline/asleep)
 *   sendAttemptedAt empty → nasa phone, naghihintay ng Send Delay
 *   sentAt         empty → nasa radio/carrier pa, o pumalya
 */
async function printMessageTimestamps(smsBatchId: string): Promise<void> {
  try {
    const res = await fetch(
      `${API_BASE}/gateway/messages?smsBatchId=${
        encodeURIComponent(smsBatchId)
      }&limit=100`,
      { headers: { 'x-api-key': apiKey }, signal: AbortSignal.timeout(10_000) },
    );
    if (!res.ok) return;
    const body = await res.json().catch(() => null) as { data?: unknown } | null;
    if (!Array.isArray(body?.data)) return;
    console.log('  Timestamps (kung saan nakaantala):');
    for (const item of body.data as Record<string, unknown>[]) {
      const at = (key: string) => String(item[key] ?? '-');
      const simUsed = item.simUsed !== null && typeof item.simUsed === 'object'
        ? item.simUsed as Record<string, unknown>
        : null;
      console.log(
        `    ${maskTextBeeNumber(item.recipient) ?? '?'} ` +
          `status=${String(item.status ?? 'unknown')} ` +
          `requested=${at('requestedAt')} dispatched=${at('dispatchedAt')} ` +
          `push_received=${at('pushReceivedAt')} ` +
          `send_attempted=${at('sendAttemptedAt')} sent=${at('sentAt')} ` +
          `delivered=${at('deliveredAt')} failed=${at('failedAt')}` +
          (simUsed
            ? ` sim_used=${
              String(simUsed.subscriptionId ?? '?')
            }(slot=${String(simUsed.slotIndex ?? '?')}, ${
              String(simUsed.carrierName ?? '?')
            })`
            : '') +
          (item.errorCode ? ` errorCode=${String(item.errorCode)}` : ''),
      );
    }
  } catch (_) {
    console.log('  (hindi mabasa ang timestamps)');
  }
}

/**
 * Kalusugan ng gateway phone — ito ang sumasagot sa "bakit pending/queued?".
 * Hindi makikita sa send response (200 = tinanggap lang).
 */
async function printGatewayHealth(): Promise<void> {
  const health = await fetchTextBeeGatewayHealth({ apiKey, deviceId });
  console.log('\n[1b] Gateway health (GET /gateway/devices)');
  if (!health) {
    console.log('  (hindi mabasa ang device health)');
    return;
  }
  line('device', health.deviceId ?? '(default)');
  line('enabled', health.enabled);
  line('is_default', health.isDefault);
  line('heartbeat_min', health.heartbeatAgeMinutes ?? 'n/a');
  line('doze', health.doze);
  line('battery_opt_ignored', health.batteryOptimizationsIgnored);
  line('sms_send_delay_s', health.smsSendDelaySeconds ?? 'n/a');
  line('sim_subscription_ids', health.simSubscriptionIds.join('/') || 'none');
  line(
    'sim_service_state',
    health.sims
      .map((sim) =>
        `${sim.subscriptionId ?? '?'}:${sim.serviceState ?? 'unknown'}`
      )
      .join(' / ') || 'none',
  );
  line('issue', health.issue ?? 'none');
  if (
    simSubscriptionId !== null &&
    !health.simSubscriptionIds.includes(simSubscriptionId)
  ) {
    console.log(
      `  ✖ TEXTBEE_SIM_SUBSCRIPTION_ID=${simSubscriptionId} ay WALA sa SIM ` +
        'list ng device. Magbabago ang id kapag inalis/isiningit ang SIM — ' +
        'kunin ang bago sa textbee app → SIM Cards.',
    );
  }
  if (health.issue) {
    console.log(
      '  ⚠ Ito ang hadlang bago pa makapagpadala ang phone — ayusin muna ito ' +
        '(Gateway Enabled, internet, lastHeartbeat, battery optimization, SIM).',
    );
  }
}

async function probeBatch(smsBatchId: string): Promise<TextBeeBatchOutcome | null> {
  const deadline = Date.now() + STATUS_WAIT_SECONDS * 1_000;
  let last: TextBeeBatchOutcome | null = null;
  while (Date.now() < deadline) {
    const report = await fetchTextBeeMessageReport({ apiKey, smsBatchId });
    if (report && report.total > 0) {
      last = report;
      const summary = report.messages
        .map((m) =>
          `${m.recipient ?? '?'}=${m.status}` +
          (m.errorCode ? `(errorCode=${m.errorCode})` : '') +
          (m.simUsedSubscriptionId !== null
            ? `[sent_via_sim=${m.simUsedSubscriptionId}]`
            : '')
        )
        .join(', ');
      console.log(
        `  +${Math.round(STATUS_WAIT_SECONDS - (deadline - Date.now()) / 1000)}s ` +
          `${summary}`,
      );
      if (report.allSent || (report.anyFailed && report.pendingCount === 0)) {
        return report;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, STATUS_POLL_MS));
  }
  return last;
}

console.log('TextBee OTP delivery diagnostic');
line('endpoint', TEXTBEE_SEND_URL);
line('x-api-key', '(naka-set, hindi ipinapakita)');  line('TEXTBEE_DEVICE_ID', deviceId === '' ? '(wala — default device)' : deviceId);
if (deviceIdCheck.error) {
  console.log(
    '  ✖ TEXTBEE_DEVICE_ID ay mukhang NUMERO NG TELEPONO, hindi device id. ' +
      'Kunin ang device id sa textbee app → Settings → Device ID (24 hex).',
  );
}
line(
  'SIM',
  simSubscriptionId === null
    ? 'default SMS SIM ng phone (walang simSubscriptionId)'
    : `naka-pin: subscriptionId=${simSubscriptionId}`,
);
line(
  'TEXTBEE_GATEWAY_NUMBER',
  gatewayNumber === ''
    ? '(wala — walang self-send check)'
    : maskTextBeeNumber(gatewayNumber) ?? '(invalid)',
);
for (const recipient of recipients) {
  line('recipient', `${recipient.masked}  →  ${recipient.e164}`);
  if (
    isTextBeeSelfSend(recipient.e164, gatewayNumber)
  ) {
    console.log(
      '    ⚠ Ito ang numero ng GATEWAY SIM (TEXTBEE_GATEWAY_NUMBER), hindi ' +
        'ng lender: self-send ito. Lalabas na "Delivered" sa TextBee Activity ' +
        'pero sa gateway phone lang darating — walang ibang teleponong makakatanggap.',
    );
  }
}
line('mode', shouldSend ? 'LIVE SEND' : 'dry run (walang SMS)');

await listDevices();
await printGatewayHealth();

if (!shouldSend) {
  console.log('\n[2] Request body na ipapadala (dry run, naka-mask)');
  for (const recipient of recipients) {
    const payload = buildTextBeePayload({
      to: recipient.raw,
      message: OTP_TEMPLATE,
      deviceId,
      simSubscriptionId,
    });
    console.log(
      `  ${JSON.stringify({
        ...payload,
        recipients: payload.recipients.map((n) => maskTextBeeNumber(n)),
      })}`,
    );
  }
  console.log(
    '\nWalang SMS na naipadala. Ulitin kasama ang `--send` (may pahintulot) ' +
      'para makita ang HTTP response, smsBatchId at tunay na status.',
  );
  Deno.exit(0);
}

for (const [index, recipient] of recipients.entries()) {
  console.log(`\n[${index + 2}] Send → ${recipient.masked}`);
  const payload = buildTextBeePayload({
    to: recipient.raw,
    message: OTP_TEMPLATE,
    deviceId: deviceId === '' ? undefined : deviceId,
    simSubscriptionId,
  });

  let res: Response;
  try {
    res = await fetch(TEXTBEE_SEND_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    const timeout = err instanceof DOMException && err.name === 'TimeoutError';
    line('http_status', timeout ? 'TIMEOUT' : 'NETWORK_ERROR');
    continue;
  }

  const body = await res.json().catch(() => null);
  const result = parseTextBeeSendResponse(res.status, body);
  const data = (body as { data?: Record<string, unknown> } | null)?.data ?? {};

  line('http_status', res.status);
  line('accepted', result.accepted);
  line('status', result.status);
  line('smsBatchId', result.gatewayReference ?? '(wala)');
  line('recipientCount', data.recipientCount ?? '(wala)');
  line('errorCode', result.errorCode ?? '(wala)');
  line('provider_detail', result.providerDetail ?? '(wala)');
  const warning = data.warning as { code?: string; message?: string } | undefined;
  if (warning) line('warning', `${warning.code ?? '?'} ${warning.message ?? ''}`);

  if (!result.accepted || !result.gatewayReference) {
    console.log('  Resulta: tinanggihan/na-fail ng API — tingnan ang errorCode.');
    continue;
  }

  console.log(
    `  Hinihintay ang tunay na status (GET /gateway/messages?smsBatchId=..., ` +
      `hanggang ${STATUS_WAIT_SECONDS}s):`,
  );
  const report = await probeBatch(result.gatewayReference);
  await printMessageTimestamps(result.gatewayReference);

  if (!report) {
    console.log(
      '  Walang status na nabasa (404/network). Tingnan ito sa TextBee ' +
        'dashboard → Messages.',
    );
    continue;
  }

  const failure = report.messages.find((m) => m.status === 'failed');
  const sim = report.messages.find((m) => m.simUsedSubscriptionId !== null)
    ?.simUsedSubscriptionId;
  console.log('  Resulta:');
  line(
    'messages',
    `${report.total} (sent=${report.sentCount}, delivered=${report.deliveredCount}, failed=${report.failedCount}, pending=${report.pendingCount}, unknown=${report.unknownCount})`,
  );
  line('delivery', textBeeDeliveryState(report));
  const audit = textBeeRecipientAudit(report, recipient.e164);
  line('recipient_expected', audit.expected ?? '(invalid)');
  line('recipient_reported', audit.reported.join(' / ') || '(walang iniulat)');
  if (!audit.ok) {
    console.log(
      '  ✖ RECIPIENT MISMATCH: iba ang numerong pinadalhan ng gateway sa ' +
        `numerong hiniling (${audit.mismatched ?? 'multiple recipients'}). ` +
        'Hindi ito makakarating sa lender — tingnan kung ang gateway phone ' +
        'ang nagpapalit ng recipient, at siguraduhing ang numero ng LENDER ' +
        'ang ipinasa, hindi ang numero ng gateway SIM.',
    );
  }
  console.log(
    '  (Ang `sent` ay tinanggap ng carrier; `delivered` lang ang may delivery ' +
      'report — maraming PH carrier ang hindi nagdadala nito.)',
  );
  if (sim) line('sent_from_sim', sim);
  if (failure) {
    line('device_error_code', failure.errorCode ?? '(wala)');
    line('device_error', failure.errorMessage ?? '(wala)');
    console.log(
      '  Diagnosis: pumalya sa GATEWAY PHONE / SIM / CARRIER — hindi sa ' +
        'recipient formatting. Ayusin ang load/promo ng SIM (cross-network), ' +
        'signal, SMS permission, o device limit, tapos ulitin.',
    );
  } else if (report.allSent) {
    console.log(
      '  Diagnosis: tinanggap ng carrier (sent)' +
        (report.deliveredCount === report.total
          ? ' AT may delivery report (delivered) — kumpirmadong umabot.'
          : ', WALANG delivery report — maraming PH carrier ang hindi ' +
            'nagdadala nito, kaya hindi ito maipapakitang "delivered".'),
    );
    if (report.deliveredCount === report.total) {
      console.log(
        '  Kung `delivered` ito pero wala sa telepono: (1) tingnan ang ' +
          'recipient_reported sa itaas — dapat iyon ang numero ng LENDER, ' +
          'hindi ang numero ng gateway SIM (self-send = delivered agad, sa ' +
          'gateway phone lang); (2) ' +
          (gatewayNumber === ''
            ? 'i-set ang TEXTBEE_GATEWAY_NUMBER para awtomatikong mahuli ang ' +
              'self-send; '
            : 'naka-set ang TEXTBEE_GATEWAY_NUMBER — hindi self-send ang numerong ito; ') +
          '(3) carrier filtering/spam block sa recipient, o ibang telepono ang may ' +
          'hawak sa numerong iyon.',
      );
    } else {
      console.log(
        '  Kung wala sa telepono: carrier filtering/A2P block, ibang network ' +
          'ang recipient, o naka-off ang phone — hindi ito problema ng ' +
          'recipient formatting.',
      );
    }
  } else if (report.pendingCount > 0) {
    console.log(
      '  Diagnosis: nasa queue pa lang (pending) — offline/asleep ang gateway ' +
        'phone o naantala ang push. Tingnan ang lastHeartbeat sa itaas.',
    );
  } else {
    console.log(
      '  Diagnosis: `dispatched`/`unknown` — walang resulta mula sa phone. ' +
        'Hindi ito maipapakitang sent/delivered; tingnan ang heartbeat, SMS ' +
        'permission at battery optimization ng textbee app.',
    );
  }
}
