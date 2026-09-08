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
