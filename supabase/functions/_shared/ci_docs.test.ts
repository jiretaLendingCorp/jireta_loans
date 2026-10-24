// supabase/functions/_shared/ci_docs.test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  CI_EVIDENCE_LIMIT_LABEL,
  MAX_CI_EVIDENCE_BYTES,
  validateCiEvidenceSize,
} from "./ci_docs.ts";

const MB = 1024 * 1024;

Deno.test("5MB ang limit kada CI evidence photo", () => {
  assertEquals(MAX_CI_EVIDENCE_BYTES, 5 * MB);
  assertEquals(CI_EVIDENCE_LIMIT_LABEL, "5MB");
});

Deno.test("tumatanggap ng hanggang 5MB, tinatanggihan ang lumampas", () => {
  assertEquals(validateCiEvidenceSize("site.jpg", 5 * MB), null);
  assertEquals(validateCiEvidenceSize("site.jpg", 2 * MB), null);
  const tooBig = validateCiEvidenceSize("site.jpg", 5 * MB + 1);
  assertEquals(typeof tooBig, "string");
  assertEquals(tooBig?.includes("5MB"), true);
  assertEquals(tooBig?.includes("site.jpg"), true);
});

Deno.test("blangko / negatibong laki ay invalid", () => {
  assertEquals(typeof validateCiEvidenceSize("photo.jpg", 0), "string");
  assertEquals(typeof validateCiEvidenceSize("photo.jpg", -5), "string");
  assertEquals(typeof validateCiEvidenceSize("photo.jpg", Number.NaN), "string");
});

Deno.test("walang file name — generic na label pa rin", () => {
  const tooBig = validateCiEvidenceSize(null, 6 * MB);
  assertEquals(typeof tooBig, "string");
  assertEquals(tooBig?.includes("Evidence photo"), true);
});
