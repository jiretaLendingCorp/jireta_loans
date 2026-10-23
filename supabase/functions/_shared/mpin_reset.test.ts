// supabase/functions/_shared/mpin_reset.test.ts
//
// Unit tests para sa server-side MPIN reset authorization — ang token na
// ibinibigay lang pagkatapos ng OTP na may purpose=reset_mpin.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MPIN_RESET_PURPOSE,
  mpinResetError,
  mpinResetRejectionReason,
} from "./mpin_reset.ts";

const NOW = Date.parse("2026-10-22T00:00:00.000Z");
const USER = "11111111-1111-4111-8111-111111111111";

function row(overrides: Record<string, unknown> = {}) {
  return {
    user_id: USER,
    purpose: MPIN_RESET_PURPOSE,
    expires_at: new Date(NOW + 5 * 60_000).toISOString(),
    used_at: null,
    attempts: 0,
    ...overrides,
  };
}

Deno.test("valid reset authorization is accepted", () => {
  assertEquals(
    mpinResetRejectionReason(row(), { userId: USER, nowMs: NOW }),
    null,
  );
});

Deno.test("expired reset authorization is rejected", () => {
  assertEquals(
    mpinResetRejectionReason(
      row({ expires_at: new Date(NOW - 1).toISOString() }),
      { userId: USER, nowMs: NOW },
    ),
    "expired",
  );
});

Deno.test("already-used reset authorization cannot be replayed", () => {
  assertEquals(
    mpinResetRejectionReason(row({ used_at: new Date(NOW).toISOString() }), {
      userId: USER,
      nowMs: NOW,
    }),
    "used",
  );
});

Deno.test("reset authorization is bound to the authenticated user", () => {
  assertEquals(
    mpinResetRejectionReason(row(), {
      userId: "22222222-2222-4222-8222-222222222222",
      nowMs: NOW,
    }),
    "wrong_user",
  );
});

Deno.test("reset authorization is bound to the reset_mpin purpose", () => {
  assertEquals(
    mpinResetRejectionReason(row({ purpose: "login" }), {
      userId: USER,
      nowMs: NOW,
    }),
    "wrong_purpose",
  );
});

Deno.test("unknown or missing authorization is rejected", () => {
  assertEquals(
    mpinResetRejectionReason(null, { userId: USER, nowMs: NOW }),
    "not_found",
  );
});

Deno.test("attempt ceiling blocks repeated reset attempts", () => {
  assertEquals(
    mpinResetRejectionReason(row({ attempts: 5 }), {
      userId: USER,
      nowMs: NOW,
      maxAttempts: 5,
    }),
    "too_many_attempts",
  );
});

Deno.test("error mapping is generic and does not leak account details", () => {
  for (const reason of ["not_found", "used", "wrong_user", "wrong_purpose"] as const) {
    const err = mpinResetError(reason);
    assertEquals(err.status, 401);
    assertEquals(err.code, "MPIN_RESET_UNAUTHORIZED");
    assert(!/phone|account|exist/i.test(err.message));
  }
  assertEquals(mpinResetError("expired").code, "MPIN_RESET_EXPIRED");
  assertEquals(mpinResetError("expired").status, 410);
  assertEquals(mpinResetError("too_many_attempts").status, 429);
});
