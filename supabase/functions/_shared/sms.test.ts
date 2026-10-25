// supabase/functions/_shared/sms.test.ts
//
// Tests para sa Semaphore response handling. Ang mahalagang panuntunan:
// API acceptance ≠ delivered — kaya ang `Queued`/`Pending` ay `pending`, at
// ang `Failed`/`Refunded` / non-2xx ay failure (hindi kailanman "sent").
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildSemaphoreForm,
  parseSemaphoreSendResponse,
  redactSensitiveDigits,
  sendSms,
} from "./sms.ts";

function message(overrides: Record<string, unknown> = {}) {
  return {
    message_id: 12345,
    recipient: "639171234567",
    status: "Queued",
    ...overrides,
  };
}

Deno.test("queued response is accepted but remains pending (not delivered)", () => {
  const result = parseSemaphoreSendResponse(200, [message()]);
  assertEquals(result.accepted, true);
  assertEquals(result.status, "pending");
  assertEquals(result.gatewayReference, "12345");
});

Deno.test("pending response maps to pending", () => {
  const result = parseSemaphoreSendResponse(200, [message({ status: "Pending" })]);
  assertEquals(result.accepted, true);
  assertEquals(result.status, "pending");
});

Deno.test("sent response maps to sent", () => {
  const result = parseSemaphoreSendResponse(200, [message({ status: "Sent" })]);
  assertEquals(result.accepted, true);
  assertEquals(result.status, "sent");
});

Deno.test("failed and refunded responses are rejected", () => {
  for (const status of ["Failed", "Refunded"]) {
    const result = parseSemaphoreSendResponse(200, [message({ status })]);
    assertEquals(result.accepted, false);
    assertEquals(result.status, "failed");
    assertEquals(result.gatewayReference, "12345");
  }
});

Deno.test("missing message_id is not treated as accepted", () => {
  const result = parseSemaphoreSendResponse(200, [
    message({ message_id: undefined }),
  ]);
  assertEquals(result.accepted, false);
  assertEquals(result.status, "failed");
  assertEquals(result.errorCode, "SEMAPHORE_REJECTED");
});

Deno.test("HTTP errors (invalid key / rate limit) are failures", () => {
  const unauthorized = parseSemaphoreSendResponse(401, {
    message: "Invalid API Key",
  });
  assertEquals(unauthorized.accepted, false);
  assertEquals(unauthorized.status, "failed");
  assertEquals(unauthorized.errorCode, "SEMAPHORE_HTTP_401");

  const limited = parseSemaphoreSendResponse(429, {
    message: "Too Many Attempts",
  });
  assertEquals(limited.accepted, false);
  assertEquals(limited.errorCode, "SEMAPHORE_HTTP_429");
});

Deno.test("empty or unexpected bodies are failures", () => {
  const empty = parseSemaphoreSendResponse(200, []);
  assertEquals(empty.accepted, false);
  assertEquals(empty.errorCode, "SEMAPHORE_EMPTY_RESPONSE");

  // Wala talagang JSON body (HTML page / proxy error) — hindi puwedeng
  // ituring na accepted.
  const nonJson = parseSemaphoreSendResponse(200, null);
  assertEquals(nonJson.accepted, false);
  assertEquals(nonJson.errorCode, "SEMAPHORE_INVALID_RESPONSE");
});

Deno.test("a single message object is accepted (OTP endpoint shape)", () => {
  const result = parseSemaphoreSendResponse(200, message());
  assertEquals(result.accepted, true);
  assertEquals(result.status, "pending");
  assertEquals(result.gatewayReference, "12345");
});

Deno.test("single object with Failed status is rejected", () => {
  const result = parseSemaphoreSendResponse(200, message({ status: "Failed" }));
  assertEquals(result.accepted, false);
  assertEquals(result.gatewayReference, "12345");
});

Deno.test("HTTP 200 error object is reported with a redacted detail", () => {
  const result = parseSemaphoreSendResponse(200, {
    message: "Invalid sender name for code 123456 / 09171234567",
  });
  assertEquals(result.accepted, false);
  assertEquals(result.status, "failed");
  assertEquals(result.errorCode, "SEMAPHORE_ERROR");
  assertEquals(result.gatewayReference, null);
  assertEquals(result.providerDetail, "Invalid sender name for code ****** / ******");
});

Deno.test("non-2xx error bodies surface a redacted reason", () => {
  const fromArray = parseSemaphoreSendResponse(500, [
    { message: "Invalid sender name 09171234567" },
  ]);
  assertEquals(fromArray.accepted, false);
  assertEquals(fromArray.errorCode, "SEMAPHORE_HTTP_500");
  assertEquals(fromArray.providerDetail, "Invalid sender name ******");

  const fromObject = parseSemaphoreSendResponse(422, {
    message: "Not enough credits for code 123456",
  });
  assertEquals(fromObject.providerDetail, "Not enough credits for code ******");

  const noBody = parseSemaphoreSendResponse(500, null);
  assertEquals(noBody.errorCode, "SEMAPHORE_HTTP_500");
  assertEquals(noBody.providerDetail, undefined);
});

