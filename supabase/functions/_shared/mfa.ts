// supabase/functions/_shared/mfa.ts
// ─────────────────────────────────────────────────────────────────────────────
// Server-side na patakaran para sa Google Authenticator (TOTP) 2FA.
//
// BAKIT: ang client (Flutter) ay HINDI pinagkakatiwalaan. Ang mga sensitibong
// aksyon (palitan ang rehistradong numero, MPIN, seguridad) ay kailangang
// tumugma sa assurance level ng SESSION na hawak ng token — hindi sa anumang
// boolean o role na ipinadala ng app.
//
//   * Ang `aal` claim (`aal1` / `aal2`) ay galing sa GoTrue at NAKAPIRMA sa
//     access token. Ang `aal2` ay nangangahulugang natapos ang MFA challenge
//     (`mfa.verify`), kaya ito ang pinagbabatayan — hindi isang client flag.
//   * Ang `enrolled` (may verified TOTP factor ba ang account) ay galing sa
//     GoTrue admin API (service-role, server-side lang).
//
// PATOKARAN (halimbawa ng "hindi lahat ng endpoint ay nangangailangan ng
// aal2"):
//
//   | Operasyon                                   | Kinakailangan      |
//   |---------------------------------------------|--------------------|
//   | Pagbasa ng sariling profile / listahan      | `aal1` (OTP)       |
//   | Loan, bayad, koleksyon, notification        | `aal1` (OTP)       |
//   | Palitan ang rehistradong numero             | `aal2` kung naka-2FA |
//   | MPIN: set / reset                           | `aal2` kung naka-2FA |
//   | 2FA: disable / reset                        | `aal2` (GoTrue)    |
//
// Ang "kung naka-2FA" ay mahalaga: ang account na WALANG authenticator app ay
// hindi dapat harangan sa pag-set ng MPIN o pagpalit ng numero dahil lang sa
// patakarang hindi pa naman niya na-enable.
//
// FAIL-CLOSED sa mga sensitibong aksyon: kapag hindi matukoy ang MFA state ng
// account (hal. down ang GoTrue admin API), hindi pinapayagan ang aksyon —
// mas mainam ang "subukan muli mamaya" kaysa sa tahimik na pagpapasa.
import { errorResponse } from './cors.ts';
import { getAdminClient } from './db.ts';

/**
 * Ang service-role client (kapareho ng ginagamit ng `_shared/auth.ts`) —
 * tanging server-side na environment ang may access dito. Hindi kailanman
 * ipinapasa ang service-role key sa Flutter.
 */
export type MfaAdminClient = ReturnType<typeof getAdminClient>;

export interface MfaFactorSummary {
  id: string;
  friendly_name: string | null;
  factor_type: string;
  status: string;
  created_at?: string | null;
}

export interface MfaState {
  /** `true` kapag matagumpay na natukoy ang state (kahit walang factor). */
  ok: boolean;
  /** May VERIFIED na TOTP factor ba ang account? */
  enrolled: boolean;
  factors: MfaFactorSummary[];
}

/** Ang base64url na JWT payload ng token, o `null` kapag hindi ito ma-decode. */
export function decodeJwtPayload(
  token: string | null | undefined,
): Record<string, unknown> | null {
  if (!token || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
    return JSON.parse(atob(padded)) as Record<string, unknown>;
  } catch (_) {
    return null;
  }
}

/**
 * Ang `aal` claim ng access token: `aal1` (OTP/password lang) o `aal2`
 * (may authenticator code na). `null` kapag wala ang claim.
 *
 * HINDI ito nagve-verify ng signature dito — ginagawa iyon ng
 * `supabase.auth.getUser(token)` sa `requireAuth` bago pa umabot sa helpers na
 * ito. Ang decoding na ito ay para sa policy decision lang.
 */
export function tokenAal(token: string | null | undefined): string | null {
  const payload = decodeJwtPayload(token);
  const aal = payload?.['aal'];
  return typeof aal === 'string' ? aal : null;
}

/** Ang `amr` (authentication methods) claims — [{method, timestamp}]. */
export function tokenAmr(token: string | null | undefined): string[] {
  const payload = decodeJwtPayload(token);
  const amr = payload?.['amr'];
  if (!Array.isArray(amr)) return [];
  return amr
    .map((entry) => {
      if (entry && typeof entry === 'object') {
        const method = (entry as { method?: unknown }).method;
        return typeof method === 'string' ? method : null;
      }
      return null;
    })
    .filter((value): value is string => value !== null);
}

/** May hindi bababa sa isang VERIFIED na TOTP factor? */
export function hasVerifiedTotpFactor(
  factors: Array<{ factor_type?: string; status?: string }> | null | undefined,
): boolean {
  if (!factors || !Array.isArray(factors)) return false;
  return factors.some(
    (factor) =>
      factor?.factor_type === 'totp' && factor?.status === 'verified',
  );
}

