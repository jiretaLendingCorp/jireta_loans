// supabase/functions/auth-password/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   auth-forgot-password         →  ?fn=forgot-password
//   auth-reset-password          →  ?fn=reset-password
//   auth-force-change-password   →  ?fn=force-change-password
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { writeAuditLog, sanitizeIpAddress } from "../_shared/audit.ts";
import { isAuthUser, requireAuth } from "../_shared/auth.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { getAdminClient, getAnonClient } from "../_shared/db.ts";
import { sendPasswordResetEmail } from "../_shared/email.ts";
import { hashPassword, matchesPasswordHistory } from "../_shared/password_hash.ts";
import { checkRateLimit, checkBlock, blockKey, recordSecurityEvent } from "../_shared/rate_limiter.ts";
import { singleWithObjectEmbeds } from "../_shared/types.ts";
import {
  sanitizeString,
  validateEmail,
  validatePasswordComplexity,
} from "../_shared/validators.ts";

// ── [moved from auth-force-change-password] ─────────────────────────────────
const PASSWORD_HISTORY_LIMIT = 5;

// Abuse detection: repeated password-reset requests for the same email or
// from the same IP are flagged as suspicious. Beyond the per-email window the
// account is temporarily blocked and a security event is recorded.
const FORGOT_WINDOW_MINUTES = 15;
const FORGOT_MAX_PER_EMAIL = 3;
const FORGOT_MAX_PER_IP = 10;
const FORGOT_BLOCK_MINUTES = 60;

function clientIp(req: Request): string {
  return req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = "forgot-password";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get("fn") ?? DEFAULT_ACTION;
    switch (fn) {
      case "forgot-password":
        // ── [moved from functions/auth-forgot-password/index.ts] ─────────
        return await handleForgotPassword(req);
      case "reset-password":
        // ── [moved from functions/auth-reset-password/index.ts] ──────────
        return await handleResetPassword(req);
      case "force-change-password":
        // ── [moved from functions/auth-force-change-password/index.ts] ───
        return await handleForceChangePassword(req);
      case "change-password":
        // Voluntary password change (lender/employee/head-manager self-service).
        // Unlike force-change-password it does NOT require force_password_change.
        return await handleChangePassword(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, "NOT_FOUND");
    }
  } catch (err) {
    console.error("auth-password error:", err);
    return errorResponse("Internal server error", 500, "SERVER_ERROR");
  }
});

