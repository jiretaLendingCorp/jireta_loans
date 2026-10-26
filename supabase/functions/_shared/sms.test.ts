// supabase/functions/_shared/sms.test.ts
//
// Tests para sa `sendSms` — TextBee lamang ang provider. Ang mahalagang
// panuntunan: API acceptance ≠ delivered, at walang fallback sa ibang
// gateway kapag kulang ang `TEXTBEE_API_KEY`.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  redactSensitiveDigits,
  resetTextBeeGatewayCache,
  sendSms,
} from "./sms.ts";
import { otpSmsBodyTemplate } from "./otp.ts";

Deno.test("redactSensitiveDigits hides codes/numbers and caps length", () => {
  assertEquals(redactSensitiveDigits("otp 123456"), "otp ******");
  assertEquals(redactSensitiveDigits("short 1234"), "short 1234");
  assertEquals(redactSensitiveDigits("x".repeat(500)).length, 201);
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
  name: "only a delivered batch is reported as confirmed delivery",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      device: Deno.env.get("TEXTBEE_DEVICE_ID"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
      mock: Deno.env.get("USE_MOCK_SMS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_DEVICE_ID", "device-1");
    Deno.env.delete("USE_MOCK_SMS");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/gateway/messages")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              data: [{ _id: "m1", status: "delivered", recipient: "+639171234567" }],
            }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: { success: true, smsBatchId: "batch-delivered", recipientCount: 1 },
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
      assertEquals(result.accepted, true);
      assertEquals(result.status, "sent");
      assertEquals(result.delivery, "confirmed");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["TEXTBEE_DEVICE_ID", previous.device],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
        ["USE_MOCK_SMS", previous.mock],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "a batch the carrier accepted is not 'confirmed' delivery",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
      mock: Deno.env.get("USE_MOCK_SMS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.delete("TEXTBEE_DEVICE_ID");
    Deno.env.delete("USE_MOCK_SMS");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/gateway/messages")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({ data: [{ status: "sent", recipient: "+639171234567" }] }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({ data: { success: true, smsBatchId: "batch-sent" } }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
      });
      assertEquals(result.status, "sent");
      // Tinanggap ng carrier — walang delivery report, kaya hindi "confirmed".
      assertEquals(result.delivery, "carrier_accepted");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
        ["USE_MOCK_SMS", previous.mock],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "an unreadable batch status is 'unconfirmed', never 'sent'",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      statusCheck: Deno.env.get("TEXTBEE_STATUS_CHECK_MS"),
      mock: Deno.env.get("USE_MOCK_SMS"),
    };
    Deno.env.set("TEXTBEE_API_KEY", "tb-test-key");
    Deno.env.set("TEXTBEE_STATUS_CHECK_MS", "150");
    Deno.env.delete("USE_MOCK_SMS");

    const originalFetch = globalThis.fetch;
    globalThis.fetch = ((input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/gateway/messages")) {
        // `unknown` = walang report galing sa phone (20-minute timeout sa API).
        return Promise.resolve(
          new Response(
            JSON.stringify({ data: [{ status: "unknown", recipient: "+639171234567" }] }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({ data: { success: true, smsBatchId: "batch-unknown" } }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
      });
      assertEquals(result.accepted, true);
      assertEquals(result.status, "pending");
      assertEquals(result.delivery, "unconfirmed");
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["TEXTBEE_STATUS_CHECK_MS", previous.statusCheck],
        ["USE_MOCK_SMS", previous.mock],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

Deno.test({
  name: "walang TEXTBEE_API_KEY: malinaw na failure, walang ibang provider",
  permissions: { env: true },
  fn: async () => {
    const previous = {
      textbee: Deno.env.get("TEXTBEE_API_KEY"),
      mock: Deno.env.get("USE_MOCK_SMS"),
    };
    Deno.env.delete("TEXTBEE_API_KEY");
    Deno.env.delete("USE_MOCK_SMS");

    let calls = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (() => {
      calls++;
      return Promise.reject(new Error("must not be called"));
    }) as typeof fetch;

    try {
      const result = await sendSms({
        to: "09171234567",
        message: "Your Jireta Loans OTP is: {otp}.",
        otpCode: "654321",
        logMessage: "Your Jireta Loans OTP was sent.",
      });

      assertEquals(result.accepted, false);
      assertEquals(result.status, "failed");
      assertEquals(result.delivery, "failed");
      assertEquals(result.errorCode, "TEXTBEE_NOT_CONFIGURED");
      // Walang tahimik na paglipat sa ibang SMS provider.
      assertEquals(calls, 0);
    } finally {
      globalThis.fetch = originalFetch;
      for (const [name, value] of [
        ["TEXTBEE_API_KEY", previous.textbee],
        ["USE_MOCK_SMS", previous.mock],
      ] as const) {
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
    }
  },
});

// ── Gateway phone / SIM / recipient verification ────────────────────────────
type FetchCall = { url: string; body: Record<string, unknown> };

async function withSmsEnv(
  values: Record<string, string | null>,
  fn: () => Promise<void>,
): Promise<void> {
  const previous: Record<string, string | undefined> = {};
  for (const [name, value] of Object.entries(values)) {
    previous[name] = Deno.env.get(name);
    if (value === null) Deno.env.delete(name);
    else Deno.env.set(name, value);
  }
  resetTextBeeGatewayCache();
  try {
    await fn();
  } finally {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
    resetTextBeeGatewayCache();
  }
}

/** Stub ng TextBee: devices, send-sms at messages ayon sa URL. */
function stubTextBee(options: {
  devices?: unknown;
  messages: unknown;
  calls: FetchCall[];
}): void {
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    options.calls.push({
      url,
      body: init?.body
        ? JSON.parse(String(init.body)) as Record<string, unknown>
        : {},
    });
    const json = (body: unknown) =>
      new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    if (url.includes("/gateway/devices")) {
      return Promise.resolve(json(options.devices ?? { data: [] }));
    }
    if (url.includes("/gateway/messages")) {
      return Promise.resolve(json({ data: options.messages }));
    }
    return Promise.resolve(
      json({
        data: { success: true, smsBatchId: "batch-test", recipientCount: 1 },
      }),
    );
  }) as typeof fetch;
}

function healthyDevice(overrides: Record<string, unknown> = {}) {
  return {
    _id: "dev1",
    name: "gateway",
    enabled: true,
    isDefault: true,
    heartbeatIntervalMinutes: 30,
    lastHeartbeat: new Date(Date.now() - 60_000).toISOString(),
    powerInfo: {
      isDeviceIdleMode: false,
      isIgnoringBatteryOptimizations: true,
    },
    simInfo: {
      sims: [
        { subscriptionId: 1, simSlotIndex: 0, serviceState: "IN_SERVICE" },
        { subscriptionId: 2, simSlotIndex: 1, serviceState: "IN_SERVICE" },
      ],
    },
    ...overrides,
  };
}

Deno.test({
  name: "a phone number pasted into TEXTBEE_DEVICE_ID fails before any SMS call",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        TEXTBEE_DEVICE_ID: "09633851074",
        TEXTBEE_SIM_SUBSCRIPTION_ID: null,
        TEXTBEE_GATEWAY_NUMBER: null,
        USE_MOCK_SMS: null,
      },
      async () => {
        let calls = 0;
        const originalFetch = globalThis.fetch;
        globalThis.fetch = (() => {
          calls++;
          return Promise.reject(new Error("must not be called"));
        }) as typeof fetch;
        try {
          const result = await sendSms({
            to: "09633851074",
            message: "Your Jireta Loans OTP is: {otp}.",
            otpCode: "123456",
            logMessage: "Your Jireta Loans OTP was sent.",
          });
          assertEquals(result.accepted, false);
          assertEquals(result.status, "failed");
          assertEquals(result.delivery, "failed");
          assertEquals(result.errorCode, "TEXTBEE_DEVICE_ID_INVALID");
          assertEquals(calls, 0);
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});

Deno.test({
  name: "a disabled gateway device is a clear failure, not a queued OTP",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        TEXTBEE_DEVICE_ID: "dev1",
        TEXTBEE_SIM_SUBSCRIPTION_ID: null,
        TEXTBEE_GATEWAY_NUMBER: null,
        USE_MOCK_SMS: null,
      },
      async () => {
        const calls: FetchCall[] = [];
        const originalFetch = globalThis.fetch;
        stubTextBee({
          devices: {
            data: [healthyDevice({ enabled: false })],
          },
          messages: [],
          calls,
        });
        try {
          const result = await sendSms({
            to: "09171234567",
            message: "Your Jireta Loans OTP is: {otp}.",
            otpCode: "123456",
          });
          assertEquals(result.accepted, false);
          assertEquals(result.errorCode, "TEXTBEE_DEVICE_DISABLED");
          // Walang send na naipadala — malinaw na hindi kaya ng phone.
          assertEquals(
            calls.some((call) => call.url.includes("/gateway/send-sms")),
            false,
          );
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});

Deno.test({
  name: "a batch sent to a different recipient is a failure (OTP went elsewhere)",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        TEXTBEE_DEVICE_ID: "dev1",
        TEXTBEE_SIM_SUBSCRIPTION_ID: null,
        TEXTBEE_GATEWAY_NUMBER: null,
        USE_MOCK_SMS: null,
        TEXTBEE_STATUS_CHECK_MS: "2000",
      },
      async () => {
        const calls: FetchCall[] = [];
        const originalFetch = globalThis.fetch;
        // Ang gateway ay nagpadala sa IBANG numero kaysa sa hiniling.
        stubTextBee({
          devices: { data: [healthyDevice()] },
          messages: [
            { status: "delivered", recipient: "+639281234567" },
          ],
          calls,
        });
        try {
          const result = await sendSms({
            to: "09171234567",
            message: "Your Jireta Loans OTP is: {otp}.",
            otpCode: "123456",
            logMessage: "Your Jireta Loans OTP was sent.",
          });
          assertEquals(result.accepted, false);
          assertEquals(result.status, "failed");
          assertEquals(result.delivery, "failed");
          assertEquals(result.errorCode, "TEXTBEE_RECIPIENT_MISMATCH");
          assert(
            String(result.providerDetail).includes("+6392*****567"),
            "the mismatched recipient should be named (masked)",
          );
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});

Deno.test({
  name: "a pinned SIM that is not in the phone is rejected before sending",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        TEXTBEE_DEVICE_ID: "dev1",
        TEXTBEE_SIM_SUBSCRIPTION_ID: "9",
        TEXTBEE_GATEWAY_NUMBER: null,
        USE_MOCK_SMS: null,
      },
      async () => {
        const calls: FetchCall[] = [];
        const originalFetch = globalThis.fetch;
        stubTextBee({
          devices: { data: [healthyDevice()] },
          messages: [],
          calls,
        });
        try {
          const result = await sendSms({
            to: "09171234567",
            message: "Your Jireta Loans OTP is: {otp}.",
            otpCode: "123456",
          });
          assertEquals(result.accepted, false);
          assertEquals(result.errorCode, "TEXTBEE_SIM_NOT_CONFIGURED");
          assertEquals(
            calls.some((call) => call.url.includes("/gateway/send-sms")),
            false,
          );
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});

Deno.test({
  name: "the resolved gateway device and SIM are sent to TextBee",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        // Walang device id: ang server ang magpi-pin ng natukoy na device
        // (dev1) para hindi lumipat sa ibang phone.
        TEXTBEE_DEVICE_ID: null,
        TEXTBEE_SIM_SUBSCRIPTION_ID: "2",
        TEXTBEE_GATEWAY_NUMBER: "+639633851074",
        USE_MOCK_SMS: null,
        TEXTBEE_STATUS_CHECK_MS: "2000",
      },
      async () => {
        const calls: FetchCall[] = [];
        const originalFetch = globalThis.fetch;
        stubTextBee({
          devices: { data: [healthyDevice()] },
          messages: [{ status: "sent", recipient: "+639171234567" }],
          calls,
        });
        try {
          const result = await sendSms({
            to: "09171234567",
            message: "Your Jireta Loans OTP is: {otp}.",
            otpCode: "123456",
          });
          assertEquals(result.status, "sent");
          const send = calls.find((call) =>
            call.url.includes("/gateway/send-sms")
          );
          assert(send, "the send request must reach TextBee");
          assertEquals(send.body.recipients, ["+639171234567"]);
          assertEquals(send.body.deviceId, "dev1");
          assertEquals(send.body.simSubscriptionId, 2);
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});

/**
 * Ang body na NAKARARATING sa TextBee ay ang maikling default template (brand +
 * code lang), hindi ang canned na "Your ... OTP is ... Do not share this code"
 * na hinaharang ng carrier anti-smishing filter kapag personal SIM ang sender.
 */
Deno.test({
  name: "the OTP that reaches TextBee is the short, non-canned body",
  permissions: { env: true },
  fn: async () => {
    await withSmsEnv(
      {
        TEXTBEE_API_KEY: "tb-test-key",
        TEXTBEE_DEVICE_ID: "dev1",
        TEXTBEE_SIM_SUBSCRIPTION_ID: null,
        TEXTBEE_GATEWAY_NUMBER: null,
        OTP_SMS_TEMPLATE: null,
        USE_MOCK_SMS: null,
        TEXTBEE_STATUS_CHECK_MS: "2000",
      },
      async () => {
        const calls: FetchCall[] = [];
        const originalFetch = globalThis.fetch;
        stubTextBee({
          devices: { data: [healthyDevice()] },
          messages: [{ status: "sent", recipient: "+639171234567" }],
          calls,
        });
        try {
          const result = await sendSms({
            to: "09171234567",
            message: otpSmsBodyTemplate(5),
            otpCode: "056264",
            logMessage: "Your Jireta Loans OTP was sent.",
          });
          assertEquals(result.accepted, true);
          const send = calls.find((call) =>
            call.url.includes("/gateway/send-sms")
          );
          assert(send, "the send request must reach TextBee");
          assertEquals(send.body.message, "Jireta: 056264. Expires in 5 min.");
          // Walang kontrol na salita at walang link sa aktwal na body.
          assert(!String(send.body.message).includes("OTP"));
          assert(!String(send.body.message).includes("Do not share"));
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  },
});
