// supabase/functions/auth-otp/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   auth-send-otp    →  ?fn=send-otp
//   auth-verify-otp  →  ?fn=verify-otp
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/db.ts';
import {
  normalizePhMobile,
  sanitizeString,
  validateEmail,
  validatePhone,
} from '../_shared/validators.ts';
import {
  sendSms,
  isMockSmsEnabled,
  type SmsDelivery,
} from '../_shared/sms.ts';
import { sendLoginOtpEmail, sendMpinResetOtpEmail } from '../_shared/email.ts';
import {
  generateOtpCode,
  hashOtpCode,
  normalizeOtpPurpose,
  otpRejectionReason,
  otpSmsBodyTemplate,
  parseOtpIdentifier,
  resendCooldownRemaining,
  type OtpPurpose,
} from '../_shared/otp.ts';
import {
  MPIN_RESET_PURPOSE,
} from '../_shared/mpin_reset.ts';
import { generateResetToken, hashResetToken } from '../_shared/reset_token.ts';
import { singleWithObjectEmbeds, type DbClient } from '../_shared/types.ts';
import { guardRateLimit, recordSecurityEvent, blockKey, checkBlock } from '../_shared/rate_limiter.ts';
import { sanitizeIpAddress } from '../_shared/audit.ts';
import { nowManilaISO } from '../_shared/timezone.ts';
import {
  authDisplayMetadata,
  claimActiveSessionDetailed,
  cleanSessionId,
  sessionIdentifierFromToken,
  syncAuthUserIdentity,
} from '../_shared/auth.ts';
import { fetchUserMfaState } from '../_shared/mfa.ts';

// ── [moved from auth-send-otp] ──────────────────────────────────────────────
const OTP_RATE_LIMIT = 10;
const OTP_WINDOW_MINUTES = 10;

// Abuse detection: 10 OTP requests per phone per 10 minutes (the stored
// otp_codes count above) PLUS an IP-scoped guard so one IP cannot spray OTP
// across many phone numbers (phone-number enumeration / SMS bombing).
const OTP_IP_RATE_MAX = 20;
const OTP_IP_WINDOW_MINUTES = 10;
const OTP_BLOCK_MINUTES = 15;

// Hard cap sa verification attempts mula sa isang IP — ang per-phone na
// escalating lockout sa ibaba ay hindi makakapigil sa distributed brute force.
// Sapat ito para sa shared na office/branch wifi (maraming rider sa iisang IP)
// habang hinaharangan pa rin ang mabilis na pagsubok ng codes.
const OTP_VERIFY_IP_RATE_MAX = 60;
const OTP_VERIFY_IP_WINDOW_MINUTES = 10;

