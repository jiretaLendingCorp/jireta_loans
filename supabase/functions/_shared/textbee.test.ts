// supabase/functions/_shared/textbee.test.ts
//
// Tests para sa TextBee request/response handling. Ang mahalagang panuntunan:
// API acceptance (queued) ≠ delivered — kaya `pending` ang status, at ang
// invalid key / plan limit / disabled device ay failure (hindi "sent").
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildTextBeePayload,
  normalizeTextBeeRecipient,
  parseTextBeeSendResponse,
  sendTextBeeSms,
  TEXTBEE_SEND_URL,
} from "./textbee.ts";

Deno.test("recipient is normalized to international format", () => {
  assertEquals(normalizeTextBeeRecipient("09171234567"), "+639171234567");
  assertEquals(normalizeTextBeeRecipient("+639171234567"), "+639171234567");
  assertEquals(normalizeTextBeeRecipient("639171234567"), "+639171234567");
  assertEquals(normalizeTextBeeRecipient("9171234567"), "+639171234567");
  assertEquals(normalizeTextBeeRecipient("0917 123 4567"), "+639171234567");
  assertEquals(normalizeTextBeeRecipient(""), "");
});

Deno.test("payload carries recipients + message, deviceId only when configured", () => {
  const withoutDevice = buildTextBeePayload({
    to: "09171234567",
    message: "Your Jireta Loans OTP is: 123456.",
  });
  assertEquals(withoutDevice.recipients, ["+639171234567"]);
  assertEquals(withoutDevice.message, "Your Jireta Loans OTP is: 123456.");
  assertEquals("deviceId" in withoutDevice, false);

  const withDevice = buildTextBeePayload({
    to: "09171234567",
    message: "hi",
    deviceId: "  device-abc  ",
  });
  assertEquals(withDevice.deviceId, "device-abc");

  const blankDevice = buildTextBeePayload({
    to: "09171234567",
    message: "hi",
    deviceId: "   ",
  });
  assertEquals("deviceId" in blankDevice, false);
});

Deno.test("a queued send is accepted but stays pending (not delivered)", () => {
  const result = parseTextBeeSendResponse(200, {
    data: {
      success: true,
      message: "SMS queued",
      smsBatchId: "batch_123",
      recipientCount: 1,
    },
  });
  assertEquals(result.accepted, true);
  assertEquals(result.status, "pending");
  assertEquals(result.gatewayReference, "batch_123");
  assertEquals(result.errorCode, undefined);
});

Deno.test("success=false is a failure and the detail is redacted", () => {
  const result = parseTextBeeSendResponse(200, {
    data: {
      success: false,
      message: "Device 09171234567 rejected code 654321",
    },
  });
  assertEquals(result.accepted, false);
  assertEquals(result.status, "failed");
  assertEquals(result.errorCode, "TEXTBEE_REJECTED");
  assertEquals(result.providerDetail?.includes("654321"), false);
  assertEquals(result.providerDetail?.includes("09171234567"), false);
});

Deno.test("HTTP errors (invalid key / plan limit / no device) are failures", () => {
  const unauthorized = parseTextBeeSendResponse(401, {
    message: "Invalid API key",
  });
  assertEquals(unauthorized.accepted, false);
  assertEquals(unauthorized.status, "failed");
  assertEquals(unauthorized.errorCode, "TEXTBEE_HTTP_401");

  const limited = parseTextBeeSendResponse(429, {
    data: { message: "Daily plan limit reached" },
  });
  assertEquals(limited.accepted, false);
  assertEquals(limited.errorCode, "TEXTBEE_HTTP_429");
  assertEquals(limited.providerDetail, "Daily plan limit reached");

  const noDevice = parseTextBeeSendResponse(400, {
    message: "No enabled device to send from",
  });
  assertEquals(noDevice.accepted, false);
  assertEquals(noDevice.errorCode, "TEXTBEE_HTTP_400");
});

Deno.test("a likely-to-fail warning is accepted but never reported as sent", () => {
  const result = parseTextBeeSendResponse(200, {
    data: {
      success: true,
      smsBatchId: "batch_9",
      warning: {
        code: "SMS_PERMISSION_MISSING",
        message: "SMS permission is off on device 09171234567",
      },
    },
  });
  assertEquals(result.accepted, true);
  assertEquals(result.status, "pending");
  assertEquals(result.errorCode, "SMS_PERMISSION_MISSING");
  assertEquals(result.providerDetail?.includes("09171234567"), false);
});

