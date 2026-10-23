// supabase/functions/_shared/mpin_reset.ts
// ─────────────────────────────────────────────────────────────────────────────
// Server-side MPIN reset authorization.
//
// Bakit: dating ang "Reset MPIN" ay client-side — pagkatapos ma-verify ang OTP
// ay tinatawag ng app ang `auth-mpin?fn=reset` (o direkta itong `set`) gamit ang
// naka-login na session. Ibig sabihin, ANUMANG OTP login ang makakabura ng MPIN,
// at ang frontend pa ang nagpapasya kung reset ba ito o hindi.
//
// Ngayon: ang `verify-otp` na may `purpose=reset_mpin` ang tanging
// nagbibigay ng token, at ang token na iyon ang kailangan ng `auth-mpin` bago
// mapalitan ang MPIN. Ito ay:
//   * short-lived (`expires_at`),
//   * single-use (`used_at`),
//   * naka-tali sa user at purpose,
//   * may limitasyon sa maling pagtatangka.
// Ang naka-store sa DB ay SHA-256 hash lang ng token.
// ─────────────────────────────────────────────────────────────────────────────

export const MPIN_RESET_PURPOSE = 'reset_mpin';

export type MpinResetAuthRow = {
  user_id?: string | null;
  purpose?: string | null;
  expires_at?: string | null;
  used_at?: string | null;
  attempts?: number | null;
};

export type MpinResetRejectReason =
  | 'not_found'
  | 'used'
  | 'expired'
  | 'wrong_user'
  | 'wrong_purpose'
  | 'too_many_attempts';

export type MpinResetValidationParams = {
  /** Ang user id ng naka-authenticate na session. */
  userId: string;
  nowMs?: number;
  maxAttempts?: number;
};

/**
 * `null` = valid ang authorization. Kapag may reason, dapat tanggihan ang
 * reset at generic na error lang ang isagot sa client.
 */
export function mpinResetRejectionReason(
  row: MpinResetAuthRow | null | undefined,
  params: MpinResetValidationParams,
): MpinResetRejectReason | null {
  if (!row) return 'not_found';
  if (row.used_at) return 'used';

  const nowMs = params.nowMs ?? Date.now();
  const expiresMs = row.expires_at ? new Date(row.expires_at).getTime() : NaN;
  if (!Number.isFinite(expiresMs) || expiresMs <= nowMs) return 'expired';

  if (row.purpose !== MPIN_RESET_PURPOSE) return 'wrong_purpose';
  if (!row.user_id || row.user_id !== params.userId) return 'wrong_user';

  const maxAttempts = params.maxAttempts ?? 5;
  if ((row.attempts ?? 0) >= maxAttempts) return 'too_many_attempts';

  return null;
}

/** HTTP status + code + generic message para sa isang reject reason. */
export function mpinResetError(
  reason: MpinResetRejectReason,
): { status: number; code: string; message: string } {
  switch (reason) {
    case 'expired':
      return {
        status: 410,
        code: 'MPIN_RESET_EXPIRED',
        message:
          'This reset session has expired. Please verify your mobile number again.',
      };
    case 'too_many_attempts':
      return {
        status: 429,
        code: 'MPIN_RESET_LOCKED',
        message: 'Too many reset attempts. Please verify your mobile number again.',
      };
    case 'not_found':
    case 'used':
    case 'wrong_user':
    case 'wrong_purpose':
    default:
      return {
        status: 401,
        code: 'MPIN_RESET_UNAUTHORIZED',
        message:
          'Your reset authorization is invalid. Please verify your mobile number again.',
      };
  }
}
