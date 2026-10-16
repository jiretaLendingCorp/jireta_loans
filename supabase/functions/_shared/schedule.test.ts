// supabase/functions/_shared/schedule.test.ts
//
// Ang interest rate ay itinatakda ng Head Manager (`system_config.interest_rate`)
// kaya hindi na ito laging 20%. Sinisiguro ng mga test na ito na:
//   * default pa rin ang 20% kapag walang override,
//   * sinusunod ang itinakdang rate (hal. 30%),
//   * bumabalik sa 20% kapag wala sa 0–100 ang value,
//   * laging umaabot sa eksaktong total payable ang kabuuan ng installments.
import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  computeSchedule,
  DEFAULT_INTEREST_RATE_PCT,
} from "./schedule.ts";

const START = new Date("2026-01-01T00:00:00Z");

Deno.test("DEFAULT_INTEREST_RATE_PCT is 20", () => {
  assertEquals(DEFAULT_INTEREST_RATE_PCT, 20);
});

Deno.test("computeSchedule defaults to 20% when no rate is given", () => {
  const s = computeSchedule(10_000, "monthly", START, 2);
  assertEquals(s.interest, 2_000);
  assertEquals(s.totalPayable, 12_000);
});

Deno.test("computeSchedule honours the Head-Manager-set rate", () => {
  const s = computeSchedule(10_000, "monthly", START, 2, 30);
  assertEquals(s.interest, 3_000);
  assertEquals(s.totalPayable, 13_000);
});

Deno.test("computeSchedule accepts a fractional rate", () => {
  const s = computeSchedule(10_000, "monthly", START, 2, 22.5);
  assertEquals(s.interest, 2_250);
  assertEquals(s.totalPayable, 12_250);
});

Deno.test("computeSchedule falls back to 20% for out-of-range rates", () => {
  for (const bad of [-5, 150, Number.NaN, Number.POSITIVE_INFINITY]) {
    const s = computeSchedule(10_000, "monthly", START, 2, bad);
    assertEquals(s.interest, 2_000, `rate ${bad} should fall back`);
  }
});

Deno.test("installments always sum back to the total payable", () => {
  const s = computeSchedule(3_000, "weekly", START, 3, 25);
  const sum = s.amounts.reduce((a, b) => a + b, 0);
  assertEquals(Math.round(sum * 100) / 100, s.totalPayable);
});
