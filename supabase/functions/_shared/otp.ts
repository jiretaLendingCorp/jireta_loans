// supabase/functions/_shared/otp.ts
// ─────────────────────────────────────────────────────────────────────────────
// OTP generation + validation policy (pure helpers, walang I/O).
//
// Ginagamit ito ng `auth-otp` at ng unit tests. Ang mga desisyon (expired,
// used, purpose mismatch, attempts) ay nandito para:
//   * iisa lang ang patakaran sa lahat ng tawag, at
//   * masubukan ang bawat branch nang walang live DB.
//
// SEGURIDAD: ang OTP ay random mula sa WebCrypto (`crypto.getRandomValues`),
// at ang naka-store lang ay SHA-256 hex ng `<code>:<phone>` — hindi kailanman
// plain text at hindi kailanman nilo-log.
// ─────────────────────────────────────────────────────────────────────────────

import { normalizePhMobile } from './validators.ts';

export type OtpPurpose = 'login' | 'reset_mpin';

export const OTP_PURPOSES: readonly OtpPurpose[] = ['login', 'reset_mpin'];

export const OTP_CODE_LENGTH = 6;

/** True kung valid na purpose string (para sa route/body validation). */
export function isOtpPurpose(value: unknown): value is OtpPurpose {
  return value === 'login' || value === 'reset_mpin';
}

/**
 * Kini-normalize ang `purpose` mula sa request body.
 *
 * Walang `purpose` → `login` (backwards compatible sa lumang app build).
 * Hindi kilalang value → `null` (400 sa caller), para hindi ito tahimik na
 * maging `login` at makaligtaan ang reset authorization.
 */
export function normalizeOtpPurpose(value: unknown): OtpPurpose | null {
  if (value === undefined || value === null) return 'login';
  if (typeof value !== 'string') return null;
  const raw = value.trim().toLowerCase();
  if (raw === '') return 'login';
  return isOtpPurpose(raw) ? raw : null;
}

/**
 * Hinihiwalay ang identifier ng OTP sa phone O email.
 *
 * Isang field lang ang pinapakita ng app ("Mobile Number or Email"), kaya ang
 * `@` lang ang pagkakakilanlan ng channel. Ang numero ay nino-normalize sa
 * `09XXXXXXXXX` (parehong hugis na hinahanap sa `users.phone_number`); ang email
 * sa `lower(trim(...))` (parehong hugis na iniimbak ng
 * `trg_users_normalize_email`).
 *
 * `phone` / `email` ay `''` kapag hindi iyon ang channel — kaya ang validation
 * sa caller (`validatePhone` / `validateEmail`) ang huling salaan.
 */
export function parseOtpIdentifier(raw: string | null | undefined): {
  phone: string;
  email: string;
} {
  const clean = (raw ?? '').trim();
  if (clean.includes('@')) return { phone: '', email: clean.toLowerCase() };
  return { phone: normalizePhMobile(clean), email: '' };
}

/**
 * 6-digit OTP mula sa cryptographically secure RNG.
 *
 * Gumagamit ng rejection sampling para pantay ang distribution — ang simpleng
 * `random % 1000000` ay may bias para sa maliliit na numero.
 */
export function generateOtpCode(): string {
  const max = 1_000_000;
  const limit = Math.floor(0xFFFFFFFF / max) * max;
  const buffer = new Uint32Array(1);
  let value = 0xFFFFFFFF;
  do {
    crypto.getRandomValues(buffer);
    value = buffer[0];
  } while (value >= limit);
  return String(value % max).padStart(OTP_CODE_LENGTH, '0');
}

