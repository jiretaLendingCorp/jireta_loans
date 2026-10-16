// supabase/functions/_shared/xendit.test.ts
//
// Coverage para sa Xendit sandbox diagnostics helpers.
//
// Mahahalagang panuntunan na sinusuri dito:
//   1. Ang connectivity probe ay READ-ONLY at hindi nag-uulat ng "connected"
//      maliban kung ang aktwal na sagot ng Xendit ang nagpapatunay nito.
//   2. Hindi kailanman lumalabas ang secret key (buo man o sa error message) —
//      prefix + huling 4 na character lang ang ipinapakita.
//   3. TEST-key lang ang tinatanggap ng sandbox payment paths, at ang
//      `reference_id`/`metadata` ay may kitang-kitang test marker.
//   4. Hindi nag-hahang ang Xendit call (timeout) at hindi naghahagis ng raw
//      error — structured na resulta ang ibinabalik.
import {
  assertEquals,
  assertFalse,
  assert,
  assertMatch,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildPaymentRequestBody,
  classifyXenditProbe,
  isTerminalPaymentRequestStatus,
  isTestSecretKey,
  isValidPaymentRequestId,
  maskSecretKey,
  normalizeIdempotencyKey,
  probeXenditConnectivity,
  sanitizePaymentRequest,
  timingSafeEqual,
  xenditEnvironmentOf,
  xenditErrorCode,
  xenditErrorMessage,
  xenditRequest,
  XENDIT_API_VERSION,
  XENDIT_PROBE_PAYMENT_REQUEST_ID,
  XENDIT_TEST_KEY_PREFIX,
  XENDIT_LIVE_KEY_PREFIX,
} from "./xendit.ts";

const TEST_KEY = `${XENDIT_TEST_KEY_PREFIX}8f3a1c7b9d2e4f60`;
const LIVE_KEY = `${XENDIT_LIVE_KEY_PREFIX}8f3a1c7b9d2e4f60`;

// ── environment detection ─────────────────────────────────────────────────

Deno.test("xenditEnvironmentOf recognises test and live keys", () => {
  assertEquals(xenditEnvironmentOf(TEST_KEY), "test");
  assertEquals(xenditEnvironmentOf(LIVE_KEY), "live");
  assertEquals(xenditEnvironmentOf("sk-whatever"), "unknown");
  assertEquals(xenditEnvironmentOf(""), "unknown");
  assertEquals(xenditEnvironmentOf(null), "unknown");
  assertEquals(xenditEnvironmentOf(undefined), "unknown");
});

Deno.test("isTestSecretKey only accepts xnd_development_ keys", () => {
  assert(isTestSecretKey(TEST_KEY));
  assertFalse(isTestSecretKey(LIVE_KEY));
  assertFalse(isTestSecretKey(null));
  // Production keys must NEVER be treated as sandbox keys.
  assertFalse(isTestSecretKey(`${XENDIT_LIVE_KEY_PREFIX}abc`));
});

// ── redaction ─────────────────────────────────────────────────────────────

Deno.test("maskSecretKey never returns the full key", () => {
  const masked = maskSecretKey(TEST_KEY)!;
  assertFalse(masked.includes(TEST_KEY));
  assertFalse(masked.includes(TEST_KEY.slice(4, 20)));
  assertEquals(masked, `${XENDIT_TEST_KEY_PREFIX}***4f60`);
  // Ang gitnang bahagi ng key ay ganap na nakatago (huling 4 na char lang).
  assertFalse(masked.includes(TEST_KEY.slice(0, -4)));
  assertMatch(masked, /^xnd_development_\*\*\*[0-9a-z]{4}$/);
  // Hindi kilalang format: kung maikli/malabo → buong redaction.
  assertEquals(maskSecretKey("short"), "***");
  assertEquals(maskSecretKey(""), null);
  assertEquals(maskSecretKey(null), null);
});

Deno.test("maskSecretKey keeps the live prefix visible for live keys", () => {
  assertEquals(maskSecretKey(LIVE_KEY), `${XENDIT_LIVE_KEY_PREFIX}***4f60`);
});

// ── probe classification ──────────────────────────────────────────────────

Deno.test("probe classification: missing secret is never a success", () => {
  const result = classifyXenditProbe({
    keyPresent: false,
    httpStatus: 0,
    failure: "not_configured",
  });
  assertEquals(result.status, "unverified");
  assertFalse(result.authenticated);
  assert(result.message.includes("XENDIT_SECRET_KEY"));
});

Deno.test("probe classification: 401 means the key failed authentication", () => {
  const result = classifyXenditProbe({
    keyPresent: true,
    httpStatus: 401,
    failure: null,
    errorCode: "UNAUTHORIZED",
  });
  assertEquals(result.status, "auth_failed");
  assertFalse(result.authenticated);
  assert(result.message.includes("401"));
});

Deno.test("probe classification: 403 means authenticated but insufficient permission", () => {
  const result = classifyXenditProbe({
    keyPresent: true,
    httpStatus: 403,
    failure: null,
    errorCode: "FORBIDDEN",
  });
  assertEquals(result.status, "permission_denied");
  assert(result.authenticated);
});