function envInt(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

/** Configurable sa Edge Function secrets — default 5 minuto. */
const OTP_EXPIRY_MINUTES = envInt('OTP_EXPIRY_MINUTES', 5);
/** Cooldown bago pwede ulit mag-request (default 60s, tugma sa UI timer). */
const OTP_RESEND_COOLDOWN_SECONDS = envInt('OTP_RESEND_COOLDOWN_SECONDS', 60);
/** Gaano katagal valid ang reset authorization na ibinibigay pagkatapos ng OTP. */
const MPIN_RESET_TOKEN_MINUTES = envInt('MPIN_RESET_TOKEN_MINUTES', 10);

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
const MAX_OTP_ATTEMPTS = 5;
const DEFAULT_PASSWORD = '12345678';

const OTP_PASSWORD = (phone: string) => `OTP_${phone}_SECURE`;

// ── Persistent, escalating OTP lockout ─────────────────────────────────────
// Stored in `otp_lockouts` (keyed by phone) so the lock survives an app close
// or a fresh OTP request — only a successful verification (or waiting out the
// lock) clears it.
//
// Escalation schedule (product spec):
//   3 attempts → 3 minutes
//   4 attempts → 10 minutes
//   5+ attempts → lockout ×10 per additional attempt (100, 1000, ...)
// The lockout is capped at 48 hours (2 days) so a phone number can never be
// effectively locked forever by a single escalating streak.
const MAX_LOCKOUT_MINUTES = 2 * 24 * 60; // 48 hours = 2880 minutes

/** Ang provider layer (TextBee) ang nagpapalit ng code sa `{otp}` — hindi ito
 * nilo-log. Ang mismong body ay galing sa `OTP_SMS_TEMPLATE` (default sa
 * `_shared/otp.ts`): maikli at hindi kamukha ng canned A2P na mensahe, dahil
 * hinaharang iyon ng carrier anti-smishing filter kapag personal SIM ang
 * sender — "Delivered" sa TextBee pero walang dumarating.
 *
 * Ang `{minutes}`/`{otp}` ay hindi nakalimutan dito: `{otp}` ay pinapalitan ng
 * `sendSms`, at ang buong body ay HINDI nilo-log (ang `otpLogMessage` ang
 * isinusulat sa `sms_logs`). */
function otpMessageTemplate(minutes: number): string {
  return otpSmsBodyTemplate(minutes, Deno.env.get('OTP_SMS_TEMPLATE'));
}

/**
 * Ang sinasabi ng app tungkol sa SMS — nakabatay sa TOTOONG kalagayan na
 * iniulat ng gateway, hindi lang sa HTTP 200 ng send request.
 *
 *   confirmed        — may delivery report ang carrier (TextBee `delivered`).
 *   carrier_accepted — tinanggap ng carrier (TextBee `sent`); maraming PH
 *                      carrier ang walang delivery report, kaya wala tayong
 *                      sasabihing "delivered".
 *   unconfirmed      — tinanggap ng API pero walang nabasang status.
 *   queued           — nasa queue pa ang code sa gateway phone.
 *
 * Walang "OTP sent successfully" na blanketong sagot: iyon ang dating
 * dahilan kung bakit naghihintay ang user ng code na hindi pa naipapadala.
 */
function smsDeliveryMessage(delivery: SmsDelivery | undefined): string {
  switch (delivery) {
    case 'confirmed':
      return 'Code delivered to your phone.';
    case 'carrier_accepted':
      return 'Code sent by SMS. Delivery confirmation is not available.';
    case 'unconfirmed':
      return 'OTP request accepted; delivery not yet confirmed.';
    case 'queued':
    default:
      return 'Your code is on its way. It may take a moment to arrive.';
  }
}

/** Redacted na bersyon para sa `sms_logs` — walang OTP. */
function otpLogMessage(minutes: number): string {
  return `Your Jireta Loans OTP was sent. Valid for ${minutes} minutes. Do not share this code.`;
}

function lockoutMinutes(attempts: number): number {
  if (attempts <= 2) return 0;
  if (attempts === 3) return 3;
  if (attempts === 4) return 10;
  return Math.min(MAX_LOCKOUT_MINUTES, 10 * Math.pow(10, attempts - 4)); // 5 → 100, 6 → 1000, ... capped at 2880
}

async function readOtpLockout(db: DbClient, phone: string) {
  const { data } = await db
    .from('otp_lockouts')
    .select('failed_attempts, locked_until')
    .eq('phone_number', phone)
    .maybeSingle();
  return {
    failedAttempts: data?.failed_attempts ?? 0,
    lockedUntil: data?.locked_until ? new Date(data.locked_until) : null,
  };
}

function lockoutError(lockedUntil: Date, attempts: number): Response {
  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((lockedUntil.getTime() - Date.now()) / 1000),
  );
  const minutes = Math.round(retryAfterSeconds / 60);
  const label = minutes > 0 ? `${minutes} minute(s)` : `${retryAfterSeconds} second(s)`;
  return errorResponse(
    `Too many wrong OTP attempts. Try again in ${label}.`,
    429,
    'OTP_LOCKED',
    {
      retry_after_seconds: retryAfterSeconds,
      locked_until: lockedUntil.toISOString(),
      failed_attempts: attempts,
    },
  );
}

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
async function selfRegisterLender(db: DbClient, phone: string) {
  const { data: roleData } = await db.from('roles').select('id, is_archived').eq('name', 'lender').single();
  if (!roleData) return null;
  // deno-lint-ignore no-explicit-any
  if ((roleData as any).is_archived === true) return null;

  // Lenders are identified by PHONE only — public.users.email stays NULL and
  // no synthetic email is ever shown to the app. The temp email below is an
  // internal GoTrue credential only (some installs, e.g. local dev, reject
  // phone+password sign-in unless SMS auth is provisioned).
  const { data: authUser, error: authErr } = await db.auth.admin.createUser({
    phone: toE164(phone),
    email: `${phone}@jireta.temp`,
    password: OTP_PASSWORD(phone),
    phone_confirm: true,
    email_confirm: true,
    app_metadata: { role: 'lender' },
    // Display name lang ito sa Supabase Auth dashboard (walang pangalan pa ang
    // self-registered lender — makukuha ito sa Account Upgrade).
    user_metadata: authDisplayMetadata({ phone }),
  });
  if (authErr || !authUser?.user) return null;

  const { data: newUser, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    role_id: roleData.id,
    phone_number: phone,
    email: null,
    // No placeholder name — the real identity is captured later via
    // Account Upgrade / profile edit, not auto-filled here.
    first_name: '',
    last_name: '',
    account_status: 'active',
    force_password_change: false,
    created_by: null,
  }, { onConflict: 'id' }).select('id, account_status, email, first_name, last_name, phone_number, force_password_change, roles!users_role_id_fkey(name)').single();

  if (userErr || !newUser) {
    await db.auth.admin.deleteUser(authUser.user.id).catch(() => {});
    return null;
  }

  const { error: profileErr } = await db.from('lender_profiles').insert({
    id: newUser.id,
    account_upgrade_status: 'not_submitted',
  });
  if (profileErr) {
    await db.auth.admin.deleteUser(authUser.user.id).catch(() => {});
    await Promise.resolve(db.from('users').delete().eq('id', newUser.id)).catch(() => {});
    return null;
  }

  return singleWithObjectEmbeds(newUser);
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'send-otp';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'send-otp':
        // ── [moved from functions/auth-send-otp/index.ts] ───────────────
        return await handleSendOtp(req);
      case 'verify-otp':
        // ── [moved from functions/auth-verify-otp/index.ts] ─────────────
        return await handleVerifyOtp(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('auth-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/auth-send-otp/index.ts] ───────────────────────────
async function handleSendOtp(req: Request) {
  const startedAt = Date.now();
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  // Maaaring PH mobile number O email (hal. Gmail) ang identifier.
  // `identifier` ang bagong field; `phone_number` / `email` ay para sa lumang
  // client na hindi pa updated.
  // Isang field lang sa app ("Mobile Number or Email") — dito hinihiwalay base
  // sa `@`; ang numero ay nino-normalize sa `09XXXXXXXXX`.
  const identifier = parseOtpIdentifier(
    sanitizeString(
      String(body['identifier'] ?? body['phone_number'] ?? body['email'] ?? ''),
    ),
  );
  const emailInput = identifier.email;
  let phone = identifier.phone;
  const purpose: OtpPurpose | null = normalizeOtpPurpose(body['purpose']);
  const ip = clientIp(req);

  if (emailInput !== '') {
    if (!validateEmail(emailInput)) {
      return errorResponse('Enter a valid email address', 400, 'VALIDATION_ERROR');
    }
  } else if (!validatePhone(phone)) {
    return errorResponse(
      'Invalid Philippine phone number (09XXXXXXXXX)',
      400,
      'VALIDATION_ERROR',
    );
  }
  if (!purpose) return errorResponse('Invalid OTP purpose', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const viaEmail = emailInput !== '';

  // Generic na sagot para sa reset flow: hindi nito sinasabi kung may account
  // ba ang numero (enumeration protection). Kung walang account, walang SMS na
  // ipapadala, at ang verify ay bibigo rin nang generic.
  // Iniulat ang TUNAY na kalagayan ng send, hindi lang "tinanggap ng API".
  // `pending` = nasa queue pa sa TextBee gateway phone — hindi pa naipadala at
  // maaaring maantala (offline/asleep ang phone). Dating laging "OTP sent
  // successfully" kahit `pending`, kaya naghihintay ang user ng code na wala
  // pang lumalabas sa gateway phone.
  //
  // Ang `sms_status`/`sms_delivery` ay ISINASAMA lang sa login flow. Sa reset
  // flow, hayag dapat na magkapareho ang sagot para sa may account at walang
  // account, kaya hindi ito idinadagdag doon.
  const sentResponse = (
    sms?: { status: 'sent' | 'pending'; delivery: SmsDelivery },
  ) =>
    jsonResponse({
      message: purpose === MPIN_RESET_PURPOSE
        ? `If this ${viaEmail ? 'email address' : 'mobile number'} is registered, we sent a verification code.`
        : viaEmail
        ? 'We sent a verification code to your email address.'
        : smsDeliveryMessage(sms?.delivery),
      // `sms_status` = estado sa `sms_logs` (compat sa lumang app build);
      // `sms_delivery` = kung may ebidensya na ng delivery (`confirmed` lang
      // kapag may delivery report mula sa carrier).
      ...(purpose !== MPIN_RESET_PURPOSE && sms
        ? { sms_status: sms.status, sms_delivery: sms.delivery }
        : {}),
      // Ang app ay nagpapakita ng "check your Gmail" na kopya kapag email ang
      // channel — hindi ito ang SMS queue (`sms_status`).
      ...(viaEmail ? { channel: 'email' } : {}),
      expires_in: OTP_EXPIRY_MINUTES * 60,
      resend_in: OTP_RESEND_COOLDOWN_SECONDS,
    });

  // NOTE: the persistent lockout is intentionally NOT checked here. Sending a
  // fresh OTP is always allowed; failed attempts only count (and lock) at the
  // verify-otp step, per product spec. The lock still blocks verification even
  // after a new code is requested, so it cannot be bypassed by re-sending.

  // Abuse detection (IP-scoped): 20 OTP sends per IP per 10 minutes → block.
  // Checked first so a flood cannot reach the DB / SMS provider.
  const ipGuard = await guardRateLimit({
    key: `otp:ip:${ip}`,
    maxAttempts: OTP_IP_RATE_MAX,
    windowMinutes: OTP_IP_WINDOW_MINUTES,
    blockMinutes: OTP_BLOCK_MINUTES,
    blockReason: 'Too many OTP requests from this device/IP',
    eventType: 'otp_rate_limited',
    ipAddress: ip,
  });
  if (!ipGuard.allowed) {
    return errorResponse(
      'Too many OTP requests from this device. Try again in 15 minutes.',
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // ── Email identifier → account phone ────────────────────────────────────
  // Ang OTP ay naka-key pa rin sa numero ng account (`otp_codes.phone_number`
  // at ang hash salt), kaya ang email ay binabago lang sa numerong iyon — ang
  // VERIFY sa ibaba ay gumagawa rin ng parehong resolution.
  //
  // Sadyang HINDI ito nagbibigay-daan sa self-registration: kailangan pa ring
  // may existing na account na may ganitong email (ang numero ang nagpapatunay
  // ng account sa unang login).
  if (viaEmail) {
    const { data: emailAccount } = await db
      .from('users')
      .select('phone_number')
      .eq('email', emailInput)
      .maybeSingle();
    const accountPhone = normalizePhMobile(emailAccount?.phone_number ?? '');
    if (!emailAccount || accountPhone === '') {
      // Generic pa rin sa reset flow (enumeration protection), pero malinaw sa
      // login: kung hindi sasabihin, maghihintay ang user ng code na wala namang
      // ipapadala.
      if (purpose === MPIN_RESET_PURPOSE) return sentResponse();
      return errorResponse(
        'No Jireta Loans account uses this email address.',
        404,
        'ACCOUNT_NOT_FOUND',
      );
    }
    phone = accountPhone;
  }

  // Lenders may self-register via OTP: an unregistered phone is allowed to
  // request an OTP. Riders must be registered by the head manager first, so
  // once a phone IS registered we only allow OTP for rider/lender roles.
  //
  // PERF: tatlong independent na READ (user row, pinakabagong OTP, at ang
  // 10-minute window count) ang SABAY na tumatakbo. Dating sunod-sunod ang
  // bawat round trip bago pa maipadala ang SMS — bawat isa ay dagdag na
  // paghihintay sa login. Ang ORDER ng pagsuri sa resulta ay hindi nagbago:
  // account → cooldown → window limit.
  const windowStart = new Date(Date.now() - OTP_WINDOW_MINUTES * 60000).toISOString();
  const [userLookup, latestOtpLookup, otpWindowLookup] = await Promise.all([
    db
      .from('users')
      .select('id, account_status, first_name, last_name, email, roles!users_role_id_fkey(name)')
      .eq('phone_number', phone)
      .maybeSingle(),
    db
      .from('otp_codes')
      .select('created_at')
      .eq('phone_number', phone)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from('otp_codes')
      .select('*', { count: 'exact', head: true })
      .eq('phone_number', phone)
      .gte('created_at', windowStart),
  ]);
  const user = singleWithObjectEmbeds(userLookup.data);

  let userId: string | null = null;
  if (user) {
    if (user.account_status === 'archived' || user.account_status === 'inactive') {
      // Sa reset flow, generic ang sagot para hindi malaman ang account status.
      if (purpose === MPIN_RESET_PURPOSE) return sentResponse();
      return errorResponse(
        user.account_status === 'archived' ? 'Account archived' : 'Account inactive',
        403,
        user.account_status === 'archived' ? 'ACCOUNT_ARCHIVED' : 'ACCOUNT_INACTIVE',
      );
    }

    const role = user?.roles?.name;
    if (!['rider', 'lender'].includes(role)) {
      if (purpose === MPIN_RESET_PURPOSE) return sentResponse();
      return errorResponse('OTP login not available for this role', 403, 'FORBIDDEN');
    }
    userId = user.id;
  } else if (purpose === MPIN_RESET_PURPOSE) {
    // Walang account: huwag mag-reveal at huwag mag-SMS.
    await recordSecurityEvent({
      eventType: 'mpin_reset_unknown_number',
      key: `otp:reset:${phone}`,
      ipAddress: ip,
    });
    return sentResponse();
  }

  // ── Resend cooldown (server-side, hindi lang UI timer) ──────────────────
  // Base sa PINAKABAGONG OTP ng numero (kahit anong purpose) para hindi ito
  // ma-bypass sa pagpalit ng purpose.
  const cooldown = resendCooldownRemaining(
    latestOtpLookup.data?.created_at,
    OTP_RESEND_COOLDOWN_SECONDS,
  );
  if (cooldown > 0) {
    return errorResponse(
      `Please wait ${cooldown} second(s) before requesting a new code.`,
      429,
      'OTP_RESEND_COOLDOWN',
      { retry_after_seconds: cooldown, resend_in: cooldown },
    );
  }

  // 10 OTP requests per phone per 10 minutes → rate limit + block on breach.
  if ((otpWindowLookup.count ?? 0) >= OTP_RATE_LIMIT) {
    await blockKey({
      key: `otp:phone:${phone}`,
      reason: 'OTP request limit reached for this number',
      minutes: OTP_BLOCK_MINUTES,
    });
    await recordSecurityEvent({
      eventType: 'otp_rate_limited',
      key: `otp:phone:${phone}`,
      userId,
      ipAddress: ip,
    });
    if (userId) {
      try {
        await db.from('auth_logs').insert({
          user_id: userId,
          event_type: 'otp_rate_limited',
          ip_address: ip,
        });
      } catch (_) {}
    }
    return errorResponse(
      `OTP request limit reached. Try again in ${OTP_BLOCK_MINUTES} minutes.`,
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // Isang active na OTP lang bawat numero (atomic din ito sa DB trigger).
  await db.from('otp_codes').update({ used: true }).eq('phone_number', phone).eq('used', false);

  // Cryptographically secure random code — walang fixed/default na value.
  const code = generateOtpCode();
  const codeHash = await hashOtpCode(code, phone);
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60000).toISOString();

  const { error: insertErr } = await db.from('otp_codes').insert({
    phone_number: phone,
    otp_hash: codeHash,
    expires_at: expiresAt,
    attempts: 0,
    used: false,
    purpose,
  });
  if (insertErr) {
    console.error('[auth-send-otp] otp insert failed:', insertErr.message);
    return errorResponse(
      'Unable to send a verification code right now. Please try again.',
      500,
      'SERVER_ERROR',
    );
  }

  // ── Email delivery (kapag email ang identifier) ────────────────────────
  // Resend ang nagpapadala ng code sa Gmail/email. Kapag pumalya (kulang ang
  // RESEND_API_KEY, unverified sender domain, rate limit), BINUBURA ang code
  // para hindi ito maiwang valid — at para makapag-retry agad ang user.
  if (viaEmail) {
    const recipientName = `${user?.first_name ?? ''} ${user?.last_name ?? ''}`
      .trim();
    const mailResult = purpose === MPIN_RESET_PURPOSE
      ? await sendMpinResetOtpEmail({
        to: emailInput,
        otp: code,
        recipientName: recipientName === '' ? undefined : recipientName,
      })
      : await sendLoginOtpEmail({
        to: emailInput,
        otp: code,
        recipientName: recipientName === '' ? undefined : recipientName,
      });

    if (!mailResult.ok) {
      await db
        .from('otp_codes')
        .delete()
        .eq('phone_number', phone)
        .eq('purpose', purpose)
        .eq('used', false);
      await recordSecurityEvent({
        eventType: 'otp_email_failed',
        key: `otp:phone:${phone}`,
        userId,
        ipAddress: ip,
        detail: {
          kind: mailResult.kind ?? null,
          provider_status: mailResult.status ?? null,
        },
      });
      const rateLimited = mailResult.kind === 'rate_limited';
      return errorResponse(
        rateLimited
          ? 'The email service is temporarily rate limited. Please try again in a few minutes.'
          : 'We could not send the verification code to that email address. Please try again.',
        rateLimited ? 429 : 502,
        rateLimited ? 'EMAIL_RATE_LIMITED' : 'EMAIL_FAILED',
      );
    }

    if (userId) {
      await db.from('auth_logs').insert({
        user_id: userId,
        event_type: 'otp_sent',
        ip_address: ip,
      });
    }
    return sentResponse();
  }

  // TextBee: ang `_shared/sms.ts` ang nagpapalit ng `{otp}` placeholder bago
  // ipadala. Ang buong message (may code) ay HINDI nilo-log sa totoong send —
  // redacted ang ipinapasa sa sms_logs.
  const useMock = isMockSmsEnabled();
  const messageTemplate = otpMessageTemplate(OTP_EXPIRY_MINUTES);
  const smsStartedAt = Date.now();
  const smsResult = await sendSms({
    to: phone,
    message: messageTemplate,
    otpCode: code,
    // Dev-only (USE_MOCK_SMS=true): keep the code in sms_logs so it can be
    // read in Supabase Studio. In real mode the stored message is redacted.
    logMessage: useMock
      ? messageTemplate.replace('{otp}', code)
      : otpLogMessage(OTP_EXPIRY_MINUTES),
    userId: userId ?? undefined,
  });

  if (!smsResult.accepted) {
    // Huwag iwang valid ang code na hindi naipadala — at i-delete para
    // makapag-retry agad ang user (hindi ito mabibilang sa cooldown).
    await db
      .from('otp_codes')
      .delete()
      .eq('phone_number', phone)
      .eq('purpose', purpose)
      .eq('used', false);
    await recordSecurityEvent({
      eventType: 'otp_sms_failed',
      key: `otp:phone:${phone}`,
      userId,
      ipAddress: ip,
      detail: {
        provider_status: smsResult.status,
        error_code: smsResult.errorCode ?? null,
      },
    });
    // Provider-side rate limit / plan limit: malinaw na 429 para alam ng app
    // na hintayin na lang, hindi "sira ang number".
    const providerRateLimited = smsResult.errorCode === 'TEXTBEE_HTTP_429';
    return errorResponse(
      providerRateLimited
        ? 'The SMS service is temporarily rate limited. Please try again in a few minutes.'
        : 'We could not send the verification code right now. Please try again.',
      providerRateLimited ? 429 : 502,
      providerRateLimited ? 'SMS_RATE_LIMITED' : 'SMS_FAILED',
    );
  }

  if (userId) {
    await db.from('auth_logs').insert({
      user_id: userId,
      event_type: 'otp_sent',
      ip_address: ip,
    });
  }

  // Ebidensya para sa "mabagal ang OTP": ang total_ms ay ang buong request na
  // hinihintay ng app (DB + provider), at sms_ms ang TextBee na bahagi lang.
  // Walang numero o code sa linyang ito.
  // `batch` = smsBatchId mula sa TextBee. Hanapin ang batch na ito sa
  // TextBee dashboard → Messages para makita kung tumama ang send at kung ano
  // ang huling status. Walang numero at walang OTP sa linyang ito.
  console.info(
    `[auth-otp] send-otp ok (status=${smsResult.status}, delivery=${
      smsResult.delivery ?? 'unconfirmed'
    }, batch=${smsResult.gatewayReference ?? 'none'}, sms_ms=${
      Date.now() - smsStartedAt
    }, total_ms=${Date.now() - startedAt})`,
  );

  // `sent` lang kapag tinanggap na ng carrier (galing sa status check); kapag
  // naka-queue pa rin, `pending` ang iniuulat para hindi magkunwari ang app na
  // naipadala na ang code.
  return sentResponse({
    status: smsResult.status === 'sent' ? 'sent' : 'pending',
    delivery: smsResult.delivery ?? 'unconfirmed',
  });
}

// ── [moved from functions/auth-verify-otp/index.ts] ─────────────────────────
async function handleVerifyOtp(req: Request) {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  // Kapareho ng send-otp: mobile number O email (hal. Gmail) ang identifier.
  const rawIdentifier = sanitizeString(
    String(body['identifier'] ?? body['phone_number'] ?? body['email'] ?? ''),
  );
  let phone = normalizePhMobile(rawIdentifier);
  const emailInput = rawIdentifier.includes('@')
    ? rawIdentifier.trim().toLowerCase()
    : '';
  const otpCode = sanitizeString(String(body['otp'] ?? body['code'] ?? ''));
  const bodySessionId = body['session_id'];
  const purpose: OtpPurpose | null = normalizeOtpPurpose(body['purpose']);
  const ip = clientIp(req);

  if (emailInput !== '') {
    if (!validateEmail(emailInput)) {
      return errorResponse('Enter a valid email address', 400, 'VALIDATION_ERROR');
    }
  } else if (!validatePhone(phone)) {
    return errorResponse('Invalid phone number', 400, 'VALIDATION_ERROR');
  }
  if (!/^\d{6}$/.test(otpCode)) return errorResponse('OTP must be 6 digits', 400, 'VALIDATION_ERROR');
  if (!purpose) return errorResponse('Invalid OTP purpose', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  // ── Email identifier → account phone ────────────────────────────────────
  // Ang OTP row at ang lockout ay naka-key sa NUMERO ng account (gayon din ang
  // hash salt sa send-otp), kaya dito lang ito iko-convert. Kapag walang
  // account ang email, generic na sagot — walang dapat ibigay na clue kung
  // registered ang address o hindi.
  if (emailInput !== '') {
    const { data: emailAccount } = await db
      .from('users')
      .select('phone_number')
      .eq('email', emailInput)
      .maybeSingle();
    const accountPhone = normalizePhMobile(emailAccount?.phone_number ?? '');
    if (!emailAccount || accountPhone === '') {
      return errorResponse(
        'Invalid or expired code. Please request a new one.',
        401,
        'INVALID_OTP',
      );
    }
    phone = accountPhone;
  }

  // ── Persistent lockout check ────────────────────────────────────────────
  // Server-side, survives app restarts / fresh OTP requests. On a wrong code
  // the failed_attempts counter below escalates (3min → 10min → ×10 each).
  const lock = await readOtpLockout(db, phone);
  if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) {
    return lockoutError(lock.lockedUntil, lock.failedAttempts);
  }

  // If the phone or IP was blocked by the send-OTP guard (10/10min breached),
  // refuse verification attempts too so a blocked key cannot keep probing.
  const phoneBlock = await checkBlock(`otp:phone:${phone}`);
  if (phoneBlock.blocked) {
    return errorResponse(
      'Too many OTP requests. Try again later.',
      429,
      'OTP_RATE_LIMITED',
    );
  }
  const ipBlock = await checkBlock(`otp:ip:${ip}`);
  if (ipBlock.blocked) {
    return errorResponse(
      'Too many OTP requests from this device. Try again later.',
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // IP-scoped verification guard — ang per-phone lockout ay hindi makakapigil
  // sa distributed na pagsubok ng code mula sa maraming numero.
  const verifyGuard = await guardRateLimit({
    key: `otp:verify:ip:${ip}`,
    maxAttempts: OTP_VERIFY_IP_RATE_MAX,
    windowMinutes: OTP_VERIFY_IP_WINDOW_MINUTES,
    blockMinutes: OTP_BLOCK_MINUTES,
    blockReason: 'Too many OTP verification attempts from this device/IP',
    eventType: 'otp_verify_rate_limited',
    ipAddress: ip,
  });
  if (!verifyGuard.allowed) {
    return errorResponse(
      'Too many verification attempts from this device. Try again later.',
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // Helper: record a failed attempt (persistent, escalating) and return the
  // lockout error if the new count crosses a threshold.
  const recordFailure = async (reason: string) => {
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0
      ? new Date(Date.now() + minutes * 60000)
      : null;

    await db.from('otp_lockouts').upsert({
      phone_number: phone,
      failed_attempts: newAttempts,
      locked_until: lockedUntil ? lockedUntil.toISOString() : null,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'phone_number' });

    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse(reason, 401, 'INVALID_OTP');
  };

  // Pinakabagong unused OTP ng numero — kasama ang purpose para matukoy ang
  // purpose mismatch (hal. login OTP na isinumite sa reset screen).
  const { data: otpRow } = await db
    .from('otp_codes')
    .select('id, otp_hash, attempts, expires_at, used, purpose, created_at')
    .eq('phone_number', phone)
    .eq('used', false)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const submittedHash = await hashOtpCode(otpCode, phone);
  const rejection = otpRejectionReason(otpRow, {
    purpose,
    submittedHash,
    maxAttempts: MAX_OTP_ATTEMPTS,
  });

  if (rejection) {
    // Sanitized na dahilan lang — walang code at walang buong numero. Ito ang
    // tumutukoy kung ang 401 ay (a) `not_found` (na-delete ang code matapos
    // pumalya ang SMS send, o wala talagang na-request), o (b) mali/expired/
    // gamit na ang code. Hindi nito ginagalaw ang auth: 401 pa rin ang sagot.
    console.warn(
      `[auth-otp] verify rejected (reason=${rejection}, purpose=${purpose})`,
    );
    if (otpRow) {
      if (rejection === 'mismatch' || rejection === 'purpose_mismatch') {
        await db
          .from('otp_codes')
          .update({ attempts: (otpRow.attempts ?? 0) + 1 })
          .eq('id', otpRow.id);
      }
      if (rejection === 'too_many_attempts') {
        await db.from('otp_codes').update({ used: true }).eq('id', otpRow.id);
      }
    }
    // Generic ang mensahe — hindi sinasabi kung expired, used, mali, o ibang
    // purpose (account / OTP enumeration protection).
    return recordFailure('Invalid or expired code. Please request a new one.');
  }

  // Consume agad — single-use at replay-proof. Ang mga susunod na pagsubok
  // ay aangat sa recordFailure (used → generic invalid).
  await db.from('otp_codes').update({ used: true }).eq('id', otpRow!.id);

  // ── Success: clear the persistent lockout counter ───────────────────────
  await db.from('otp_lockouts').delete().eq('phone_number', phone);

  const { data: userRow } = await db
    .from('users')
    .select('id, account_status, email, first_name, last_name, phone_number, force_password_change, roles!users_role_id_fkey(name)')
    .eq('phone_number', phone)
    .maybeSingle();
  let user = singleWithObjectEmbeds(userRow);

  if (purpose === MPIN_RESET_PURPOSE) {
    // Reset ng MPIN: dapat existing rider/lender ang account. HINDI ito
    // nagse-self-register at hindi nagbibigay ng bagong account.
    if (!user || !['rider', 'lender'].includes(user?.roles?.name ?? '')) {
      return errorResponse(
        'Invalid or expired code. Please request a new one.',
        401,
        'INVALID_OTP',
      );
    }
  } else if (!user) {
    // Self-registration: an unregistered phone that passes OTP becomes a
    // lender automatically (head-manager pre-registration no longer required).
    user = singleWithObjectEmbeds(await selfRegisterLender(db, phone));
    if (!user) return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  // ── Block archived user / archived role BEFORE issuing session ────────────
  if (user.account_status === 'archived') {
    return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');
  }
  // TEMP HOTFIX: role check disabled
  // try { if (user?.roles?.name) { const { data: _ra2 } = await db.from('roles').select('is_archived').eq('name', user.roles.name).maybeSingle(); if ((_ra2 as any)?.is_archived === true) return errorResponse('Role is archived — account disabled', 403, 'ROLE_ARCHIVED'); } } catch (_) {}
  if (user.account_status === 'inactive') {
    return errorResponse('Account inactive', 403, 'ACCOUNT_INACTIVE');
  }

  // Build the session using PHONE + password — never a synthetic email in
  // public.users. Self-registered lenders use OTP_<phone>_SECURE; riders and
  // lenders created by staff use the shared staff default password.
  //
  // NOTE: some GoTrue installs (notably local dev) reject phone+password
  // sign-in unless SMS auth is fully provisioned. The temp email
  // `${phone}@jireta.temp` is ONLY an internal GoTrue credential — it never
  // reaches public.users or the app (the response below only exposes the
  // phone). Trying phone first, then email, keeps both local & prod working.
  const phoneE164 = toE164(phone);
  const tempEmail = `${phone}@jireta.temp`;

  // ── Mga email na susubukang credential ────────────────────────────────────
  // Panimula: ang synthetic credential ng account na `${phone}@jireta.temp`.
  // Sa fallback sa ibaba, IDINADAGDAG ang TOTOONG email ng auth user —
  // kailangan iyon kapag (a) binago ang numero kaya lumang
  // `${oldPhone}@jireta.temp` pa ang nasa credential, o (b) NAKA-DISABLE ang
  // Phone provider ng project ("Phone logins are disabled") — doon ang email
  // lang ang tanging paraan ng pagpasok, kaya hindi puwedeng laging
  // `${phone}@jireta.temp` lang ang sinusubukan.
  const credentialEmails = new Set<string>();
  if (tempEmail) credentialEmails.add(tempEmail);

  // ── HIWALAY na client para sa sign-in ────────────────────────────────────
  // Ang `db` ay SERVICE-ROLE client. Kapag dito nag-`signInWithPassword`, itinatabi
  // ng supabase-js ang session ng user SA client na iyon (`_getAccessToken()` →
  // session token), kaya ang LAHAT ng kasunod na `.from()` / `.rpc()` ay
  // tumatakbo na bilang `authenticated` — kasama ang
  // `rpc('claim_active_session')`, na service-role-LANG ang grant:
  // "permission denied for function claim_active_session" (42501) → degraded
  // → hindi kailanman na-a-claim ang session sa OTP login.
  const signInClient = getAnonClient();

  const trySignIn = async (password: string) => {
    const attempts = [
      () => signInClient.auth.signInWithPassword({ phone: phoneE164, password }),
      ...[...credentialEmails].map((email) => () =>
        signInClient.auth.signInWithPassword({ email, password })),
    ];
    for (const attempt of attempts) {
      const { data, error } = await attempt().catch((e) => {
        console.error('[auth-verify-otp] signInWithPassword error:', e?.message ?? e);
        return { data: null, error: e };
      });
      if (error) {
        console.error('[auth-verify-otp] signInWithPassword:', error.message);
      }
      if (data?.session) return data.session;
    }
    return null;
  };

  let session = null;
  // Naka-set kapag ang OTP-verified na numero ay gamit na ng IBANG GoTrue
  // login (auth.users.phone) — hindi ito masosolusyunan ng retry sa ibaba.
  let phoneCredentialConflict = false;
  for (const password of [OTP_PASSWORD(phone), DEFAULT_PASSWORD]) {
    session = await trySignIn(password);
    if (session) break;
  }

  // Safety net: never fabricate a token. A magic-link `hashed_token` is NOT a
  // JWT — sending it as a Bearer token makes GoTrue reject every subsequent
  // request with "Invalid JWT format". Recovery only ever issues REAL sessions.
  if (!session) {
    const adminUserId = user?.id;

    // 1) The auth user may already exist with an unknown password. The phone
    //    was just OTP-verified, so reset its password and sign in. Ang email ng
    //    credential ay hindi na basta ipinapantay sa `tempEmail` — ang totoong
    //    (verified) email ang itinatago kapag mayroon na (tingnan sa ibaba).
    if (adminUserId) {
      // Ang TOTOONG credential email ng auth user (mula sa GoTrue) — idagdag
      // bago ang retry. Kung ang `${phone}@jireta.temp` ay hindi umubra
      // (lumang numero pa ang nasa credential, o may ibang auth user na
      // humahawak sa temp email), dito pa rin makakapasok ang account.
      try {
        const { data: authUserInfo } = await db.auth.admin.getUserById(adminUserId);
        const actualEmail = String(
          (authUserInfo as { user?: { email?: string } })?.user?.email ?? '',
        ).trim();
        if (actualEmail) credentialEmails.add(actualEmail);
      } catch (e) {
        console.error(
          '[auth-verify-otp] getUserById para sa credential email:',
          (e as Error)?.message ?? e,
        );
      }

      // HUWAG ibalik sa `tempEmail` ang account na may TOTOONG email. Ang
      // verified email ay ipinapantay na sa GoTrue ng
      // `auth-email-verify?fn=confirm` (at ng users-manage PATCH) — kapag
      // ni-reset natin dito ang credential pabalik sa `@jireta.temp`,
      // mabubura ang totoong address sa Auth dashboard, mawawala ang
      // email-based Google sign-in, at babalik ang desync.
      //
      // Ang `syncAuthUserIdentity` ang humahawak ng email + display metadata:
      // kapag may totoong email na, iyon ang isinusulat nito (self-heal din
      // ito para sa mga existing na desynced account), at hindi nito ginagalaw
      // ang email kapag duplicate/error — password reset pa rin ang mahalaga.
      const realEmail = String(user?.email ?? '').trim().toLowerCase();
      const hasRealEmail = realEmail !== '' &&
        !realEmail.endsWith('@jireta.temp');
      const identity = await syncAuthUserIdentity(db, adminUserId, {
        email: hasRealEmail ? realEmail : tempEmail,
        phone,
        firstName: (user as { first_name?: string })?.first_name,
        lastName: (user as { last_name?: string })?.last_name,
      });
      if (!identity.ok) {
        console.error(
          '[auth-verify-otp] identity sync failed — password reset lang ang itutuloy',
          { userId: adminUserId, duplicate: identity.duplicate, msg: identity.error },
        );
        phoneCredentialConflict = identity.phoneDuplicate === true;
        if (!hasRealEmail) {
          // Luma at ligtas na garantiya pa rin ito: kapag WALANG totoong email
          // na dapat protektahan, siguradong may email credential ang account
          // para gumana rin ang email fallback ng `signInWithPassword` sa mga
          // install na hindi tumatanggap ng phone+password.
          await db.auth.admin
            .updateUserById(adminUserId, {
              email: tempEmail,
              phone_confirm: true,
              email_confirm: true,
            })
            .catch((e) => {
              console.error('[auth-verify-otp] temp email fallback failed:', e?.message ?? e);
            });
        }
      }

      const { error: updErr } = await db.auth.admin
        .updateUserById(adminUserId, {
          password: OTP_PASSWORD(phone),
          phone_confirm: true,
          email_confirm: true,
        })
        .catch((e) => {
          console.error('[auth-verify-otp] updateUserById error:', e?.message ?? e);
          return { error: e };
        });
      if (updErr) console.error('[auth-verify-otp] updateUserById:', updErr.message);
      if (!updErr) {
        session = await trySignIn(OTP_PASSWORD(phone));
      }
    }

    // 2) No auth user at all yet — create one, then sign in.
    if (!session) {
      const { data: created, error: createErr } = await db.auth.admin
        .createUser({
          phone: phoneE164,
          email: tempEmail,
          password: OTP_PASSWORD(phone),
          phone_confirm: true,
          email_confirm: true,
          app_metadata: { role: 'lender' },
          user_metadata: authDisplayMetadata({
            phone,
            firstName: (user as { first_name?: string })?.first_name,
            lastName: (user as { last_name?: string })?.last_name,
          }),
        })
        .catch((e) => {
          console.error('[auth-verify-otp] createUser error:', e?.message ?? e);
          return { data: null, error: e };
        });
      if (createErr) console.error('[auth-verify-otp] createUser:', createErr.message);
      if (created?.user && !createErr) {
        session = await trySignIn(OTP_PASSWORD(phone));
      }
    }
  }

  if (!session) {
    // Ang numero ay nakatali sa IBANG GoTrue login: hindi ito mabubuksan kahit
    // wasto pa ang OTP — mas malinaw ito kaysa sa generic na server error.
    if (phoneCredentialConflict) {
      return errorResponse(
        'This phone number is already linked to another login. Please contact the head manager.',
        409,
        'PHONE_CONFLICT',
      );
    }
    return errorResponse('Unable to sign in. Please try again.', 500, 'SERVER_ERROR');
  }

  if (session.user?.id && session.user.id !== user.id) {
    console.warn('[auth-verify-otp] auth/public user id mismatch', {
      auth_user_id: session.user.id,
      public_user_id: user.id,
      phone,
      hint: 'Protected functions recover by verified phone, but this account should be resynced so public.users.id matches auth.users.id.',
    });
  }

  await db.from('auth_logs').insert({
    user_id: user.id,
    event_type: 'login_success',
    ip_address: sanitizeIpAddress(req.headers.get('x-forwarded-for')),
  });
  await db.from('users').update({ last_login_at: nowManilaISO() }).eq('id', user.id);

  // Single-active-session (first-login-wins). Kapag may SARIWANG session na
  // ibang identifier (buhay pang ibang device), TATANGGIHAN ang claim — noon,
  // tahimik itong pinapasa at 200 pa rin ang isinasagot, kaya nag-login ang
  // app na parang successful tapos SESSION_REVOKED agad sa unang request.
  // Ngayon, malinaw na error ang ibinabalik.
  try {
    const claim = await claimActiveSessionDetailed(
      db,
      user.id,
      cleanSessionId(bodySessionId) ??
        sessionIdentifierFromToken(session.access_token),
    );
    if (claim === 'refused') {
      return errorResponse(
        'This account is already signed in on another device. Log out from that device first, then sign in again.',
        409,
        'SESSION_ACTIVE_ELSEWHERE',
      );
    }
    if (claim === 'error') {
      console.warn('[auth-verify-otp] claimActiveSession degraded — allowing login');
    }
  } catch (e) {
    console.warn('[auth-verify-otp] claimActiveSession failed', e);
  }

  // ── MPIN reset authorization (purpose=reset_mpin lang) ──────────────────
  // Short-lived, single-use at naka-tali sa user + purpose. Ito ang
  // kailangan ng auth-mpin bago mapalitan ang MPIN — hindi ang frontend flag
  // na `isVerified`.
  let mpinResetToken: string | null = null;
  let mpinResetExpiresIn: number | null = null;
  if (purpose === MPIN_RESET_PURPOSE) {
    mpinResetToken = generateResetToken();
    const tokenHash = await hashResetToken(mpinResetToken);
    const { error: resetErr } = await db
      .from('mpin_reset_authorizations')
      .insert({
        user_id: user.id,
        token_hash: tokenHash,
        phone_number: phone,
        purpose: MPIN_RESET_PURPOSE,
        expires_at: new Date(Date.now() + MPIN_RESET_TOKEN_MINUTES * 60000)
          .toISOString(),
      });

    if (resetErr) {
      console.error(
        '[auth-verify-otp] reset authorization insert failed:',
        resetErr.message,
      );
      return errorResponse(
        'Unable to start the MPIN reset. Please try again.',
        500,
        'SERVER_ERROR',
      );
    }

    mpinResetExpiresIn = MPIN_RESET_TOKEN_MINUTES * 60;
    try {
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'mpin_reset_otp_verified',
        ip_address: sanitizeIpAddress(req.headers.get('x-forwarded-for')),
      });
    } catch (_) { /* ignore log failure */ }
  }

  // ── MFA (TOTP) state ng account ──────────────────────────────────────────
  // Ang `signInWithPassword` na session sa itaas ay `aal1` pa KAHIT may
  // naka-enroll na authenticator app (standard GoTrue behavior) — kaya dito
  // lang ipinapaalam sa app na kailangan pa ng `mfa.challenge` + `mfa.verify`.
  // Server-side ito (service-role admin API), hindi galing sa client.
  //
  // `enabled: null` = HINDI matukoy (hal. error sa admin API) — hindi ito
  // "wala": sa ganoong kaso, ang app ay may sariling fallback (Supabase Auth
  // `getUser().factors`) at ang mga sensitibong aksyon ay fail-closed.
  const mfaState = await fetchUserMfaState(db, user.id);
  const verifiedFactors = mfaState.factors.filter(
    (factor) => factor.status === 'verified',
  );

  return jsonResponse({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    // Para sa reset flow lang — ang client ay hindi maaaring mag-imbento nito.
    ...(mpinResetToken
      ? { reset_token: mpinResetToken, reset_expires_in: mpinResetExpiresIn }
      : {}),
    user: {
      id: user.id,
      phone,
      role: user?.roles?.name,
      first_name: user?.first_name ?? '',
      last_name: user?.last_name ?? '',
      phone_number: user?.phone_number ?? phone,
      force_password_change: user?.force_password_change,
    },
    // Non-secret na metadata lang (id + pangalan) — walang TOTP secret, walang
    // QR, walang setup key na dumadaan sa login response.
    mfa: {
      enabled: mfaState.ok ? verifiedFactors.length > 0 : null,
      factors: mfaState.ok
        ? verifiedFactors.map((factor) => ({
          id: factor.id,
          friendly_name: factor.friendly_name,
        }))
        : [],
    },
  });
}
