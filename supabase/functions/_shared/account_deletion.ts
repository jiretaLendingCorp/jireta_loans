// supabase/functions/_shared/account_deletion.ts
//
// Pure helpers para sa Google Play account deletion. Walang DB/network dito
// para masubukan ang bawat alituntunin nang walang Supabase project.
//
// Ang tunay na deletion ay nasa `account-delete/index.ts` (orchestration) at
// `00195_account_deletion.sql` (transaction + auth scrub).

import { normalizePhMobile, phoneToE164 } from './validators.ts';

/** Mga loan status na wala nang perang nakataya — safe nang i-anonymize. */
export const TERMINAL_LOAN_STATUSES: ReadonlySet<string> = new Set([
  'completed',
  'rejected',
  'cancelled',
]);

/** Mga status na may utang pa — HINDI pwedeng i-delete ang account. */
export const OUTSTANDING_LOAN_STATUSES: ReadonlySet<string> = new Set([
  'active',
  'overdue',
]);

export interface LoanStatusRow {
  id?: string;
  status: string;
}

/**
 * Status ng mga loan na humaharang sa deletion. Tanging `active`/`overdue`
 * ang humaharang; ang pending/under_review/approved ay kinakansela ng RPC.
 */
export function outstandingLoanStatuses(loans: LoanStatusRow[]): string[] {
  const found = new Set<string>();
  for (const loan of loans) {
    const status = String(loan.status ?? '').trim().toLowerCase();
    if (OUTSTANDING_LOAN_STATUSES.has(status)) found.add(status);
  }
  return [...found].sort();
}

/** Status ng mga loan na walang perang lumabas — kinakansela sa deletion. */
export function cancellableLoanStatuses(loans: LoanStatusRow[]): string[] {
  const found = new Set<string>();
  for (const loan of loans) {
    const status = String(loan.status ?? '').trim().toLowerCase();
    if (!status) continue;
    if (TERMINAL_LOAN_STATUSES.has(status)) continue;
    if (OUTSTANDING_LOAN_STATUSES.has(status)) continue;
    found.add(status);
  }
  return [...found].sort();
}

export type DeletionIdentifier =
  | {
    type: 'phone';
    /** Local system format: 09XXXXXXXXX */
    value: string;
    /** GoTrue format: +639XXXXXXXXX */
    e164: string;
  }
  | {
    type: 'email';
    value: string;
  };

/**
 * Normalizes the public form's "registered mobile number or email".
 * Returns null for empty / malformed input so the caller can show one
 * generic validation message (no account-existence oracle).
 */
export function normalizeDeletionIdentifier(
  raw: unknown,
): DeletionIdentifier | null {
  if (typeof raw !== 'string') return null;
  const value = raw.trim();
  if (!value || value.length > 255) return null;

  if (value.includes('@')) {
    const email = value.toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
    return { type: 'email', value: email };
  }

  const local = normalizePhMobile(value);
  if (!local) return null;
  return { type: 'phone', value: local, e164: phoneToE164(local) };
}

/** `09*****1234` / `ju***@example.com` — safe for logs and request lists. */
export function maskIdentifier(
  type: 'phone' | 'email',
  value: string,
): string {
  if (type === 'phone') {
    const digits = value.replace(/\D/g, '');
    if (digits.length < 6) return '****';
    return `${digits.slice(0, 2)}${'*'.repeat(5)}${digits.slice(-4)}`;
  }
  const [local, domain] = value.split('@');
  if (!domain) return '***';
  const head = local.slice(0, 2);
  return `${head}${'*'.repeat(Math.max(1, Math.min(2, local.length - 2)))}@${domain}`;
}

/** 10 uppercase hex chars: `DEL-1A2B3C4D5E`. */
export function buildDeletionReference(bytes?: Uint8Array): string {
  const buf = bytes ?? crypto.getRandomValues(new Uint8Array(5));
  let hex = '';
  for (const byte of buf.slice(0, 5)) {
    hex += byte.toString(16).padStart(2, '0');
  }
  return `DEL-${hex.toUpperCase().padEnd(10, '0')}`;
}

/** Validates a reference the user read back to support. */
export function isDeletionReference(value: unknown): boolean {
  return typeof value === 'string' && /^DEL-[0-9A-F]{10}$/.test(value.trim());
}

/** Trims + strips control chars, caps at 500 chars. */
export function sanitizeDeletionReason(value: unknown): string {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 500);
}

/** `sha256Hex('pepper:value')` — used for duplicate detection in the queue. */
export async function hashDeletionIdentifier(
  pepper: string,
  identifier: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${pepper}:${identifier}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export interface DeletionResultSummary {
  anonymized_email: string;
  cancelled_loans: number;
  removed: string[];
  retained: string[];
}

/**
 * Narrow the RPC's JSONB result into the small shape returned to the client.
 * Unknown/missing fields fall back to safe defaults so a DB upgrade cannot
 * crash the Edge Function.
 */
export function summarizeDeletionResult(result: unknown): DeletionResultSummary {
  const row = (result ?? {}) as Record<string, unknown>;
  const removed = Array.isArray(row.removed)
    ? row.removed.filter((v): v is string => typeof v === 'string')
    : [];
  const retained = Array.isArray(row.retained)
    ? row.retained.filter((v): v is string => typeof v === 'string')
    : [];
  return {
    anonymized_email: typeof row.anonymized_email === 'string'
      ? row.anonymized_email
      : '',
    cancelled_loans: typeof row.cancelled_loans === 'number'
      ? row.cancelled_loans
      : 0,
    removed,
    retained,
  };
}
