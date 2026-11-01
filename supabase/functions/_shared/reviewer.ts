// supabase/functions/_shared/reviewer.ts
// ─────────────────────────────────────────────────────────────────────────────
// Google Play Store REVIEWER access policy (server-side only).
//
// Bakit hiwalay ang file na ito:
//   * Ang reviewer credentials ay nasa Supabase Edge Function SECRETS lamang —
//     walang password, OTP, o bypass flag sa Flutter build.
//   * Ang reviewer login ay TINATANGGIHAN by default. Kailangang tahasang
//     i-set ang `REVIEWER_LOGIN_ENABLED=true` at ang dalawang account bago ito
//     gumana, kaya walang client-side na paraan para i-activate ito.
//   * Ang allowlist ay dalawang layer: (1) ang numero ay dapat tumugma sa
//     configured na reviewer phone, at (2) ang auth user ay dapat may
//     `app_metadata.reviewer === true` (service-role lang ang makakapagsulat
//     nito). Hindi kaya ng reviewer login na buksan ang ibang account.
//
// Walang I/O ang mga helper dito para masubukan nang walang live na Supabase.
// ─────────────────────────────────────────────────────────────────────────────

import type { AuthUser } from './auth.ts';
import { errorResponse } from './cors.ts';
import { normalizePhMobile } from './validators.ts';

export type ReviewerRole = 'lender' | 'rider';

export interface ReviewerAccount {
  role: ReviewerRole;
  /** Normalized na PH mobile number (`09XXXXXXXXX`) — hindi secret. */
  phone: string;
  /** Galing sa Edge Function secret; hindi kailanman lumalabas sa response. */
  password: string;
}

export interface ReviewerConfig {
  /** `true` lang kapag naka-enable at may valid na account. */
  enabled: boolean;
  accounts: ReviewerAccount[];
}

/** Mga pangalan ng Edge Function secrets na binabasa ng reviewer login. */
export const REVIEWER_ENV = {
  enabled: 'REVIEWER_LOGIN_ENABLED',
  lenderPhone: 'REVIEWER_LENDER_PHONE',
  lenderPassword: 'REVIEWER_LENDER_PASSWORD',
  riderPhone: 'REVIEWER_RIDER_PHONE',
  riderPassword: 'REVIEWER_RIDER_PASSWORD',
} as const;

/** Minimum na haba ng reviewer password (tugma sa setup script + docs). */
export const REVIEWER_PASSWORD_MIN_LENGTH = 12;

/** Placeholder para sa dummy comparison kapag walang tumugmang account. */
const DUMMY_SECRET = 'jireta-reviewer-login-no-such-account';

/**
 * Constant-time string comparison — para hindi mabasa sa timing kung gaano
 * karaming character ang tumama. Ang haba ay isinasama sa diff, kaya hindi
 * rin ito nagsasabi kung tama ang haba ng password.
 */
export function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  const length = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

/**
 * Binabasa ang reviewer configuration mula sa secrets.
 *
 * FAIL-CLOSED: kailangan ang `REVIEWER_LOGIN_ENABLED=true` at kumpletong
 * phone+password para sa role. Ang kulang/invalid na entry ay basta hindi
 * isinasama — walang default na numero o password.
 */
export function parseReviewerConfig(
  read: (name: string) => string | undefined,
): ReviewerConfig {
  const enabled =
    (read(REVIEWER_ENV.enabled) ?? '').trim().toLowerCase() === 'true';

  const definitions: Array<{
    role: ReviewerRole;
    phoneKey: string;
    passwordKey: string;
  }> = [
    {
      role: 'lender',
      phoneKey: REVIEWER_ENV.lenderPhone,
      passwordKey: REVIEWER_ENV.lenderPassword,
    },
    {
      role: 'rider',
      phoneKey: REVIEWER_ENV.riderPhone,
      passwordKey: REVIEWER_ENV.riderPassword,
    },
  ];

  const accounts: ReviewerAccount[] = [];
  for (const definition of definitions) {
    const phone = normalizePhMobile(read(definition.phoneKey) ?? '');
    const password = (read(definition.passwordKey) ?? '').trim();
    if (!phone || password.length < REVIEWER_PASSWORD_MIN_LENGTH) continue;
    // Isang account lang bawat numero — hindi pwedeng pagsamahin ang role.
    if (accounts.some((account) => account.phone === phone)) continue;
    accounts.push({ role: definition.role, phone, password });
  }

  return { enabled: enabled && accounts.length > 0, accounts };
}

/** Production convenience wrapper — binabasa ang `Deno.env`. */
export function reviewerConfigFromEnv(): ReviewerConfig {
  return parseReviewerConfig((name) => Deno.env.get(name));
}

/**
 * Hinahanap ang reviewer account sa allowlist. `null` kapag hindi reviewer
 * ang numero (normal user o invalid na input).
 */
export function reviewerAccountFor(
  config: ReviewerConfig,
  phoneInput: string,
): ReviewerAccount | null {
  const phone = normalizePhMobile(phoneInput);
  if (!phone) return null;
  return config.accounts.find((account) => account.phone === phone) ?? null;
}

/**
 * Sinusuri ang password laban sa secret ng account. Kapag walang account,
 * gumagamit pa rin ng dummy comparison para pantay ang gastos sa oras.
 */
export function reviewerPasswordMatches(
  account: ReviewerAccount | null,
  password: string,
): boolean {
  const submitted = (password ?? '').trim();
  if (!account) {
    constantTimeEqual(submitted, DUMMY_SECRET);
    return false;
  }
  return constantTimeEqual(submitted, account.password);
}

/** Reviewer ba ang numerong ito ayon sa configuration? */
export function isReviewerPhone(
  config: ReviewerConfig,
  phoneInput: string,
): boolean {
  return reviewerAccountFor(config, phoneInput) != null;
}

/**
 * Reviewer ba ang session? Ang flag ay galing sa `auth.users.app_metadata`,
 * na service-role lang ang makakapagsulat — hindi ito kayang baguhin ng app
 * o ng request body.
 */
export function isReviewerAuthUser(
  user: Pick<AuthUser, 'isReviewer'> | null | undefined,
): boolean {
  return user?.isReviewer === true;
}

/**
 * Guard para sa mga function na naglilipat ng pera (payments, disbursements,
 * collections). Ang reviewer session ay 403 — walang tunay na transaction o
 * disbursement na magagawa kahit tama ang credentials.
 */
export function requireNonReviewer(
  user: AuthUser,
  message?: string,
): Response | null {
  if (!isReviewerAuthUser(user)) return null;
  return errorResponse(
    message ??
      'Reviewer test accounts cannot perform payments, disbursements, or cash collections. Sign in with a regular account to continue.',
    403,
    'REVIEWER_NOT_ALLOWED',
  );
}

/**
 * Generic na sagot sa bigong reviewer login. Pareho ito sa unknown number at
 * maling password — hindi nito sinasabi kung reviewer account ang numero.
 */
export function reviewerLoginFailedResponse(): Response {
  return errorResponse(
    'Invalid reviewer credentials.',
    401,
    'REVIEWER_LOGIN_FAILED',
  );
}

/** `09XX****XX` — para sa logs, walang buong numero. */
export function maskedReviewerPhone(phone: string): string {
  const clean = normalizePhMobile(phone);
  if (!clean) return 'invalid';
  return `${clean.slice(0, 4)}****${clean.slice(-2)}`;
}