// ── [moved from functions/auth-forgot-password/index.ts] ────────────────────
// UPDATED: Now sends the reset link via Resend (third-party API) when
// RESEND_API_KEY is configured. Falls back to Supabase's built-in
// resetPasswordForEmail in local dev (Inbucket) or when Resend fails.
async function handleForgotPassword(req: Request) {
  const body = await req.json().catch(() => ({}));
  const { email } = body as { email?: unknown };
  if (!email) {
    return errorResponse("Email is required", 400, "VALIDATION_ERROR");
  }

  const cleanEmail = sanitizeString(email).toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse("Invalid email format", 400, "VALIDATION_ERROR");
  }

  const ip = clientIp(req);

  // Abuse detection: block if this email or IP was already flagged.
  const emailBlock = await checkBlock(`forgot:${cleanEmail}`);
  if (emailBlock.blocked) {
    return errorResponse(
      "Too many reset requests for this account. Try again in an hour.",
      429,
      "PASSWORD_RESET_RATE_LIMITED",
    );
  }
  const ipBlock = await checkBlock(`forgot:ip:${ip}`);
  if (ipBlock.blocked) {
    return errorResponse(
      "Too many reset requests from this device. Try again later.",
      429,
      "PASSWORD_RESET_RATE_LIMITED",
    );
  }

  // Per-email: up to 3 reset requests / 15 min.
  const { allowed } = await checkRateLimit({
    key: `forgot_password:${cleanEmail}`,
    maxAttempts: FORGOT_MAX_PER_EMAIL,
    windowMinutes: FORGOT_WINDOW_MINUTES,
  });
  if (!allowed) {
    await blockKey({
      key: `forgot:${cleanEmail}`,
      reason: "Multiple password reset requests",
      minutes: FORGOT_BLOCK_MINUTES,
    });
    await recordSecurityEvent({
      eventType: "password_reset_suspicious",
      key: `forgot:${cleanEmail}`,
      ipAddress: ip,
      detail: { attempts: FORGOT_MAX_PER_EMAIL, windowMinutes: FORGOT_WINDOW_MINUTES },
    });
    return errorResponse(
      "Too many reset requests for this account. Try again in an hour.",
      429,
      "PASSWORD_RESET_RATE_LIMITED",
    );
  }

  // Per-IP: up to 10 reset requests / 15 min
  const ipResult = await checkRateLimit({
    key: `forgot:ip:${ip}`,
    maxAttempts: FORGOT_MAX_PER_IP,
    windowMinutes: FORGOT_WINDOW_MINUTES,
  });
  if (!ipResult.allowed) {
    await blockKey({
      key: `forgot:ip:${ip}`,
      reason: "Password reset flooding from single device/IP",
      minutes: FORGOT_BLOCK_MINUTES,
    });
    await recordSecurityEvent({
      eventType: "password_reset_suspicious",
      key: `forgot:ip:${ip}`,
      ipAddress: ip,
      detail: { attempts: FORGOT_MAX_PER_IP, windowMinutes: FORGOT_WINDOW_MINUTES },
    });
    return errorResponse(
      "Too many reset requests from this device. Try again later.",
      429,
      "PASSWORD_RESET_RATE_LIMITED",
    );
  }

  const db = getAdminClient();

  const { data: userRow } = await db
    .from("users")
    .select("id, account_status, first_name, last_name, roles!inner(name)")
    .eq("email", cleanEmail)
    .maybeSingle();
  const user = singleWithObjectEmbeds(userRow);

  // Anti-enumeration: same generic response when not found / wrong role / inactive
  // This matches the spec flow: "Email not registered → Generic response: If an account exists, we'll send a reset link."
  // Do NOT reveal whether the email exists or which role it has.
  if (!user || !["head_manager", "employee"].includes(user?.roles?.name)) {
    return jsonResponse({
      message: "If an account exists, we'll send a reset link.",
    });
  }

  if (user.account_status !== "active") {
    return jsonResponse({
      message: "If an account exists, we'll send a reset link.",
    });
  }

  const appUrl = Deno.env.get("APP_URL") ?? Deno.env.get("SITE_URL") ?? "https://app.jiretaloanscorp.com";
  const redirectTo = `${appUrl.replace(/\/$/, "")}/reset-password`;
  const resendApiKey = Deno.env.get("RESEND_API_KEY");

  // ── Primary path: Resend via generateLink ──────────────────────────────────
  if (resendApiKey) {
    try {
      const { data: linkData, error: linkError } = await db.auth.admin.generateLink({
        type: "recovery",
        email: cleanEmail,
        options: { redirectTo },
      });

      const actionLink = (linkData as unknown as { properties?: { action_link?: string } })?.properties?.action_link
        ?? (linkData as unknown as { action_link?: string })?.action_link;

      if (linkError || !actionLink) {
        console.error("[forgot-password] generateLink failed:", linkError?.message ?? "no action_link", linkError);
        // Fallback to Supabase built-in email so user still gets a reset
        const { error: fbErr } = await db.auth.resetPasswordForEmail(cleanEmail, { redirectTo });
        if (!fbErr) {
          try {
            await db.from("auth_logs").insert({
              user_id: user.id,
              event_type: "password_reset_requested",
              ip_address: ip,
            });
          } catch (_) { /* no-op */ }
          console.log("[forgot-password] fallback Supabase email sent for", cleanEmail);
        } else {
          console.error("[forgot-password] fallback also failed:", fbErr.message);
        }
        return jsonResponse({
          message: "If an account exists, we'll send a reset link.",
        });
      }

      const recipientName = [user.first_name, user.last_name].filter(Boolean).join(" ") || undefined;
      const sendResult = await sendPasswordResetEmail({
        to: cleanEmail,
        resetLink: actionLink,
        recipientName,
      });

      if (!sendResult.ok) {
        console.error("[forgot-password] Resend failed, falling back to Supabase email:", sendResult.error);
        const { error: fbErr } = await db.auth.resetPasswordForEmail(cleanEmail, { redirectTo });
        if (!fbErr) {
          console.log("[forgot-password] fallback Supabase email sent after Resend failure");
        } else {
          console.error("[forgot-password] fallback Supabase email also failed:", fbErr.message);
        }
      } else {
        console.log(`[forgot-password] Reset email via Resend sent to ${cleanEmail} id=${sendResult.id}`);
      }

      try {
        await db.from("auth_logs").insert({
          user_id: user.id,
          event_type: "password_reset_requested",
          ip_address: ip,
        });
      } catch (e) {
        console.error("[forgot-password] auth_logs insert failed:", e);
      }

      return jsonResponse({
        message: "If an account exists, we'll send a reset link.",
      });
    } catch (e) {
      console.error("[forgot-password] Resend path exception:", e);
      // Last-resort fallback to Supabase email
      try {
        const { error: fbErr } = await db.auth.resetPasswordForEmail(cleanEmail, { redirectTo });
        if (!fbErr) {
          try {
            await db.from("auth_logs").insert({
              user_id: user.id,
              event_type: "password_reset_requested",
              ip_address: ip,
            });
          } catch (_) { /* no-op */ }
        }
      } catch (_) { /* no-op */ }
      return jsonResponse({
        message: "If an account exists, we'll send a reset link.",
      });
    }
  }

  // ── Fallback: no RESEND_API_KEY (local dev / Inbucket) ─────────────────────
  console.warn("[forgot-password] RESEND_API_KEY not set — using Supabase built-in email (Inbucket in local dev)");
  const { error } = await db.auth.resetPasswordForEmail(cleanEmail, { redirectTo });

  if (error) {
    console.error("[forgot-password] resetPasswordForEmail error:", error.message);
    // Still return generic to avoid enumeration (spec flow requirement)
    return jsonResponse({
      message: "If an account exists, we'll send a reset link.",
    });
  }

  try {
    await db.from("auth_logs").insert({
      user_id: user.id,
      event_type: "password_reset_requested",
      ip_address: ip,
    });
  } catch (_) { /* no-op */ }

  return jsonResponse({
    message: "If an account exists, we'll send a reset link.",
  });
}

