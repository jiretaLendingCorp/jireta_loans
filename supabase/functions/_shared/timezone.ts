// supabase/functions/_shared/timezone.ts
// Asia/Manila (UTC+8) timezone helpers for Edge Functions.
// All timestamps stored in the database should be in Manila local time.

/** Manila timezone identifier */
export const MANILA_TZ = 'Asia/Manila';

/** Get current Manila date/time as a Date object */
export function nowManila(): Date {
  return new Date(new Date().toLocaleString('en-US', { timeZone: MANILA_TZ }));
}

/** Get current time as ISO string (for DB storage).
 * NOTE: TIMESTAMPTZ columns store a true UTC instant. The Flutter client
 * converts to Manila (+8) via `parseManila()`, so we must store real UTC
 * here — NOT Manila wall-time masquerading as UTC (which double-shifts
 * Accepted At / Completed At by +8h on display). */
export function nowManilaISO(): string {
  return new Date().toISOString();
}

/** Convert a UTC ISO string to Manila time as Date */
export function toManila(utcISO: string): Date {
  return new Date(new Date(utcISO).toLocaleString('en-US', { timeZone: MANILA_TZ }));
}

/** Convert a UTC ISO string to Manila time as ISO string */
export function toManilaISO(utcISO: string): string {
  return toManila(utcISO).toISOString();
}

/** Get current Manila timestamp for unique IDs (epoch ms in Manila) */
export function manilaTimestamp(): number {
  return nowManila().getTime();
}

/**
 * Normalize a client-sent timestamp to a true UTC ISO string.
 *
 * Ang Flutter date/time picker ay nagpapadala ng ISO string na WALANG
 * timezone marker (hal. "2026-09-16T14:00:00.000" = 2:00 PM Manila wall
 * clock). Kapag ganoon ang isinulat sa TIMESTAMPTZ column, UTC ang gagamitin
 * ng Postgres — kaya 8 oras ang pagka-mali (2:00 PM Manila → 10:00 PM sa
 * lender notification at sa deadline display).
 *
 * Dito, ang walang marker ay itinuturing na Manila (+08:00); ang may `Z` o
 * offset ay pinapanatili ang instant. `null` kapag blangko o hindi mabasa.
 */
export function normalizeManilaInput(value: unknown): string | null {
  if (value == null) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  const hasZone = /(?:z|[+-]\d{2}:?\d{2})$/i.test(raw);
  const hasTime = /\d{1,2}:\d{2}/.test(raw);
  const candidate = hasZone ? raw : `${raw}${hasTime ? '' : 'T00:00:00'}+08:00`;
  const dt = new Date(candidate);
  return Number.isNaN(dt.getTime()) ? null : dt.toISOString();
}

/**
 * Convert a Manila calendar date (y, m, d) to the UTC instant of that
 * Manila midnight. Manila is UTC+8, so 00:00 Manila = 16:00 UTC on the
 * PREVIOUS day. Used for exact-day filters — without the shift, a day filter
 * would start at 08:00 Manila and silently exclude the first 8 hours.
 */
export function manilaMidnightUTC(y: number, m: number, d: number): Date {
  return new Date(Date.UTC(y, m - 1, d, 0, 0, 0) - 8 * 60 * 60 * 1000);
}

/**
 * UTC instants covering a full Manila calendar month [first 00:00, next 00:00).
 * Use these (not Date.UTC month boundaries) for any created_at/paid_at filter.
 */
export function manilaMonthRangeUTC(y: number, m: number): {
  start: Date;
  end: Date;
} {
  return {
    start: manilaMidnightUTC(y, m, 1),
    end: manilaMidnightUTC(y, m + 1, 1),
  };
}