Deno.test("redactSensitiveDigits hides codes/numbers and caps length", () => {
  assertEquals(redactSensitiveDigits("otp 123456"), "otp ******");
  assertEquals(redactSensitiveDigits("short 1234"), "short 1234");
  assertEquals(redactSensitiveDigits("x".repeat(500)).length, 201);
});

Deno.test("failed message detail names the network/sender, never the body", () => {
  const result = parseSemaphoreSendResponse(200, message({
    status: "Failed",
    network: "Globe",
    sender_name: "JiretaLoans",
    type: "Single",
    message: "Your Jireta Loans OTP is: 123456.",
  }));
  assertEquals(result.accepted, false);
  assertEquals(result.errorCode, "SEMAPHORE_REJECTED");
  assertEquals(
    result.providerDetail,
    "provider_status=Failed, network=Globe, sender=JiretaLoans, type=Single",
  );
  assertEquals(result.providerDetail?.includes("123456"), false);
});

Deno.test({
  name: "OTP route 5xx falls back to /api/v4/messages with the real code",
  permissions: { env: true },
  fn: async () => {
    Deno.env.set("SEMAPHORE_API_KEY", "test-key");
    Deno.env.delete("SEMAPHORE_SENDER_NAME");

    const calls: { url: string; body: string }[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      calls.push({ url, body: String(init?.body ?? "") });
      if (url.endsWith("/otp")) {
        return Promise.resolve(
          new Response("[]", {
            status: 500,
            headers: { "content-type": "application/json" },
          }),
        );
      }
      return Promise.resolve(
        new Response(JSON.stringify([{ message_id: 42, status: "Queued" }]), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}. Do not share this code.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, true);
      assertEquals(result.gatewayReference, "42");
      assertEquals(calls.length, 2);
      assert(calls[0].url.endsWith("/api/v4/otp"));
      assert(calls[1].url.endsWith("/api/v4/messages"));

      const fallback = new URLSearchParams(calls[1].body);
      assertEquals(
        fallback.get("message"),
        "Your Jireta Loans OTP is: 654321. Do not share this code.",
      );
      assertEquals(fallback.get("code"), null);
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.delete("SEMAPHORE_API_KEY");
    }
  },
});