Deno.test("probe classification: 404 on the unknown probe id = connected", () => {
  const result = classifyXenditProbe({
    keyPresent: true,
    httpStatus: 404,
    failure: null,
    errorCode: "DATA_NOT_FOUND",
  });
  assertEquals(result.status, "connected");
  assert(result.authenticated);
});

Deno.test("probe classification: 2xx = connected", () => {
  for (const status of [200, 201]) {
    const result = classifyXenditProbe({
      keyPresent: true,
      httpStatus: status,
      failure: null,
    });
    assertEquals(result.status, "connected");
    assert(result.authenticated);
  }
});

Deno.test("probe classification: network/timeout/server errors are unverified", () => {
  for (
    const input of [
      { keyPresent: true, httpStatus: 0, failure: "timeout" as const },
      { keyPresent: true, httpStatus: 0, failure: "unreachable" as const },
      { keyPresent: true, httpStatus: 500, failure: null },
      { keyPresent: true, httpStatus: 503, failure: null },
      { keyPresent: true, httpStatus: 400, failure: null, errorCode: "FEATURE_NOT_AVAILABLE" },
    ]
  ) {
    const result = classifyXenditProbe(input);
    assertEquals(result.status, "unverified", JSON.stringify(input));
    assertFalse(result.authenticated, JSON.stringify(input));
  }
});

Deno.test("the probe id satisfies Xendit's documented 39-char path param", () => {
  assertEquals(XENDIT_PROBE_PAYMENT_REQUEST_ID.length, 39);
  assertMatch(XENDIT_PROBE_PAYMENT_REQUEST_ID, /^pr-0{8}-0{4}-0{4}-0{4}-0{12}$/);
});

Deno.test("probe never leaves the process when no key is configured", async () => {
  // Walang XENDIT_SECRET_KEY sa test env → hindi dapat tumawag sa network.
  const previous = Deno.env.get("XENDIT_SECRET_KEY");
  Deno.env.delete("XENDIT_SECRET_KEY");
  try {
    const probe = await probeXenditConnectivity();
    assertEquals(probe.status, "unverified");
    assertFalse(probe.keyPresent);
    assertEquals(probe.keyPreview, null);
    assertEquals(probe.environment, "unknown");
    assertEquals(probe.apiVersion, XENDIT_API_VERSION);
    assertEquals(probe.httpStatus, null);
  } finally {
    if (previous != null) Deno.env.set("XENDIT_SECRET_KEY", previous);
  }
});

// ── request wrapper ───────────────────────────────────────────────────────

Deno.test("xenditRequest short-circuits when the secret is missing", async () => {
  const result = await xenditRequest("/v3/payment_requests", {
    method: "POST",
    body: { reference_id: "x" },
    secretKey: null,
  });
  assertEquals(result.failure, "not_configured");
  assertEquals(result.httpStatus, 0);
  assertEquals(result.data, null);
  assertEquals(result.latencyMs, 0);
});

// ── payment request body ──────────────────────────────────────────────────

Deno.test("buildPaymentRequestBody sends PHP + the documented v3 fields", () => {
  const body = buildPaymentRequestBody({
    referenceId: "JR-TEST-abc",
    amount: 100,
    channelCode: "GCASH",
    description: "Jireta sandbox test payment",
  });
  assertEquals(body.currency, "PHP");
  assertEquals(body.country, "PH");
  assertEquals(body.type, "PAY");
  assertEquals(body.request_amount, 100);
  assertEquals(body.channel_code, "GCASH");
  assertEquals(body.capture_method, "AUTOMATIC");
  assertEquals(body.reference_id, "JR-TEST-abc");
  // Test marker sa metadata — makikita sa Xendit dashboard.
  assertEquals(body.metadata.env, "sandbox");
  assertEquals(body.metadata.source, "jireta-test");
  // Walang secret o card field sa body.
  assertFalse("channel_properties" in body);
});

Deno.test("buildPaymentRequestBody only adds return urls when provided", () => {
  const withUrls = buildPaymentRequestBody({
    referenceId: "JR-TEST-abc",
    amount: 1,
    channelCode: "GCASH",
    description: "d",
    successReturnUrl: "https://jireta.example/ok",
    failureReturnUrl: "https://jireta.example/fail",
  });
  assertEquals(
    (withUrls.channel_properties as Record<string, string>).success_return_url,
    "https://jireta.example/ok",
  );
});

// ── sanitization ──────────────────────────────────────────────────────────