// ── [moved from functions/auth-reset-password/index.ts] ─────────────────────
// UPDATED: Supports multiple token formats so the Resend-generated
// `action_link` (PKCE `code`, `token_hash`, legacy userId, or JWT
// access_token) all work. Falls back to legacy UUID path for backwards
// compat.
async function handleResetPassword(req: Request) {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  // Accept `token`, `code`, `token_hash`, or `access_token` from various clients
  const rawToken = (body["token"] ?? body["code"] ?? body["token_hash"] ?? body["access_token"]) as string | undefined;
  const new_password = body["new_password"] as string | undefined;

  if (!rawToken || !new_password) {
    return errorResponse(
      "Token and new_password are required",
      400,
      "VALIDATION_ERROR",
    );
  }

  const pw = sanitizeString(new_password);
  const check = validatePasswordComplexity(pw);
  if (!check.valid) {
    return errorResponse(check.message!, 400, "VALIDATION_ERROR");
  }

  const db = getAdminClient();
  const anon = getAnonClient();
  let userId: string | null = null;
  const token = String(rawToken).trim();

  // 1) Try recovery token_hash via verifyOtp (used by Resend generateLink)
  if (!userId && token.length > 20) {
    try {
      const verify = (anon.auth as unknown as { verifyOtp: (p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }> }).verifyOtp;
      const { data, error } = await verify({ token_hash: token, type: "recovery" });
      if (!error && (data as { user?: { id?: string } })?.user?.id) {
        userId = (data as { user: { id: string } }).user.id;
        console.log("[reset-password] verified via token_hash recovery");
      } else if (error) {
        // Not a token_hash — will try other methods
      }
    } catch (_) { /* no-op */ }
  }

  // 2) Try PKCE code exchange (new Supabase flow: ?code=xxx)
  if (!userId && token.length > 20) {
    try {
      const exchange = (anon.auth as unknown as { exchangeCodeForSession: (c: string) => Promise<{ data: unknown; error: unknown }> }).exchangeCodeForSession;
      if (exchange) {
        const { data, error } = await exchange(token);
        if (!error && (data as { user?: { id?: string } })?.user?.id) {
          userId = (data as { user: { id: string } }).user.id;
          console.log("[reset-password] exchanged PKCE code for session");
        } else if (!error && (data as { session?: { user?: { id?: string } } })?.session?.user?.id) {
          userId = (data as { session: { user: { id: string } } }).session.user.id;
          console.log("[reset-password] exchanged PKCE code for session (session.user)");
        }
      }
    } catch (_) { /* no-op */ }
  }

  // 3) Try JWT access_token via getUser(token)
  if (!userId && token.includes(".")) {
    try {
      const { data, error } = await anon.auth.getUser(token);
      if (!error && data?.user?.id) {
        userId = data.user.id;
        console.log("[reset-password] verified via JWT access_token");
      }
    } catch (_) { /* no-op */ }
    // Also try admin getUser with token as JWT
    if (!userId) {
      try {
        const { data, error } = await db.auth.getUser(token);
        if (!error && data?.user?.id) userId = data.user.id;
      } catch (_) { /* no-op */ }
    }
  }

  // 4) Legacy: token is a UUID userId (old app behaviour)
  if (!userId && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token)) {
    try {
      const { data, error } = await db.auth.admin.getUserById(token);
      if (!error && data?.user?.id) {
        userId = data.user.id;
        console.log("[reset-password] verified via legacy UUID");
      }
    } catch (_) { /* no-op */ }
  }

  // 5) Last attempt: treat token as hashed_token / otp and try verifyOtp with email-type
  if (!userId) {
    for (const t of ["recovery", "email"] as const) {
      try {
        const verify2 = (anon.auth as unknown as { verifyOtp: (p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }> }).verifyOtp;
        const { data, error } = await verify2({ token_hash: token, type: t });
        if (!error && (data as { user?: { id?: string } })?.user?.id) {
          userId = (data as { user: { id: string } }).user.id;
          console.log(`[reset-password] verified via token_hash type=${t}`);
          break;
        }
      } catch (_) { /* no-op */ }
    }
  }

  if (!userId) {
    return errorResponse(
      "Invalid or expired reset token",
      400,
      "INVALID_TOKEN",
    );
  }

  // Check password history BEFORE updating (prevent reuse)
  try {
    const { data: history } = await db
      .from("password_history")
      .select("password_hash")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(PASSWORD_HISTORY_LIMIT);
    for (const h of (history as { password_hash: string }[] | null) ?? []) {
      if (await matchesPasswordHistory(userId, pw, h.password_hash)) {
        return errorResponse(
          `Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`,
          400,
          "PASSWORD_REUSE",
        );
      }
    }
  } catch (_) { /* no-op */ }

  const { error: updateError } = await db.auth.admin.updateUserById(userId, {
    password: pw,
  });
  if (updateError) {
    console.error("[reset-password] updateUserById failed:", updateError);
    return errorResponse("Failed to reset password", 500, "SERVER_ERROR");
  }

  try {
    await db.from("password_history").insert({
      user_id: userId,
      password_hash: await hashPassword(userId, pw),
    });
  } catch (e) { console.error("[reset-password] password_history insert failed:", e); }

  try {
    await writeAuditLog({
      performedBy: userId,
      action: "password_reset",
      tableName: "users",
      recordId: userId,
      ipAddress: req.headers.get("x-forwarded-for") ?? "unknown",
    });
  } catch (_) { /* no-op */ }

  // Also clear force_password_change if set
  try {
    await db.from("users").update({ force_password_change: false }).eq("id", userId);
  } catch (_) { /* no-op */ }

  return jsonResponse({ message: "Password reset successfully" });
}

