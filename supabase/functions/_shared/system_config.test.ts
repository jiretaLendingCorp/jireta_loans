// supabase/functions/_shared/system_config.test.ts
//
// `getInterestRatePct` ang nagbabasa ng interest rate na itinakda ng Head
// Manager. Dapat laging may ligtas na default (20%) kapag kulang o sira ang
// config row — hindi dapat ito pumasa ng labis sa 0–100 na saklaw.
import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { getInterestRatePct, getLoanLimits } from "./system_config.ts";
import type { DbClient } from "./types.ts";

function fakeDb(value: string | null, error?: unknown): DbClient {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () =>
            error
              ? { data: null, error }
              : {
                data: value === null ? null : { config_value: value },
                error: null,
              },
        }),
      }),
    }),
  } as unknown as DbClient;
}

Deno.test("getInterestRatePct reads the configured percentage", async () => {
  assertEquals(await getInterestRatePct(fakeDb("20")), 20);
  assertEquals(await getInterestRatePct(fakeDb("30")), 30);
  assertEquals(await getInterestRatePct(fakeDb(" 22.5 ")), 22.5);
});

Deno.test("getInterestRatePct falls back to 20 on missing/invalid values", async () => {
  assertEquals(await getInterestRatePct(fakeDb(null)), 20);
  assertEquals(await getInterestRatePct(fakeDb("")), 20);
  assertEquals(await getInterestRatePct(fakeDb("abc")), 20);
  assertEquals(await getInterestRatePct(fakeDb("150")), 20);
  assertEquals(await getInterestRatePct(fakeDb("-1")), 20);
});

Deno.test("getInterestRatePct falls back to 20 on a DB error", async () => {
  assertEquals(await getInterestRatePct(fakeDb(null, { message: "boom" })), 20);
});

// ── getLoanLimits ────────────────────────────────────────────────────────────
function fakeLimitsDb(
  rows: Array<{ config_key: string; config_value: string }> | null,
  error?: unknown,
): DbClient {
  return {
    from: () => ({
      select: () => ({
        in: async () =>
          error ? { data: null, error } : { data: rows, error: null },
      }),
    }),
  } as unknown as DbClient;
}

Deno.test("getLoanLimits reads the configured min/max", async () => {
  assertEquals(
    await getLoanLimits(fakeLimitsDb([
      { config_key: "min_loan_amount", config_value: "3500" },
      { config_key: "max_loan_amount", config_value: "600000" },
    ])),
    { min: 3500, max: 600000 },
  );
});

Deno.test("getLoanLimits falls back to 3000/500000 on missing rows", async () => {
  assertEquals(await getLoanLimits(fakeLimitsDb(null)), { min: 3000, max: 500000 });
  assertEquals(await getLoanLimits(fakeLimitsDb([])), { min: 3000, max: 500000 });
});

Deno.test("getLoanLimits ignores invalid or reversed values", async () => {
  assertEquals(
    await getLoanLimits(fakeLimitsDb([
      { config_key: "min_loan_amount", config_value: "abc" },
      { config_key: "max_loan_amount", config_value: "500000" },
    ])),
    { min: 3000, max: 500000 },
  );
  assertEquals(
    await getLoanLimits(fakeLimitsDb([
      { config_key: "min_loan_amount", config_value: "700000" },
      { config_key: "max_loan_amount", config_value: "500000" },
    ])),
    { min: 3000, max: 500000 },
  );
});

Deno.test("getLoanLimits falls back on a DB error", async () => {
  assertEquals(
    await getLoanLimits(fakeLimitsDb(null, { message: "boom" })),
    { min: 3000, max: 500000 },
  );
});
