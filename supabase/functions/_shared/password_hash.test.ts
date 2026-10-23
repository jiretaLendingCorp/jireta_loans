// supabase/functions/_shared/password_hash.test.ts
//
// Tests para sa MPIN hashing:
//   * bagong MPIN → PBKDF2 (random salt, mataas na iteration count),
//   * legacy `sha256$...` → sinusuportahan pa rin para sa existing accounts,
//   * maling MPIN / ibang user → tanggi,
//   * ang bagong MPIN pagkatapos ng reset ay tumatanggap, luma ay hindi.
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  hashMpin,
  hashPassword,
  isLegacyMpinHash,
  verifyMpinHash,
} from "./password_hash.ts";

const USER_A = "11111111-1111-4111-8111-111111111111";
const USER_B = "22222222-2222-4222-8222-222222222222";

Deno.test("hashMpin produces a salted PBKDF2 hash, never plaintext", async () => {
  const stored = await hashMpin(USER_A, "1234");
  assert(/^pbkdf2\$\d+\$[0-9a-f]{32}\$[0-9a-f]{64}$/.test(stored));
  assert(!stored.includes("1234"), "hash must not contain the MPIN");
  assert(parseInt(stored.split("$")[1], 10) >= 100_000);
});

Deno.test("hashMpin salts every row (same MPIN, different hash)", async () => {
  const a = await hashMpin(USER_A, "1234");
  const b = await hashMpin(USER_A, "1234");
  assertNotEquals(a, b);

  const otherUser = await hashMpin(USER_B, "1234");
  assertNotEquals(a, otherUser);
});

Deno.test("verifyMpinHash accepts the correct MPIN only", async () => {
  const stored = await hashMpin(USER_A, "1234");
  assertEquals(await verifyMpinHash(USER_A, "1234", stored), true);
  assertEquals(await verifyMpinHash(USER_A, "1235", stored), false);
  assertEquals(await verifyMpinHash(USER_B, "1234", stored), false);
  assertEquals(await verifyMpinHash(USER_A, "1234", null), false);
  assertEquals(await verifyMpinHash(USER_A, "1234", "garbage"), false);
});

Deno.test("legacy sha256 MPIN hashes still verify (no forced reset)", async () => {
  const legacy = await hashPassword(USER_A, "4321");
  assert(isLegacyMpinHash(legacy));
  assertEquals(await verifyMpinHash(USER_A, "4321", legacy), true);
  assertEquals(await verifyMpinHash(USER_A, "0000", legacy), false);
});

Deno.test("successful MPIN reset: new MPIN works, old MPIN stops working", async () => {
  const oldHash = await hashMpin(USER_A, "1234");
  // Reset = palitan ang hash gamit ang bagong MPIN (pagkatapos ng OTP reset).
  const newHash = await hashMpin(USER_A, "9876");

  assertEquals(await verifyMpinHash(USER_A, "1234", oldHash), true);
  assertEquals(await verifyMpinHash(USER_A, "9876", newHash), true);
  // Ang login gamit ang BAGONG MPIN ay gumagana; ang luma ay hindi na.
  assertEquals(await verifyMpinHash(USER_A, "1234", newHash), false);
});
