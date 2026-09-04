// supabase/functions/_shared/ai_helpers.ts
//
// Pure helpers for the AI analytics layer — intentionally network-free so the
// parsing / validation / classification logic can be unit tested without
// calling Gemini (see ai_helpers.test.ts).
//
// SECURITY CONTRACT:
//   • Only aggregated statistics ever reach Gemini (sanitizeAiPayload).
//   • Sensitive-data requests are blocked WITHOUT calling Gemini.
//   • Gemini responses are strictly validated before being returned to the UI.
//   • Gemini never generates SQL and never receives credentials/PII.

export interface AiInsightsResponse {
  summary: string;
  trends: string[];
  attention: string[];
  recommendations: string[];
}

export interface AiAskResponse {
  answer: string;
  intent: string;
}

/** Strict system instruction sent to Gemini for every AI request. */
export const AI_SYSTEM_PROMPT = `You are the AI analytics assistant for a Lending Management System.

Analyze only the verified statistics provided by the backend.

Never invent or fabricate numbers.
Never assume data that was not provided.
Never generate SQL.
Never request or reveal credentials.
Never reveal unnecessary personally identifiable information.

Do not modify, approve, reject, create, or delete lending records.
PostgreSQL and the backend are the source of truth for all financial calculations.

Your responsibilities are to:
1. summarize current performance,
2. identify meaningful trends,
3. identify important areas requiring attention,
4. provide practical advisory recommendations.

All financial figures must use the exact values provided by the backend.
If there is insufficient information, clearly state that the available data is insufficient.
Recommendations are advisory only and must remain subject to authorized human review.`;

/**
 * Keys allowed to leave the edge function and reach Gemini. Everything else on
 * the dashboard stats payload (even if aggregated) is dropped so we only send
 * the minimum information needed for analysis. No PII exists in the source
 * payload, but this whitelist is the last line of defense.
 */
const ALLOWED_STAT_KEYS = [
  'total_head_managers',
  'total_employees',
  'total_riders',
  'total_lenders',
  'total_loan_applications',
  'total_approved_loans',
  'total_rejected_loans',
  'total_active_loans',
  'total_completed_loans',
  'total_overdue_loans',
  'total_loan_amount_released',
  'total_amount_collected',
  'total_outstanding_balance',
  'total_interest_earned',
  'total_penalties_collected',
  'total_revenue',
  'total_collection_transactions',
  'total_ci_assignments',
  'total_report_exports',
  'total_pending_account_upgrade',
  'monthly_series',
  'loan_status_breakdown',
  'pending_bucket',
  'selected_month',
  'is_monthly',
  'period',
] as const;

/**
 * Build the aggregated, sanitized snapshot of the dashboard stats that is safe
 * (and sufficient) to hand to Gemini. Numbers are rounded to whole pesos.
 */
export function sanitizeAiPayload(
  stats: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of ALLOWED_STAT_KEYS) {
    const v = stats[key];
    if (v === undefined || v === null) continue;
    if (typeof v === 'number') {
      out[key] = Math.round(v * 100) / 100;
    } else if (Array.isArray(v)) {
      // monthly_series — keep only month/applications/released/collected
      out[key] = v.map((p) => {
        if (!p || typeof p !== 'object') return p;
        const point = p as Record<string, unknown>;
        const clean: Record<string, unknown> = {};
        for (const k of ['month', 'applications', 'released', 'collected']) {
          if (point[k] !== undefined) clean[k] = point[k];
        }
        return clean;
      });
    } else {
      out[key] = v;
    }
  }
  return out;
}

/**
 * Human-readable rendering of the stats for the Gemini prompt. Money is shown
 * in Philippine pesos because the system operates in PHP.
 */