Deno.test("immediate dispatch counts decide acceptance", () => {
  const allFailed = parseTextBeeSendResponse(200, {
    data: { successCount: 0, failureCount: 1 },
  });
  assertEquals(allFailed.accepted, false);
  assertEquals(allFailed.status, "failed");

  const dispatched = parseTextBeeSendResponse(200, {
    data: { successCount: 1, failureCount: 0 },
  });
  assertEquals(dispatched.accepted, true);
  assertEquals(dispatched.status, "pending");
  assertEquals(dispatched.gatewayReference, null);
});

Deno.test("unexpected or empty bodies are failures", () => {
  assertEquals(
    parseTextBeeSendResponse(200, null).errorCode,
    "TEXTBEE_INVALID_RESPONSE",
  );
  assertEquals(
    parseTextBeeSendResponse(200, { ok: true }).errorCode,
    "TEXTBEE_INVALID_RESPONSE",
  );
  assertEquals(
    parseTextBeeSendResponse(200, []).accepted,
    false,
  );
  assertEquals(
    parseTextBeeSendResponse(204, null).accepted,
    false,
  );
});

Deno.test("sendTextBeeSms posts recipients/message with the x-api-key header", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    calls.push({ url, init: init ?? {} });
    return Promise.resolve(
      new Response(
        JSON.stringify({
          data: { success: true, smsBatchId: "batch_1", recipientCount: 1 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;

  try {
    const result = await sendTextBeeSms({
      apiKey: "tb_test_key",
      to: "09171234567",
      message: "Your Jireta Loans OTP is: 654321. Valid for 5 minutes.",
      deviceId: "device-1",
    });

    assertEquals(result.accepted, true);
    assertEquals(result.status, "pending");
    assertEquals(result.gatewayReference, "batch_1");

    assertEquals(calls.length, 1);
    assertEquals(calls[0].url, TEXTBEE_SEND_URL);
    assertEquals(calls[0].init.method, "POST");
    const headers = calls[0].init.headers as Record<string, string>;
    assertEquals(headers["x-api-key"], "tb_test_key");
    assertEquals(headers["Content-Type"], "application/json");

    const body = JSON.parse(String(calls[0].init.body)) as Record<string, unknown>;
    assertEquals(body.recipients, ["+639171234567"]);
    assertEquals(
      body.message,
      "Your Jireta Loans OTP is: 654321. Valid for 5 minutes.",
    );
    assertEquals(body.deviceId, "device-1");
    // Ang key at ang code ay hindi dumadaan sa URL/query.
    assertEquals(calls[0].url.includes("tb_test_key"), false);
    assertEquals(calls[0].url.includes("654321"), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("failed TextBee call never logs the API key or the OTP", async () => {
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const logged: string[] = [];
  console.error = (...args: unknown[]) => {
    logged.push(args.map((arg) => String(arg)).join(" "));
  };
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({ message: "Invalid API key for code 123456" }),
        { status: 401, headers: { "content-type": "application/json" } },
      ),
    )) as typeof fetch;

  try {
    const result = await sendTextBeeSms({
      apiKey: "tb_secret_key_value",
      to: "09171234567",
      message: "Your Jireta Loans OTP is: 123456.",
    });

    assertEquals(result.accepted, false);
    assertEquals(result.status, "failed");
    assertEquals(result.errorCode, "TEXTBEE_HTTP_401");

    const output = logged.join("\n");
    assert(output.length > 0);
    assertStringIncludes(output, "TEXTBEE_HTTP_401");
    assertEquals(output.includes("tb_secret_key_value"), false);
    assertEquals(output.includes("123456"), false);
    assertEquals(output.includes("09171234567"), false);
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
  }
});

Deno.test("network errors are reported as failures, never as sent", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new Error("offline"))) as typeof fetch;

  try {
    const result = await sendTextBeeSms({
      apiKey: "tb_test_key",
      to: "09171234567",
      message: "Your Jireta Loans OTP is: 123456.",
    });
    assertEquals(result.accepted, false);
    assertEquals(result.status, "failed");
    assertEquals(result.errorCode, "TEXTBEE_NETWORK_ERROR");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