Deno.test({
  name: "TEXTBEE_API_KEY routes OTP traffic through TextBee (code substituted)",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      provider: Deno.env.get("SMS_PROVIDER"),
      device: Deno.env.get("TEXTBEE_DEVICE_ID"),
      mock: Deno.env.get("USE_MOCK_SMS"),
      semaphore: Deno.env.get("SEMAPHORE_API_KEY"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_DEVICE_ID", "device-1");
    // Status probe off: sinusukat lang dito ang send request mismo.
    Deno.env.set("TEXTBEE_STATUS_CHECK_MS", "0");
    Deno.env.delete("SMS_PROVIDER");
    Deno.env.delete("USE_MOCK_SMS");
    Deno.env.delete("SEMAPHORE_API_KEY");

    const calls: { url: string; body: string; headers: Record<string, string> }[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      calls.push({
        url,
        body: String(init?.body ?? ""),
        headers: (init?.headers ?? {}) as Record<string, string>,
      });
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: { success: true, smsBatchId: "batch-42", recipientCount: 1 },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}. Valid for 5 minutes.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, true);
      assertEquals(result.status, "pending"); // queued, hindi delivered
      assertEquals(result.gatewayReference, "batch-42");
      assertEquals(calls.length, 1);
      assert(calls[0].url.startsWith("https://api.textbee.dev/"));
      assertEquals(calls[0].headers["x-api-key"], "tb-test-key");

      const body = JSON.parse(calls[0].body) as Record<string, unknown>;
      assertEquals(body.recipients, ["+639171234567"]);
      assertEquals(
        body.message,
        "Your Jireta Loans OTP is: 654321. Valid for 5 minutes.",
      );
      assertEquals(body.deviceId, "device-1");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["SMS_PROVIDER", previous.provider],
        ["TEXTBEE_DEVICE_ID", previous.device],
        ["USE_MOCK_SMS", previous.mock],
        ["SEMAPHORE_API_KEY", previous.semaphore],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "a device-level TextBee failure is reported as failed, not 'sent'",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      provider: Deno.env.get("SMS_PROVIDER"),
      device: Deno.env.get("TEXTBEE_DEVICE_ID"),
      mock: Deno.env.get("USE_MOCK_SMS"),
      semaphore: Deno.env.get("SEMAPHORE_API_KEY"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_STATUS_CHECK_MS", "1500");
    Deno.env.delete("TEXTBEE_DEVICE_ID");
    Deno.env.delete("SMS_PROVIDER");
    Deno.env.delete("USE_MOCK_SMS");
    Deno.env.delete("SEMAPHORE_API_KEY");

    const calls: string[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      calls.push(url);
      if (url.includes("/gateway/messages")) {
        // Ang sagot ng device: failed sa SIM/carrier, hindi naipadala.
        return Promise.resolve(
          new Response(
            JSON.stringify({
              data: [{
                status: "failed",
                recipient: "+639281234567",
                errorCode: "1",
                errorMessage:
                  "SMS failed on device. Common causes: no SMS credit on SIM, weak signal, or carrier blocked.",
              }],
            }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: { success: true, smsBatchId: "batch-9", recipientCount: 1 },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09281234567",
        message: "Your Jireta Loans OTP is: {otp}. Valid for 5 minutes.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, false);
      assertEquals(result.status, "failed");
      assertEquals(result.errorCode, "TEXTBEE_SEND_FAILED");
      assertEquals(result.gatewayReference, "batch-9");
      assert(result.providerDetail?.includes("device_error_code=1") ?? false);
      // Walang OTP at walang buong numero sa detail/provider log.
      assertEquals(result.providerDetail?.includes("654321"), false);
      assertEquals(result.providerDetail?.includes("9281234567"), false);
      assert(calls.some((url) => url.includes("/gateway/messages")));
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["SMS_PROVIDER", previous.provider],
        ["TEXTBEE_DEVICE_ID", previous.device],
        ["USE_MOCK_SMS", previous.mock],
        ["SEMAPHORE_API_KEY", previous.semaphore],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "a batch the carrier accepted is recorded as sent (not just pending)",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      device: Deno.env.get("TEXTBEE_DEVICE_ID"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_STATUS_CHECK_MS", "1500");
    Deno.env.delete("TEXTBEE_DEVICE_ID");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/gateway/messages")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              data: [{ status: "sent", recipient: "+639281234567" }],
            }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: { success: true, smsBatchId: "batch-10", recipientCount: 1 },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09281234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, true);
      assertEquals(result.status, "sent");
      assertEquals(result.gatewayReference, "batch-10");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["TEXTBEE_DEVICE_ID", previous.device],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "a batch still sitting on the gateway phone stays pending, never 'sent'",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      device: Deno.env.get("TEXTBEE_DEVICE_ID"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_STATUS_CHECK_MS", "400");
    Deno.env.delete("TEXTBEE_DEVICE_ID");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/gateway/messages")) {
        // Tulog/offline ang gateway phone: natanggap ng API, hindi pa naipadala.
        return Promise.resolve(
          new Response(
            JSON.stringify({
              data: [{ status: "pending", recipient: "+639171234567" }],
            }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: { success: true, smsBatchId: "batch-11", recipientCount: 1 },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      // Tinanggap ng API pero naka-queue — hindi ito "sent".
      assertEquals(result.accepted, true);
      assertEquals(result.status, "pending");
      assertEquals(result.gatewayReference, "batch-11");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["TEXTBEE_DEVICE_ID", previous.device],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "SMS_PROVIDER=semaphore keeps the Semaphore path as an escape hatch",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      provider: Deno.env.get("SMS_PROVIDER"),
      mock: Deno.env.get("USE_MOCK_SMS"),
      semaphore: Deno.env.get("SEMAPHORE_API_KEY"),
      sender: Deno.env.get("SEMAPHORE_SENDER_NAME"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("SMS_PROVIDER", "semaphore");
    Deno.env.set("SEMAPHORE_API_KEY", "sem-key");
    Deno.env.delete("SEMAPHORE_SENDER_NAME");
    Deno.env.delete("USE_MOCK_SMS");

    const calls: string[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      calls.push(typeof input === "string" ? input : input.toString());
      return Promise.resolve(
        new Response(
          JSON.stringify([{ message_id: 7, status: "Queued" }]),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, true);
      assertEquals(result.gatewayReference, "7");
      assertEquals(calls.length, 1);
      assert(calls[0].startsWith("https://api.semaphore.co/"));
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["SMS_PROVIDER", previous.provider],
        ["USE_MOCK_SMS", previous.mock],
        ["SEMAPHORE_API_KEY", previous.semaphore],
        ["SEMAPHORE_SENDER_NAME", previous.sender],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test("form omits sendername unless configured (unapproved name = Failed)", () => {
  const unset = buildSemaphoreForm({
    apiKey: "key",
    to: "0917 123 4567",
    message: "Your OTP is: {otp}",
    senderName: undefined,
    otpCode: "123456",
  });
  assertEquals(unset.get("sendername"), null);
  assertEquals(unset.get("number"), "09171234567");
  assertEquals(unset.get("code"), "123456");
  assertEquals(unset.get("message"), "Your OTP is: {otp}");

  const blank = buildSemaphoreForm({
    apiKey: "key",
    to: "09171234567",
    message: "hi",
    senderName: "   ",
  });
  assertEquals(blank.get("sendername"), null);
  assertEquals(blank.get("code"), null);

  const configured = buildSemaphoreForm({
    apiKey: "key",
    to: "09171234567",
    message: "hi",
    senderName: "  JiretaLoans ",
  });
  assertEquals(configured.get("sendername"), "JiretaLoans");
});
