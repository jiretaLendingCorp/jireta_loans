// supabase/functions/users-create/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   users-create-employee →  ?fn=create-employee
//   users-create-rider    →  ?fn=create-rider
//   users-create-lender   →  ?fn=create-lender
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateEmail, sanitizeString, validatePhone, normalizeVehicleType } from '../_shared/validators.ts';
import { hashPassword } from '../_shared/password_hash.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

// ── [moved from users-create-employee] ──────────────────────────────────────
const DEFAULT_PASSWORD = '12345678';

// ── [moved from users-create-rider] ─────────────────────────────────────────
// Renamed from `DEFAULT_PASSWORD` to avoid a collision with users-create-employee.
const riderDefaultPassword = '12345678';

// ── [moved from users-create-lender] ────────────────────────────────────────
// Renamed from `DEFAULT_PASSWORD` to avoid a collision with users-create-employee.
const lenderDefaultPassword = '12345678';

// ── [moved from users-create-rider] ─────────────────────────────────────────
function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ── [moved from users-create-lender] ────────────────────────────────────────
// Renamed from `toE164` to avoid a collision with users-create-rider.
function lenderToE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'create-employee';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'create-employee':
        // ── [moved from functions/users-create-employee/index.ts] ───────
        return await handleCreateEmployee(req);
      case 'create-rider':
        // ── [moved from functions/users-create-rider/index.ts] ──────────
        return await handleCreateRider(req);
      case 'create-lender':
        // ── [moved from functions/users-create-lender/index.ts] ─────────
        return await handleCreateLender(req);
      case 'create-head-manager':
        // ── Head Manager creation (Head Manager only) ───────────────────
        return await handleCreateHeadManager(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('users-create error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── Staff (employee / head manager) field validation ────────────────────────
// gender / civil_status must match the lookup-table codes
// (gender_types / civil_statuses) or the FK insert fails.
const STAFF_GENDERS = ['male', 'female', 'other'];
const STAFF_CIVIL_STATUSES = ['single', 'married', 'widowed', 'separated'];

function normalizeStaffCode(v: unknown): string | null {
  if (v === undefined || v === null || v === '') return null;
  return sanitizeString(String(v)).trim().toLowerCase();
}

// Returns an error message when the date of birth is unusable, else null.
// Staff must be at least 18 years old (mirrors the create-form date picker).
function validateStaffDob(dob: unknown): string | null {
  if (typeof dob !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dob.trim())) {
    return 'Invalid date of birth format (YYYY-MM-DD)';
  }
  const clean = dob.trim();
  const d = new Date(clean + 'T00:00:00Z');
  if (Number.isNaN(d.getTime())) return 'Invalid date of birth';
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  if (d.getTime() > today.getTime()) return 'Date of birth cannot be in the future';
  let age = today.getFullYear() - d.getUTCFullYear();
  const m = today.getMonth() - d.getUTCMonth();
  if (m < 0 || (m === 0 && today.getDate() < d.getUTCDate())) age--;
  if (age < 18) return 'Staff must be at least 18 years old';
  return null;
}

// ── [moved from functions/users-create-employee/index.ts] ───────────────────
async function handleCreateEmployee(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const {
    first_name, middle_name, last_name, suffix,
    gender, civil_status, date_of_birth, email, phone_number,
    position, hired_at,
  } = body;

  if (!first_name || !last_name || !email || !phone_number || !position) {
    return errorResponse('Required fields missing', 400, 'VALIDATION_ERROR');
  }
  const dobErr = validateStaffDob(date_of_birth);
  if (dobErr) return errorResponse(dobErr, 400, 'VALIDATION_ERROR');
  const cleanGender = normalizeStaffCode(gender);
  if (cleanGender && !STAFF_GENDERS.includes(cleanGender)) {
    return errorResponse('Invalid gender', 400, 'VALIDATION_ERROR');
  }
  const cleanCivil = normalizeStaffCode(civil_status);
  if (cleanCivil && !STAFF_CIVIL_STATUSES.includes(cleanCivil)) {
    return errorResponse('Invalid civil status', 400, 'VALIDATION_ERROR');
  }
  // ── Normalise + validate before any DB hit ──────────────────────────
  const cleanEmail = sanitizeString(email).trim().toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  }
  const cleanPhone = sanitizeString(phone_number).trim();
  if (!validatePhone(cleanPhone)) {
    return errorResponse('Invalid phone number format (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();

  // ── Email Uniqueness Validation (security) ──────────────────────────
  // Case-insensitive check (`ilike`) + phone duplicate guard.  The DB's
  // partial unique index `uq_users_email_lower` is the atomic final guard;
  // this pre-check returns a clean 409 without creating an orphan auth user.
  const { data: dupEmail } = await db
    .from('users')
    .select('id')
    .ilike('email', cleanEmail)
    .maybeSingle();
  if (dupEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');

  const { data: dupPhone } = await db
    .from('users')
    .select('id')
    .eq('phone_number', cleanPhone)
    .maybeSingle();
  if (dupPhone) return errorResponse('Phone number already registered', 409, 'DUPLICATE');

  // ── Resilient role-archived check (if column missing, allow creation)
  let roleRow: any = null;
  try {
    const { data } = await db.from('roles').select('id, is_archived').eq('name', 'employee').single();
    roleRow = data;
    if ((roleRow as any)?.is_archived === true) return errorResponse('Cannot create user — employee role is archived', 403, 'ROLE_ARCHIVED');
  } catch (_) {
    const { data } = await db.from('roles').select('id').eq('name', 'employee').single();
    roleRow = data;
  }
  if (!roleRow) return errorResponse('Employee role not found', 500, 'SERVER_ERROR');

  const { data: authUser, error: createErr } = await db.auth.admin.createUser({
    email: cleanEmail,
    password: DEFAULT_PASSWORD,
    email_confirm: true,
    app_metadata: { role: 'employee' },
  });

  if (createErr || !authUser?.user) {
    // GoTrue also enforces email uniqueness in auth.users; surface as 409.
    if (createErr?.message?.toLowerCase().includes('already') || createErr?.message?.toLowerCase().includes('duplicate')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: user, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    role_id: roleRow.id,
    email: cleanEmail,
    phone_number: cleanPhone,
    first_name: sanitizeString(first_name),
    middle_name: middle_name ? sanitizeString(middle_name) : null,
    last_name: sanitizeString(last_name),
    suffix: suffix ? sanitizeString(suffix) : null,
    account_status: 'active',
    force_password_change: true,
    created_by: authResult.id,
  }, { onConflict: 'id' }).select().single();

  if (userErr || !user) {
    // If the DB's partial unique index `uq_users_email_lower` fired, surface as 409.
    const msg = (userErr as unknown as { message?: string; code?: string })?.message?.toLowerCase() ?? '';
    const code = (userErr as unknown as { code?: string })?.code ?? '';
    if (code === '23505' || msg.includes('duplicate') || msg.includes('uq_users_email_lower') || msg.includes('users_email')) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  await db.from('employee_profiles').insert({
    id: user.id,
    position: sanitizeString(position),
    hired_at: hired_at ?? new Date().toISOString().split('T')[0],
    gender: cleanGender,
    civil_status: cleanCivil,
    date_of_birth: String(date_of_birth).trim().substring(0, 10),
  });

  await db.from('password_history').insert({
    user_id: user.id,
    password_hash: await hashPassword(user.id, DEFAULT_PASSWORD),
  });

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'user_created',
    tableName: 'users',
    recordId: user.id,
    newValues: { role: 'employee', email, position, date_of_birth: String(date_of_birth).trim().substring(0, 10) },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  return jsonResponse({ user_id: user.id, message: 'Employee created successfully' }, 201);
}

// ── Head Manager creation ───────────────────────────────────────────────────
// Business rule: only the Head Manager can create another Head Manager.
async function handleCreateHeadManager(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const {
    first_name, middle_name, last_name, suffix,
    gender, civil_status, date_of_birth, email, phone_number,
  } = body;

  if (!first_name || !last_name || !email || !phone_number) {
    return errorResponse('Required fields missing', 400, 'VALIDATION_ERROR');
  }
  const dobErr = validateStaffDob(date_of_birth);
  if (dobErr) return errorResponse(dobErr, 400, 'VALIDATION_ERROR');
  const cleanGender = normalizeStaffCode(gender);
  if (cleanGender && !STAFF_GENDERS.includes(cleanGender)) {
    return errorResponse('Invalid gender', 400, 'VALIDATION_ERROR');
  }
  const cleanCivil = normalizeStaffCode(civil_status);
  if (cleanCivil && !STAFF_CIVIL_STATUSES.includes(cleanCivil)) {
    return errorResponse('Invalid civil status', 400, 'VALIDATION_ERROR');
  }
  // ── Normalise + validate before any DB hit ──────────────────────────
  const cleanEmail = sanitizeString(email).trim().toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  }
  const cleanPhone = sanitizeString(phone_number).trim();
  if (!validatePhone(cleanPhone)) {
    return errorResponse('Invalid phone number format (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();

  // ── Email / phone uniqueness (security) ─────────────────────────────
  const { data: dupEmail } = await db
    .from('users')
    .select('id')
    .ilike('email', cleanEmail)
    .maybeSingle();
  if (dupEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');

  const { data: dupPhone } = await db
    .from('users')
    .select('id')
    .eq('phone_number', cleanPhone)
    .maybeSingle();
  if (dupPhone) return errorResponse('Phone number already registered', 409, 'DUPLICATE');

  // ── Resilient role-archived check ───────────────────────────────────
  let roleRow: any = null;
  try {
    const { data } = await db.from('roles').select('id, is_archived').eq('name', 'head_manager').single();
    roleRow = data;
    if ((roleRow as any)?.is_archived === true) return errorResponse('Cannot create user — head manager role is archived', 403, 'ROLE_ARCHIVED');
  } catch (_) {
    const { data } = await db.from('roles').select('id').eq('name', 'head_manager').single();
    roleRow = data;
  }
  if (!roleRow) return errorResponse('Head Manager role not found', 500, 'SERVER_ERROR');

  const { data: authUser, error: createErr } = await db.auth.admin.createUser({
    email: cleanEmail,
    password: DEFAULT_PASSWORD,
    email_confirm: true,
    app_metadata: { role: 'head_manager' },
  });

  if (createErr || !authUser?.user) {
    if (createErr?.message?.toLowerCase().includes('already') || createErr?.message?.toLowerCase().includes('duplicate')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: user, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    role_id: roleRow.id,
    email: cleanEmail,
    phone_number: cleanPhone,
    first_name: sanitizeString(first_name),
    middle_name: middle_name ? sanitizeString(middle_name) : null,
    last_name: sanitizeString(last_name),
    suffix: suffix ? sanitizeString(suffix) : null,
    account_status: 'active',
    force_password_change: true,
    created_by: authResult.id,
  }, { onConflict: 'id' }).select().single();

  if (userErr || !user) {
    const msg = (userErr as unknown as { message?: string; code?: string })?.message?.toLowerCase() ?? '';
    const code = (userErr as unknown as { code?: string })?.code ?? '';
    if (code === '23505' || msg.includes('duplicate') || msg.includes('uq_users_email_lower') || msg.includes('users_email')) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  await db.from('password_history').insert({
    user_id: user.id,
    password_hash: await hashPassword(user.id, DEFAULT_PASSWORD),
  });

  // Staff profile row (same store the My Profile screen reads via
  // get-profile's employee_profiles flattening). Without this row the
  // head manager's gender / civil status / date of birth would stay blank.
  const { error: hmProfileErr } = await db.from('employee_profiles').insert({
    id: user.id,
    position: 'Head Manager',
    hired_at: new Date().toISOString().split('T')[0],
    gender: cleanGender,
    civil_status: cleanCivil,
    date_of_birth: String(date_of_birth).trim().substring(0, 10),
  });
  if (hmProfileErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    await db.from('users').delete().eq('id', user.id);
    console.error('[users-create] head manager profile insert failed:', hmProfileErr.message);
    return errorResponse('Failed to save head manager profile', 500, 'SERVER_ERROR');
  }

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'user_created',
    tableName: 'users',
    recordId: user.id,
    newValues: { role: 'head_manager', email },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  return jsonResponse({ user_id: user.id, message: 'Head Manager created successfully' }, 201);
}

// ── [moved from functions/users-create-rider/index.ts] ──────────────────────
async function handleCreateRider(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const { email, first_name, middle_name, last_name, suffix, phone, vehicle_type, plate_number,
    drivers_license_number, drivers_license_expiry, vehicle_brand } = body;

  if (!email || !first_name || !last_name || !phone || !vehicle_type || !plate_number || !drivers_license_number) {
    return errorResponse('Missing required fields', 400, 'VALIDATION_ERROR');
  }
  const cleanEmail = sanitizeString(email).trim().toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  }
  const canonicalVehicleType = normalizeVehicleType(vehicle_type);
  if (!canonicalVehicleType) {
    return errorResponse('Invalid vehicle type', 400, 'VALIDATION_ERROR');
  }
  if (!validatePhone(sanitizeString(phone))) {
    return errorResponse('Invalid phone number format (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: dupEmail } = await db.from('users').select('id').ilike('email', cleanEmail).maybeSingle();
  if (dupEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');

  const { data: existingPhone } = await db.from('users').select('id').eq('phone_number', phone.trim()).maybeSingle();
  if (existingPhone) return errorResponse('Phone number already registered', 409, 'DUPLICATE');

  // ── Resilient role-archived check
  let roleData: any = null;
  try {
    const { data } = await db.from('roles').select('id, is_archived').eq('name', 'rider').single();
    roleData = data;
    if ((roleData as any)?.is_archived === true) return errorResponse('Cannot create user — rider role is archived', 403, 'ROLE_ARCHIVED');
  } catch (_) {
    const { data } = await db.from('roles').select('id').eq('name', 'rider').single();
    roleData = data;
  }
  if (!roleData) return errorResponse('Rider role not found', 500, 'SERVER_ERROR');

  const { data: authUser, error: authErr } = await db.auth.admin.createUser({
    email: cleanEmail,
    phone: toE164(phone.trim()),
    password: riderDefaultPassword,
    email_confirm: true,
    phone_confirm: true,
    app_metadata: { role: 'rider' },
  });
  if (authErr || !authUser.user) {
    if (authErr?.message?.toLowerCase().includes('already') || authErr?.message?.toLowerCase().includes('duplicate')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    console.error('[users-create] rider auth user creation failed:', authErr?.message);
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: newUser, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    email: cleanEmail,
    first_name: sanitizeString(first_name),
    middle_name: middle_name ? sanitizeString(middle_name) : null,
    last_name: sanitizeString(last_name),
    suffix: suffix ? sanitizeString(suffix) : null,
    phone_number: phone.trim(),
    role_id: roleData.id,
    account_status: 'active',
    force_password_change: true,
    created_by: user.id,
  }, { onConflict: 'id' }).select('id').single();

  if (userErr) {
    const msg = (userErr as unknown as { message?: string; code?: string })?.message?.toLowerCase() ?? '';
    const code = (userErr as unknown as { code?: string })?.code ?? '';
    if (code === '23505' || msg.includes('duplicate') || msg.includes('uq_users_email_lower') || msg.includes('users_email')) {
      await db.auth.admin.deleteUser(authUser.user.id);
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  const { error: riderProfileErr } = await db.from('rider_profiles').insert({
    id: newUser.id,
    vehicle_type: canonicalVehicleType,
    plate_number: sanitizeString(plate_number).toUpperCase(),
    drivers_license_number: sanitizeString(drivers_license_number),
    drivers_license_expiry: drivers_license_expiry || null,
    vehicle_brand: vehicle_brand ? sanitizeString(vehicle_brand) : null,
    is_available: true,
  });
  if (riderProfileErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    await db.from('users').delete().eq('id', newUser.id);
    console.error('[users-create] rider profile insert failed:', riderProfileErr.message);
    return errorResponse('Failed to save rider profile', 500, 'SERVER_ERROR');
  }

  await db.from('password_history').insert({
    user_id: newUser.id,
    password_hash: await hashPassword(newUser.id, riderDefaultPassword),
  });

  await writeAuditLog({ performedBy: user.id, action: 'create_rider', tableName: 'users', recordId: newUser.id, newValues: { role: 'rider', first_name, last_name, email: cleanEmail, phone_number: phone.trim() }, ipAddress: ip });
  await sendPushNotification({ userId: user.id, title: 'Rider Created', body: `Rider ${first_name} ${last_name} has been created.`, type: 'user_created' });

  return jsonResponse({ message: 'Rider created successfully', user_id: newUser.id }, 201);
}

// ── [moved from functions/users-create-lender/index.ts] ─────────────────────
async function handleCreateLender(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const { first_name, middle_name, last_name, suffix, phone, gender, civil_status,
    dob, employment_type, employer_name, monthly_income, source_of_funds } = body;

  if (!first_name || !last_name || !phone || !gender || !civil_status || !dob) {
    return errorResponse('Missing required fields', 400, 'VALIDATION_ERROR');
  }
  if (!validatePhone(sanitizeString(phone))) {
    return errorResponse('Invalid phone number (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: existingPhone } = await db.from('users').select('id').eq('phone_number', phone.trim()).maybeSingle();
  if (existingPhone) return errorResponse('Phone number already registered', 409, 'DUPLICATE');

  // ── Resilient role-archived check
  let roleDataL: any = null;
  try {
    const { data } = await db.from('roles').select('id, is_archived').eq('name', 'lender').single();
    roleDataL = data;
    if ((roleDataL as any)?.is_archived === true) return errorResponse('Cannot create user — lender role is archived', 403, 'ROLE_ARCHIVED');
  } catch (_) {
    const { data } = await db.from('roles').select('id').eq('name', 'lender').single();
    roleDataL = data;
  }
  if (!roleDataL) return errorResponse('Lender role not found', 500, 'SERVER_ERROR');
  const roleData = roleDataL;

  const { data: authUser, error: authErr } = await db.auth.admin.createUser({
    phone: lenderToE164(phone.trim()),
    password: lenderDefaultPassword,
    phone_confirm: true,
    app_metadata: { role: 'lender' },
  });
  if (authErr || !authUser.user) {
    console.error('[users-create] lender auth user creation failed:', authErr?.message);
    return errorResponse('Failed to create auth user', 500, 'SERVER_ERROR');
  }

  const { data: newUser, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    first_name: sanitizeString(first_name),
    middle_name: middle_name ? sanitizeString(middle_name) : null,
    last_name: sanitizeString(last_name),
    suffix: suffix ? sanitizeString(suffix) : null,
    phone_number: phone.trim(),
    role_id: roleData.id,
    account_status: 'active',
    force_password_change: true,
    created_by: user.id,
  }, { onConflict: 'id' }).select('id').single();

  if (userErr) {
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create user record', 500, 'SERVER_ERROR');
  }

  const { error: lenderProfileErr } = await db.from('lender_profiles').insert({
    id: newUser.id,
    gender: gender ? sanitizeString(gender).toLowerCase() : null,
    civil_status: civil_status ? sanitizeString(civil_status).toLowerCase() : null,
    date_of_birth: dob ?? null,
    employment_type: employment_type ? sanitizeString(employment_type).toLowerCase() : null,
    employer_name: employer_name ? sanitizeString(employer_name) : null,
    monthly_income: monthly_income ? Number(monthly_income) : null,
    source_of_funds: source_of_funds ? sanitizeString(source_of_funds).toLowerCase() : null,
    account_upgrade_status: 'not_submitted',
  });

  if (lenderProfileErr) {
    console.error('[users-create] lender profile insert failed:', lenderProfileErr.message);
    await db.auth.admin.deleteUser(authUser.user.id);
    return errorResponse('Failed to create lender profile', 500, 'SERVER_ERROR');
  }

  await db.from('password_history').insert({
    user_id: newUser.id,
    password_hash: await hashPassword(newUser.id, lenderDefaultPassword),
  });

  await writeAuditLog({ performedBy: user.id, action: 'create_lender', tableName: 'users', recordId: newUser.id, newValues: { role: 'lender', first_name, last_name, phone_number: phone.trim() }, ipAddress: ip });

  return jsonResponse({ message: 'Lender created successfully', user_id: newUser.id }, 201);
}