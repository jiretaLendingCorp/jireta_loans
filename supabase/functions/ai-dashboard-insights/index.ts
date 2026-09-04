// supabase/functions/ai-dashboard-insights/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// AI-Powered Dashboard Insights + Ask AI for the Head Manager dashboard.
//
// Architecture (per spec):
//   Flutter Dashboard
//     ↓ Supabase Auth
//   Deno Supabase Edge Function
//     ↓ Authenticate user (requireAuth)
//     ↓ Verify role / permission (head_manager only)
//     ↓ Retrieve approved dashboard statistics (shared with kpi-view — the
//       exact same queries the dashboard renders, no duplicated DB logic)
//     ↓ Sanitize / aggregate data (aggregated numbers only, zero PII)
//     ↓ Gemini API (server-side; GEMINI_API_KEY stays in Supabase secrets)
//     ↓ Validate AI response (strict JSON schema)
//   Flutter Dashboard
//
// SECURITY:
//   • The Gemini API key lives only in Supabase Edge Function secrets.
//   • Gemini NEVER receives database credentials, tokens, or PII — only the
//     aggregated stat snapshot from sanitizeAiPayload().
//   • Gemini NEVER runs SQL — the Ask AI path uses a deterministic intent
//     allowlist, and sensitive-data questions are blocked before Gemini is
//     contacted.
//   • Rate limiting is per-user, configurable via env vars.
//   • Every request is audit-logged (user id, role, action, success/failure).
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { guardRateLimit } from '../_shared/rate_limiter.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { getHeadManagerDashboardStats } from '../_shared/dashboard_stats.ts';
import {
  AI_SYSTEM_PROMPT,
  AI_UNAVAILABLE_ANSWER,
  AI_CAPABILITIES_NOTE,
  SENSITIVE_REQUEST_RESPONSE,
  sanitizeAiPayload,
  formatStatsForPrompt,
  detectSensitiveRequest,
  classifyIntent,
  parseGeminiJson,
  validateInsightsResponse,
  validateAskResponse,
} from '../_shared/ai_helpers.ts';

// ── Config (env-driven, with sane defaults) ────────────────────────────────
function envInt(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

// Default: gemini-2.5-flash (stable, supports JSON output mode, good
// price-performance). Older names like gemini-2.0-flash were SHUT DOWN by
// Google — calling them returns HTTP 404 "model not found".
// Override per project with: supabase secrets set AI_GEMINI_MODEL=gemini-3.5-flash
const GEMINI_MODEL = Deno.env.get('AI_GEMINI_MODEL') ?? 'gemini-2.5-flash';
const GEMINI_TIMEOUT_MS = Math.min(
  envInt('AI_GEMINI_TIMEOUT_MS', 45000),
  50000,
);
// Per-user rate limits (window minutes + max attempts in that window).
const GENERATE_MAX = envInt('AI_GENERATE_MAX', 10);
const GENERATE_WINDOW = envInt('AI_GENERATE_WINDOW_MINUTES', 60);
const ASK_MAX = envInt('AI_ASK_MAX', 30);
const ASK_WINDOW = envInt('AI_ASK_WINDOW_MINUTES', 60);

// ── Gemini caller ──────────────────────────────────────────────────────────
interface GeminiResult {
  ok: boolean;
  text: string | null;
  status: number;
}

/**
 * Calls the Gemini REST API with JSON output mode. The key is read from
 * Deno.env — never from the client — and never echoed anywhere.
 */
async function callGemini(opts: {
  systemPrompt: string;
  userPrompt: string;
}): Promise<GeminiResult> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    console.error('[ai-dashboard-insights] GEMINI_API_KEY is not configured');
    return { ok: false, text: null, status: 503 };
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(GEMINI_MODEL)}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: opts.userPrompt }] }],
        systemInstruction: {
          parts: [{ text: opts.systemPrompt }],
        },
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 2048,
          responseMimeType: 'application/json',
        },
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      // 429 = quota/rate limit; 404 = model not found or wrong model name.
      // Never leak the API key or raw auth details to the client, but log the
      // API's own message so model-name issues are easy to diagnose.
      let bodySnippet: string | null = null;
      try {
        const raw = await res.text();
        bodySnippet = raw.slice(0, 300);
      } catch (_) { /* ignore read failure */ }
      console.error('[ai-dashboard-insights] Gemini HTTP error', {
        status: res.status,
        model: GEMINI_MODEL,
        bodySnippet,
      });
      return { ok: false, text: null, status: res.status };
    }

    const data = await res.json() as {
      candidates?: Array<{
        content?: { parts?: Array<{ text?: string }> };
      }>;
    };
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? null;
    return { ok: true, text, status: res.status };
  } catch (err) {
    const aborted = err instanceof DOMException && err.name === 'AbortError';
    console.error('[ai-dashboard-insights] Gemini call failed', {
      aborted,
      error: err instanceof Error ? err.message : 'unknown',
    });
    return { ok: false, text: null, status: aborted ? 504 : 502 };
  } finally {
    clearTimeout(timer);
  }
}

