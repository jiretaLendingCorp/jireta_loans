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
import { DEFAULT_INTEREST_RATE_PCT } from './schedule.ts';

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
