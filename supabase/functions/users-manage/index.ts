// supabase/functions/users-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-update-profile →  ?fn=update-profile
//   users-get-profile    →  ?fn=get-profile
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validateEmail, validatePhone, normalizeVehicleType } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { getLenderAddress } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

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

  if (body.phone && body.phone !== existing.phone_number) {
    if (!validatePhone(sanitizeString(body.phone))) return errorResponse('Invalid phone', 400, 'VALIDATION_ERROR');
    const { data: taken } = await db.from('users').select('id').eq('phone_number', body.phone.trim()).neq('id', targetId).maybeSingle();
    if (taken) return errorResponse('Phone already used', 409, 'DUPLICATE');
    updateFields.phone_number = body.phone.trim();
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
      if (!validateEmail(cleanEmail)) return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
      // Skip duplicate check if the normalised value equals existing (case-only
      // change is still an update, but not a duplicate of another user).
      const existingNorm = (existing.email ?? '').trim().toLowerCase();
      if (cleanEmail !== existingNorm) {
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

  // Account status — head manager only.
  if (
    body.account_status !== undefined &&
    ['active', 'pending', 'inactive', 'archived'].includes(body.account_status) &&
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
    // Keep GoTrue email in sync when the canonical users.email changes.
    // Do it BEFORE the users row so an auth duplicate fails early and we
    // don't end up with a desynced address.  If auth rejects, surface as 409.
    if (updateFields.email !== undefined && updateFields.email !== null) {
      const newEmail = String(updateFields.email);
      if (newEmail !== existing.email) {
        try {
          const { error: authEmailErr } = await db.auth.admin.updateUserById(
            targetId,
            { email: newEmail, email_confirm: true },
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
  const lp = body.lender_profile ?? (body.gender || body.civil_status || body.dob ||
    body.date_of_birth || body.employment_type || body.employer_name ||
    body.monthly_income || body.source_of_funds
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
      employment_type: lp.employment_type !== undefined && lp.employment_type !== null && lp.employment_type !== ''
        ? (normalizeEnum(lp.employment_type) ?? undefined)
        : undefined,
      employer_name: lp.employer_name ? sanitizeString(lp.employer_name) : undefined,
      monthly_income: lp.monthly_income !== undefined && lp.monthly_income !== null && lp.monthly_income !== ''
        ? Number(lp.monthly_income)
        : undefined,
      source_of_funds: lp.source_of_funds ? normalizeEnum(lp.source_of_funds) : undefined,
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
    } else if (addr.street_address && addr.barangay && addr.city && addr.province) {
      await db.from('addresses').insert({
        user_id: targetId,
        address_type: 'home',
        street: sanitizeString(addr.street_address),
        barangay: sanitizeString(addr.barangay),
        city: sanitizeString(addr.city),
        province: sanitizeString(addr.province),
        zip_code: addr.zip_code ? sanitizeString(addr.zip_code) : null,
        is_primary: true,
      });
    }
  }

  if (body.employee_profile && ['head_manager'].includes(user.role)) {
    const ep = body.employee_profile;
    await db.from('employee_profiles').update({
      department: ep.department ? sanitizeString(ep.department) : undefined,
      position: ep.position ? sanitizeString(ep.position) : undefined,
    }).eq('id', targetId);
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
  let { data, error } = await db
    .from('users')
    .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
      force_password_change, last_login_at, created_at, profile_photo_url,
      roles(id, name),
      employee_profiles(department, position, hired_at, gender, civil_status),
      rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
      lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`)
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
          .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
            force_password_change, last_login_at, created_at, profile_photo_url,
            roles(id, name),
            employee_profiles(department, position, hired_at, gender, civil_status),
            rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
            lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`)
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
            .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
              force_password_change, last_login_at, created_at, profile_photo_url,
              roles(id, name),
              employee_profiles(department, position, hired_at, gender, civil_status),
              rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
              lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`)
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
      const res = await db
        .from('users')
        .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
          force_password_change, last_login_at, created_at, profile_photo_url,
          roles(id, name),
          employee_profiles(department, position, hired_at, gender, civil_status),
          rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
          lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`)
        .ilike('email', String(user.email).trim().toLowerCase())
        .maybeSingle();
      if (res.data) {
        fallbackData = res.data;
        fallbackError = res.error;
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

  const { data: emergencyContacts } = await db
    .from('emergency_contacts')
    .select('id, name, relationship, phone_number, address')
    .eq('lender_id', targetId);

  const address = await getLenderAddress(db, targetId);

  // Flatten nested profile rows onto the user so the mobile/web models can
  // read department, position, plate_number, etc. straight off the object.
  const emp = embedAsObject(data?.employee_profiles);
  const rider = embedAsObject(data?.rider_profiles);
  const lender = embedAsObject(data?.lender_profiles);

  const flattened = {
    ...data,
    department: emp?.department ?? null,
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
    employment_type: lender?.employment_type ?? null,
    employer_name: lender?.employer_name ?? null,
    monthly_income: lender?.monthly_income ?? null,
    gcash_number: lender?.gcash_number ?? null,
    account_upgrade_status: lender?.account_upgrade_status ?? null,
    date_of_birth: lender?.date_of_birth ?? null,
    source_of_funds: lender?.source_of_funds ?? null,
    street_address: address?.street ?? null,
    barangay: address?.barangay ?? null,
    city: address?.city ?? null,
    province: address?.province ?? null,
    zip_code: address?.zip_code ?? null,
    emergency_contacts: emergencyContacts ?? [],
  };

  return jsonResponse({ user: flattened });
}