// ── Prompt builders ────────────────────────────────────────────────────────
function buildGeneratePrompt(stats: Record<string, unknown>): string {
  return `${formatStatsForPrompt(stats)}

Based EXCLUSIVELY on the verified statistics above, produce an analysis of the lending portfolio as strict JSON with exactly this shape:
{
  "summary": "one concise paragraph (2-4 sentences) summarizing overall performance",
  "trends": ["2-4 short bullet strings describing meaningful trends or notable changes"],
  "attention": ["1-3 short bullet strings flagging areas needing attention; if nothing needs attention say so"],
  "recommendations": ["2-4 short bullet strings with practical advisory recommendations"]
}

Rules:
- Use ONLY the numbers above. Never invent or modify figures.
- If a figure is 0 or the data is insufficient, say so plainly.
- Mention the period (month or lifetime) when relevant.
- No SQL, no credentials, no personal data. Advisory language only.`;
}

function buildAskPrompt(
  intent: string,
  question: string,
  stats: Record<string, unknown>,
): string {
  return `Intent: ${intent}
User question: "${question}"

${formatStatsForPrompt(stats)}

Answer the user's question using ONLY the verified statistics above.
Respond as strict JSON with exactly this shape:
{
  "answer": "a concise, friendly answer (1-3 sentences)",
  "intent": "${intent}"
}

Rules:
- Use ONLY the numbers above. Never invent or modify figures.
- If the question cannot be answered from the provided data, say that the available data is insufficient.
- If the question asks for individual borrower details, phone numbers, emails, addresses, IDs or payment credentials, answer with a polite refusal.
- ${AI_CAPABILITIES_NOTE}
- No SQL, no credentials.`;
}

// ── Action: generate insights ──────────────────────────────────────────────
async function handleGenerate(req: Request, auth: { id: string; role: string }, ip: string) {
  const db = getAdminClient();

  // Rate limit generate/regenerate together — one budget per user.
  const guard = await guardRateLimit({
    key: `ai:generate:${auth.id}`,
    maxAttempts: GENERATE_MAX,
    windowMinutes: GENERATE_WINDOW,
    blockMinutes: 30,
    blockReason: 'Too many AI insight requests',
    eventType: 'ai_generate_rate_limited',
    userId: auth.id,
    ipAddress: ip,
  });
  if (!guard.allowed) {
    return errorResponse(
      'Too many AI requests. Please try again later.',
      429,
      'RATE_LIMITED',
    );
  }

  let month: string | null = null;
  try {
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    const rawMonth = body?.month;
    if (rawMonth != null && rawMonth !== '') {
      if (typeof rawMonth !== 'string' || !/^\d{4}-\d{2}$/.test(rawMonth)) {
        return errorResponse('Invalid month. Expected YYYY-MM.', 400, 'VALIDATION_ERROR');
      }
      month = rawMonth;
    }
  } catch (_) {
    // Missing/invalid body — month stays null (lifetime).
  }

  try {
    // Retrieve the SAME aggregated stats the dashboard renders.
    const stats = await getHeadManagerDashboardStats(db, { month });
    const safeStats = sanitizeAiPayload(stats);

    const gemini = await callGemini({
      systemPrompt: AI_SYSTEM_PROMPT,
      userPrompt: buildGeneratePrompt(safeStats),
    });

    if (!gemini.ok || !gemini.text) {
      await writeAuditLog({
        performedBy: auth.id,
        action: 'ai_insights_generate',
        tableName: 'ai_insights',
        recordId: crypto.randomUUID(),
        newValues: { success: false, month, reason: 'gemini_unavailable' },
        ipAddress: ip,
      });
      return errorResponse(
        'Unable to generate AI insights right now. Please try again.',
        502,
        'AI_UNAVAILABLE',
      );
    }

    const parsed = parseGeminiJson(gemini.text);
    const insights = validateInsightsResponse(parsed);
    if (!insights) {
      console.error('[ai-dashboard-insights] malformed Gemini insights payload');
      await writeAuditLog({
        performedBy: auth.id,
        action: 'ai_insights_generate',
        tableName: 'ai_insights',
        recordId: crypto.randomUUID(),
        newValues: { success: false, month, reason: 'malformed_response' },
        ipAddress: ip,
      });
      return errorResponse(
        'Unable to generate AI insights right now. Please try again.',
        502,
        'AI_RESPONSE_INVALID',
      );
    }

    const generatedAt = new Date().toISOString();
    await writeAuditLog({
      performedBy: auth.id,
      action: 'ai_insights_generate',
      tableName: 'ai_insights',
      recordId: crypto.randomUUID(),
      newValues: { success: true, month },
      ipAddress: ip,
    });

    return jsonResponse({
      success: true,
      insights,
      generated_at: generatedAt,
      month: stats['selected_month'] ?? null,
      period: stats['period'] ?? 'lifetime',
      disclaimer: AI_CAPABILITIES_NOTE,
    }, 200, req);
  } catch (err) {
    console.error('[ai-dashboard-insights] generate error:', err);
    await writeAuditLog({
      performedBy: auth.id,
      action: 'ai_insights_generate',
      tableName: 'ai_insights',
      recordId: crypto.randomUUID(),
      newValues: { success: false, month, reason: 'internal_error' },
      ipAddress: ip,
    });
    return errorResponse(
      'Unable to generate AI insights right now. Please try again.',
      500,
      'SERVER_ERROR',
    );
  }
}