export function formatStatsForPrompt(
  stats: Record<string, unknown>,
): string {
  const n = (v: unknown): string =>
    typeof v === 'number' ? v.toLocaleString('en-US', { maximumFractionDigits: 2 }) : String(v ?? '0');

  const month = stats['selected_month']
    ? ` (selected month: ${stats['selected_month']})`
    : ' (lifetime)';
  const series = Array.isArray(stats['monthly_series'])
    ? (stats['monthly_series'] as Array<Record<string, unknown>>)
        .map((p) => {
          const released = typeof p['released'] === 'number'
            ? `₱${p['released'].toLocaleString('en-US', { maximumFractionDigits: 2 })}`
            : '₱0.00';
          const collected = typeof p['collected'] === 'number'
            ? `₱${p['collected'].toLocaleString('en-US', { maximumFractionDigits: 2 })}`
            : '₱0.00';
          return `${p['month']}: ${p['applications'] ?? 0} applications, released ${released}, collected ${collected}`;
        })
        .join('\n    ')
    : '';

  return [
    'VERIFIED DASHBOARD STATISTICS (source of truth: PostgreSQL backend)',
    month,
    '',
    `Head Managers: ${n(stats['total_head_managers'])}`,
    `Total Employees: ${n(stats['total_employees'])}`,
    `Total Riders: ${n(stats['total_riders'])}`,
    `Total Lenders: ${n(stats['total_lenders'])}`,
    `Pending Account Upgrades: ${n(stats['total_pending_account_upgrade'])}`,
    '',
    `Total Loan Applications: ${n(stats['total_loan_applications'])}`,
    `Approved Loans: ${n(stats['total_approved_loans'])}`,
    `Active Loans: ${n(stats['total_active_loans'])}`,
    `Completed Loans: ${n(stats['total_completed_loans'])}`,
    `Rejected Loans: ${n(stats['total_rejected_loans'])}`,
    `Overdue Loans: ${n(stats['total_overdue_loans'])}`,
    `CI Assignments: ${n(stats['total_ci_assignments'])}`,
    `Collection Transactions: ${n(stats['total_collection_transactions'])}`,
    '',
    `Amount Released: ₱${n(stats['total_loan_amount_released'])}`,
    `Amount Collected: ₱${n(stats['total_amount_collected'])}`,
    `Outstanding Balance: ₱${n(stats['total_outstanding_balance'])}`,
    `Interest Earned: ₱${n(stats['total_interest_earned'])}`,
    `Penalties Collected: ₱${n(stats['total_penalties_collected'])}`,
    `Total Revenue: ₱${n(stats['total_revenue'])}`,
    '',
    'MONTHLY TREND (last 6 months):',
    series || '  no trend data available',
  ].join('\n');
}

/**
 * Detect requests for sensitive borrower data that must NEVER be answered via
 * the AI assistant. When this returns true the request is short-circuited
 * with a canned safe response — Gemini is not called at all.
 */
