import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { classifyResendFailure, resolveFromAddress } from "./email.ts";

// Real Resend 403 body returned when the sender is still onboarding@resend.dev
// (the shared testing domain). This exact response is what made registration
// look like "code sent" while no email ever arrived.
const TESTING_DOMAIN_BODY = JSON.stringify({
  statusCode: 403,
  name: "validation_error",
  message:
    "Testing domain restriction: The resend.dev domain is for testing and can only send to your own email address. To send to other recipients, verify a domain and update the from address to use it.",
});

Deno.test("403 testing-domain restriction is reported as an unverified sender", () => {
  assertEquals(classifyResendFailure(403, TESTING_DOMAIN_BODY), "sender_not_verified");
});

Deno.test("403 for an unverified domain is reported as an unverified sender", () => {
  const body = JSON.stringify({
    statusCode: 403,
    name: "validation_error",
    message: "The jireta.com domain is not verified. Please add and verify it in Resend.",
  });
  assertEquals(classifyResendFailure(403, body), "sender_not_verified");
});

Deno.test("401 is reported as a bad API key", () => {
  assertEquals(classifyResendFailure(401, "{\"message\":\"API key is invalid\"}"), "invalid_api_key");
});

Deno.test("422 is reported as a rejected recipient", () => {
  assertEquals(classifyResendFailure(422, "{\"message\":\"Invalid `to` field\"}"), "recipient_rejected");
});

Deno.test("429 is reported as rate limited", () => {
  assertEquals(classifyResendFailure(429, "{\"message\":\"Too many requests\"}"), "rate_limited");
});

Deno.test("unexpected statuses fall back to http_error", () => {
  assertEquals(classifyResendFailure(500, "internal"), "http_error");
});

Deno.test("resolveFromAddress uses RESEND_FROM_EMAIL with the display name", () => {
  const previousEmail = Deno.env.get("RESEND_FROM_EMAIL");
  const previousName = Deno.env.get("RESEND_FROM_NAME");
  try {
    Deno.env.set("RESEND_FROM_EMAIL", "noreply@mail.jireta.com");
    Deno.env.set("RESEND_FROM_NAME", "Jireta Loans");
    assertEquals(resolveFromAddress(), "Jireta Loans <noreply@mail.jireta.com>");

    // An address that already carries a display name is passed through untouched.
    Deno.env.set("RESEND_FROM_EMAIL", "Jireta <noreply@mail.jireta.com>");
    assertEquals(resolveFromAddress(), "Jireta <noreply@mail.jireta.com>");
  } finally {
    if (previousEmail === undefined) Deno.env.delete("RESEND_FROM_EMAIL");
    else Deno.env.set("RESEND_FROM_EMAIL", previousEmail);
    if (previousName === undefined) Deno.env.delete("RESEND_FROM_NAME");
    else Deno.env.set("RESEND_FROM_NAME", previousName);
  }
});

Deno.test("resolveFromAddress warns and falls back to the resend.dev testing domain", () => {
  const previousEmail = Deno.env.get("RESEND_FROM_EMAIL");
  const previousLegacy = Deno.env.get("RESEND_FROM");
  try {
    Deno.env.delete("RESEND_FROM_EMAIL");
    Deno.env.delete("RESEND_FROM");
    const from = resolveFromAddress();
    assert(from.includes("onboarding@resend.dev"), from);
  } finally {
    if (previousEmail !== undefined) Deno.env.set("RESEND_FROM_EMAIL", previousEmail);
    if (previousLegacy !== undefined) Deno.env.set("RESEND_FROM", previousLegacy);
  }
});
