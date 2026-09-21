// supabase/functions/auth-mpin/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// SERVER-SIDE (ACCOUNT-LEVEL) 4-digit MPIN — para sa rider / lender.
//
// Dating LOCAL-only ang MPIN (hash sa secure storage ng device). Ngayon, ang
// `user_mpins` table ang source of truth, kaya:
//   * pareho ang MPIN sa lahat ng device ng account (hindi na kailangang
//     i-setup muli sa bagong phone),
//   * server-side ang attempts / lockout, at
//   * server-side din ang "10 palit sa loob ng 15 araw" na limitasyon.
//
// Actions (tinatawag lahat ng naka-authenticate na client):
//   ?fn=status  → may MPIN ba ang account? (at ang lockout / change quota)
//   ?fn=set     → gumawa o magpalit ng MPIN
//   ?fn=verify  → i-verify ang MPIN (kasama ang attempts + lockout)
//   ?fn=reset   → burahin ang MPIN (forgot MPIN — pagkatapos ng OTP login)
//
// SEGURIDAD: hindi ito nagbabalik ng anumang hash; ang `mpin_hash` ay
// `sha256$<hex>` ng `jireta::<user_id>::<mpin>` (tingnan ang
// `_shared/password_hash.ts`) at hindi kailanman lumalabas sa response.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { writeAuditLog, sanitizeIpAddress } from "../_shared/audit.ts";
import { isAuthUser, requireAuth } from "../_shared/auth.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { getAdminClient } from "../_shared/db.ts";
import { hashPassword } from "../_shared/password_hash.ts";
import { sanitizeString } from "../_shared/validators.ts";

// ── Mga pare-parehong bilang (tugma sa client: MpinService) ──────────────────
const MPIN_LENGTH = 4;
const MPIN_MAX_ATTEMPTS = 3;
const MPIN_LOCKOUT_SECONDS = 60;
const MPIN_MAX_CHANGES_PER_WINDOW = 10;
const MPIN_CHANGE_WINDOW_DAYS = 15;

const MPIN_RE = /^\d{4}$/;

function nowMs(): number {
  return Date.now();
}

function secondsUntil(iso: string | null | undefined): number {
  if (!iso) return 0;
  const target = new Date(iso).getTime();
  if (Number.isNaN(target)) return 0;
  return Math.max(0, Math.ceil((target - nowMs()) / 1000));
}

/** Ang MPIN ay 4 na digit lang — walang ibang valid na format. */
function isValidMpinFormat(value: string): boolean {
  return value.length === MPIN_LENGTH && MPIN_RE.test(value);
}

/**
 * Hindi kailanman plain text ang naiimbak: `sha256$<hex>` na may salt na user
 * id (hindi mai-replay kahit ma-leak ang row para sa ibang account).
 */
function hashMpin(userId: string, mpin: string): Promise<string> {
  return hashPassword(userId, mpin);
}

type MpinRow = {
  user_id: string;
  mpin_hash: string;
  failed_attempts: number | null;
  locked_until: string | null;
  change_window_start: string | null;
  change_count: number | null;
};

async function readMpinRow(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
): Promise<MpinRow | null> {
  const { data } = await db
    .from("user_mpins")
    .select("user_id, mpin_hash, failed_attempts, locked_until, change_window_start, change_count")
    .eq("user_id", userId)
    .maybeSingle();
  return (data as MpinRow | null) ?? null;
}

/** Locked pa ba? (may `locked_until` pa sa hinaharap) */
function lockSecondsLeft(row: MpinRow | null): number {
  if (!row?.locked_until) return 0;
  return secondsUntil(row.locked_until);
}

function lockedResponse(seconds: number): Response {
  return errorResponse(
    "Too many wrong MPIN attempts. Please try again later.",
    429,
    "MPIN_LOCKED",
    {
      retry_after_seconds: seconds,
      attempts_left: 0,
    },
  );
}

/**
 * Nagtatala ng isang maling attempt at nagbibigay ng lockout kapag naubos na
 * ang budget. Isinasauli ang bilang ng natitirang attempts (`0` kapag na-lock,
 * kasama ang `retry_after_seconds` sa pamamagitan ng `lockSeconds`).
 */
async function registerFailedAttempt(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
  row: MpinRow,
): Promise<{ attemptsLeft: number; lockSeconds: number }> {
  const fails = (row.failed_attempts ?? 0) + 1;
  if (fails >= MPIN_MAX_ATTEMPTS) {
    await db
      .from("user_mpins")
      .update({
        failed_attempts: 0,
        locked_until: new Date(nowMs() + MPIN_LOCKOUT_SECONDS * 1000).toISOString(),
      })
      .eq("user_id", userId);
    return { attemptsLeft: 0, lockSeconds: MPIN_LOCKOUT_SECONDS };
  }
  await db.from("user_mpins").update({ failed_attempts: fails }).eq("user_id", userId);
  return { attemptsLeft: MPIN_MAX_ATTEMPTS - fails, lockSeconds: 0 };
}

