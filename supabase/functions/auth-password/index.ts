// supabase/functions/auth-password/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — OTP-based password reset per spec:
//
//   User → Forgot Password → Enter email → Edge generates 6-digit OTP
//        → Hash + save → Resend → Gmail → User enters OTP → Verify → New Password
//
// Actions:
//   auth-forgot-password   →  ?fn=forgot-password   (send OTP)
//   auth-verify-otp        →  ?fn=verify-otp        (check OTP)
//   auth-reset-password    →  ?fn=reset-password    (OTP + new password)
//   auth-force-change-password → ?fn=force-change-password
//   auth-change-password   →  ?fn=change-password
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { writeAuditLog, sanitizeIpAddress } from "../_shared/audit.ts";
import { isAuthUser, requireAuth } from "../_shared/auth.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { getAdminClient, getAnonClient } from "../_shared/db.ts";
import { sendPasswordResetOtpEmail } from "../_shared/email.ts";
import { hashPassword, matchesPasswordHistory } from "../_shared/password_hash.ts";
import { checkRateLimit, checkBlock, blockKey, recordSecurityEvent } from "../_shared/rate_limiter.ts";
import { singleWithObjectEmbeds } from "../_shared/types.ts";
import {
  sanitizeString,
  validateEmail,
  validatePasswordComplexity,
} from "../_shared/validators.ts";

const PASSWORD_HISTORY_LIMIT = 5;

// Abuse detection
const FORGOT_WINDOW_MINUTES = 15;
const FORGOT_MAX_PER_EMAIL = 3;
const FORGOT_MAX_PER_IP = 10;
const FORGOT_BLOCK_MINUTES = 60;

// OTP settings (per spec: 6-digit, hashed, 1 min expiry, 5 attempts)
// deno-lint-ignore no-unused-vars
const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 1;
const OTP_MAX_ATTEMPTS = 5;
const MAX_LOCKOUT_MINUTES = 2 * 24 * 60; // 48h

function clientIp(req: Request): string {
  return req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
}

function generateOtp(): string {
  // Use crypto for secure random 6-digit
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  const n = 100000 + (arr[0] % 900000);
  return String(n);
}

