// supabase/functions/_shared/system_config.ts
// ─────────────────────────────────────────────────────────────────────────────
// Binabasang config values mula sa `system_config`.
//
// Ang INTEREST RATE ay kontrolado na ng Head Manager sa System Settings
// (`system_config.interest_rate`) — kapag nagtakda siya ng 20%, 30%, atbp.,
// iyon ang sinisingil sa mga BAGONG loan application. Ang bawat loan ay
// nagsa-snapshot nito sa `loans.interest_rate`, kaya hindi naaapektuhan ang
// mga naunang loan kapag nagbago ang setting.
//
// Ang PENALTY RATE ay HINDI kasama rito — naka-fix ito sa 20% sa
// `loans-manage` / automatic term-end penalty at hindi dapat baguhin.
// ─────────────────────────────────────────────────────────────────────────────

import type { DbClient } from './types.ts';
import {
  DEFAULT_INTEREST_RATE_PCT,
  MAX_LOAN_AMOUNT,
  MIN_LOAN_AMOUNT,
} from './schedule.ts';

/** Loan amount bounds na itinatakda ng Head Manager sa System Settings. */
export interface LoanLimits {
  min: number;
  max: number;
}

/**
 * Binabasa ang `system_config.interest_rate` (porsyento, hal. "20") at
 * ibinabalik bilang number. Bumalik sa 20 kapag kulang ang row o wala sa
 * 0–100 na saklaw (kapareho ng DB check ng `loans.interest_rate`).
 */
export async function getInterestRatePct(db: DbClient): Promise<number> {
  const { data, error } = await db
    .from('system_config')
    .select('config_value')
    .eq('config_key', 'interest_rate')
    .maybeSingle();

  if (error || !data) return DEFAULT_INTEREST_RATE_PCT;

  const raw = String((data as { config_value: unknown }).config_value ?? '').trim();
  // Blank = walang nakatakda → default, hindi 0% (ang `Number('')` ay 0).
  if (raw === '') return DEFAULT_INTEREST_RATE_PCT;

  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 100) {
    return DEFAULT_INTEREST_RATE_PCT;
  }
  return parsed;
}

function parsePositiveAmount(raw: unknown, fallback: number): number {
  const text = String(raw ?? '').trim();
  if (text === '') return fallback;
  const parsed = Number(text);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

/**
 * Binabasa ang `system_config.min_loan_amount` / `max_loan_amount` — ito ang
 * aktwal na minimum at maximum na tinatanggap ng loan application. Dati,
 * naka-fix ang validation sa ₱3,000–₱500,000 kahit may setting ang Head
 * Manager, kaya hindi umiiral ang pagbabago niya.
 *
 * Ligtas na default (₱3,000–₱500,000) kapag kulang, sira, o baligtad ang
 * values (min > max).
 */
export async function getLoanLimits(db: DbClient): Promise<LoanLimits> {
  const fallback: LoanLimits = { min: MIN_LOAN_AMOUNT, max: MAX_LOAN_AMOUNT };
  const { data, error } = await db
    .from('system_config')
    .select('config_key, config_value')
    .in('config_key', ['min_loan_amount', 'max_loan_amount']);

  if (error || !data) return fallback;

  const byKey: Record<string, unknown> = {};
  for (const row of data as Array<Record<string, unknown>>) {
    const key = String(row.config_key ?? '');
    if (key) byKey[key] = row.config_value;
  }

  const min = parsePositiveAmount(byKey['min_loan_amount'], fallback.min);
  const max = parsePositiveAmount(byKey['max_loan_amount'], fallback.max);
  if (min > max) return fallback;
  return { min, max };
}

export const DEFAULT_LOAN_LIMITS: LoanLimits = {
  min: MIN_LOAN_AMOUNT,
  max: MAX_LOAN_AMOUNT,
};