/** Natitirang palit at gaano pa katagal bago mag-reset ang 15-day window. */
function changeQuota(row: MpinRow | null): {
  remaining: number;
  resetInSeconds: number | null;
} {
  if (!row) {
    return { remaining: MPIN_MAX_CHANGES_PER_WINDOW, resetInSeconds: null };
  }
  const startMs = row.change_window_start ? new Date(row.change_window_start).getTime() : null;
  const windowMs = MPIN_CHANGE_WINDOW_DAYS * 24 * 60 * 60 * 1000;
  if (startMs == null || Number.isNaN(startMs) || nowMs() - startMs >= windowMs) {
    // Bagong window na — buo na muli ang quota.
    return { remaining: MPIN_MAX_CHANGES_PER_WINDOW, resetInSeconds: null };
  }
  const count = row.change_count ?? 0;
  const remaining = Math.max(0, MPIN_MAX_CHANGES_PER_WINDOW - count);
  const resetInSeconds = remaining > 0
    ? null
    : Math.max(0, Math.ceil((startMs + windowMs - nowMs()) / 1000));
  return { remaining, resetInSeconds };
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = "status";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const fn = new URL(req.url).searchParams.get("fn") ?? DEFAULT_ACTION;
    switch (fn) {
      case "status":
        return await handleStatus(req);
      case "set":
        return await handleSet(req);
      case "verify":
        return await handleVerify(req);
      case "reset":
        return await handleReset(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, "NOT_FOUND");
    }
  } catch (err) {
    console.error("auth-mpin error:", err);
    return errorResponse("Internal server error", 500, "SERVER_ERROR");
  }
});

// ── STATUS: may MPIN ba ang account (at ang kasalukuyang lock/quota)? ───────
async function handleStatus(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const db = getAdminClient();
  const row = await readMpinRow(db, authResult.id);
  const lockSeconds = lockSecondsLeft(row);
  const quota = changeQuota(row);

  return jsonResponse({
    has_mpin: row != null,
    locked: lockSeconds > 0,
    retry_after_seconds: lockSeconds,
    attempts_left: MPIN_MAX_ATTEMPTS,
    changes_remaining: quota.remaining,
    change_reset_in_seconds: quota.resetInSeconds,
    max_changes: MPIN_MAX_CHANGES_PER_WINDOW,
    change_window_days: MPIN_CHANGE_WINDOW_DAYS,
    max_attempts: MPIN_MAX_ATTEMPTS,
  });
}

