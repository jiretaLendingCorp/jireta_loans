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
  fetchTextBeeMessageReport,
  maskTextBeeNumber,
  parseTextBeeSendResponse,
  TEXTBEE_SEND_URL,
  type TextBeeBatchOutcome,
} from '../supabase/functions/_shared/textbee.ts';

const API_BASE = 'https://api.textbee.dev/api/v1';
const STATUS_POLL_MS = 3_000;
const STATUS_WAIT_SECONDS = 45;

/** Parehong template na ginagamit ng auth-otp — placeholder lang ang code. */
const OTP_TEMPLATE =
  'Your Jireta Loans OTP is: 000000. Valid for 5 minutes. Do not share this code.';

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
const deviceId = (Deno.env.get('TEXTBEE_DEVICE_ID') ?? '').trim();

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
    console.log(
      `    lastHeartbeat=${String(device.lastHeartbeat ?? 'never')} ` +
        `sims=${Array.isArray(sims?.sims) ? sims?.sims.length : 0} ` +
        `receiveSMSEnabled=${String(device.receiveSMSEnabled)}`,
    );
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
          (m.simSubscriptionId ? `[sim=${m.simSubscriptionId}]` : '')
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
line('x-api-key', '(naka-set, hindi ipinapakita)');
line('TEXTBEE_DEVICE_ID', deviceId === '' ? '(wala — default device)' : deviceId);
for (const recipient of recipients) {
  line('recipient', `${recipient.masked}  →  ${recipient.e164}`);
}
line('mode', shouldSend ? 'LIVE SEND' : 'dry run (walang SMS)');

await listDevices();

if (!shouldSend) {
  console.log('\n[2] Request body na ipapadala (dry run, naka-mask)');
  for (const recipient of recipients) {
    const payload = buildTextBeePayload({
      to: recipient.raw,
      message: OTP_TEMPLATE,
      deviceId,
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

  if (!report) {
    console.log(
      '  Walang status na nabasa (404/network). Tingnan ito sa TextBee ' +
        'dashboard → Messages.',
    );
    continue;
  }

  const failure = report.messages.find((m) => m.status === 'failed');
  const sim = report.messages.find((m) => m.simSubscriptionId)?.simSubscriptionId;
  console.log('  Resulta:');
  line('messages', `${report.total} (sent=${report.sentCount}, failed=${report.failedCount}, pending=${report.pendingCount})`);
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
      '  Diagnosis: tinanggap ng carrier (sent). Kung wala pa rin sa ' +
        'telepono: carrier filtering/A2P block o naka-off ang phone — hindi ' +
        'ito problema ng recipient formatting.',
    );
  } else {
    console.log(
      '  Diagnosis: nasa queue pa lang (pending) — offline/asleep ang gateway ' +
        'phone o naantala ang push. Tingnan ang lastHeartbeat sa itaas.',
    );
  }
}