// ── [moved from functions/auth-force-change-password/index.ts] ──────────────
async function handleForceChangePassword(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  // FIX: Flutter sends both `current_password` and `new_password`.
  // The previous version only read `new_password` and never validated
  // `current_password`, meaning anyone with a valid JWT could change any
  // account's password without knowing the old one.
  const { current_password, new_password } = await req.json();

  if (!new_password) {
    return errorResponse("new_password is required", 400, "VALIDATION_ERROR");
  }
  if (!current_password) {
    return errorResponse(
      "current_password is required",
      400,
      "VALIDATION_ERROR",
    );
  }

  const cleanNew = sanitizeString(new_password);
  const complexity = validatePasswordComplexity(cleanNew);
  if (!complexity.valid) {
    return errorResponse(complexity.message!, 400, "VALIDATION_ERROR");
  }

  // Verify the current password is correct before allowing the change.
  // Use the anon client (signInWithPassword) — it validates against auth.users.
  // Lenders/riders authenticate by PHONE (staff-created temp email is an
  // internal GoTrue credential); staff authenticate by EMAIL. Try the
  // identifier the account actually uses, falling back to the other if needed.
  const anonClient = getAnonClient();
  const verifyWithPhone = async (phone: string, password: string) => {
    const { error } = await anonClient.auth.signInWithPassword({ phone, password });
    return !error;
  };
  const verifyWithEmail = async (email: string, password: string) => {
    const { error } = await anonClient.auth.signInWithPassword({ email, password });
    return !error;
  };

  const passwordValid =
    (!!authResult.phone &&
      (await verifyWithPhone(authResult.phone, current_password))) ||
    (!!authResult.email &&
      (await verifyWithEmail(authResult.email, current_password)));

  if (!passwordValid) {
    return errorResponse(
      "Current password is incorrect",
      401,
      "INVALID_CREDENTIALS",
    );
  }

  const db = getAdminClient();

  const { data: user } = await db
    .from("users")
    .select("id, force_password_change")
    .eq("id", authResult.id)
    .single();

  if (!user) return errorResponse("User not found", 404, "NOT_FOUND");
  if (!user.force_password_change) {
    return errorResponse(
      "Password change not required",
      400,
      "VALIDATION_ERROR",
    );
  }

  // Check password history
  const { data: history } = await db
    .from("password_history")
    .select("password_hash")
    .eq("user_id", authResult.id)
    .order("created_at", { ascending: false })
    .limit(PASSWORD_HISTORY_LIMIT);

  for (const h of history ?? []) {
    if (await matchesPasswordHistory(authResult.id, cleanNew, h.password_hash)) {
      return errorResponse(
        `Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`,
        400,
        "PASSWORD_REUSE",
      );
    }
  }

  const { error: updateErr } = await db.auth.admin.updateUserById(
    authResult.id,
    {
      password: cleanNew,
    },
  );

  if (updateErr) {
    return errorResponse("Failed to update password", 500, "SERVER_ERROR");
  }

  await db.from("users")
    .update({ force_password_change: false })
    .eq("id", authResult.id);

  await db.from("password_history").insert({
    user_id: authResult.id,
    password_hash: await hashPassword(authResult.id, cleanNew),
  });

  await db.from("auth_logs").insert({
    user_id: authResult.id,
    event_type: "force_password_changed",
    ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")),
  });

  await writeAuditLog({
    performedBy: authResult.id,
    action: "force_password_changed",
    tableName: "users",
    recordId: authResult.id,
    ipAddress: req.headers.get("x-forwarded-for") ?? undefined,
  });

  return jsonResponse({ message: "Password changed successfully" });
}

