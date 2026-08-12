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
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
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

  if (targetId !== user.id && !['head_manager', 'employee'].includes(user.role)) {
    return errorResponse('Access denied', 403, 'FORBIDDEN');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: existing } = await db.from('users').select('*').eq('id', targetId).single();
  if (!existing) return errorResponse('User not found', 404, 'NOT_FOUND');

  const updateFields: Record<string, unknown> = {};
  const allowed = ['first_name', 'middle_name', 'last_name', 'suffix', 'profile_photo_url'];
  for (const f of allowed) {
    if (body[f] !== undefined) updateFields[f] = sanitizeString(body[f]);
  }
  if (body.avatar_url !== undefined) updateFields.profile_photo_url = sanitizeString(body.avatar_url);

  if (body.phone && body.phone !== existing.phone_number) {
    if (!validatePhone(sanitizeString(body.phone))) return errorResponse('Invalid phone', 400, 'VALIDATION_ERROR');
    const { data: taken } = await db.from('users').select('id').eq('phone_number', body.phone.trim()).neq('id', targetId).maybeSingle();
    if (taken) return errorResponse('Phone already used', 400, 'DUPLICATE');
    updateFields.phone_number = body.phone.trim();
  }

  if (body.fcm_token !== undefined) updateFields.fcm_token = body.fcm_token;

  if (Object.keys(updateFields).length > 0) {
    await db.from('users').update(updateFields).eq('id', targetId);
  }

  // Rider profile — accept both the flat mobile payload and the nested form.
  if (body.rider_profile || body.plate_number || body.drivers_license_number || body.vehicle_type || body.vehicle_brand) {
    const rp = body.rider_profile ?? body;
    await db.from('rider_profiles').update({
      vehicle_type: rp.vehicle_type ? sanitizeString(rp.vehicle_type) : undefined,
      plate_number: rp.plate_number ? sanitizeString(rp.plate_number).toUpperCase() : undefined,
      vehicle_brand: rp.vehicle_brand ? sanitizeString(rp.vehicle_brand) : undefined,
      drivers_license_number: rp.drivers_license_number ? sanitizeString(rp.drivers_license_number) : undefined,
      drivers_license_expiry: rp.drivers_license_expiry ?? undefined,
    }).eq('id', targetId);
  }

  // Lender profile — accept both the flat mobile payload and the nested form.
  const lp = body.lender_profile ?? (body.gender || body.civil_status || body.dob ||
    body.date_of_birth || body.employment_type || body.employer_name ||
    body.monthly_income || body.gcash_number || body.source_of_funds
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
      gcash_number: lp.gcash_number ? sanitizeString(lp.gcash_number) : undefined,
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

  await writeAuditLog({ performedBy: user.id, action: 'update_profile', tableName: 'users', recordId: targetId, oldValues: existing, ipAddress: ip });

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
      const { data: targetUser } = await db.from('users').select('roles(name)').eq('id', targetId).single();
      const targetRole = embedAsObject(targetUser?.roles)?.name;
      if (!['rider', 'lender'].includes(targetRole)) {
        return errorResponse('Access denied', 403, 'FORBIDDEN');
      }
    }
  }

  const db = getAdminClient();
  const { data, error } = await db
    .from('users')
    .select(`id, first_name, middle_name, last_name, suffix, email, phone_number, account_status,
      force_password_change, last_login_at, created_at, profile_photo_url,
      roles(id, name),
      employee_profiles(department, position, hired_at, gender, civil_status),
      rider_profiles(vehicle_type, plate_number, drivers_license_number, drivers_license_expiry, vehicle_brand, is_available),
      lender_profiles!lender_profiles_id_fkey(employment_type, employer_name, monthly_income, gcash_number, account_upgrade_status, gender, civil_status, date_of_birth, source_of_funds)`)
    .eq('id', targetId)
    .single();

  if (error || !data) return errorResponse('User not found', 404, 'NOT_FOUND');

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