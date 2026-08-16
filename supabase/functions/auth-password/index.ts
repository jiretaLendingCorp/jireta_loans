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
import { writeAuditLog } from "../_shared/audit.ts";
import { isAuthUser, requireAuth } from "../_shared/auth.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { getAdminClient, getAnonClient } from "../_shared/db.ts";
import { hashPassword, matchesPasswordHistory } from "../_shared/password_hash.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";
import { singleWithObjectEmbeds } from "../_shared/types.ts";
import {
  sanitizeString,
  validateEmail,
  validatePasswordComplexity,
} from "../_shared/validators.ts";

// ── [moved from auth-force-change-password] ─────────────────────────────────
const PASSWORD_HISTORY_LIMIT = 5;

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
async function handleForgotPassword(req: Request) {
  const { email } = await req.json();
  if (!email) {
    return errorResponse("Email is required", 400, "VALIDATION_ERROR");
  }

  const cleanEmail = sanitizeString(email).toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse("Invalid email format", 400, "VALIDATION_ERROR");
  }

  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const { allowed } = await checkRateLimit({
    key: `forgot_password:${cleanEmail}`,
    maxAttempts: 3,
    windowMinutes: 15,
  });
  if (!allowed) {
    return errorResponse(
      "Too many requests. Try again in 15 minutes.",
      429,
      "RATE_LIMITED",
    );
  }

  const db = getAdminClient();

  const { data: userRow } = await db
    .from("users")
    .select("id, account_status, roles!inner(name)")
    .eq("email", cleanEmail)
    .single();
  const user = singleWithObjectEmbeds(userRow);

  if (!user || !["head_manager", "employee"].includes(user?.roles?.name)) {
    return jsonResponse({
      message: "If that email is registered, a reset link has been sent.",
    });
  }

  if (user.account_status !== "active") {
    return jsonResponse({
      message: "If that email is registered, a reset link has been sent.",
    });
  }

  const { error } = await db.auth.resetPasswordForEmail(cleanEmail, {
    redirectTo: `${
      Deno.env.get("APP_URL") ?? "https://app.jiretaloanscorp.com"
    }/reset-password`,
  });

  if (!error) {
    await db.from("auth_logs").insert({
      user_id: user.id,
      event_type: "password_reset_requested",
      ip_address: ip,
    });
  }

  return jsonResponse({
    message: "If that email is registered, a reset link has been sent.",
  });
}

// ── [moved from functions/auth-reset-password/index.ts] ─────────────────────
async function handleResetPassword(req: Request) {
  const { token, new_password } = await req.json();
  if (!token || !new_password) {
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

  const { data, error } = await db.auth.admin.getUserById(token);
  if (error || !data.user) {
    return errorResponse(
      "Invalid or expired reset token",
      400,
      "INVALID_TOKEN",
    );
  }

  const userId = data.user.id;

  const { error: updateError } = await db.auth.admin.updateUserById(userId, {
    password: pw,
  });
  if (updateError) {
    return errorResponse("Failed to reset password", 500, "SERVER_ERROR");
  }

  await db.from("password_history").insert({
    user_id: userId,
    password_hash: await hashPassword(userId, pw),
  });

  await writeAuditLog({
    performedBy: userId,
    action: "password_reset",
    tableName: "users",
    recordId: userId,
    ipAddress: req.headers.get("x-forwarded-for") ?? "unknown",
  });

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
    ip_address: req.headers.get("x-forwarded-for") ?? "unknown",
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
    ip_address: req.headers.get("x-forwarded-for") ?? "unknown",
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
