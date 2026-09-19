// supabase/functions/_shared/reset_token.test.ts
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  generateResetToken,
  hashResetToken,
  isResetToken,
} from "./reset_token.ts";

Deno.test("generateResetToken returns 64 lowercase hex chars", () => {
  const token = generateResetToken();
  assertEquals(token.length, 64);
  assert(/^[0-9a-f]{64}$/.test(token), `unexpected token shape: ${token}`);
});

Deno.test("generateResetToken never repeats (256-bit entropy)", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 200; i++) seen.add(generateResetToken());
  assertEquals(seen.size, 200);
});

Deno.test("hashResetToken is deterministic and 64 hex chars", async () => {
  const token = generateResetToken();
  const a = await hashResetToken(token);
  const b = await hashResetToken(token);
  assertEquals(a, b);
  assert(/^[0-9a-f]{64}$/.test(a));
});

Deno.test("hashResetToken differs per token and hides the input", async () => {
  const one = generateResetToken();
  const two = generateResetToken();
  const h1 = await hashResetToken(one);
  const h2 = await hashResetToken(two);
  assertNotEquals(h1, h2);
  assert(!h1.includes(one), "hash must not embed the raw token");
});

Deno.test("isResetToken accepts only 64-char hex tokens", () => {
  assert(isResetToken(generateResetToken()));
  assert(!isResetToken(""));
  assert(!isResetToken("kyl@gmail.com"));
  assert(!isResetToken("A".repeat(64)), "uppercase hex is not a valid token");
  assert(!isResetToken("a".repeat(63)));
  assert(!isResetToken("a".repeat(65)));
  assert(!isResetToken(undefined));
  assert(!isResetToken(12345));
});