/** SHA-256 hex ng `<code>:<phone>` — pareho sa existing na format ng DB. */
export async function hashOtpCode(code: string, phone: string): Promise<string> {
  const data = new TextEncoder().encode(`${code}:${phone}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Prefix ng synthetic na OTP key para sa email-only signup. */
export const EMAIL_OTP_KEY_PREFIX = 'mail:';

/**
 * Stable na synthetic na key para sa OTP na nakabatay sa EMAIL.
 *
 * Ang `otp_codes.phone_number` ay VARCHAR(20) at ang buong OTP machinery
 * (cooldown, lockout, rate limit, hash salt) ay naka-key doon. Kapag email
 * lang ang identifier — bagong email na wala pang account, o email-only na
 * lender — walang tunay na numero. Isang maikling SHA-256 digest ng
 * lowercased na email ang ginagamit: `mail:` + 15 hex chars = 20 chars,
 * kasya sa column at hindi makakabangga sa PH number (puro digit iyon).
 *
 * Deterministic ito, kaya pareho ang key sa send-otp at verify-otp.
 */
export async function emailOtpKey(email: string): Promise<string> {
  const normalized = email.trim().toLowerCase();
  const data = new TextEncoder().encode(`otp-email:${normalized}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `${EMAIL_OTP_KEY_PREFIX}${hex.slice(0, 15)}`;
}

/** True kung ang OTP key ay galing sa [emailOtpKey] (hindi tunay na numero). */
export function isEmailOtpKey(value: string): boolean {
  return value.startsWith(EMAIL_OTP_KEY_PREFIX);
}

export type OtpRow = {
  otp_hash?: string | null;
  attempts?: number | null;
  expires_at?: string | null;
  used?: boolean | null;
  purpose?: string | null;
};

export type OtpRejectReason =
  | 'not_found'
  | 'used'
  | 'expired'
  | 'purpose_mismatch'
  | 'too_many_attempts'
  | 'mismatch';

export type OtpValidationParams = {
  /** Purpose ng kasalukuyang request (login / reset_mpin). */
  purpose: OtpPurpose;
  /** Ang hash ng code na isinumite (naka-hash na, hindi plain). */
  submittedHash: string;
  nowMs?: number;
  maxAttempts?: number;
};

/**
 * Sinusuri ang isang OTP row laban sa isinumiteng code.
 *
 * `null` = valid. Kapag may reason, HINDI ito dapat sabihin nang detalyado sa
 * client — generic na "Invalid or expired code" lang ang isinasagot (para
 * hindi malaman kung may account ang numero o kung expired/used lang).
 */
export function otpRejectionReason(
  row: OtpRow | null | undefined,
  params: OtpValidationParams,
): OtpRejectReason | null {
  if (!row) return 'not_found';
  if (row.used === true) return 'used';

  const nowMs = params.nowMs ?? Date.now();
  const expiresMs = row.expires_at ? new Date(row.expires_at).getTime() : NaN;
  if (!Number.isFinite(expiresMs) || expiresMs <= nowMs) return 'expired';

  if (row.purpose && row.purpose !== params.purpose) return 'purpose_mismatch';

  const maxAttempts = params.maxAttempts ?? 5;
  if ((row.attempts ?? 0) >= maxAttempts) return 'too_many_attempts';

  if (!row.otp_hash || row.otp_hash !== params.submittedHash) return 'mismatch';

  return null;
}

/**
 * Default na body ng OTP SMS.
 *
 * MAIKLI at walang canned na A2P na salita ("OTP", "Do not share this code",
 * "Valid for ... minutes") dahil iyon ang hinaharang ng anti-smishing filter
 * ng PH carrier kapag ang sender ay personal SIM at hindi rehistradong A2P.
 *
 * Ebidensya: mula sa PAREHONG gateway SIM patungo sa PAREHONG numero, ang
 * ordinaryong text mula sa Messaging app ay dumarating, samantalang ang canned
 * na OTP template sa itaas ay hindi — kahit nag-uuwi pa ang carrier ng
 * delivery report (kaya "Delivered" sa TextBee Activity pero walang SMS sa
 * telepono). Brand + code lang ang ipinapadala, tulad ng normal na P2P text.
 *
 * `OTP_SMS_TEMPLATE` ang nagpapalit nito; kailangang may `{otp}`.
 */
export const DEFAULT_OTP_SMS_TEMPLATE = 'Jireta: {otp}. Expires in {minutes} min.';

/**
 * Ang totoong ipapadalang body ng OTP, galing sa `OTP_SMS_TEMPLATE` o sa
 * default. Pinapalitan dito ang `{minutes}`; ang `{otp}` ay pinapalitan ng
 * `sendSms` (para hindi dumaan ang code sa kahit anong log).
 *
 * Ang override na walang `{otp}` ay TINATANGGIHAN (default ang gagamitin) —
 * kung hindi, may OTP na walang code ang ipapadala.
 */
export function otpSmsBodyTemplate(
  minutes: number,
  configured?: string | null,
): string {
  const raw = (configured ?? '').trim();
  const template = raw.includes('{otp}') ? raw : DEFAULT_OTP_SMS_TEMPLATE;
  return template.replace(/\{minutes\}/g, String(minutes));
}

/**
 * Natitirang segundo bago pwede ulit mag-request ng bagong OTP.
 *
 * Ang cooldown ay base sa `created_at` ng PINAKABAGONG OTP ng numero (kahit
 * anong purpose) — para hindi ito ma-bypass sa pagpalit ng purpose. `0` =
 * pwede nang mag-resend.
 */
export function resendCooldownRemaining(
  lastCreatedAt: string | null | undefined,
  cooldownSeconds: number,
  nowMs = Date.now(),
): number {
  if (!lastCreatedAt || cooldownSeconds <= 0) return 0;
  const createdMs = new Date(lastCreatedAt).getTime();
  if (!Number.isFinite(createdMs)) return 0;
  const elapsed = Math.floor((nowMs - createdMs) / 1000);
  return Math.max(0, cooldownSeconds - Math.max(0, elapsed));
}
