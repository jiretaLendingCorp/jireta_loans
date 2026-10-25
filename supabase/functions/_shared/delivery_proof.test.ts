// supabase/functions/_shared/delivery_proof.test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DELIVERY_PROOF_LIMIT_LABEL,
  MAX_DELIVERY_PROOF_BYTES,
  validateDeliveryProofTotal,
} from "./delivery_proof.ts";

const MB = 1024 * 1024;

Deno.test("5MB TOTAL ang limit ng Cash on Delivery proof upload", () => {
  assertEquals(MAX_DELIVERY_PROOF_BYTES, 5 * MB);
  assertEquals(DELIVERY_PROOF_LIMIT_LABEL, "5MB");
});

Deno.test("tumatanggap ng hanggang 5MB total, tinatanggihan ang lumampas", () => {
  // Dalawang 2.5MB na photo = 5MB total — pasado pa rin.
  assertEquals(validateDeliveryProofTotal(2.5 * MB + 2.5 * MB), null);
  assertEquals(validateDeliveryProofTotal(1 * MB), null);
  const tooBig = validateDeliveryProofTotal(5 * MB + 1);
  assertEquals(typeof tooBig, "string");
  assertEquals(tooBig?.includes("5MB"), true);
  assertEquals(tooBig?.includes("total"), true);
});

Deno.test("blangko / negatibong laki ay invalid", () => {
  assertEquals(typeof validateDeliveryProofTotal(0), "string");
  assertEquals(typeof validateDeliveryProofTotal(-5), "string");
  assertEquals(typeof validateDeliveryProofTotal(Number.NaN), "string");
});
