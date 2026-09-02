// supabase/functions/_shared/timezone.ts
// Asia/Manila (UTC+8) timezone helpers for Edge Functions.
// All timestamps stored in the database should be in Manila local time.

/** Manila timezone identifier */
export const MANILA_TZ = 'Asia/Manila';

/** Get current Manila date/time as a Date object */
export function nowManila(): Date {
  return new Date(new Date().toLocaleString('en-US', { timeZone: MANILA_TZ }));
}

/** Get current Manila time as ISO string (for DB storage) */
export function nowManilaISO(): string {
  return nowManila().toISOString();
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
