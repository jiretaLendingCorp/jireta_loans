// supabase/functions/kyc-submit/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { writeAuditLog } from "../_shared/audit.ts";
import {
  isAuthUser,
  requireAuth,
  syncAuthUserIdentity,
} from "../_shared/auth.ts";
import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { getAdminClient } from "../_shared/db.ts";
import { notifyStaff } from "../_shared/notifications.ts";
import { requireRole, ROLES } from "../_shared/rbac.ts";
import { sanitizeString } from "../_shared/validators.ts";
import {
  validateDocumentMeta,
  validateDocumentSet,
  validateDocumentSize,
} from "../_shared/kyc_docs.ts";
import { guardRateLimit } from "../_shared/rate_limiter.ts";
import { geocodeInBackground } from "../_shared/geocode.ts";

function normalizeEnum(value: string | undefined | null): string | null {
  if (!value) return null;
  return sanitizeString(value).trim().toLowerCase().replace(/\s+/g, "_");
}

const ALLOWED_TYPES = [
  "valid_id",
  "valid_id_back",
  "selfie",
  "proof_of_billing",
  "proof_of_income",
  "barangay_clearance",
  "pay_slip",
  "certificate_of_employment",
  "itr",
  "business_registration",
  "mayors_permit",
  "co_maker",
  // 00147: lender's signature captured on the Account Upgrade Residence step.
  "lender_signature",
  // 00149: frontal face capture for identity verification.
  "face_recognition",
  "other",
];

// Lookup allowlists mirror the DB FK tables (gender_types, civil_statuses,
// employment_types). Unknown "Other" free-text must map to "other" instead
// of failing the FK and 500-ing the whole submit.
const ALLOWED_GENDER = ["male", "female", "other"];
const ALLOWED_CIVIL = ["single", "married", "widowed", "separated"];
const ALLOWED_EMPLOYMENT = [
  "employed",
  "self_employed",
  "business_owner",
  "ofw",
  "freelancer",
  "unemployed",
  "student",
  "other",
];

function coerceLookup(
  value: string | undefined | null,
  allowed: string[],
): string | null {
  const n = normalizeEnum(value);
  if (!n) return null;
  if (allowed.includes(n)) return n;
  // Free-text "Other" (e.g. "Retired") has no lookup row — fall back to other.
  return "other";
}

function mimeFromExt(ext: string): string {
  switch (ext) {
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "png":
      return "image/png";
    case "webp":
      return "image/webp";
    case "pdf":
      return "application/pdf";
    default:
      return "application/octet-stream";
  }
}