// ── SET: gumawa (o magpalit) ng MPIN ────────────────────────────────────────
async function handleSet(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const mpin = sanitizeString(body["mpin"]);
  const currentMpin = sanitizeString(body["current_mpin"]);

  if (!isValidMpinFormat(mpin)) {
    return errorResponse(
      `MPIN must be exactly ${MPIN_LENGTH} digits`,
      400,
      "VALIDATION_ERROR",
    );
  }

  const db = getAdminClient();
  const row = await readMpinRow(db, authResult.id);
  const isChange = row != null;

  // ── Nagpapalit: kailangan ang KASALUKUYANG MPIN ──────────────────────────
  // Ang UI ay dumadaan muna sa `?fn=verify` (kaya buo ang attempts/lockout
  // handling doon); dito ay pangalawang tsek para hindi ma-bypass ang change
  // flow sa isang direktang tawag.
  if (isChange) {
    if (!currentMpin || !isValidMpinFormat(currentMpin)) {
      return errorResponse(
        "Current MPIN is required to change your MPIN",
        400,
        "INVALID_CURRENT_MPIN",
      );
    }
    const expected = await hashMpin(authResult.id, currentMpin);
    if (expected !== row.mpin_hash) {
      const { attemptsLeft, lockSeconds } = await registerFailedAttempt(db, authResult.id, row);
      if (lockSeconds > 0) return lockedResponse(lockSeconds);
      return errorResponse("Current MPIN is incorrect.", 400, "INVALID_CURRENT_MPIN", {
        attempts_left: attemptsLeft,
      });
    }
  }

  // ── Limitasyon: 10 palit sa loob ng 15 araw (unang set-up = libre) ──────
  if (isChange) {
    const quota = changeQuota(row);
    if (quota.remaining <= 0) {
      return errorResponse(
        `Limit reached: you can only change your MPIN ${MPIN_MAX_CHANGES_PER_WINDOW} times within ${MPIN_CHANGE_WINDOW_DAYS} days.`,
        429,
        "MPIN_CHANGE_LIMIT",
        { retry_after_seconds: quota.resetInSeconds ?? 0 },
      );
    }
  }

  const mpinHash = await hashMpin(authResult.id, mpin);
  const nowIso = new Date().toISOString();

  if (isChange) {
    const startMs = row.change_window_start ? new Date(row.change_window_start).getTime() : null;
    const windowMs = MPIN_CHANGE_WINDOW_DAYS * 24 * 60 * 60 * 1000;
    const windowExpired = startMs == null || Number.isNaN(startMs) || nowMs() - startMs >= windowMs;
    const { error } = await db
      .from("user_mpins")
      .update({
        mpin_hash: mpinHash,
        failed_attempts: 0,
        locked_until: null,
        change_window_start: windowExpired ? nowIso : row.change_window_start,
        change_count: windowExpired ? 1 : (row.change_count ?? 0) + 1,
      })
      .eq("user_id", authResult.id);
    if (error) {
      console.error("[auth-mpin] update failed:", error.message);
      return errorResponse("Failed to save your MPIN", 500, "SERVER_ERROR");
    }
  } else {
    const { error } = await db.from("user_mpins").insert({
      user_id: authResult.id,
      mpin_hash: mpinHash,
      failed_attempts: 0,
      locked_until: null,
      change_window_start: nowIso,
      change_count: 0,
    });
    if (error) {
      console.error("[auth-mpin] insert failed:", error.message);
      return errorResponse("Failed to save your MPIN", 500, "SERVER_ERROR");
    }
  }

  try {
    await db.from("auth_logs").insert({
      user_id: authResult.id,
      event_type: isChange ? "mpin_changed" : "mpin_set",
      ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")),
    });
  } catch (_) { /* ignore log failure */ }

  try {
    await writeAuditLog({
      performedBy: authResult.id,
      action: isChange ? "mpin_changed" : "mpin_set",
      tableName: "user_mpins",
      recordId: authResult.id,
      ipAddress: req.headers.get("x-forwarded-for") ?? undefined,
    });
  } catch (_) { /* ignore audit failure */ }

  return jsonResponse({ message: "MPIN saved successfully", changed: isChange });
}

// ── VERIFY: i-verify ang MPIN (attempts + lockout) ──────────────────────────
async function handleVerify(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const mpin = sanitizeString(body["mpin"]);
  if (!isValidMpinFormat(mpin)) {
    return errorResponse(
      `MPIN must be exactly ${MPIN_LENGTH} digits`,
      400,
      "VALIDATION_ERROR",
    );
  }

  const db = getAdminClient();
  const row = await readMpinRow(db, authResult.id);
  if (!row) {
    return errorResponse("No MPIN is set for this account", 404, "MPIN_NOT_SET");
  }

  // Naka-lock pa: hindi tinatanggap kahit TAMA ang MPIN.
  const lockSeconds = lockSecondsLeft(row);
  if (lockSeconds > 0) return lockedResponse(lockSeconds);

  const submitted = await hashMpin(authResult.id, mpin);
  if (submitted === row.mpin_hash) {
    await db
      .from("user_mpins")
      .update({ failed_attempts: 0, locked_until: null })
      .eq("user_id", authResult.id);
    return jsonResponse({ message: "MPIN verified", verified: true });
  }

  const { attemptsLeft, lockSeconds: newLock } = await registerFailedAttempt(db, authResult.id, row);
  if (newLock > 0) {
    try {
      await db.from("auth_logs").insert({
        user_id: authResult.id,
        event_type: "mpin_locked",
        ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")),
      });
    } catch (_) { /* ignore log failure */ }
    return lockedResponse(newLock);
  }
  return errorResponse("Incorrect MPIN", 400, "INVALID_MPIN", {
    attempts_left: attemptsLeft,
  });
}

// ── RESET: burahin ang MPIN (forgot MPIN, pagkatapos ng OTP login) ──────────
async function handleReset(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const db = getAdminClient();
  const { error } = await db.from("user_mpins").delete().eq("user_id", authResult.id);
  if (error) {
    console.error("[auth-mpin] reset failed:", error.message);
    return errorResponse("Failed to reset your MPIN", 500, "SERVER_ERROR");
  }

  try {
    await db.from("auth_logs").insert({
      user_id: authResult.id,
      event_type: "mpin_reset",
      ip_address: sanitizeIpAddress(req.headers.get("x-forwarded-for")),
    });
  } catch (_) { /* ignore log failure */ }

  return jsonResponse({ message: "MPIN reset successfully", reset: true });
}
