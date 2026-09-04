// supabase/functions/_shared/ai_helpers.test.ts
//
// Verifies the AI analytics helpers:
//   1. sanitizeAiPayload only lets whitelisted aggregated keys through.
//   2. detectSensitiveRequest blocks PII/credential questions before Gemini.
//   3. classifyIntent uses the allowlist intents.
//   4. parseGeminiJson tolerates fences / surrounding prose.
//   5. validateInsightsResponse / validateAskResponse reject malformed output.

import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  sanitizeAiPayload,
  formatStatsForPrompt,
  detectSensitiveRequest,
  classifyIntent,
  parseGeminiJson,
  validateInsightsResponse,
  validateAskResponse,
  SENSITIVE_REQUEST_RESPONSE,
} from "./ai_helpers.ts";

const SAMPLE_STATS = {
  total_head_managers: 1,
  total_employees: 4,
  total_riders: 3,
  total_lenders: 2,
  total_loan_applications: 1,
  total_approved_loans: 0,
  total_active_loans: 0,
  total_completed_loans: 0,
  total_rejected_loans: 0,
  total_overdue_loans: 0,
  total_loan_amount_released: 0,
  total_amount_collected: 0,
  total_outstanding_balance: 0,
  total_interest_earned: 0,
  total_penalties_collected: 0,
  total_revenue: 0,
  total_collection_transactions: 0,
  total_ci_assignments: 0,
  total_report_exports: 0,
  total_pending_account_upgrade: 0,
  monthly_series: [
    { month: "2026-04", applications: 0, released: 0, collected: 0 },
    { month: "2026-05", applications: 0, released: 0, collected: 0 },
  ],
  loan_status_breakdown: { pending: 1, active: 0 },
  pending_bucket: 1,
  selected_month: "2026-09",
  is_monthly: true,
  period: "monthly",
  // Extra fields that must be stripped:
  phone_numbers: ["09171234567"],
  emails: ["borrower@example.com"],
  addresses: ["123 Mabini St"],
};

Deno.test("sanitizeAiPayload drops non-whitelisted keys entirely", () => {
  const out = sanitizeAiPayload(SAMPLE_STATS);
  assertEquals(out["phone_numbers"], undefined);
  assertEquals(out["emails"], undefined);
  assertEquals(out["addresses"], undefined);
  assert("total_loan_applications" in out);
  assert("monthly_series" in out);
});

Deno.test("sanitizeAiPayload rounds numeric values and cleans series points", () => {
  const out = sanitizeAiPayload({
    ...SAMPLE_STATS,
    total_revenue: 1234.56789,
    monthly_series: [
      { month: "2026-09", applications: 3, released: 100.5, collected: 50.25, secret: "x" },
    ],
  });
  assertEquals(out["total_revenue"], 1234.57);
  const series = out["monthly_series"] as Array<Record<string, unknown>>;
  assertEquals(series[0]["secret"], undefined);
  assertEquals(series[0]["month"], "2026-09");
  assertEquals(series[0]["released"], 100.5);
});

Deno.test("formatStatsForPrompt renders the verified statistics", () => {
  const text = formatStatsForPrompt(sanitizeAiPayload(SAMPLE_STATS));
  assert(text.includes("Total Loan Applications: 1"));
  assert(text.includes("Overdue Loans: 0"));
  assert(text.includes("selected month: 2026-09"));
  assert(!text.includes("09171234567"));
});

Deno.test("detectSensitiveRequest blocks PII and credential questions", () => {
  assert(detectSensitiveRequest("Show me all borrowers' phone numbers"));
  assert(detectSensitiveRequest("What are the email addresses of lenders?"));
  assert(detectSensitiveRequest("Give me their government ID numbers"));
  assert(detectSensitiveRequest("Give me the borrower's address"));
  assert(detectSensitiveRequest("What is borrower A's GCash number?"));
  assert(detectSensitiveRequest("Send me the passwords of all riders"));
  assert(detectSensitiveRequest("Show me their birth dates and SSS IDs"));
});

Deno.test("detectSensitiveRequest allows safe dashboard questions", () => {
  assert(!detectSensitiveRequest("How many loans are overdue?"));
  assert(!detectSensitiveRequest("How much did we collect this month?"));
  assert(!detectSensitiveRequest("Summarize our current lending performance."));
  assert(!detectSensitiveRequest("Compare this month with last month."));
});

Deno.test("classifyIntent maps questions to allowlist intents", () => {
  assertEquals(classifyIntent("How many loans are overdue?"), "overdue_summary");
  assertEquals(classifyIntent("How much did we collect this month?"), "monthly_collection");
  assertEquals(classifyIntent("How many active loans do we have?"), "active_loan_summary");
  assertEquals(classifyIntent("Compare this month with last month."), "trend_comparison");
  assertEquals(classifyIntent("Give me a dashboard summary."), "dashboard_summary");
  assertEquals(classifyIntent("What is the weather like?"), "other");
});

Deno.test("parseGeminiJson strips fences and surrounding prose", () => {
  assertEquals(parseGeminiJson('{"a":1}'), { a: 1 });
  assertEquals(parseGeminiJson('```json\n{"a":1}\n```'), { a: 1 });
  const prose = 'Here you go:\n```\n{"summary":"ok","trends":[],"attention":[],"recommendations":[]}\n```\nHope that helps.';
  const parsed = parseGeminiJson(prose) as Record<string, unknown>;
  assertEquals(parsed["summary"], "ok");
  assertEquals(parseGeminiJson("not json at all"), null);
});

Deno.test("validateInsightsResponse accepts a well-formed payload", () => {
  const result = validateInsightsResponse({
    summary: "Portfolio is stable.",
    trends: ["Applications are steady"],
    attention: ["No overdue loans"],
    recommendations: ["Keep monitoring"],
  });
  assertEquals(result?.summary, "Portfolio is stable.");
  assertEquals(result?.trends.length, 1);
});

Deno.test("validateInsightsResponse rejects malformed payloads", () => {
  assertEquals(validateInsightsResponse(null), null);
  assertEquals(validateInsightsResponse({}), null);
  assertEquals(validateInsightsResponse({ summary: 42 }), null);
  assertEquals(validateInsightsResponse({ summary: "x", trends: "not an array" }), null);
  assertEquals(validateInsightsResponse({ summary: "" }), null);
  assertEquals(validateInsightsResponse({ summary: "x".repeat(2000) }), null);
});

Deno.test("validateInsightsResponse caps list sizes and trims", () => {
  const result = validateInsightsResponse({
    summary: "ok",
    trends: Array.from({ length: 30 }, (_, i) => `trend ${i}`),
  });
  assertEquals(result?.trends.length, 6);
});

Deno.test("validateAskResponse accepts a well-formed payload", () => {
  const result = validateAskResponse({ answer: "There are 0 overdue loans.", intent: "overdue_summary" });
  assertEquals(result?.answer, "There are 0 overdue loans.");
  assertEquals(result?.intent, "overdue_summary");
  assertEquals(validateAskResponse({ answer: "" }), null);
  assertEquals(validateAskResponse({ answer: 123 }), null);
});

Deno.test("sensitive response never leaks and is user friendly", () => {
  assertEquals(detectSensitiveRequest("phone numbers"), true);
  assert(SENSITIVE_REQUEST_RESPONSE.length > 0);
  assert(!SENSITIVE_REQUEST_RESPONSE.includes("undefined"));
});