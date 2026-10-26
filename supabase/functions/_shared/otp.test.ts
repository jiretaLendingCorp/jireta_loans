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
  DEFAULT_OTP_SMS_TEMPLATE,
  generateOtpCode,
  hashOtpCode,
  isOtpPurpose,
  normalizeOtpPurpose,
  otpRejectionReason,
  otpSmsBodyTemplate,
  parseOtpIdentifier,
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

Deno.test("parseOtpIdentifier splits phone and email identifiers", () => {
  assertEquals(parseOtpIdentifier("09171234567"), {
    phone: "09171234567",
    email: "",
  });
  assertEquals(parseOtpIdentifier("+639171234567"), {
    phone: "09171234567",
    email: "",
  });
  assertEquals(parseOtpIdentifier("9171234567"), {
    phone: "09171234567",
    email: "",
  });
  // Email: trimmed at lowercased — pareho ng DB trigger ng users.email.
  assertEquals(parseOtpIdentifier("  Juan@Gmail.com "), {
    phone: "",
    email: "juan@gmail.com",
  });
  // Walang `@` at hindi mobile number ang hugis → walang channel (caller ang
  // magsasabi ng validation error).
  assertEquals(parseOtpIdentifier("juan"), { phone: "", email: "" });
  assertEquals(parseOtpIdentifier(""), { phone: "", email: "" });
  assertEquals(parseOtpIdentifier(null), { phone: "", email: "" });
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

/**
 * Ang body ng OTP SMS ay dapat ordinaryong P2P text ang hitsura. Ang canned na
 * A2P na salita ("OTP", "Do not share this code", "Valid for ... minutes") ang
 * hinaharang ng carrier anti-smishing filter kapag personal SIM ang sender —
 * "Delivered" sa TextBee pero walang dumarating sa telepono.
 */
Deno.test("the default OTP body carries no canned A2P/smishing wording", () => {
  const body = otpSmsBodyTemplate(5);
  assertEquals(body, DEFAULT_OTP_SMS_TEMPLATE.replace("{minutes}", "5"));
  assert(body.includes("{otp}"), "the code placeholder must survive");
  for (const canned of ["OTP", "Do not share", "Valid for", "Your "] ) {
    assertEquals(
      body.includes(canned),
      false,
      `default OTP body must not contain ${JSON.stringify(canned)}`,
    );
  }
});

Deno.test("OTP_SMS_TEMPLATE overrides the body and keeps {otp}", () => {
  assertEquals(
    otpSmsBodyTemplate(10, "Jireta code {otp} ({minutes} min)"),
    "Jireta code {otp} (10 min)",
  );
  // Maraming placeholder — lahat pinapalitan.
  assertEquals(
    otpSmsBodyTemplate(3, "{minutes}m: {otp} ({minutes}m)"),
    "3m: {otp} (3m)",
  );
});

Deno.test("an override without {otp} falls back to the default body", () => {
  assertEquals(
    otpSmsBodyTemplate(5, "Jireta verification"),
    DEFAULT_OTP_SMS_TEMPLATE.replace("{minutes}", "5"),
  );
  assertEquals(
    otpSmsBodyTemplate(5, "   "),
    DEFAULT_OTP_SMS_TEMPLATE.replace("{minutes}", "5"),
  );
  assertEquals(
    otpSmsBodyTemplate(5, null),
    DEFAULT_OTP_SMS_TEMPLATE.replace("{minutes}", "5"),
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
