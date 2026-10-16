// supabase/functions/_shared/system_config.test.ts
//
// `getInterestRatePct` ang nagbabasa ng interest rate na itinakda ng Head
// Manager. Dapat laging may ligtas na default (20%) kapag kulang o sira ang
// config row — hindi dapat ito pumasa ng labis sa 0–100 na saklaw.
import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { getInterestRatePct } from "./system_config.ts";
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
