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
  fetchTextBeeMessageReport,
  maskTextBeeNumber,
  normalizeTextBeeRecipient,
  parseTextBeeMessageReport,
  parseTextBeeSendResponse,
  sendTextBeeSms,
  TEXTBEE_MESSAGES_URL,
  TEXTBEE_SEND_URL,
  waitForTextBeeBatchOutcome,
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

Deno.test("two different entered numbers are the recipients; deviceId is the gateway", async () => {
  // Ito ang buong dahilan ng bug report: ang `recipients` ay dapat ang numerong
  // inilagay ng lender/rider (hindi ang numero/SIM ng gateway phone), at ang
  // `deviceId` lang ang gateway. Walang recipient na kailangang i-register.
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({
      url: typeof input === "string" ? input : input.toString(),
      body: JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>,
    });
    return Promise.resolve(
      new Response(
        JSON.stringify({
          data: { success: true, smsBatchId: `b${calls.length}`, recipientCount: 1 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;

  try {
    await sendTextBeeSms({
      apiKey: "tb_key",
      to: "09171234567",
      message: "code A",
      deviceId: "gateway-device-id",
    });
    await sendTextBeeSms({
      apiKey: "tb_key",
      to: "+63 928 123 4567",
      message: "code B",
      deviceId: "gateway-device-id",
    });

    assertEquals(calls.length, 2);
    assertEquals(calls[0].body.recipients, ["+639171234567"]);
    assertEquals(calls[1].body.recipients, ["+639281234567"]);
    assertEquals(calls[1].body.deviceId, "gateway-device-id");
    assertEquals(calls[0].body.deviceId, "gateway-device-id");
    // Ang gateway device ay HINDI recipient, at ang recipients ay hindi device.
    const secondRecipients = calls[1].body.recipients as string[];
    assertEquals(secondRecipients.includes("gateway-device-id"), false);
    assertEquals(calls[0].url, TEXTBEE_SEND_URL);
  } finally {
    globalThis.fetch = originalFetch;
  }
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

Deno.test("message report masks numbers and summarizes the batch", () => {
  const report = parseTextBeeMessageReport({
    data: [
      {
        _id: "m1",
        status: "delivered",
        recipient: "+639171234567",
        smsBatch: "b1",
        simSubscriptionId: 1,
      },
      {
        _id: "m2",
        status: "failed",
        recipient: "+639281234567",
        smsBatch: "b1",
        errorCode: "1",
        errorMessage:
          "SMS failed on device. Common causes: no SMS credit on SIM, weak signal, or carrier blocked.",
      },
      { _id: "m3", status: "pending", recipient: "+639991234567", smsBatch: "b1" },
    ],
  });
  assert(report);
  assertEquals(report.total, 3);
  assertEquals(report.sentCount, 1);
  assertEquals(report.failedCount, 1);
  assertEquals(report.pendingCount, 1);
  assertEquals(report.allSent, false);
  assertEquals(report.anyFailed, true);
  assertEquals(report.messages[0].recipient, "+6391*****567");
  assertEquals(report.messages[1].recipient, "+6392*****567");
  assertEquals(report.messages[1].errorCode, "1");
  assertEquals(report.messages[0].simSubscriptionId, "1");
  // Walang buong numero sa kahit anong daraanan ng log.
  assertEquals(JSON.stringify(report).includes("9171234567"), false);
  assertEquals(maskTextBeeNumber("+639171234567"), "+6391*****567");
  assertEquals(maskTextBeeNumber("n/a"), null);
});

Deno.test("a batch where every message is sent is reported as allSent", () => {
  const report = parseTextBeeMessageReport({
    data: [
      { status: "sent", recipient: "+639171234567" },
      { status: "delivered", recipient: "+639281234567" },
    ],
  });
  assert(report);
  assertEquals(report.allSent, true);
  assertEquals(report.anyFailed, false);
  assertEquals(parseTextBeeMessageReport({ data: "nope" }), null);
});

Deno.test("fetchTextBeeMessageReport uses the documented batch filter", async () => {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({
      url: typeof input === "string" ? input : input.toString(),
      headers: (init?.headers ?? {}) as Record<string, string>,
    });
    return Promise.resolve(
      new Response(
        JSON.stringify({ data: [{ status: "sent", recipient: "+639171234567" }] }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;

  try {
    const report = await fetchTextBeeMessageReport({
      apiKey: "tb_key",
      smsBatchId: "batch 1/2",
    });
    assert(report);
    assertEquals(report.allSent, true);
    assertEquals(calls.length, 1);
    assert(calls[0].url.startsWith(TEXTBEE_MESSAGES_URL));
    assert(calls[0].url.includes("smsBatchId=batch%201%2F2"));
    assertEquals(calls[0].headers["x-api-key"], "tb_key");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("an unreadable batch status fails open (never invents a failure)", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ error: "Not found" }), {
        status: 404,
        headers: { "content-type": "application/json" },
      }),
    )) as typeof fetch;

  try {
    assertEquals(
      await fetchTextBeeMessageReport({ apiKey: "k", smsBatchId: "gone" }),
      null,
    );
  } finally {
    globalThis.fetch = originalFetch;
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

Deno.test("the status wait never outlives its budget, even while the batch stays pending", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ data: [{ status: "pending", recipient: "+639171234567" }] }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }) as typeof fetch;

  try {
    const startedAt = Date.now();
    const report = await waitForTextBeeBatchOutcome({
      apiKey: "tb_key",
      smsBatchId: "batch-pending",
      timeoutMs: 600,
    });
    const elapsed = Date.now() - startedAt;

    // Nasa queue pa lang: `pending` ang totoong kalagayan, hindi "sent".
    assertEquals(report?.pendingCount, 1);
    assertEquals(report?.allSent, false);
    assert(calls >= 1);
    // Dati: 500ms sleep + fetch na tig-5s ang timeout bago suriin ang oras,
    // kaya lumalampas sa budget. Ngayon: hard deadline sa loob ng `timeoutMs`.
    assert(
      elapsed < 900,
      `waitForTextBeeBatchOutcome took ${elapsed}ms for a 600ms budget`,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("an already-sent batch is read on the first poll, without a fixed sleep", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          data: [{ status: "sent", recipient: "+639171234567" }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    )) as typeof fetch;

  try {
    const startedAt = Date.now();
    const report = await waitForTextBeeBatchOutcome({
      apiKey: "tb_key",
      smsBatchId: "batch-sent",
      timeoutMs: 1_200,
    });
    const elapsed = Date.now() - startedAt;

    assertEquals(report?.allSent, true);
    // Dati: may fixed 500ms na tulog BAGO ang unang poll, kaya dagdag na
    // kalahating segundo sa bawat OTP kahit `sent` na agad ang batch.
    assert(
      elapsed < 250,
      `the first poll waited ${elapsed}ms before asking the gateway`,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("a slow status fetch is cut off by the remaining budget", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      // Sumasagot lang kapag inabort ng AbortSignal.timeout — hindi kailanman
      // kusang magre-resolve, tulad ng hung na network request.
      init?.signal?.addEventListener("abort", () =>
        reject(new DOMException("The signal has timed out", "TimeoutError"))
      );
    })) as typeof fetch;

  try {
    const startedAt = Date.now();
    const report = await fetchTextBeeMessageReport({
      apiKey: "tb_key",
      smsBatchId: "batch-hung",
      timeoutMs: 150,
    });
    const elapsed = Date.now() - startedAt;

    // Fail-open: hindi ginagawang "failed" ang isang send na tinanggap ng API.
    assertEquals(report, null);
    assert(elapsed < 1_000, `status fetch took ${elapsed}ms for a 150ms budget`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
