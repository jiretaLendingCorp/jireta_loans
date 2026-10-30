// supabase/functions/users-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-update-profile →  ?fn=update-profile
//   users-get-profile    →  ?fn=get-profile
//   users-unpause-lender →  ?fn=unpause-lender
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import {
  isAuthUser,
  requireAuth,
  syncAuthUserIdentity,
} from '../_shared/auth.ts';
import { requireMfaIfEnrolled } from '../_shared/mfa.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validateEmail, validatePhone, normalizeVehicleType, credentialEmailFor, phoneCredentialEmail } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import {
  EMAIL_CHANGE_OTP_PURPOSE,
  emailOtpKey,
  generateOtpCode,
  hashOtpCode,
  OTP_CODE_LENGTH,
  otpRejectionReason,
  resendCooldownRemaining,
} from '../_shared/otp.ts';
import { guardRateLimit } from '../_shared/rate_limiter.ts';
import { sendEmailChangeOtpEmail } from '../_shared/email.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getLenderAddress } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';
import { geocodeInBackground } from '../_shared/geocode.ts';

// ── [moved from users-update-profile] ───────────────────────────────────────
// Normalize display values (e.g. "Self-Employed") to the lowercase/underscored
// form the lender_profiles CHECK constraints expect (e.g. "self_employed").
function normalizeEnum(value: string | undefined | null): string | null {
  if (!value) return null;
  return sanitizeString(value).trim().toLowerCase().replace(/\s+/g, '_');
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'update-profile';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'update-profile':
        // ── [moved from functions/users-update-profile/index.ts] ─────────
        return await handleUpdateProfile(req);
      case 'get-profile':
        // ── [moved from functions/users-get-profile/index.ts] ────────────
        return await handleGetProfile(req);
      case 'unpause-lender':
        // ── escalation follow-up: accounts paused by
        //    apply_loan_term_penalties() (00152) ──────────────────────────
        return await handleUnpauseLender(req);
      case 'request-email-change':
        // Rider / lender: 6-digit OTP sa BAGONG email bago ito maisulat.
        return await handleRequestEmailChange(req);
      case 'confirm-email-change':
        return await handleConfirmEmailChange(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('users-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/users-update-profile/index.ts] ────────────────────
async function handleUpdateProfile(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const body = await req.json();
  const targetId = body.user_id ?? user.id;

  // Only the Head Manager may edit another user's profile. Employees (and
  // self-edits by any role) are handled by the rules below — employees may
  // NOT alter lender/rider data.
  if (targetId !== user.id && user.role !== 'head_manager') {
    return errorResponse('Access denied', 403, 'FORBIDDEN');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: existing } = await db.from('users').select('*').eq('id', targetId).single();
  if (!existing) return errorResponse('User not found', 404, 'NOT_FOUND');

  // Resolve the current role name so the audit snapshot can show the role
  // that was in place before the update (users.role_id only stores the FK).
  const { data: existingRole } = await db
    .from('roles')
    .select('name')
    .eq('id', existing.role_id)
    .maybeSingle();

  const updateFields: Record<string, unknown> = {};
  const allowed = ['first_name', 'middle_name', 'last_name', 'suffix', 'profile_photo_url'];
  for (const f of allowed) {
    if (body[f] !== undefined) updateFields[f] = sanitizeString(body[f]);
  }
  if (body.avatar_url !== undefined) updateFields.profile_photo_url = sanitizeString(body.avatar_url);

  // The app sends `phone_number` (and some legacy clients send `phone`).
  // Accept both so edited phone numbers are actually saved.
  const newPhone = body.phone_number ?? body.phone;
  if (newPhone !== undefined && newPhone !== null && String(newPhone).trim() !== (existing.phone_number ?? '')) {
    // ── MFA policy: pagpapalit ng REHISTRADONG numero ────────────────────
    // Ito ang credential ng OTP login, kaya sensitibo ito. Kapag may VERIFIED
    // TOTP factor ang SARILING account ng nagbabago, kailangan ang `aal2`
    // (natapos na ang authenticator challenge sa session na ito) — hindi
    // sapat ang `aal1` na OTP session. Ang `aal` ay galing sa NAKAPIRMANG
    // token (tingnan ang `requireAuth`), kaya hindi ito maipapasa ng client.
    //
    // Ang HM na nag-e-edit ng IBANG account ay hindi hinihigpitan dito: ang
    // sariling assurance ng HM ang sinusuri ng kanyang session, at may
    // hiwalay (naka-audit) na path para sa mga account na hindi maabot.
    if (targetId === user.id) {
      const mfaGuard = await requireMfaIfEnrolled(db, user);
      if (mfaGuard) return mfaGuard;
    }
    if (!validatePhone(sanitizeString(newPhone))) return errorResponse('Invalid phone', 400, 'VALIDATION_ERROR');
    const { data: taken } = await db.from('users').select('id').eq('phone_number', String(newPhone).trim()).neq('id', targetId).maybeSingle();
    if (taken) return errorResponse('Phone already used', 409, 'DUPLICATE');
    updateFields.phone_number = sanitizeString(String(newPhone));
  }

  // ── Email Uniqueness Check (security) ──────────────────────────────────
  // Head-manager or self-service email change must still enforce
  // case-insensitive uniqueness.  The DB trigger normalises to
  // lower(trim(email)) and `uq_users_email_lower` is the atomic guard;
  // we pre-check with `ilike` for a clean 409.
  // `body.email` is the canonical field; some clients send `body.email`
  // as empty string to clear — treat as not-allowed for accounts that
  // require an email (head_manager / employee).  For rider/lender the
  // trigger will NULL a jireta.temp address anyway.
  if (body.email !== undefined && body.email !== null) {
    const rawEmail = String(body.email).trim();
    // Empty string → caller wants to clear email.  Only allow for rider/lender
    // roles where email is optional; otherwise keep existing email.
    if (rawEmail === '') {
      // Explicit clear: set to NULL so the partial unique index is not hit.
      // Only rider/lender can have NULL email; head_manager/employee must
      // keep their email, so reject empty for them.
      const curRole = existingRole?.name ?? '';
      if (['rider', 'lender'].includes(curRole)) {
        updateFields.email = null;
      } else if (rawEmail !== (existing.email ?? '')) {
        return errorResponse('Email is required', 400, 'VALIDATION_ERROR');
      }
    } else {
      const cleanEmail = rawEmail.toLowerCase();
      // HEAD MANAGER lang: walang @gmail.com / format validation — puwedeng
      // kahit pangalan lang (hal. "juan") ang identifier. Ang ibang roles ay
      // nananatili sa email-format check. Ang GoTrue credential ay ang
      // `credentialEmailFor(cleanEmail)` (tingnan ang sync sa ibaba).
      const targetRole = existingRole?.name ?? '';
      if (targetRole !== 'head_manager' && !validateEmail(cleanEmail)) {
        return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
      }
      // Skip duplicate check if the normalised value equals existing (case-only
      // change is still an update, but not a duplicate of another user).
      const existingNorm = (existing.email ?? '').trim().toLowerCase();
      if (cleanEmail !== existingNorm) {
        // ── Rider / lender: HINDI basta-basta maisusulat ang bagong email ──
        // Kailangan muna ng 6-digit na code sa BAGONG address
        // (`?fn=request-email-change` → `?fn=confirm-email-change`). Ang
        // direktang pag-save dito ay para lang sa staff / Head Manager na
        // nag-e-edit ng account ng iba.
        if (targetId === user.id && ['rider', 'lender'].includes(targetRole)) {
          return errorResponse(
            'Enter the 6-digit code we sent to your new email address to finish the change.',
            400,
            'EMAIL_VERIFICATION_REQUIRED',
          );
        }
        const { data: takenEmail } = await db
          .from('users')
          .select('id')
          .ilike('email', cleanEmail)
          .neq('id', targetId)
          .maybeSingle();
        if (takenEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');
        updateFields.email = cleanEmail;
      } else if (cleanEmail !== existing.email) {
        // Case normalisation only (e.g. Admin@Ex.COM → admin@ex.com)
        updateFields.email = cleanEmail;
      }
    }
  }

  if (body.fcm_token !== undefined) updateFields.fcm_token = body.fcm_token;

  // Account status — head manager only. 'paused' is included so the head
  // manager can also clear an escalation pause from here; employees use the
  // narrower ?fn=unpause-lender action below.
  if (
    body.account_status !== undefined &&
    ['active', 'pending', 'inactive', 'archived', 'paused'].includes(body.account_status) &&
    ['head_manager'].includes(user.role)
  ) {
    updateFields.account_status = body.account_status;
  }

  // Role change — head manager only. Re-shape the one-to-one profile rows so
  // the target role always has a row (with NOT-NULL placeholders) and the
  // other role rows are dropped.
  if (
    body.role &&
    ['head_manager', 'employee', 'rider', 'lender'].includes(body.role) &&
    ['head_manager'].includes(user.role)
  ) {
    let newRole: any = null;
    try {
      const { data } = await db.from('roles').select('id, is_archived').eq('name', body.role).single();
      newRole = data;
      if ((newRole as any)?.is_archived === true) return errorResponse(`Cannot assign archived role '${body.role}'`, 403, 'ROLE_ARCHIVED');
    } catch (_) {
      const { data } = await db.from('roles').select('id').eq('name', body.role).single();
      newRole = data;
    }
    if (!newRole) return errorResponse('Role not found', 404, 'NOT_FOUND');
    if (newRole.id !== existing.role_id) {
      updateFields.role_id = newRole.id;
      if (body.role === 'rider') {
        await db.from('rider_profiles').upsert(
          {
            id: targetId,
            vehicle_type: 'Motorcycle',
            plate_number: 'PENDING',
            drivers_license_number: 'PENDING',
            is_available: true,
          },
          { onConflict: 'id' },
        );
      } else if (body.role === 'employee') {
        await db.from('employee_profiles').upsert(
          {
            id: targetId,
            position: 'Staff',
            hired_at: new Date().toISOString(),
          },
          { onConflict: 'id' },
        );
      } else if (body.role === 'lender') {
        await db.from('lender_profiles').upsert(
          { id: targetId, account_upgrade_status: 'not_submitted' },
          { onConflict: 'id' },
        );
      }
      const drop = async (
        table: 'rider_profiles' | 'employee_profiles' | 'lender_profiles',
      ) => {
        try {
          await db.from(table).delete().eq('id', targetId);
        } catch {
          // ignore: no row to drop or FK still attached
        }
      };
      if (body.role !== 'rider') await drop('rider_profiles');
      if (body.role !== 'employee') await drop('employee_profiles');
      if (body.role !== 'lender') await drop('lender_profiles');
    }
  }

  if (Object.keys(updateFields).length > 0) {
    // ── Display name (Auth dashboard) + LOGIN CREDENTIAL ayon sa GoTrue ─────
    // Sinusundan din nito ang pangalan: kung hindi, `-` ang nakikita ng staff
    // sa Authentication → Users kahit na-update na ang profile. Sinusundan din
    // ang NUMERO (phone + credential email) tuwing may nabago — ang OTP login
    // (`auth-otp?fn=verify-otp`) ay dito naghahanap ng session at kapag hindi
    // sumunod ang credential, "Unable to sign in. Please try again." ang
    // isasagot (tingnan ang [syncAuthUserIdentity]).
    if (
      updateFields.first_name !== undefined ||
      updateFields.last_name !== undefined ||
      updateFields.phone_number !== undefined
    ) {
      // Kapag binago ang numero, dapat SUMUNOD ang credential email ng GoTrue
      // (`${phone}@jireta.temp`): iyon ang hinahanap ng OTP login sa
      // `signInWithPassword({ email })` — lalo na kapag NAKA-DISABLE ang Phone
      // provider ng project ("Phone logins are disabled"), kung saan ang email
      // lang ang tanging paraan ng pagpasok. Hindi ito ginagalaw kapag may
      // TOTOONG email ang account (iyon na ang credential) o kapag may email na
      // ipinapadala ang app (hiwalay na block sa ibaba ang humahawak noon).
      const followPhoneEmail = phoneCredentialEmail(
        String(updateFields.phone_number ?? existing.phone_number ?? ''),
        String(existing.email ?? ''),
        updateFields.email !== undefined,
      );
      const identitySync = await syncAuthUserIdentity(db, targetId, {
        firstName: (updateFields.first_name ?? existing.first_name) as string,
        lastName: (updateFields.last_name ?? existing.last_name) as string,
        phone: (updateFields.phone_number ?? existing.phone_number) as string,
        email: followPhoneEmail || null,
      });
      if (!identitySync.ok) {
        console.error('[users-manage] auth identity sync failed', {
          targetId,
          duplicate: identitySync.duplicate,
          msg: identitySync.error,
        });
        // Bagong numero na gamit na ng IBANG GoTrue login: hindi ito dapat
        // maisulat sa `public.users` — kung hindi, hindi na makakapasok ang
        // may-ari nito (walang credential na tugma sa bagong numero).
        if (updateFields.phone_number !== undefined && identitySync.phoneDuplicate) {
          return errorResponse(
            'Phone number is already registered to another login',
            409,
            'DUPLICATE',
          );
        }
      }
    }

    // Keep GoTrue email in sync when the canonical users.email changes.
    // Do it BEFORE the users row so an auth duplicate fails early and we
    // don't end up with a desynced address.  If auth rejects, surface as 409.
    if (updateFields.email !== undefined && updateFields.email !== null) {
      const newEmail = String(updateFields.email);
      if (newEmail !== existing.email) {
        try {
          const { error: authEmailErr } = await db.auth.admin.updateUserById(
            targetId,
            // GoTrue-valid na credential — `${identifier}@jireta.temp` kapag
            // hindi email-format ang bagong identifier ng head manager.
            { email: credentialEmailFor(newEmail), email_confirm: true },
          );
          if (authEmailErr) {
            const msg = (authEmailErr.message ?? '').toLowerCase();
            if (msg.includes('already') || msg.includes('duplicate') || msg.includes('exists')) {
              return errorResponse('Email already registered', 409, 'DUPLICATE');
            }
            console.error('auth email sync error:', authEmailErr);
            return errorResponse(`Failed to update email: ${authEmailErr.message}`, 400, 'UPDATE_FAILED');
          }
        } catch (e) {
          console.error('auth email sync unexpected:', e);
        }
      }
    }

    const { error: updateError } = await db
      .from('users')
      .update(updateFields)
      .eq('id', targetId);
    if (updateError) {
      console.error('users update error:', updateError);
      const msg = (updateError.message ?? '').toLowerCase();
      const code = (updateError as unknown as { code?: string }).code ?? '';
      if (code === '23505' || msg.includes('duplicate') || msg.includes('uq_users_email_lower') || msg.includes('users_email')) {
        return errorResponse('Email already registered', 409, 'DUPLICATE');
      }
      if (msg.includes('phone_number') && (msg.includes('duplicate') || code === '23505')) {
        return errorResponse('Phone already used', 409, 'DUPLICATE');
      }
      return errorResponse(
        `Failed to update user: ${updateError.message}`,
        400,
        'UPDATE_FAILED',
      );
    }
  }

  // Rider profile — accept both the flat mobile payload and the nested form.
  if (body.rider_profile || body.plate_number || body.drivers_license_number || body.vehicle_type || body.vehicle_brand) {
    const rp = body.rider_profile ?? body;
    await db.from('rider_profiles').update({
      vehicle_type: rp.vehicle_type !== undefined && rp.vehicle_type !== null && rp.vehicle_type !== ''
        ? (normalizeVehicleType(rp.vehicle_type) ?? undefined)
        : undefined,
      plate_number: rp.plate_number ? sanitizeString(rp.plate_number).toUpperCase() : undefined,
      vehicle_brand: rp.vehicle_brand ? sanitizeString(rp.vehicle_brand) : undefined,
      drivers_license_number: rp.drivers_license_number ? sanitizeString(rp.drivers_license_number) : undefined,
      drivers_license_expiry: rp.drivers_license_expiry ?? undefined,
    }).eq('id', targetId);
  }

  // Lender profile — accept both the flat mobile payload and the nested form.
  // NOTE (00128): only IDENTITY fields are edited here (gender / civil status /
  // DOB). Employment, income and source of funds are no longer profile data —
  // they are declared per loan and snapshot onto loans / loan_emergency_contacts.
  const lp = body.lender_profile ?? (body.gender || body.civil_status || body.dob ||
    body.date_of_birth
    ? body : null);

  if (lp) {
    const dob = lp.dob ?? lp.date_of_birth;
    await db.from('lender_profiles').update({
      gender: lp.gender !== undefined && lp.gender !== null && lp.gender !== ''
        ? (normalizeEnum(lp.gender) ?? undefined)
        : undefined,
      civil_status: lp.civil_status !== undefined && lp.civil_status !== null && lp.civil_status !== ''
        ? (normalizeEnum(lp.civil_status) ?? undefined)
        : undefined,
      date_of_birth: dob ? String(dob).substring(0, 10) : undefined,
    }).eq('id', targetId);
  }

  // Address lives in the addresses table now (3NF) — upsert the primary home address.
  const hasAddressField =
    body.street_address !== undefined || body.barangay !== undefined ||
    body.city !== undefined || body.province !== undefined || body.zip_code !== undefined ||
    lp?.street_address !== undefined || lp?.barangay !== undefined ||
    lp?.city !== undefined || lp?.province !== undefined || lp?.zip_code !== undefined;

  if (hasAddressField) {
    const addr = lp ?? body;
    const { data: existingAddr } = await db
      .from('addresses')
      .select('id')
      .eq('user_id', targetId)
      .eq('address_type', 'home')
      .eq('is_primary', true)
      .maybeSingle();
    if (existingAddr) {
      await db.from('addresses').update({
        street: addr.street_address !== undefined ? sanitizeString(addr.street_address) : undefined,
        barangay: addr.barangay !== undefined ? sanitizeString(addr.barangay) : undefined,
        city: addr.city !== undefined ? sanitizeString(addr.city) : undefined,
        province: addr.province !== undefined ? sanitizeString(addr.province) : undefined,
        zip_code: addr.zip_code !== undefined ? sanitizeString(addr.zip_code) : undefined,
      }).eq('id', existingAddr.id);
      // Coordinates (pin ng rider maps): `overwrite` dahil nag-EDIT ng address
      // text — kung hindi, stale na pin ang mananatili sa lumang address.
      geocodeInBackground(db, [existingAddr.id], { overwrite: true });
    } else if (addr.street_address && addr.barangay && addr.city && addr.province) {
      const { data: inserted } = await db.from('addresses').insert({
        user_id: targetId,
        address_type: 'home',
        street: sanitizeString(addr.street_address),
        barangay: sanitizeString(addr.barangay),
        city: sanitizeString(addr.city),
        province: sanitizeString(addr.province),
        zip_code: addr.zip_code ? sanitizeString(addr.zip_code) : null,
        is_primary: true,
      }).select('id').single();
      geocodeInBackground(db, [inserted?.id as string | undefined]);
    }
  }

  // Employee profile — HM may edit anyone; staff may edit their OWN
  // date_of_birth (self-service via My Profile). Position stays HM-only.
  // Gender / civil status / DOB are editable by HM for any staff row, and
  // by staff for their own row (Edit User modal + My Profile).
  if (body.employee_profile && (user.role === 'head_manager' || (targetId === user.id && ['head_manager', 'employee'].includes(user.role)))) {
    const ep = body.employee_profile;
    const patch: Record<string, unknown> = {};
    if (user.role === 'head_manager' && ep.position) patch.position = sanitizeString(ep.position);
    if (ep.gender !== undefined && ep.gender !== null && String(ep.gender).trim() !== '') {
      const g = sanitizeString(String(ep.gender)).trim().toLowerCase();
      if (!['male', 'female', 'other'].includes(g)) {
        return errorResponse('Invalid gender', 400, 'VALIDATION_ERROR');
      }
      patch.gender = g;
    }
    if (ep.civil_status !== undefined && ep.civil_status !== null && String(ep.civil_status).trim() !== '') {
      const c = sanitizeString(String(ep.civil_status)).trim().toLowerCase();
      if (!['single', 'married', 'widowed', 'separated'].includes(c)) {
        return errorResponse('Invalid civil status', 400, 'VALIDATION_ERROR');
      }
      patch.civil_status = c;
    }
    if (ep.date_of_birth !== undefined && ep.date_of_birth !== null && String(ep.date_of_birth).trim() !== '') {
      const dob = String(ep.date_of_birth).trim().substring(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || Number.isNaN(new Date(dob + 'T00:00:00Z').getTime())) {
        return errorResponse('Invalid date of birth format (YYYY-MM-DD)', 400, 'VALIDATION_ERROR');
      }
      if (dob > new Date().toISOString().split('T')[0]) {
        return errorResponse('Date of birth cannot be in the future', 400, 'VALIDATION_ERROR');
      }
      patch.date_of_birth = dob;
    }
    if (Object.keys(patch).length > 0) {
      // Legacy staff rows (head managers created before the profile row
      // existed) may have no employee_profiles row — update, else insert
      // with safe defaults so the edit is never silently lost.
      const { data: existingEp } = await db
        .from('employee_profiles')
        .select('id')
        .eq('id', targetId)
        .maybeSingle();
      if (existingEp) {
        await db.from('employee_profiles').update(patch).eq('id', targetId);
      } else {
        const targetRoleName = (existingRole as { name?: string } | null)?.name ?? 'employee';
        const { error: epInsertErr } = await db.from('employee_profiles').insert({
          id: targetId,
          position: targetRoleName === 'head_manager' ? 'Head Manager' : 'Staff',
          hired_at: new Date().toISOString().split('T')[0],
          ...patch,
        });
        if (epInsertErr) {
          console.error('employee profile upsert error:', epInsertErr);
          return errorResponse(`Failed to update staff profile: ${epInsertErr.message}`, 400, 'UPDATE_FAILED');
        }
      }
    }
  }

  // Build a readable newValues snapshot so the audit trail shows what changed
  // (role / account_status / profile edits) — not just the "before" state.
  const newValues: Record<string, unknown> = {
    first_name: updateFields.first_name ?? existing.first_name,
    middle_name: updateFields.middle_name ?? existing.middle_name,
    last_name: updateFields.last_name ?? existing.last_name,
    suffix: updateFields.suffix ?? existing.suffix,
    email: updateFields.email !== undefined ? updateFields.email : existing.email,
    phone_number: updateFields.phone_number ?? existing.phone_number,
    account_status: updateFields.account_status ?? existing.account_status,
    role: body.role ?? existingRole?.name ?? undefined,
  };
  // Drop undefined keys so the stored JSON stays clean.
  Object.keys(newValues).forEach((k) => {
    if (newValues[k] === undefined) delete newValues[k];
  });

  await writeAuditLog({ performedBy: user.id, action: 'update_profile', tableName: 'users', recordId: targetId, oldValues: existing, newValues, ipAddress: ip });

  return jsonResponse({ message: 'Profile updated successfully' });
}

// ── [moved from functions/users-get-profile/index.ts] ───────────────────────
async function handleGetProfile(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const url = new URL(req.url);
  const targetId = url.searchParams.get('user_id') ?? user.id;

  if (targetId !== user.id) {
    if (user.role === ROLES.RIDER || user.role === ROLES.LENDER) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
    if (user.role === ROLES.EMPLOYEE) {
      const db = getAdminClient();
      const { data: targetUser } = await db.from('users').select('roles!users_role_id_fkey(name)').eq('id', targetId).single();
      const targetRole = embedAsObject(targetUser?.roles)?.name;
      if (!['rider', 'lender'].includes(targetRole)) {
        return errorResponse('Access denied', 403, 'FORBIDDEN');
      }
    }
  }

  const db = getAdminClient();
  // Unified select string — explicit FK hint on roles required after 00115
  // (roles.archived_by -> users.id creates a second users<->roles path, so
  // plain `roles(id,name)` throws PGRST "more than one relationship").
  // lender_profiles has single path, plain is fine.
  // `terms_accepted_at` — SERVER-side na katibayan ng one-time Terms &
  // Conditions acceptance (isinusulat ng auth-session ?fn=terms-accept). Ito
  // ang basehan ng app para hindi na ipakita muli ang Terms / Fill In
  // Information sa existing account (kahit bagong install o bagong device).
  const PROFILE_SELECT = `id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
      force_password_change, last_login_at, created_at, profile_photo_url,
      terms_accepted_at,
      roles!users_role_id_fkey(id, name),
      employee_profiles(position, hired_at, gender, civil_status, date_of_birth),
      rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
      lender_profiles(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`;
  let { data, error } = await db
    .from('users')
    .select(PROFILE_SELECT)
    .eq('id', targetId)
    .maybeSingle();

  // Fallback for legacy mismatched auth/public IDs (common for mobile OTP accounts):
  // if id lookup fails, try phone/email from the verified token. This ensures
  // riders/lenders who were created via self-register or old scripts still see
  // their profile instead of "User not found" (404).
  // NOTE: Always尝试 fallback even when user_id was explicitly supplied,
  // because the supplied id (e.g. stale SecureStorage id 21fc2fcb...) may itself
  // be the mismatched auth id that does not exist in public.users (see Log 1).
  if (error || !data) {
    let fallbackData: typeof data | null = null;
    let fallbackError: typeof error | null = null;
    if (user.phone) {
      const rawPhone = String(user.phone ?? '').trim();
      const digits = rawPhone.replace(/\D/g, '');
      const localPhone = digits.startsWith('63') ? '0' + digits.slice(2) : rawPhone;
      const e164Phone = digits.startsWith('63') ? `+${digits}` : digits.startsWith('0') ? `+63${digits.slice(1)}` : `+63${digits}`;
      for (const cand of [...new Set([localPhone, e164Phone, rawPhone])]) {
        const res = await db
          .from('users')
          .select(PROFILE_SELECT)
          .eq('phone_number', cand)
          .maybeSingle();
        if (res.data) {
          fallbackData = res.data;
          fallbackError = res.error;
          break;
        }
        fallbackError = res.error;
      }
      // Fuzzy fallback: try last 9/10 digits with ilike (handles spaces/dashes in DB)
      if (!fallbackData) {
        const last9 = digits.slice(-9);
        const last10 = digits.slice(-10);
        for (const pat of [`%${last9}`, `%${last10}`]) {
          const res = await db
            .from('users')
            .select(PROFILE_SELECT)
            .ilike('phone_number', pat)
            .maybeSingle();
          if (res.data) {
            fallbackData = res.data;
            fallbackError = res.error;
            console.warn('[users-manage] get-profile recovered via fuzzy phone', { pattern: pat, recoveredId: (res.data as { id?: string })?.id });
            break;
          }
        }
      }
    }
    if (!fallbackData && user.email) {
      const rawEmail = String(user.email).trim().toLowerCase();
      // Synthetic jireta.temp emails are GoTrue-only; public.users stores NULL for lenders.
      // Skip email fallback for those to avoid false miss.
      const isSynthetic = rawEmail.endsWith('@jireta.temp');
      if (!isSynthetic) {
        const res = await db
          .from('users')
          .select(PROFILE_SELECT)
          .ilike('email', rawEmail)
          .maybeSingle();
        if (res.data) {
          fallbackData = res.data;
          fallbackError = res.error;
        } else {
          fallbackError = res.error;
        }
      } else {
        console.warn('[users-manage] skipped synthetic email fallback', { rawEmail });
      }
    }
    if (fallbackData) {
      console.warn('[users-manage] get-profile id miss, recovered via phone/email fallback', { targetId, recoveredId: (fallbackData as { id?: string })?.id });
      data = fallbackData;
      error = fallbackError as typeof error;
    }
  }

  if (error || !data) {
    console.error('[users-manage] get-profile still not found', {
      targetId,
      authId: user.id,
      authPhone: user.phone,
      authEmail: user.email,
      authRole: user.role,
      dbError: error?.message ?? null,
      fallbackTried: true,
    });
    return errorResponse(
      `User not found (id=${targetId} phone=${user.phone ?? 'null'} email=${user.email ?? 'null'} role=${user.role})`,
      404,
      'NOT_FOUND',
      { targetId, authId: user.id, phone: user.phone, email: user.email, role: user.role },
    );
  }

  // After fallback, the canonical id lives in `data.id` — use it, not the stale `targetId`.
  const canonicalId = (data as { id: string }).id;
  const { data: emergencyContacts } = await db
    .from('emergency_contacts')
    .select('id, name, relationship, phone_number, address')
    .eq('lender_id', canonicalId);

  const address = await getLenderAddress(db, canonicalId);

  // Flatten nested profile rows onto the user so the mobile/web models can
  // read position, plate_number, etc. straight off the object.
  const emp = embedAsObject(data?.employee_profiles);
  const rider = embedAsObject(data?.rider_profiles);
  const lender = embedAsObject(data?.lender_profiles);

  // Walk-in origin flag for lender — mirrors kyc-view logic: show "Created via Walk-in"
  let inOfficeApplication: Record<string, unknown> | null = null;
  let isWalkIn = false;
  try {
    if (lender) {
      const { data: ioApp } = await db.from('in_office_applications')
        .select('id,status,wizard_step,created_at,created_by,lender_id,users!in_office_applications_created_by_fkey(first_name,last_name)')
        .eq('lender_id', canonicalId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (ioApp) {
        inOfficeApplication = ioApp as unknown as Record<string, unknown>;
        isWalkIn = true;
      } else {
        // fallback phone match for legacy where lender_id not yet linked
        const { data: rawUser } = await db.from('users').select('phone_number').eq('id', canonicalId).maybeSingle();
        const phone = (rawUser as any)?.phone_number;
        if (phone) {
          const { data: match } = await db.from('application_personal_info')
            .select('application_id, in_office_applications!inner(id,status,created_at,created_by,lender_id,users!in_office_applications_created_by_fkey(first_name,last_name))')
            .eq('phone_number', phone)
            .limit(1)
            .maybeSingle();
          const app = (match as any)?.in_office_applications;
          if (app && (app.status === 'submitted' || app.status === 'converted')) {
            inOfficeApplication = app;
            isWalkIn = true;
          }
        }
      }
    }
  } catch (_) {}

  // ── Per-lender insights (outstanding balance + early-payer detection) ──
  // Nakikita ito ng Head Manager / Employee sa Lender Details. Best-effort:
  // kapag nabigo ang RPC, blangko na lang ang mga field at hindi masisira ang
  // buong profile.
  let lenderInsights: Record<string, unknown> | null = null;
  const targetRole = (embedAsObject((data as any)?.roles)?.name ?? '') as string;
  if (targetRole === 'lender') {
    try {
      const { data: insightRows, error: insightErr } = await (db as any).rpc(
        'lender_payment_insights',
        { p_lender_ids: [canonicalId] },
      );
      if (insightErr) {
        console.error('lender_payment_insights (profile) failed:', insightErr.message);
      } else {
        lenderInsights = (insightRows ?? [])[0] ?? null;
      }
    } catch (err) {
      console.error('lender_payment_insights (profile) threw:', err);
    }
  }

  const flattened = {
    ...data,
    position: emp?.position ?? null,
    hired_at: emp?.hired_at ?? null,
    gender: lender?.gender ?? emp?.gender ?? null,
    civil_status: lender?.civil_status ?? emp?.civil_status ?? null,
    plate_number: rider?.plate_number ?? null,
    drivers_license_number: rider?.drivers_license_number ?? null,
    drivers_license_expiry: rider?.drivers_license_expiry ?? null,
    vehicle_brand: rider?.vehicle_brand ?? null,
    vehicle_type: rider?.vehicle_type ?? null,
    is_available: rider?.is_available ?? null,
    // Ang `address` (00165) ay HINDI kasama sa PROFILE_SELECT — hindi ito
    // binabasa ng app (buo na ang address sa `street_address`/`barangay`/…
    // mula sa `addresses` table sa ibaba). Iniwan nating ganito para hindi
    // sumandal ang get-profile sa isang column na maaaring wala pa sa isang
    // environment; type-level cast lang ito, walang pagbabago sa runtime.
    rider_address: (rider as { address?: string | null } | null)?.address ?? null,
    employment_type: lender?.employment_type ?? null,
    employer_name: lender?.employer_name ?? null,
    monthly_income: lender?.monthly_income ?? null,
    gcash_number: lender?.gcash_number ?? null,
    account_upgrade_status: lender?.account_upgrade_status ?? null,
    date_of_birth: (emp as any)?.date_of_birth ?? lender?.date_of_birth ?? null,
    source_of_funds: lender?.source_of_funds ?? null,
    street_address: address?.street ?? null,
    barangay: address?.barangay ?? null,
    city: address?.city ?? null,
    province: address?.province ?? null,
    zip_code: address?.zip_code ?? null,
    emergency_contacts: emergencyContacts ?? [],
    in_office_application: inOfficeApplication,
    is_walk_in: isWalkIn,
    // Current outstanding balance + payment behavior (lenders only).
    outstanding_balance: Number(lenderInsights?.outstanding_balance ?? 0),
    active_loans_count: Number(lenderInsights?.active_loans_count ?? 0),
    settled_loans_count: Number(lenderInsights?.settled_loans_count ?? 0),
    verified_payment_count: Number(lenderInsights?.verified_payment_count ?? 0),
    on_time_payment_count: Number(lenderInsights?.on_time_payment_count ?? 0),
    late_payment_count: Number(lenderInsights?.late_payment_count ?? 0),
    max_days_early: Number(lenderInsights?.max_days_early ?? 0),
    is_early_payer: Boolean(lenderInsights?.is_early_payer ?? false),
  };

  return jsonResponse({ user: flattened });
}

// ── [escalation follow-up] users-unpause-lender ──────────────────────────────
// Inaalis ang account pause na awtomatikong ibinigay ng
// apply_loan_term_penalties() (00152) kapag pangalawa nang natapos ang loan
// term ng lender na may utang.
//
// Hiwalay na action ito (imbes na buksan ang update-profile para sa
// employee) para HIGPIT ang saklaw: HM o Employee, lender lang, 'paused' →
// 'active' lang, at naka-reset ang term_default_count para malinis ang
// escalation counter pagkatapos ng review.
async function handleUnpauseLender(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const { user_id, reason } = await req.json();
  if (!user_id) return errorResponse('user_id is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: target } = await db
    .from('users')
    .select('id, account_status, roles!users_role_id_fkey(name)')
    .eq('id', user_id)
    .maybeSingle();
  if (!target) return errorResponse('User not found', 404, 'NOT_FOUND');

  const role = (target as any)?.roles?.name as string | undefined;
  if (role !== 'lender') {
    return errorResponse('Only lender accounts can be unpaused here', 400, 'INVALID_ROLE');
  }
  if (target.account_status !== 'paused') {
    return errorResponse('Account is not paused', 400, 'INVALID_STATUS');
  }

  await db.from('users').update({ account_status: 'active' }).eq('id', user_id);
  // Malinis na ang escalation counter pagkatapos ng review — ang susunod na
  // term default ay muling mag-o-pause (count restarts at 1).
  await db.from('lender_profiles').update({ term_default_count: 0 }).eq('id', user_id);

  await writeAuditLog({
    performedBy: user.id,
    action: 'unpause_lender',
    tableName: 'users',
    recordId: user_id,
    oldValues: { account_status: 'paused' },
    newValues: { account_status: 'active', reason: reason ?? 'Unpaused by staff' },
    ipAddress: ip,
  });

  await sendPushNotification({
    userId: user_id,
    title: 'Account Reactivated',
    body: 'Your account has been reactivated. You can now use the app and apply for a new loan. Please settle any outstanding balance to avoid another pause.',
    type: 'account_status_change',
    referenceId: user_id,
    sentBy: user.id,
  });

  return jsonResponse({ success: true, account_status: 'active' });
}

// ══ Pagbabago ng email ng rider / lender — 6-digit OTP sa BAGONG address ═════
// Ang email ay isa sa mga credential/contact ng account, kaya hindi na
// basta-basta maisusulat: (1) humihingi ang app ng code, (2) ipinapadala ito sa
// BAGONG email, at (3) dito lang naisusulat ang pagbabago pagkatapos ng
// tamang code. Hiwalay ang purpose para hindi magamit ang login OTP.
const EMAIL_CHANGE_PURPOSE = EMAIL_CHANGE_OTP_PURPOSE;
/** Gaano katagal bago ma-expire ang code. */
const EMAIL_CHANGE_OTP_EXPIRY_MINUTES = 10;
/** Pagitan bago muling makapag-resend (iwas-spam / dobleng pindot). */
const EMAIL_CHANGE_RESEND_SECONDS = 60;
/** Bilang ng maling code bago kailangang humingi ng bago. */
const EMAIL_CHANGE_MAX_ATTEMPTS = 5;
const EMAIL_CHANGE_ROLES = ['rider', 'lender'];

/** Tapat na paliwanag kung bakit hindi naipadala ang code (galing sa helper). */
function emailChangeSendFailureMessage(result: {
  kind?: string;
  status?: number;
}): string {
  switch (result.kind) {
    case 'no_api_key':
      return 'Hindi pa naka-configure ang pagpapadala ng email. Please contact the office.';
    case 'invalid_api_key':
      return 'May problema sa email service (invalid API key). Please contact the office.';
    case 'sender_not_verified':
      return 'Hindi pa verified ang sender ng email, kaya hindi ito makakarating sa ibang address. Please contact the office.';
    case 'recipient_rejected':
      return 'Tinanggihan ng email service ang address na ito. Please check it and try again.';
    case 'rate_limited':
      return 'Masyadong maraming email na hiniling. Please wait a minute and try again.';
    case 'timeout':
      return 'Nag-timeout ang email service. Please try again.';
    default:
      return 'Hindi naipadala ang verification code. Please check the address or try again.';
  }
}

/** Ang account na binabago (sarili lang — walang `user_id` na tinatanggap). */
async function loadEmailChangeAccount(
  db: ReturnType<typeof getAdminClient>,
  userId: string,
) {
  const { data } = await db
    .from('users')
    .select('id, first_name, email, roles!users_role_id_fkey(name)')
    .eq('id', userId)
    .maybeSingle();
  return data;
}

function emailChangeRoleOf(account: unknown): string | undefined {
  const raw = (account as { roles?: unknown } | null)?.roles;
  // Ang embed ay pwedeng object o one-item array (depende sa cardinality).
  const obj = Array.isArray(raw) ? raw[0] : raw;
  const name = (obj as { name?: unknown } | null)?.name;
  return typeof name === 'string' ? name : undefined;
}

// ── ?fn=request-email-change ────────────────────────────────────────────────
async function handleRequestEmailChange(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const email = sanitizeString(
    String((body as { email?: unknown }).email ?? ''),
  ).trim().toLowerCase();

  if (!validateEmail(email)) {
    return errorResponse('Enter a valid email address', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const account = await loadEmailChangeAccount(db, user.id);
  if (!account) return errorResponse('User not found', 404, 'NOT_FOUND');

  const role = emailChangeRoleOf(account);
  if (!role || !EMAIL_CHANGE_ROLES.includes(role)) {
    return errorResponse(
      'Changing email here is for rider and lender accounts only',
      403,
      'FORBIDDEN',
    );
  }

  if (email === String(account.email ?? '').trim().toLowerCase()) {
    return errorResponse(
      'That is already your email address',
      400,
      'EMAIL_UNCHANGED',
    );
  }

  // Maagang 409 para malinaw sa app kung hindi available ang address.
  const { data: taken } = await db
    .from('users')
    .select('id')
    .ilike('email', email)
    .neq('id', user.id)
    .maybeSingle();
  if (taken) return errorResponse('Email already registered', 409, 'DUPLICATE');

  // Iwas-spam: 5 kahilingan kada oras kada account (may 60s na cooldown pa).
  const guard = await guardRateLimit({
    key: `email-change:${user.id}`,
    maxAttempts: 5,
    windowMinutes: 60,
    blockMinutes: 60,
    blockReason: 'Too many email change requests',
    eventType: 'email_change_rate_limited',
    userId: user.id,
    ipAddress: ip,
  });
  if (!guard.allowed) {
    return errorResponse(
      'Too many verification codes requested. Please try again later.',
      429,
      'RATE_LIMITED',
      { retry_after_seconds: guard.block?.retryAfterSeconds ?? 3600 },
    );
  }

  // Ang `otp_codes.phone_number` ay ang salting key. Para sa email, stable na
  // synthetic key ang gamit — 20 chars, kasya sa VARCHAR(20).
  const key = await emailOtpKey(email);

  const { data: latest } = await db
    .from('otp_codes')
    .select('created_at')
    .eq('phone_number', key)
    .eq('purpose', EMAIL_CHANGE_PURPOSE)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const wait = resendCooldownRemaining(
    latest?.created_at as string | null,
    EMAIL_CHANGE_RESEND_SECONDS,
  );
  if (wait > 0) {
    return errorResponse(
      `Please wait ${wait} second(s) before requesting another code.`,
      429,
      'RESEND_COOLDOWN',
      { retry_after_seconds: wait },
    );
  }

  const otp = generateOtpCode();
  const otpHash = await hashOtpCode(otp, key);
  const expiresAt = new Date(
    Date.now() + EMAIL_CHANGE_OTP_EXPIRY_MINUTES * 60000,
  ).toISOString();

  // Isang buhay na code lang: patayin ang mga lumang hindi pa nagamit.
  await db
    .from('otp_codes')
    .update({ used: true })
    .eq('phone_number', key)
    .eq('purpose', EMAIL_CHANGE_PURPOSE)
    .eq('used', false);

  const { error: insertErr } = await db.from('otp_codes').insert({
    phone_number: key,
    otp_hash: otpHash,
    purpose: EMAIL_CHANGE_PURPOSE,
    expires_at: expiresAt,
  });
  if (insertErr) {
    console.error('[email-change] OTP insert failed:', insertErr.message);
    return errorResponse(
      'We could not create a verification code. Please try again.',
      500,
      'INSERT_FAILED',
    );
  }

  const recipientName = typeof account.first_name === 'string'
    ? account.first_name
    : undefined;
  const sendResult = await sendEmailChangeOtpEmail({
    to: email,
    otp,
    recipientName,
    expiresInMinutes: EMAIL_CHANGE_OTP_EXPIRY_MINUTES,
  });

  if (!sendResult.ok) {
    console.error(
      `[email-change] Resend failed [${sendResult.kind ?? 'http_error'}] ` +
        `status=${sendResult.status ?? 'n/a'}:`,
      sendResult.error,
    );
    // Huwag iwang buhay ang code na hindi naman naipadala.
    await db.from('otp_codes').update({ used: true }).eq('otp_hash', otpHash);
    return errorResponse(
      emailChangeSendFailureMessage(sendResult),
      502,
      'EMAIL_SEND_FAILED',
    );
  }

  console.log(`[email-change] verification code sent to ${email}`);
  return jsonResponse({
    message: `We sent a 6-digit verification code to ${email}.`,
    email,
    expires_in: EMAIL_CHANGE_OTP_EXPIRY_MINUTES * 60,
    resend_in: EMAIL_CHANGE_RESEND_SECONDS,
  });
}

// ── ?fn=confirm-email-change ────────────────────────────────────────────────
async function handleConfirmEmailChange(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const email = sanitizeString(
    String((body as { email?: unknown }).email ?? ''),
  ).trim().toLowerCase();
  const otp = String((body as { otp?: unknown }).otp ?? '').replace(/\D/g, '');

  if (!validateEmail(email)) {
    return errorResponse('Enter a valid email address', 400, 'VALIDATION_ERROR');
  }
  if (otp.length !== OTP_CODE_LENGTH) {
    return errorResponse(
      'Enter the 6-digit code sent to your new email address',
      400,
      'VALIDATION_ERROR',
    );
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const account = await loadEmailChangeAccount(db, user.id);
  if (!account) return errorResponse('User not found', 404, 'NOT_FOUND');

  const role = emailChangeRoleOf(account);
  if (!role || !EMAIL_CHANGE_ROLES.includes(role)) {
    return errorResponse(
      'Changing email here is for rider and lender accounts only',
      403,
      'FORBIDDEN',
    );
  }

  const key = await emailOtpKey(email);
  const { data: row } = await db
    .from('otp_codes')
    .select('id, otp_hash, attempts, expires_at, used, purpose')
    .eq('phone_number', key)
    .eq('purpose', EMAIL_CHANGE_PURPOSE)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const submittedHash = await hashOtpCode(otp, key);
  const reason = otpRejectionReason(row, {
    purpose: EMAIL_CHANGE_PURPOSE,
    submittedHash,
    maxAttempts: EMAIL_CHANGE_MAX_ATTEMPTS,
  });

  const rowId = (row as { id?: string } | null)?.id;
  const attempts = Number((row as { attempts?: number } | null)?.attempts ?? 0);

  if (reason) {
    if (rowId && (reason === 'mismatch' || reason === 'too_many_attempts')) {
      await db.from('otp_codes').update({ attempts: attempts + 1 }).eq('id', rowId);
    }
    if (reason === 'not_found' || reason === 'expired' || reason === 'used') {
      return errorResponse(
        'This code has expired. Please request a new one.',
        400,
        'OTP_EXPIRED',
      );
    }
    if (reason === 'too_many_attempts') {
      return errorResponse(
        'Too many incorrect codes. Please request a new one.',
        429,
        'OTP_LOCKED',
      );
    }
    const attemptsLeft = Math.max(
      0,
      EMAIL_CHANGE_MAX_ATTEMPTS - (attempts + 1),
    );
    return errorResponse(
      `Incorrect code. ${attemptsLeft} attempt(s) left.`,
      400,
      'OTP_INVALID',
      { attempts_left: attemptsLeft },
    );
  }

  // Muling tsekan: baka may nakakuha na ng address habang hinihintay ang code.
  const { data: taken } = await db
    .from('users')
    .select('id')
    .ilike('email', email)
    .neq('id', user.id)
    .maybeSingle();
  if (taken) return errorResponse('Email already registered', 409, 'DUPLICATE');

  const nowIso = new Date().toISOString();

  // GoTrue credential muna (kapareho ng update-profile) para hindi maiwang
  // desynced ang login credential at ang canonical `users.email`.
  try {
    const { error: authEmailErr } = await db.auth.admin.updateUserById(
      user.id,
      { email: credentialEmailFor(email), email_confirm: true },
    );
    if (authEmailErr) {
      const msg = (authEmailErr.message ?? '').toLowerCase();
      if (
        msg.includes('already') ||
        msg.includes('duplicate') ||
        msg.includes('exists')
      ) {
        return errorResponse('Email already registered', 409, 'DUPLICATE');
      }
      console.error('[email-change] auth email sync error:', authEmailErr);
      return errorResponse(
        `Failed to update email: ${authEmailErr.message}`,
        400,
        'UPDATE_FAILED',
      );
    }
  } catch (e) {
    console.error('[email-change] auth email sync unexpected:', e);
  }

  const { error: updateErr } = await db
    .from('users')
    .update({ email, email_verified_at: nowIso })
    .eq('id', user.id);
  if (updateErr) {
    console.error('[email-change] users update error:', updateErr);
    const msg = (updateErr.message ?? '').toLowerCase();
    if (msg.includes('duplicate') || msg.includes('uq_users_email_lower')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    return errorResponse(
      `Failed to update email: ${updateErr.message}`,
      400,
      'UPDATE_FAILED',
    );
  }

  if (rowId) {
    await db.from('otp_codes').update({ used: true }).eq('id', rowId);
  }

  await writeAuditLog({
    performedBy: user.id,
    action: 'update_email',
    tableName: 'users',
    recordId: user.id,
    oldValues: { email: account.email },
    newValues: { email, email_verified_at: nowIso },
    ipAddress: ip,
  });

  return jsonResponse({
    message: 'Email updated and verified.',
    email,
    verified_at: nowIso,
  });
}