Deno.test("sanitizePaymentRequest drops internal + sensitive fields", () => {
  const sanitized = sanitizePaymentRequest({
    business_id: "5f27a14a9bf05c73dd040bc8",
    payment_request_id: "pr-8877c08a-740d-4153-9816-3d744ed197a5",
    reference_id: "JR-TEST-abc",
    status: "REQUIRES_ACTION",
    currency: "PHP",
    request_amount: 100,
    channel_code: "GCASH",
    channel_properties: { card_details: { masked_card_number: "4111****1111" } },
    actions: [
      { type: "REDIRECT_CUSTOMER", descriptor: "WEB_URL", value: "https://checkout.xendit.co/x" },
      { descriptor: "NO_TYPE" },
      "not-an-object",
    ],
    created: "2026-10-17T00:00:00Z",
  })!;
  assertEquals(sanitized.payment_request_id, "pr-8877c08a-740d-4153-9816-3d744ed197a5");
  assertEquals(sanitized.request_amount, 100);
  assertEquals(sanitized.actions.length, 1);
  assertEquals(sanitized.actions[0].value, "https://checkout.xendit.co/x");
  assertFalse("business_id" in sanitized);
  assertFalse("channel_properties" in sanitized);
  assertEquals(sanitizePaymentRequest(null), null);
});

Deno.test("sanitizePaymentRequest tolerates a partial/blank body", () => {
  const sanitized = sanitizePaymentRequest({ payment_request_id: "pr-x" })!;
  assertEquals(sanitized.payment_request_id, "pr-x");
  assertEquals(sanitized.status, null);
  assertEquals(sanitized.request_amount, null);
  assertEquals(sanitized.actions, []);
});

// ── status lifecycle ──────────────────────────────────────────────────────

Deno.test("isTerminalPaymentRequestStatus only matches finished states", () => {
  for (const status of ["SUCCEEDED", "FAILED", "EXPIRED", "CANCELED"]) {
    assert(isTerminalPaymentRequestStatus(status), status);
  }
  for (const status of ["REQUIRES_ACTION", "PENDING", "ACTIVE", null, ""]) {
    assertFalse(isTerminalPaymentRequestStatus(status), String(status));
  }
});

// ── input validation ──────────────────────────────────────────────────────

Deno.test("normalizeIdempotencyKey accepts uuid-like keys and rejects junk", () => {
  const uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
  assertEquals(normalizeIdempotencyKey(uuid), uuid);
  assertEquals(normalizeIdempotencyKey(`  ${uuid}  `), uuid);
  assertEquals(normalizeIdempotencyKey("short"), null);
  assertEquals(normalizeIdempotencyKey("has space-in-key"), null);
  assertEquals(normalizeIdempotencyKey("has/slash"), null);
  assertEquals(normalizeIdempotencyKey("a".repeat(101)), null);
  assertEquals(normalizeIdempotencyKey(null), null);
});

Deno.test("isValidPaymentRequestId matches only pr-<uuid> (39 chars)", () => {
  assert(isValidPaymentRequestId(XENDIT_PROBE_PAYMENT_REQUEST_ID));
  assert(isValidPaymentRequestId("pr-8877c08a-740d-4153-9816-3d744ed197a5"));
  assertFalse(isValidPaymentRequestId("8877c08a-740d-4153-9816-3d744ed197a5"));
  assertFalse(isValidPaymentRequestId("pr-123"));
  assertFalse(isValidPaymentRequestId("pr-../../etc/passwd"));
  assertFalse(isValidPaymentRequestId(null));
  assertFalse(isValidPaymentRequestId(123));
});

// ── error handling / no leakage ───────────────────────────────────────────

Deno.test("xenditErrorCode reads error_code and nested error.code", () => {
  assertEquals(xenditErrorCode({ error_code: "API_VALIDATION_ERROR" }), "API_VALIDATION_ERROR");
  assertEquals(xenditErrorCode({ error: { code: "FORBIDDEN" } }), "FORBIDDEN");
  assertEquals(xenditErrorCode({}), null);
  assertEquals(xenditErrorCode(null), null);
});

Deno.test("xenditErrorMessage is sanitized and never echoes the secret key", () => {
  const cases = [
    { httpStatus: 0, failure: "timeout" as const, data: null },
    { httpStatus: 0, failure: "unreachable" as const, data: null },
    { httpStatus: 401, failure: null, data: { error_code: "UNAUTHORIZED" } },
    { httpStatus: 403, failure: null, data: { error_code: "FORBIDDEN" } },
    { httpStatus: 422, failure: null, data: { error_code: "CHANNEL_NOT_AVAILABLE" } },
    { httpStatus: 500, failure: null, data: { error_code: "SERVER_ERROR" } },
  ];
  for (const input of cases) {
    const message = xenditErrorMessage(input);
    assert(message.length > 0, "message must not be empty");
    assertFalse(message.includes(TEST_KEY), "the key must never appear in a message");
    assertFalse(message.includes("Authorization"), "no header info in messages");
    assertFalse(message.includes("Basic "), "no auth scheme in messages");
  }
});

Deno.test("timingSafeEqual compares secrets without short-circuiting on content", () => {
  assert(timingSafeEqual("abc123", "abc123"));
  assertFalse(timingSafeEqual("abc123", "abc124"));
  assertFalse(timingSafeEqual("abc", "abcd"));
  assertFalse(timingSafeEqual("", "a"));
  assert(timingSafeEqual("", ""));
});