// ── Diagnostic: list available Gemini models ───────────────────────────────
// Read-only helper used to debug "model not found" (404) errors: returns the
// model names this project's key can access. Only names are returned — the
// key itself never leaves the edge function and is never echoed.
async function handleModels(req: Request, auth: { id: string; role: string }, ip: string) {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    return errorResponse('GEMINI_API_KEY is not configured', 503, 'AI_NOT_CONFIGURED');
  }
  // Light per-user throttle so this cannot be used to hammer Google.
  const guard = await guardRateLimit({
    key: `ai:models:${auth.id}`,
    maxAttempts: 10,
    windowMinutes: 60,
    blockMinutes: 30,
    blockReason: 'Too many AI model-list requests',
    eventType: 'ai_models_rate_limited',
    userId: auth.id,
    ipAddress: ip,
  });
  if (!guard.allowed) {
    return errorResponse('Too many requests. Please try again later.', 429, 'RATE_LIMITED');
  }

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`,
      { headers: { 'Content-Type': 'application/json' } },
    );
    if (!res.ok) {
      console.error('[ai-dashboard-insights] models list error', { status: res.status });
      return errorResponse('Unable to list AI models', 502, 'AI_UNAVAILABLE');
    }
    const data = await res.json() as { models?: Array<{ name?: string }> };
    const names = (data.models ?? [])
      .map((m) => (m.name ?? '').replace(/^models\//, ''))
      .filter((n) => n.includes('gemini') || n.includes('flash') || n.includes('pro'))
      .sort();
    return jsonResponse({ success: true, model: GEMINI_MODEL, models: names }, 200, req);
  } catch (err) {
    console.error('[ai-dashboard-insights] models list failed:', err);
    return errorResponse('Unable to list AI models', 502, 'AI_UNAVAILABLE');
  }
}

// ── Action: ask AI ─────────────────────────────────────────────────────────
async function handleAsk(req: Request, auth: { id: string; role: string }, ip: string) {
  const db = getAdminClient();

  let question = '';
  let month: string | null = null;
  try {
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (typeof body?.question !== 'string' || body.question.trim().length === 0) {
      return errorResponse('Question is required', 400, 'VALIDATION_ERROR');
    }
    if (body.question.trim().length > 500) {
      return errorResponse('Question is too long (max 500 characters)', 400, 'VALIDATION_ERROR');
    }
    question = body.question.trim();
    const rawMonth = body?.month;
    if (rawMonth != null && rawMonth !== '') {
      if (typeof rawMonth !== 'string' || !/^\d{4}-\d{2}$/.test(rawMonth)) {
        return errorResponse('Invalid month. Expected YYYY-MM.', 400, 'VALIDATION_ERROR');
      }
      month = rawMonth;
    }
  } catch (_) {
    return errorResponse('Invalid request body', 400, 'VALIDATION_ERROR');
  }

  // Safe-response short circuit for sensitive requests — Gemini is NOT called.
  if (detectSensitiveRequest(question)) {
    await writeAuditLog({
      performedBy: auth.id,
      action: 'ai_ask',
      tableName: 'ai_insights',
      recordId: crypto.randomUUID(),
      newValues: { success: true, intent: 'blocked_sensitive', month },
      ipAddress: ip,
    });
    return jsonResponse({
      success: true,
      answer: SENSITIVE_REQUEST_RESPONSE,
      intent: 'blocked_sensitive',
      generated_at: new Date().toISOString(),
    }, 200, req);
  }

  const guard = await guardRateLimit({
    key: `ai:ask:${auth.id}`,
    maxAttempts: ASK_MAX,
    windowMinutes: ASK_WINDOW,
    blockMinutes: 30,
    blockReason: 'Too many AI questions',
    eventType: 'ai_ask_rate_limited',
    userId: auth.id,
    ipAddress: ip,
  });
  if (!guard.allowed) {
    return errorResponse(
      'Too many AI requests. Please try again later.',
      429,
      'RATE_LIMITED',
    );
  }

  const intent = classifyIntent(question);

  try {
    const stats = await getHeadManagerDashboardStats(db, { month });
    const safeStats = sanitizeAiPayload(stats);

    const gemini = await callGemini({
      systemPrompt: AI_SYSTEM_PROMPT,
      userPrompt: buildAskPrompt(intent, question, safeStats),
    });

    if (!gemini.ok || !gemini.text) {
      await writeAuditLog({
        performedBy: auth.id,
        action: 'ai_ask',
        tableName: 'ai_insights',
        recordId: crypto.randomUUID(),
        newValues: { success: false, intent, month, reason: 'gemini_unavailable' },
        ipAddress: ip,
      });
      return jsonResponse({
        success: true,
        answer: AI_UNAVAILABLE_ANSWER,
        intent,
        generated_at: new Date().toISOString(),
      }, 200, req);
    }

    const parsed = parseGeminiJson(gemini.text);
    const result = validateAskResponse(parsed);
    if (!result) {
      console.error('[ai-dashboard-insights] malformed Gemini ask payload');
      await writeAuditLog({
        performedBy: auth.id,
        action: 'ai_ask',
        tableName: 'ai_insights',
        recordId: crypto.randomUUID(),
        newValues: { success: false, intent, month, reason: 'malformed_response' },
        ipAddress: ip,
      });
      return jsonResponse({
        success: true,
        answer: AI_UNAVAILABLE_ANSWER,
        intent,
        generated_at: new Date().toISOString(),
      }, 200, req);
    }

    await writeAuditLog({
      performedBy: auth.id,
      action: 'ai_ask',
      tableName: 'ai_insights',
      recordId: crypto.randomUUID(),
      newValues: { success: true, intent: result.intent, month },
      ipAddress: ip,
    });

    return jsonResponse({
      success: true,
      answer: result.answer,
      intent: result.intent,
      generated_at: new Date().toISOString(),
    }, 200, req);
  } catch (err) {
    console.error('[ai-dashboard-insights] ask error:', err);
    await writeAuditLog({
      performedBy: auth.id,
      action: 'ai_ask',
      tableName: 'ai_insights',
      recordId: crypto.randomUUID(),
      newValues: { success: false, intent, month, reason: 'internal_error' },
      ipAddress: ip,
    });
    return jsonResponse({
      success: true,
      answer: AI_UNAVAILABLE_ANSWER,
      intent,
      generated_at: new Date().toISOString(),
    }, 200, req);
  }
}

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    // ── Authenticate + authorize (server-side, never trusts the client) ────
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const ip = clientIp(req);
    const fn = new URL(req.url).searchParams.get('fn') ?? 'generate';
    const auth = { id: authResult.id, role: authResult.role };

    switch (fn) {
      case 'generate':
        return await handleGenerate(req, auth, ip);
      case 'ask':
        return await handleAsk(req, auth, ip);
      case 'models':
        return await handleModels(req, auth, ip);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('ai-dashboard-insights error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});