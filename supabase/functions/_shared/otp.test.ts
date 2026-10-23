// supabase/functions/_shared/otp.test.ts
//
// Unit tests para sa OTP policy. Sinasaklaw nito ang mga desisyon ng server
// (expired / used / purpose / attempts / cooldown) nang walang live DB — ang
// `auth-otp` ay ginagamit lang ang mga function na ito.
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  generateOtpCode,
  hashOtpCode,
  isOtpPurpose,
  normalizeOtpPurpose,
  otpRejectionReason,
  resendCooldownRemaining,
} from "./otp.ts";

const NOW = Date.parse("2026-10-22T00:00:00.000Z");

function row(overrides: Record<string, unknown> = {}) {
  return {
    otp_hash: "a".repeat(64),
    attempts: 0,
    expires_at: new Date(NOW + 60_000).toISOString(),
    used: false,
    purpose: "login",
    ...overrides,
  };
}

Deno.test("normalizeOtpPurpose defaults to login and rejects unknown values", () => {
  assertEquals(normalizeOtpPurpose(undefined), "login");
  assertEquals(normalizeOtpPurpose(""), "login");
  assertEquals(normalizeOtpPurpose("LOGIN"), "login");
  assertEquals(normalizeOtpPurpose("reset_mpin"), "reset_mpin");
  assertEquals(normalizeOtpPurpose("create_account"), null);
  assertEquals(normalizeOtpPurpose(123), null);
  assert(isOtpPurpose("login"));
  assert(isOtpPurpose("reset_mpin"));
  assert(!isOtpPurpose("register"));
});

Deno.test("generateOtpCode produces 6-digit codes from a secure RNG", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 500; i++) {
    const code = generateOtpCode();
    assertEquals(code.length, 6);
    assert(/^\d{6}$/.test(code), `unexpected code: ${code}`);
    seen.add(code);
  }
  // 500 draws from 1,000,000 values should not collapse to one value.
  assert(seen.size > 400, `unexpectedly low entropy: ${seen.size} unique`);
});

Deno.test("hashOtpCode is deterministic, 64 hex chars, and phone-scoped", async () => {
  const a = await hashOtpCode("123456", "09171234567");
  const b = await hashOtpCode("123456", "09171234567");
  const otherPhone = await hashOtpCode("123456", "09171234568");
  const otherCode = await hashOtpCode("654321", "09171234567");

  assertEquals(a, b);
  assert(/^[0-9a-f]{64}$/.test(a));
  assert(!a.includes("123456"), "hash must not embed the OTP");
  assertNotEquals(a, otherPhone);
  assertNotEquals(a, otherCode);
});

Deno.test("valid OTP is accepted for its purpose", () => {
  assertEquals(
    otpRejectionReason(row(), {
      purpose: "login",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
    }),
    null,
  );
});

Deno.test("incorrect OTP is rejected", () => {
  assertEquals(
    otpRejectionReason(row(), {
      purpose: "login",
      submittedHash: "b".repeat(64),
      nowMs: NOW,
    }),
    "mismatch",
  );
});

Deno.test("expired OTP is rejected", () => {
  assertEquals(
    otpRejectionReason(row({ expires_at: new Date(NOW - 1).toISOString() }), {
      purpose: "login",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
    }),
    "expired",
  );
});

Deno.test("OTP purpose mismatch is rejected (login code on reset screen)", () => {
  assertEquals(
    otpRejectionReason(row({ purpose: "login" }), {
      purpose: "reset_mpin",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
    }),
    "purpose_mismatch",
  );
});

Deno.test("already-used OTP cannot be replayed", () => {
  assertEquals(
    otpRejectionReason(row({ used: true }), {
      purpose: "login",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
    }),
    "used",
  );
});

Deno.test("missing OTP row is rejected generically", () => {
  assertEquals(
    otpRejectionReason(null, {
      purpose: "login",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
    }),
    "not_found",
  );
});

Deno.test("attempt ceiling blocks further guesses", () => {
  assertEquals(
    otpRejectionReason(row({ attempts: 5 }), {
      purpose: "login",
      submittedHash: "a".repeat(64),
      nowMs: NOW,
      maxAttempts: 5,
    }),
    "too_many_attempts",
  );
});

Deno.test("resend cooldown counts down and then releases", () => {
  const createdAt = new Date(NOW - 10_000).toISOString();
  assertEquals(resendCooldownRemaining(createdAt, 60, NOW), 50);
  assertEquals(
    resendCooldownRemaining(new Date(NOW - 90_000).toISOString(), 60, NOW),
    0,
  );
  assertEquals(resendCooldownRemaining(null, 60, NOW), 0);
  assertEquals(resendCooldownRemaining(createdAt, 0, NOW), 0);
});