/**
 * Sine-sanitize ang factor list mula sa GoTrue: tanging ang NON-SECRET na
 * metadata ang isinasama (wala ang `secret`, `friendly_name` lang, atbp.).
 * Kahit ang admin API ay may `secret` sa ilang bersyon, hindi ito kailanman
 * lalabas sa response ng Edge Function.
 */
export function sanitizeFactors(raw: unknown): MfaFactorSummary[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((entry) => {
      if (!entry || typeof entry !== 'object') return null;
      const factor = entry as Record<string, unknown>;
      const id = typeof factor.id === 'string' ? factor.id : null;
      if (!id) return null;
      return {
        id,
        friendly_name:
          typeof factor.friendly_name === 'string'
            ? factor.friendly_name
            : null,
        factor_type:
          typeof factor.factor_type === 'string' ? factor.factor_type : '',
        status: typeof factor.status === 'string' ? factor.status : '',
        created_at:
          typeof factor.created_at === 'string' ? factor.created_at : null,
      } as MfaFactorSummary;
    })
    .filter((value): value is MfaFactorSummary => value !== null);
}

type ListFactorsResult = {
  data?: { factors?: unknown } | null;
  error?: unknown;
};

type GetUserResult = {
  data?: { user?: { factors?: unknown } } | null;
  error?: unknown;
};

/**
 * Kinukuha (server-side) kung may verified TOTP factor ang account.
 *
 * Dalawang daan ang sinusubukan para tumugma sa iba't ibang bersyon ng
 * supabase-js: `auth.admin.mfa.listFactors` (mas bago) at
 * `auth.admin.getUserById().user.factors` (fallback).
 */
export async function fetchUserMfaState(
  db: MfaAdminClient,
  userId: string,
): Promise<MfaState> {
  if (!userId) return { ok: false, enrolled: false, factors: [] };

  const adminMfa = db?.auth?.admin?.mfa;
  if (adminMfa?.listFactors) {
    try {
      const { data, error } = (await adminMfa.listFactors({
        userId,
      })) as unknown as ListFactorsResult;
      if (!error) {
        const factors = sanitizeFactors(data?.factors);
        return {
          ok: true,
          enrolled: hasVerifiedTotpFactor(factors),
          factors,
        };
      }
      console.error('[mfa] admin.mfa.listFactors error', String(error));
    } catch (e) {
      console.error('[mfa] admin.mfa.listFactors threw', e);
    }
  }

  const getUserById = db?.auth?.admin?.getUserById;
  if (getUserById) {
    try {
      const { data, error } = (await getUserById(
        userId,
      )) as unknown as GetUserResult;
      if (!error) {
        const factors = sanitizeFactors(data?.user?.factors);
        return {
          ok: true,
          enrolled: hasVerifiedTotpFactor(factors),
          factors,
        };
      }
      console.error('[mfa] admin.getUserById error', String(error));
    } catch (e) {
      console.error('[mfa] admin.getUserById threw', e);
    }
  }

  return { ok: false, enrolled: false, factors: [] };
}

/**
 * Pasya ng patakaran: kailangan ba ng `aal2` para sa isang sensitibong aksyon?
 * Purong function ito (walang I/O) para masubukan.
 */
export function mfaRequiredForSensitiveOp(
  aal: string | null | undefined,
  enrolled: boolean,
): boolean {
  if (aal === 'aal2') return false; // natapos na ang challenge
  return enrolled === true; // `aal1` (o wala) + may naka-enroll na factor
}

/**
 * Ang guard na tinatawag ng mga sensitibong handler: `null` kapag OK ang
 * request, o ang 403/503 na [Response] na dapat ibalik.
 *
 * Ginagamit ang `aal` mula sa VERIFIED na token (`requireAuth`) at ang
 * server-side na MFA state ng account — walang anumang input galing sa app ang
 * pinagkakatiwalaan.
 */
export async function requireMfaIfEnrolled(
  db: MfaAdminClient,
  user: { id: string; aal?: string | null },
): Promise<Response | null> {
  const aal = user?.aal ?? null;
  if (aal === 'aal2') return null;

  const state = await fetchUserMfaState(db, user.id);
  if (!state.ok) {
    // Fail-closed: hindi matukoy ang MFA state ng account.
    console.error(
      '[mfa] hindi matukoy ang MFA state — sensitibong aksyon ay tinanggihan',
      { userId: user.id },
    );
    return errorResponse(
      'We could not verify your two-factor authentication status. Please try again.',
      503,
      'MFA_CHECK_FAILED',
    );
  }
  if (!mfaRequiredForSensitiveOp(aal, state.enrolled)) return null;

  return errorResponse(
    'Two-factor authentication is required for this action. Enter the 6-digit code from your authenticator app and try again.',
    403,
    'MFA_REQUIRED',
    { current_level: aal ?? 'aal1', next_level: 'aal2' },
  );
}