async function hashOtp(otp: string, email: string): Promise<string> {
  const data = new TextEncoder().encode(`${otp}:${email.toLowerCase()}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function lockoutMinutes(attempts: number): number {
  if (attempts <= 2) return 0;
  if (attempts === 3) return 3;
  if (attempts === 4) return 10;
  return Math.min(MAX_LOCKOUT_MINUTES, 10 * Math.pow(10, attempts - 4));
}

async function readEmailLockout(db: ReturnType<typeof getAdminClient>, email: string) {
  const { data } = await db.from("email_otp_lockouts").select("failed_attempts, locked_until").eq("email", email).maybeSingle();
  return { failedAttempts: data?.failed_attempts ?? 0, lockedUntil: data?.locked_until ? new Date(data.locked_until) : null };
}

function lockoutError(lockedUntil: Date, attempts: number): Response {
  const retryAfterSeconds = Math.max(1, Math.ceil((lockedUntil.getTime() - Date.now()) / 1000));
  const minutes = Math.round(retryAfterSeconds / 60);
  const label = minutes > 0 ? `${minutes} minute(s)` : `${retryAfterSeconds} second(s)`;
  return errorResponse(`Too many wrong attempts. Try again in ${label}.`, 429, "OTP_LOCKED", {
    retry_after_seconds: retryAfterSeconds,
    locked_until: lockedUntil.toISOString(),
    failed_attempts: attempts,
  });
}

const DEFAULT_ACTION = "forgot-password";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const fn = new URL(req.url).searchParams.get("fn") ?? DEFAULT_ACTION;
    switch (fn) {
      case "forgot-password":
        return await handleForgotPassword(req);
      case "verify-otp":
        return await handleVerifyOtp(req);
      case "reset-password":
        return await handleResetPassword(req);
      case "force-change-password":
        return await handleForceChangePassword(req);
      case "change-password":
        return await handleChangePassword(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, "NOT_FOUND");
    }
  } catch (err) {
    console.error("auth-password error:", err);
    return errorResponse("Internal server error", 500, "SERVER_ERROR");
  }
});

// ── FORGOT PASSWORD: generate 6-digit OTP ───────────────────────────────────
async function handleForgotPassword(req: Request) {
  const body = await req.json().catch(() => ({}));
  const { email } = body as { email?: unknown };
  if (!email) return errorResponse("Email is required", 400, "VALIDATION_ERROR");
  const cleanEmail = sanitizeString(email).toLowerCase();
  if (!validateEmail(cleanEmail)) return errorResponse("Invalid email format", 400, "VALIDATION_ERROR");
  const ip = clientIp(req);

  // Block checks
  const emailBlock = await checkBlock(`forgot:${cleanEmail}`);
  if (emailBlock.blocked) return errorResponse("Too many reset requests for this account. Try again in an hour.", 429, "PASSWORD_RESET_RATE_LIMITED");
  const ipBlock = await checkBlock(`forgot:ip:${ip}`);
  if (ipBlock.blocked) return errorResponse("Too many reset requests from this device. Try again later.", 429, "PASSWORD_RESET_RATE_LIMITED");

  const { allowed } = await checkRateLimit({ key: `forgot_password:${cleanEmail}`, maxAttempts: FORGOT_MAX_PER_EMAIL, windowMinutes: FORGOT_WINDOW_MINUTES });
  if (!allowed) {
    await blockKey({ key: `forgot:${cleanEmail}`, reason: "Multiple password reset requests", minutes: FORGOT_BLOCK_MINUTES });
    await recordSecurityEvent({ eventType: "password_reset_suspicious", key: `forgot:${cleanEmail}`, ipAddress: ip, detail: { attempts: FORGOT_MAX_PER_EMAIL } });
    return errorResponse("Too many reset requests for this account. Try again in an hour.", 429, "PASSWORD_RESET_RATE_LIMITED");
  }
  const ipResult = await checkRateLimit({ key: `forgot:ip:${ip}`, maxAttempts: FORGOT_MAX_PER_IP, windowMinutes: FORGOT_WINDOW_MINUTES });
  if (!ipResult.allowed) {
    await blockKey({ key: `forgot:ip:${ip}`, reason: "Password reset flooding", minutes: FORGOT_BLOCK_MINUTES });
    await recordSecurityEvent({ eventType: "password_reset_suspicious", key: `forgot:ip:${ip}`, ipAddress: ip, detail: { attempts: FORGOT_MAX_PER_IP } });
    return errorResponse("Too many reset requests from this device. Try again later.", 429, "PASSWORD_RESET_RATE_LIMITED");
  }

  const db = getAdminClient();
  const { data: userRow } = await db.from("users").select("id, account_status, first_name, last_name, roles!inner(name)").eq("email", cleanEmail).maybeSingle();
  const user = singleWithObjectEmbeds(userRow);

  if (!user || !["head_manager", "employee"].includes(user?.roles?.name)) {
    return jsonResponse({ message: "If an account exists, we'll send a reset code." });
  }
  if (user.account_status !== "active") {
    return jsonResponse({ message: "If an account exists, we'll send a reset code." });
  }

  // Generate 6-digit OTP
  const otp = generateOtp();
  const otpHash = await hashOtp(otp, cleanEmail);
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60000).toISOString();

  // Invalidate previous unused OTPs and insert new one (trigger also does)
  try {
    await db.from("email_reset_otps").update({ used: true }).eq("email", cleanEmail).eq("used", false);
  } catch (_) { /* ignore update failure */ }
  const { error: insertErr } = await db.from("email_reset_otps").insert({
    user_id: user.id,
    email: cleanEmail,
    otp_hash: otpHash,
    expires_at: expiresAt,
    attempts: 0,
    used: false,
    verified: false,
  });
  if (insertErr) {
    console.error("[forgot-password] insert otp failed:", insertErr.message);
    return errorResponse("Failed to generate reset code", 500, "SERVER_ERROR");
  }

  // Send via Resend
  const recipientName = [user.first_name, user.last_name].filter(Boolean).join(" ") || undefined;
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (resendApiKey) {
    const sendResult = await sendPasswordResetOtpEmail({ to: cleanEmail, otp, recipientName });
    if (!sendResult.ok) console.error("[forgot-password] Resend OTP failed:", sendResult.error);
    else console.log(`[forgot-password] OTP via Resend sent to ${cleanEmail} id=${sendResult.id}`);
  } else {
    // Local dev — log OTP so Inbucket/console can see it
    console.log(`[forgot-password] OTP for ${cleanEmail} is ${otp} (RESEND_API_KEY not set, not emailed)`);
    // Also try Supabase built-in as fallback? No OTP template, so just log.
  }

  try {
    await db.from("auth_logs").insert({ user_id: user.id, event_type: "password_reset_requested", ip_address: ip });
  } catch (_) { /* ignore log failure */ }

  return jsonResponse({ message: "If an account exists, we'll send a reset code.", expires_in: OTP_EXPIRY_MINUTES * 60 });
}

// ── VERIFY OTP ───────────────────────────────────────────────────────────────
async function handleVerifyOtp(req: Request) {
  const body = await req.json().catch(() => ({}));
  const { email, otp, code } = body as { email?: unknown; otp?: unknown; code?: unknown };
  const cleanEmail = sanitizeString(email).toLowerCase();
  const cleanOtp = sanitizeString(otp ?? code);
  if (!cleanEmail || !cleanOtp) return errorResponse("Email and OTP are required", 400, "VALIDATION_ERROR");
  if (!validateEmail(cleanEmail)) return errorResponse("Invalid email format", 400, "VALIDATION_ERROR");
  if (!/^\d{6}$/.test(cleanOtp)) return errorResponse("OTP must be 6 digits", 400, "VALIDATION_ERROR");

  const db = getAdminClient();
  // Lockout check
  const lock = await readEmailLockout(db, cleanEmail);
  if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) return lockoutError(lock.lockedUntil, lock.failedAttempts);

  const { data: otpRow } = await db.from("email_reset_otps")
    .select("*")
    .eq("email", cleanEmail)
    .eq("used", false)
    .gte("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!otpRow) {
    // Record failure for lockout
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from("email_otp_lockouts").upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: "email" });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse("Invalid or expired OTP", 400, "INVALID_OTP");
  }

  if (otpRow.attempts >= OTP_MAX_ATTEMPTS) {
    await db.from("email_reset_otps").update({ used: true }).eq("id", otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from("email_otp_lockouts").upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: "email" });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse("Too many attempts. Request a new code.", 400, "INVALID_OTP");
  }

  const submittedHash = await hashOtp(cleanOtp, cleanEmail);
  if (otpRow.otp_hash !== submittedHash) {
    await db.from("email_reset_otps").update({ attempts: otpRow.attempts + 1 }).eq("id", otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from("email_otp_lockouts").upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: "email" });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse("Invalid OTP code", 400, "INVALID_OTP");
  }

  // Success — mark verified and EXTEND expiry so user has time to type new password
  // Original OTP is 1 minute, but after verification we give 10 minutes grace for the reset step.
  // Without this, if user verifies at 55s then spends 10s typing, reset would fail as "expired".
  const verifiedGraceExpiresAt = new Date(Date.now() + 10 * 60000).toISOString();
  await db.from("email_reset_otps").update({ verified: true, expires_at: verifiedGraceExpiresAt }).eq("id", otpRow.id);
  // Clear lockout
  await db.from("email_otp_lockouts").delete().eq("email", cleanEmail);

  return jsonResponse({ message: "OTP verified successfully", verified: true });
}

// ── RESET PASSWORD with OTP ────────────────────────────────────────────────
async function handleResetPassword(req: Request) {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const email = sanitizeString(body["email"] ?? "").toLowerCase();
  const otp = sanitizeString((body["otp"] ?? body["code"] ?? body["token"]) as unknown);
  const new_password = body["new_password"] as string | undefined;

  if (!email || !otp || !new_password) {
    return errorResponse("Email, OTP and new_password are required", 400, "VALIDATION_ERROR");
  }
  if (!validateEmail(email)) return errorResponse("Invalid email format", 400, "VALIDATION_ERROR");
  if (!/^\d{6}$/.test(otp)) return errorResponse("OTP must be 6 digits", 400, "VALIDATION_ERROR");

  const pw = sanitizeString(new_password);
  const check = validatePasswordComplexity(pw);
  if (!check.valid) return errorResponse(check.message!, 400, "VALIDATION_ERROR");

  const db = getAdminClient();

  // Lockout check
  const lock = await readEmailLockout(db, email);
  if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) return lockoutError(lock.lockedUntil, lock.failedAttempts);

  // Find OTP — allow both verified and unverified, but must be unused and not expired
  const { data: otpRow } = await db.from("email_reset_otps")
    .select("*")
    .eq("email", email)
    .eq("used", false)
    .gte("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!otpRow) {
    return errorResponse("Invalid or expired OTP", 400, "INVALID_OTP");
  }
  if (otpRow.attempts >= OTP_MAX_ATTEMPTS) {
    await db.from("email_reset_otps").update({ used: true }).eq("id", otpRow.id);
    return errorResponse("Too many attempts. Request a new code.", 400, "INVALID_OTP");
  }

  const submittedHash = await hashOtp(otp, email);
  if (otpRow.otp_hash !== submittedHash) {
    await db.from("email_reset_otps").update({ attempts: otpRow.attempts + 1 }).eq("id", otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from("email_otp_lockouts").upsert({ email, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: "email" });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse("Invalid OTP code", 400, "INVALID_OTP");
  }

  // OTP correct — get user
  const { data: userRow } = await db.from("users").select("id").eq("email", email).maybeSingle();
  if (!userRow) return errorResponse("User not found", 404, "NOT_FOUND");
  const userId = (userRow as { id: string }).id;

  // Check password history
  try {
    const { data: history } = await db.from("password_history").select("password_hash").eq("user_id", userId).order("created_at", { ascending: false }).limit(PASSWORD_HISTORY_LIMIT);
    for (const h of (history as { password_hash: string }[] | null) ?? []) {
      if (await matchesPasswordHistory(userId, pw, h.password_hash)) {
        return errorResponse(`Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`, 400, "PASSWORD_REUSE");
      }
    }
  } catch (_) { /* ignore history check failure */ }

  const { error: updateError } = await db.auth.admin.updateUserById(userId, { password: pw });
  if (updateError) {
    console.error("[reset-password] updateUserById failed:", updateError);
    return errorResponse("Failed to reset password", 500, "SERVER_ERROR");
  }

  // Mark OTP as used
  await db.from("email_reset_otps").update({ used: true, verified: true }).eq("id", otpRow.id);
  // Clear lockout
  await db.from("email_otp_lockouts").delete().eq("email", email);

  try {
    await db.from("password_history").insert({ user_id: userId, password_hash: await hashPassword(userId, pw) });
  } catch (e) { console.error("[reset-password] password_history insert failed:", e); }

  try {
    await writeAuditLog({ performedBy: userId, action: "password_reset", tableName: "users", recordId: userId, ipAddress: req.headers.get("x-forwarded-for") ?? "unknown" });
  } catch (_) { /* ignore audit failure */ }

  try {
    await db.from("users").update({ force_password_change: false }).eq("id", userId);
  } catch (_) { /* ignore update failure */ }

  return jsonResponse({ message: "Password reset successfully" });
}

// ── FORCE CHANGE & CHANGE PASSWORD remain same ─────────────────────────────
async function handleForceChangePassword(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const { current_password, new_password } = await req.json();
  if (!new_password) return errorResponse("new_password is required", 400, "VALIDATION_ERROR");
  if (!current_password) return errorResponse("current_password is required", 400, "VALIDATION_ERROR");
  const cleanNew = sanitizeString(new_password);
  const complexity = validatePasswordComplexity(cleanNew);
  if (!complexity.valid) return errorResponse(complexity.message!, 400, "VALIDATION_ERROR");
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
    (!!authResult.phone && (await verifyWithPhone(authResult.phone, current_password))) ||
    (!!authResult.email && (await verifyWithEmail(authResult.email, current_password)));
  if (!passwordValid) return errorResponse("Current password is incorrect", 401, "INVALID_CREDENTIALS");
  const db = getAdminClient();
  const { data: user } = await db.from("users").select("id, force_password_change").eq("id", authResult.id).single();
  if (!user) return errorResponse("User not found", 404, "NOT_FOUND");
  if (!user.force_password_change) return errorResponse("Password change not required", 400, "VALIDATION_ERROR");
  const { data: history } = await db.from("password_history").select("password_hash").eq("user_id", authResult.id).order("created_at", { ascending: false }).limit(PASSWORD_HISTORY_LIMIT);
  for (const h of history ?? []) {
    if (await matchesPasswordHistory(authResult.id, cleanNew, h.password_hash)) {
      return errorResponse(`Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`, 400, "PASSWORD_REUSE");
    }
  }
  const { error: updateErr } = await db.auth.admin.updateUserById(authResult.id, { password: cleanNew });
  if (updateErr) return errorResponse("Failed to update password", 500, "SERVER_ERROR");
  await db.from("users").update({ force_password_change: false }).eq("id", authResult.id);
  await db.from("password_history").insert({ user_id: authResult.id, password_hash: await hashPassword(authResult.id, cleanNew) });
  await db.from("auth_logs").insert({ user_id: authResult.id, event_type: "force_password_changed", ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")) });
  await writeAuditLog({ performedBy: authResult.id, action: "force_password_changed", tableName: "users", recordId: authResult.id, ipAddress: req.headers.get("x-forwarded-for") ?? undefined });
  return jsonResponse({ message: "Password changed successfully" });
}

async function handleChangePassword(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const { current_password, new_password } = await req.json();
  if (!current_password) return errorResponse("current_password is required", 400, "VALIDATION_ERROR");
  if (!new_password) return errorResponse("new_password is required", 400, "VALIDATION_ERROR");
  const cleanNew = sanitizeString(new_password);
  const complexity = validatePasswordComplexity(cleanNew);
  if (!complexity.valid) return errorResponse(complexity.message!, 400, "VALIDATION_ERROR");
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
    (!!authResult.phone && (await verifyWithPhone(authResult.phone, current_password))) ||
    (!!authResult.email && (await verifyWithEmail(authResult.email, current_password)));
  if (!passwordValid) return errorResponse("Current password is incorrect", 401, "INVALID_CREDENTIALS");
  const db = getAdminClient();
  const { data: history } = await db.from("password_history").select("password_hash").eq("user_id", authResult.id).order("created_at", { ascending: false }).limit(PASSWORD_HISTORY_LIMIT);
  for (const h of history ?? []) {
    if (await matchesPasswordHistory(authResult.id, cleanNew, h.password_hash)) {
      return errorResponse(`Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`, 400, "PASSWORD_REUSE");
    }
  }
  const { error: updateErr } = await db.auth.admin.updateUserById(authResult.id, { password: cleanNew });
  if (updateErr) {
    console.error("auth password update error:", updateErr);
    return errorResponse("Failed to update password", 500, "SERVER_ERROR");
  }
  await db.from("users").update({ force_password_change: false }).eq("id", authResult.id);
  await db.from("password_history").insert({ user_id: authResult.id, password_hash: await hashPassword(authResult.id, cleanNew) });
  await db.from("auth_logs").insert({ user_id: authResult.id, event_type: "password_changed", ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")) });
  await writeAuditLog({ performedBy: authResult.id, action: "password_changed", tableName: "users", recordId: authResult.id, ipAddress: req.headers.get("x-forwarded-for") ?? undefined });
  return jsonResponse({ message: "Password changed successfully" });
}