// Decode a base64 string into a Uint8Array without relying on atob.
// Whitespace (newlines/carriage returns) must be stripped first — the Flutter
// client and some HTTP layers emit padded/multiline base64 which atob rejects.
function base64ToBytes(base64: string): Uint8Array {
  const bin = atob(base64.replace(/\s+/g, ""));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();

    // ── Rate limit: 5 submits / 15 min bawat lender ──────────────────────
    // Abusadong paulit-ulit na submit (at upload ng base64 documents) ang
    // pinipigilan dito. Ang bawat lumampas ay naba-block pansamantala at
    // naitala sa security events.
    const submitGuard = await guardRateLimit({
      key: `kyc_submit:${user.id}`,
      maxAttempts: 5,
      windowMinutes: 15,
      blockMinutes: 15,
      blockReason: "too many account upgrade submissions",
      eventType: "kyc_submit_rate_limited",
      userId: user.id,
      ipAddress: req.headers.get("x-forwarded-for") ?? null,
    });
    if (!submitGuard.allowed) {
      return errorResponse(
        "Too many submission attempts. Please try again in a few minutes.",
        429,
        "RATE_LIMITED",
        { retry_after_seconds: submitGuard.block?.retryAfterSeconds ?? 0 },
      );
    }

    // ── Resubmit cooldown after rejection ─────────────────────────────────
    // Ang staff-chosen `reapply_allowed_at` (00191) ang basehan; kung wala
    // (lumang data / lumang app build), default na 30 days mula sa latest
    // rejection (reviewed_at, fallback sa lender_profiles.updated_at).
    // `*` para hindi bumagsak ang buong check kapag wala pa ang 00191 column
    // (lumang deploy) — optional na lang ang flag sa ibaba.
    const { data: curProfile } = await db
      .from("lender_profiles")
      .select("*")
      .eq("id", user.id)
      .maybeSingle();
    // 00191: permanenteng rejection — hindi na makakapag-resubmit kahit kailan.
    if (
      curProfile?.account_upgrade_status === "rejected" &&
      curProfile?.account_upgrade_permanently_rejected === true
    ) {
      return errorResponse(
        "Account upgrade was permanently rejected. You can no longer resubmit.",
        403,
        "ACCOUNT_UPGRADE_PERMANENT",
      );
    }
    if (curProfile?.account_upgrade_status === "rejected") {
      const { data: rejDocs } = await db
        .from("account_upgrade_documents")
        .select("reviewed_at, reapply_allowed_at")
        .eq("lender_id", user.id)
        .eq("status", "rejected")
        .order("reviewed_at", { ascending: false })
        .limit(1);
      const latestRejected = rejDocs?.[0] ?? null;
      const rawRejectedAt =
        latestRejected?.reviewed_at ?? curProfile?.updated_at ?? null;
      const rawReapply = latestRejected?.reapply_allowed_at ?? null;
      if (rawRejectedAt) {
        const rejectedAt = new Date(rawRejectedAt);
        const resubmitAfter = rawReapply
          ? new Date(rawReapply)
          : new Date(rejectedAt.getTime() + 30 * 24 * 60 * 60 * 1000);
        if (new Date() < resubmitAfter) {
          const daysLeft = Math.ceil(
            (resubmitAfter.getTime() - Date.now()) / (24 * 60 * 60 * 1000),
          );
          return errorResponse(
            `Account upgrade rejected. You may resubmit on ${resubmitAfter.toISOString().substring(0, 10)}. ${daysLeft} day(s) remaining.`,
            403,
            "ACCOUNT_UPGRADE_COOLDOWN",
            {
              rejected_at: rejectedAt.toISOString(),
              resubmit_after: resubmitAfter.toISOString(),
              days_remaining: daysLeft,
            },
          );
        }
      }
    }

    const body = await req.json();
    const {
      profile,
      documents,
      address_info,
      source_of_funds,
      emergency_contact,
    } = body;

    if (!documents || !Array.isArray(documents)) {
      return errorResponse(
        "Documents are required",
        400,
        "VALIDATION_ERROR",
      );
    }

    // Bilang / duplicates / required docs. Kasama sa kailangan ang Valid
    // Government ID (front + back), Selfie with ID, Business Permit, at Face
    // Recognition.
    const docTypes = documents.map((d) =>
      normalizeEnum(d?.document_type) ?? ""
    );
    const setError = validateDocumentSet(docTypes);
    if (setError) {
      return errorResponse(setError, 400, "VALIDATION_ERROR");
    }

    // Kapag may Valid ID front, kailangan ding may back — hindi pwedeng
    // kalahati lang ang ID (optional pa rin ang buong ID).
    if (docTypes.includes("valid_id") && !docTypes.includes("valid_id_back")) {
      return errorResponse(
        "Valid ID needs both sides — front and back required",
        400,
        "VALIDATION_ERROR",
      );
    }

    for (const doc of documents) {
      if (!doc.document_type) {
        return errorResponse(
          "Each document needs document_type",
          400,
          "VALIDATION_ERROR",
        );
      }
      if (!ALLOWED_TYPES.includes(doc.document_type)) {
        return errorResponse(
          `Invalid document_type: ${doc.document_type}`,
          400,
          "VALIDATION_ERROR",
        );
      }
    }

    // Account Upgrade is now IDENTITY + documents only (00128). Employment /
    // income / emergency contact are declared by the borrower PER LOAN inside
    // the Apply Loan flow and snapshot onto loans / loan_emergency_contacts —
    // they no longer live on lender_profiles.
    const p = profile ?? {};
    const REQUIRED_PROFILE = [
      "first_name",
      "last_name",
      "email",
      "gender",
      "civil_status",
      "dob",
    ];
    for (const f of REQUIRED_PROFILE) {
      const v = p[f];
      if (v === undefined || v === null || String(v).trim() === "") {
        return errorResponse(
          `Missing required profile field: ${f}`,
          400,
          "VALIDATION_ERROR",
        );
      }
    }

    const ip = req.headers.get("x-forwarded-for") ?? "unknown";

    // ── 1) Identity (users) — names are captured here in Account Upgrade, never auto-filled.
    const { error: userErr } = await db.from("users").update({
      first_name: sanitizeString(p.first_name),
      middle_name: p.middle_name ? sanitizeString(p.middle_name) : null,
      last_name: sanitizeString(p.last_name),
      suffix: p.suffix ? sanitizeString(p.suffix) : null,
      email: p.email ? sanitizeString(p.email) : undefined,
    }).eq("id", user.id);
    if (userErr) {
      console.error("kyc-submit user update error:", userErr.message);
    }

    // ── Identity sync (GoTrue) ─────────────────────────────────────────────────
    // Dito unang nakukuha ng self-registered lender ang totoong email at
    // pangalan (Account Upgrade). DATI, `public.users` lang ang naisusulat —
    // kaya sa Authentication → Users ay TEMP (`@jireta.temp`) pa rin ang email
    // at `-` ang Display name. Ang epekto: hindi makapasok sa Google sign-in
    // (`auth-google` ay tumatanggi sa `@jireta.temp`) at hindi magagamit ng
    // GoTrue (email login / recovery) ang totoong address.
    //
    // Non-fatal: ang `public.users` ang pinagmumulan ng katotohanan para sa
    // app — hindi dapat mabigo ang account upgrade dahil lang sa GoTrue.
    if (p.email || p.first_name || p.last_name) {
      const identitySync = await syncAuthUserIdentity(db, user.id, {
        email: p.email ? sanitizeString(p.email).trim().toLowerCase() : null,
        firstName: sanitizeString(p.first_name),
        lastName: sanitizeString(p.last_name),
      });
      if (!identitySync.ok) {
        console.error("kyc-submit identity sync failed (non-fatal):", {
          userId: user.id,
          duplicate: identitySync.duplicate,
          msg: identitySync.error,
        });
      }
    }

    // Upload each document to the account-upgrade-documents storage bucket (service role)
    // and store the returned object path — NOT the raw base64 payload which
    // would overflow the VARCHAR(255) file_path column.
    const docsToInsert = [];
    for (let i = 0; i < documents.length; i++) {
      const doc = documents[i];
      const ext =
        (doc.file_name ?? "document").split(".").pop()?.toLowerCase() ?? "jpg";
      const safeExt = ["jpg", "jpeg", "png", "webp", "pdf"].includes(ext)
        ? ext
        : "jpg";
      const objectPath =
        `account-upgrade/${user.id}/${crypto.randomUUID()}.${safeExt}`;

      // Uri ng file (extension + mime) bago pa mag-decode ng base64.
      const metaError = validateDocumentMeta({
        document_type: doc.document_type,
        file_name: doc.file_name,
        mime_type: doc.mime_type,
      });
      if (metaError) {
        return errorResponse(metaError, 400, "VALIDATION_ERROR");
      }

      let storedPath = doc.file_url ?? null;
      let uploadedBytes: Uint8Array | null = null;
      if (doc.content_base64) {
        try {
          uploadedBytes = base64ToBytes(doc.content_base64);
        } catch {
          return errorResponse(
            `Invalid file content for ${doc.document_type}`,
            400,
            "VALIDATION_ERROR",
          );
        }

        // Laki: 10MB per side ng Valid ID, 5MB sa ibang dokumento.
        const sizeError = validateDocumentSize(
          doc.document_type,
          uploadedBytes.length,
        );
        if (sizeError) {
          return errorResponse(sizeError, 400, "VALIDATION_ERROR");
        }

        const { error: uploadErr } = await db.storage
          .from("account-upgrade-documents")
          .upload(objectPath, uploadedBytes, {
            contentType: doc.mime_type ?? mimeFromExt(safeExt),
            upsert: false,
          });
        if (uploadErr) {
          return errorResponse(
            `Failed to upload document (${doc.document_type}): ${uploadErr.message}`,
            500,
            "STORAGE_ERROR",
          );
        }
        storedPath = objectPath;
      }

      if (!storedPath) {
        return errorResponse(
          `Document (${doc.document_type}) has no content to store`,
          400,
          "VALIDATION_ERROR",
        );
      }

      docsToInsert.push({
        lender_id: user.id,
        document_type: doc.document_type,
        file_path: storedPath,
        file_name: doc.file_name ?? "document",
        // Ang totoong laki ng na-upload ang itinatala, hindi ang sinabi ng
        // client (mababaluktot kasi iyon).
        file_size: uploadedBytes?.length ?? doc.file_size ?? 1,
        mime_type: doc.mime_type ?? mimeFromExt(safeExt),
        status: "pending",
      });
    }

    const { error: insertErr } = await db.from("account_upgrade_documents")
      .insert(docsToInsert);
    if (insertErr) {
      return errorResponse(
        `Failed to save Account Upgrade documents: ${insertErr.message}`,
        500,
        "DB_ERROR",
      );
    }

    // ── 2) Lender profile identity details ──────────────────────────────────
    // Employment/income/source_of_funds are intentionally NOT written here
    // (00128): they are captured per loan at application time instead.
    // profileErr must NOT be swallowed: this is an atomic UPDATE whose FK/CHECK
    // violations silently wipe every field, which is exactly how a lender
    // "submits Account Upgrade but staff sees nothing". Surface it so it can be fixed.
    const { error: profileErr } = await db.from("lender_profiles").update({
      gender: coerceLookup(p.gender, ALLOWED_GENDER),
      civil_status: coerceLookup(p.civil_status, ALLOWED_CIVIL),
      date_of_birth: String(p.dob).substring(0, 10),
    }).eq("id", user.id);
    if (profileErr) {
      console.error("kyc-submit profile update error:", profileErr.message);
      return errorResponse(
        `Failed to update lender profile: ${profileErr.message}`,
        500,
        "DB_ERROR",
      );
    }

    // ── 3) Residence — now lives in `addresses` (3NF), not lender_profiles. ──
    const ai = address_info ?? {};
    if (ai.street_address || ai.barangay || ai.city || ai.province) {
      const { data: existingAddr } = await db
        .from("addresses")
        .select("id")
        .eq("user_id", user.id)
        .eq("address_type", "home")
        .eq("is_primary", true)
        .maybeSingle();
      if (existingAddr) {
        await db.from("addresses").update({
          street: ai.street_address
            ? sanitizeString(ai.street_address)
            : undefined,
          barangay: ai.barangay ? sanitizeString(ai.barangay) : undefined,
          city: ai.city ? sanitizeString(ai.city) : undefined,
          province: ai.province ? sanitizeString(ai.province) : undefined,
          region: ai.region ? sanitizeString(ai.region) : undefined,
          zip_code: ai.zip_code ? sanitizeString(ai.zip_code) : undefined,
        }).eq("id", existingAddr.id);
        // Coordinates (pin ng rider maps): `overwrite` dahil nag-EDIT ng
        // address text — kung hindi, stale na pin ang mananatili.
        geocodeInBackground(db, [existingAddr.id], { overwrite: true });
      } else {
        const { data: inserted } = await db.from("addresses").insert({
          user_id: user.id,
          address_type: "home",
          street: sanitizeString(ai.street_address),
          barangay: sanitizeString(ai.barangay),
          city: sanitizeString(ai.city),
          province: sanitizeString(ai.province),
          region: ai.region ? sanitizeString(ai.region) : null,
          zip_code: ai.zip_code ? sanitizeString(ai.zip_code) : null,
          is_primary: true,
        }).select("id").single();
        // TEXT lang ang kinukuha ng KYC form (walang lat/lng) → i-geocode sa
        // background para may naka-save na pin ang rider maps (web + mobile).
        geocodeInBackground(db, [inserted?.id as string | undefined]);
      }
    }

    // Emergency contact is NOT stored on the lender here (00128). It is
    // declared per loan (loan_emergency_contacts) when the borrower applies.

    const { error: statusErr } = await db.from("lender_profiles").update({
      account_upgrade_status: "submitted",
    }).eq("id", user.id);
    if (statusErr) {
      return errorResponse(
        "Failed to update Account Upgrade status",
        500,
        "DB_ERROR",
      );
    }

    await writeAuditLog({
      performedBy: user.id,
      action: "account_upgrade_submit",
      tableName: "account_upgrade_documents",
      recordId: user.id,
      ipAddress: ip,
    });
    await notifyStaff({
      title: "Account Upgrade Submitted",
      body: "A lender has submitted Account Upgrade documents for review.",
      type: "account_upgrade_submitted",
      referenceId: user.id,
      sentBy: user.id,
    });

    return jsonResponse({
      message: "Account Upgrade documents submitted successfully",
    }, 201);
  } catch (err) {
    console.error("kyc-submit error:", err);
    return errorResponse("Internal server error", 500, "SERVER_ERROR");
  }
});