// ── [auth change-password] ───────────────────────────────────────────────────
// Voluntary self-service password change. Available to any authenticated user
// (lender, employee, or head manager). Verifies the current password through
// Supabase auth before updating, records the change, and enforces the password
// history rule. Does NOT require force_password_change to be set.
async function handleChangePassword(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const { current_password, new_password } = await req.json();

  if (!current_password) {
    return errorResponse("current_password is required", 400, "VALIDATION_ERROR");
  }
  if (!new_password) {
    return errorResponse("new_password is required", 400, "VALIDATION_ERROR");
  }

  const cleanNew = sanitizeString(new_password);
  const complexity = validatePasswordComplexity(cleanNew);
  if (!complexity.valid) {
    return errorResponse(complexity.message!, 400, "VALIDATION_ERROR");
  }

  // Verify the current password first. Lenders and riders authenticate by
  // PHONE (their effective credential is OTP_<phone>_SECURE or the password
  // they previously set); staff authenticate by EMAIL. Try the identifier the
  // account actually uses, falling back to the other only if needed.
  const anonClient = getAnonClient();
  const verifyWithPhone = async (phone: string, password: string) => {
    const { error } = await anonClient.auth.signInWithPassword({ phone, password });
    return !error;
  };
  const verifyWithEmail = async (email: string, password: string) => {
    const { error } = await anonClient.auth.signInWithPassword({ email, password });
    return !error;
  };

  const passwordValid =
    (!!authResult.phone &&
      (await verifyWithPhone(authResult.phone, current_password))) ||
    (!!authResult.email &&
      (await verifyWithEmail(authResult.email, current_password)));

  if (!passwordValid) {
    return errorResponse(
      "Current password is incorrect",
      401,
      "INVALID_CREDENTIALS",
    );
  }

  const db = getAdminClient();

  // Check password history before allowing a reuse.
  const { data: history } = await db
    .from("password_history")
    .select("password_hash")
    .eq("user_id", authResult.id)
    .order("created_at", { ascending: false })
    .limit(PASSWORD_HISTORY_LIMIT);

  for (const h of history ?? []) {
    if (await matchesPasswordHistory(authResult.id, cleanNew, h.password_hash)) {
      return errorResponse(
        `Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`,
        400,
        "PASSWORD_REUSE",
      );
    }
  }

  const { error: updateErr } = await db.auth.admin.updateUserById(
    authResult.id,
    {
      password: cleanNew,
    },
  );
  if (updateErr) {
    console.error("auth password update error:", updateErr);
    return errorResponse("Failed to update password", 500, "SERVER_ERROR");
  }

  // Clear the forced flag whenever the password is changed (even voluntarily).
  await db.from("users")
    .update({ force_password_change: false })
    .eq("id", authResult.id);

  await db.from("password_history").insert({
    user_id: authResult.id,
    password_hash: await hashPassword(authResult.id, cleanNew),
  });

  await db.from("auth_logs").insert({
    user_id: authResult.id,
    event_type: "password_changed",
    ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")),
  });

  await writeAuditLog({
    performedBy: authResult.id,
    action: "password_changed",
    tableName: "users",
    recordId: authResult.id,
    ipAddress: req.headers.get("x-forwarded-for") ?? undefined,
  });

  return jsonResponse({ message: "Password changed successfully" });
}