export function detectSensitiveRequest(question: string): boolean {
  const q = question.toLowerCase();
  const patterns = [
    // Auth secrets / credentials
    /\b(password(s)?|otp|one[- ]?time[- ]?pin|reset password|api ?k(e|e)y(s)?|secret(s)?|service[- ]?role|credentials?)\b/i,
    // Government / identity documents & numbers
    /\b(government id(s)?|gov'?t id(s)?|voter('|’)s? id(s)?|passport(s)?|sss( number)?|tin( id| number)?|driver('|’)s? license(s)?|license number(s)?|valid id(s)?|id image(s)?|id photo(s)?|selfie(s)?)\b/i,
    // Payment / bank credentials
    /\b(credit card(s)?|debit card(s)?|card number(s)?|cvv|bank account(s)?|account number(s)?|gcash number(s)?|gcash pin|card pin)\b/i,
    // Contact details
    /\bphone\s+number(s)?\b|\bcontact\s+number(s)?\b|\bmobile\s+number(s)?\b|\btelephone(s)?\b|\bcellphone(s)?\b/i,
    // Email addresses
    /\be[- ]?mail(s)?\b|\bemail\s+address(es)?\b/i,
    // Physical addresses / location of people
    /\baddress(es)?\b|\bhouse\s+number(s)?\b|\b(barangay|street|purok|sitio)\b/i,
    // Personal demographics
    /\b(birth\s?date(s)?|birthday(s)?|date\s+of\s+birth|\bdob\b)\b/i,
    /\bemergency\s+contact(s)?\b/i,
  ];
  return patterns.some((re) => re.test(q));
}

export type AiIntent =
  | 'overdue_summary'
  | 'monthly_collection'
  | 'active_loan_summary'
  | 'dashboard_summary'
  | 'trend_comparison'
  | 'other';

/**
 * Deterministic intent classification (allowlist approach — the AI is never
 * allowed to run free-form queries against the database). Every intent maps to
 * a curated subset of the verified aggregated stats; the actual wording of the
 * answer is still generated by Gemini from that verified data.
 */
export function classifyIntent(question: string): AiIntent {
  const q = question.toLowerCase();
  if (/\boverdue\b/.test(q)) return 'overdue_summary';
  if (/\b(collect|collection|collected|payment|paid|revenue)\b/.test(q)) {
    return 'monthly_collection';
  }
  if (/\bactive\b|\bongoing\b/.test(q)) return 'active_loan_summary';
  if (/\b(compare|comparison|vs|versus|trend|monthly|last month|previous month)\b/.test(q)) {
    return 'trend_comparison';
  }
  if (/\b(summarize|summary|overview|performance|dashboard|status|how are we doing)\b/.test(q)) {
    return 'dashboard_summary';
  }
  return 'other';
}

/** The canned safe response for sensitive-data requests (Gemini never sees them). */
export const SENSITIVE_REQUEST_RESPONSE =
  "Sorry, I can't provide sensitive borrower information through the AI Assistant. " +
  'If you need this data, please use the appropriate module in the dashboard where access is controlled by your account permissions.';

/** Default answer when Gemini is unavailable for the Ask AI feature. */
export const AI_UNAVAILABLE_ANSWER =
  "I'm having trouble connecting to the AI service right now. Please try again in a moment.";

/** Helpers for the conversation: what the AI can and cannot answer about. */
export const AI_CAPABILITIES_NOTE =
  'I can only answer from verified, aggregated dashboard statistics (loan counts, collections, financial totals, and trends). I cannot access or reveal individual borrower details.';

/**
 * Extract JSON from a Gemini candidate text. Gemini sometimes wraps JSON in
 * markdown fences or adds trailing commentary even with responseMimeType set.
 */
export function parseGeminiJson(raw: string): unknown {
  if (!raw) return null;
  let text = raw.trim();
  // Strip ```json ... ``` fences
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) text = fence[1].trim();
  // If the output still contains a JSON object, extract the first object/array.
  try {
    return JSON.parse(text);
  } catch (_) {
    const start = Math.min(
      text.indexOf('{') === -1 ? Infinity : text.indexOf('{'),
      text.indexOf('[') === -1 ? Infinity : text.indexOf('['),
    );
    if (start === Infinity) return null;
    const end = Math.max(text.lastIndexOf('}'), text.lastIndexOf(']'));
    if (end <= start) return null;
    try {
      return JSON.parse(text.slice(start, end + 1));
    } catch (_) {
      return null;
    }
  }
}

const MAX_LIST_ITEMS = 6;
const MAX_ITEM_LEN = 400;
const MAX_SUMMARY_LEN = 1200;
const MAX_ANSWER_LEN = 1500;

function cleanString(v: unknown, maxLen: number): string | null {
  if (typeof v !== 'string') return null;
  const s = String(v).trim();
  if (!s || s.length > maxLen) return null;
  return s;
}

function cleanStringList(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  const items: string[] = [];
  for (const item of v) {
    const s = cleanString(item, MAX_ITEM_LEN);
    if (s) {
      items.push(s);
      if (items.length >= MAX_LIST_ITEMS) break;
    }
  }
  return items;
}

/**
 * Validate + normalize the Generate Insights response from Gemini.
 * Returns null when the payload is malformed so the caller can fail safely.
 */
export function validateInsightsResponse(data: unknown): AiInsightsResponse | null {
  if (!data || typeof data !== 'object') return null;
  const obj = data as Record<string, unknown>;
  const summary = cleanString(obj['summary'], MAX_SUMMARY_LEN);
  if (!summary) return null;
  // Present-but-wrong-typed list fields are malformed — reject rather than
  // silently substituting empty lists (defense against prompt injection).
  for (const key of ['trends', 'attention', 'recommendations'] as const) {
    const v = obj[key];
    if (v !== undefined && v !== null && !Array.isArray(v)) return null;
  }
  return {
    summary,
    trends: cleanStringList(obj['trends']),
    attention: cleanStringList(obj['attention']),
    recommendations: cleanStringList(obj['recommendations']),
  };
}

/**
 * Validate + normalize the Ask AI response from Gemini. Returns null when
 * malformed so the caller can fail safely.
 */
export function validateAskResponse(data: unknown): AiAskResponse | null {
  if (!data || typeof data !== 'object') return null;
  const obj = data as Record<string, unknown>;
  const answer = cleanString(obj['answer'], MAX_ANSWER_LEN);
  if (!answer) return null;
  const intent = cleanString(obj['intent'], 60) ?? 'other';
  return { answer, intent };
}