// supabase/functions/in-office-create/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   in-office-create-draft →  ?fn=create-draft
//   in-office-save-step    →  ?fn=save-step
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';

// ── [moved from in-office-save-step] ────────────────────────────────────────
const db = () => getAdminClient();

// ── [moved from in-office-save-step] ────────────────────────────────────────
// Controlled vocabularies (00025): relationship and document_type are FKs to
// relationship_types / document_types. Unknown client-supplied values are
// normalized to the fallback code so a draft never fails to save.
const RELATIONSHIPS = new Set([
  'Spouse', 'Parent', 'Sibling', 'Child', 'Relative',
  'Friend', 'Colleague', 'Employer', 'Other',
]);
const DOCUMENT_TYPES = new Set([
  'valid_id', 'proof_of_income', 'barangay_clearance', 'pay_slip', 'selfie',
  'proof_of_billing', 'certificate_of_employment', 'itr',
  'business_registration', 'co_maker', 'ci_photo', 'evidence', 'site_photo',
  'neighbor_interview', 'proof_of_residence', 'other',
]);

// ── [moved from in-office-save-step] ────────────────────────────────────────
function normalizeRelationship(v?: string | null): string | null {
  if (!v) return null;
  return RELATIONSHIPS.has(v) ? v : 'Other';
}

function normalizeDocumentType(v?: string | null): string | null {
  if (!v) return null;
  return DOCUMENT_TYPES.has(v) ? v : 'other';
}

// ── [moved from in-office-save-step] ────────────────────────────────────────
interface StepHandlers {
  [step: number]: (applicationId: string, data: Record<string, unknown>) => Promise<void>;
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'create-draft';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'create-draft':
        // ── [moved from functions/in-office-create-draft/index.ts] ─────
        return await handleCreateDraft(req);
      case 'save-step':
        // ── [moved from functions/in-office-save-step/index.ts] ────────
        return await handleSaveStep(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('in-office-create error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/in-office-create-draft/index.ts] ──────────────────
async function handleCreateDraft(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();

  const { data: draft, error } = await db
    .from('in_office_applications')
    .insert({
      created_by: authResult.id,
      status: 'draft',
      wizard_step: 1,
    })
    .select()
    .single();

  if (error) return errorResponse('Failed to create draft application', 500, 'DB_ERROR');

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'in_office_draft_created',
    tableName: 'in_office_applications',
    recordId: draft.id,
    newValues: { status: 'draft' },
  });

  return jsonResponse({ success: true, application_id: draft.id, draft });
}

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function handleSaveStep(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json();
  const { application_id, step, data } = body;

  if (!application_id || !step || !data) {
    return errorResponse('application_id, step, and data are required', 400, 'MISSING_FIELDS');
  }
  if (step < 1 || step > 5) {
    return errorResponse('step must be between 1 and 5', 400, 'INVALID_STEP');
  }

  const client = db();

  const { data: app, error: fetchErr } = await client
    .from('in_office_applications')
    .select('id, created_by, status')
    .eq('id', application_id)
    .single();

  if (fetchErr || !app) return errorResponse('Application not found', 404, 'NOT_FOUND');
  if (authResult.role === ROLES.EMPLOYEE && app.created_by !== authResult.id) {
    return errorResponse('Access denied', 403, 'FORBIDDEN');
  }
  if (app.status === 'converted') {
    return errorResponse('Cannot edit a converted application', 422, 'ALREADY_CONVERTED');
  }

  const handlers: StepHandlers = {
    1: saveStep1,
    2: saveStep2,
    3: saveStep3,
    4: saveStep4,
    5: saveStep5,
  };

  try {
    await handlers[step](application_id, data);
  } catch (err) {
    console.error('save-step handler error:', err);
    return errorResponse('Failed to save step data', 500, 'DB_ERROR');
  }

  const { data: updated, error: updateErr } = await client
    .from('in_office_applications')
    .update({
      wizard_step: step,
      updated_at: new Date().toISOString(),
    })
    .eq('id', application_id)
    .select()
    .single();

  if (updateErr) return errorResponse('Failed to save step', 500, 'DB_ERROR');

  return jsonResponse({ success: true, application: updated });
}

// ── [moved from in-office-save-step] ────────────────────────────────────────
// Step handlers — persist wizard step data into the normalized child tables.
// 1:1 tables (personal/employment/loan details) are upserted on application_id;
// 1:N tables (addresses, contacts, co-makers, documents) are replaced.
// ─────────────────────────────────────────────────────────────────────────────

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function saveStep1(applicationId: string, data: Record<string, unknown>) {
  const client = db();
  await client.from('application_personal_info').upsert({
    application_id: applicationId,
    first_name: data.first_name ?? null,
    middle_name: data.middle_name ?? null,
    last_name: data.last_name ?? null,
    phone_number: data.phone_number ?? data.phone ?? null,
    gender: data.gender ?? null,
    civil_status: data.civil_status ?? null,
    date_of_birth: data.date_of_birth ?? null,
    gcash_number: data.gcash_number ?? null,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'application_id' });

  await client.from('application_employment_info').upsert({
    application_id: applicationId,
    employment_type: data.employment_type ?? null,
    employer_name: data.employer_name ?? null,
    monthly_income: data.monthly_income != null ? Number(data.monthly_income) : null,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'application_id' });
}

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function saveStep2(applicationId: string, data: Record<string, unknown>) {
  const client = db();
  await client.from('application_addresses').delete().eq('application_id', applicationId);
  const addresses = Array.isArray(data.addresses) ? data.addresses : [];
  if (addresses.length > 0) {
    await client.from('application_addresses').insert(
      addresses.map((a) => ({
        application_id: applicationId,
        address_type: a.address_type ?? 'home',
        street: a.street ?? null,
        barangay: a.barangay ?? null,
        city: a.city ?? null,
        province: a.province ?? null,
        zip_code: a.zip_code ?? null,
        latitude: a.latitude ?? null,
        longitude: a.longitude ?? null,
        is_primary: a.is_primary ?? false,
      }))
    );
  }

  await client.from('application_emergency_contacts').delete().eq('application_id', applicationId);
  const contacts = Array.isArray(data.emergency_contacts) ? data.emergency_contacts : [];
  if (contacts.length > 0) {
    await client.from('application_emergency_contacts').insert(
      contacts.map((c) => ({
        application_id: applicationId,
        name: c.name ?? c.full_name ?? null,
        relationship: normalizeRelationship(c.relationship ?? null),
        phone_number: c.phone_number ?? c.contact_number ?? null,
        address: c.address ?? null,
      }))
    );
  }
}

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function saveStep3(applicationId: string, data: Record<string, unknown>) {
  const client = db();
  await client.from('application_loan_details').upsert({
    application_id: applicationId,
    principal_amount: data.principal_amount != null ? Number(data.principal_amount) : null,
    interest_rate: data.interest_rate != null ? Number(data.interest_rate) : 20.00,
    payment_frequency: data.frequency ?? data.payment_frequency ?? null,
    term_days: data.term_days != null ? Number(data.term_days) : null,
    term_periods: data.term_periods != null ? Number(data.term_periods) : null,
    purpose: data.purpose ?? null,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'application_id' });
}

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function saveStep4(applicationId: string, data: Record<string, unknown>) {
  const client = db();
  await client.from('application_co_makers').delete().eq('application_id', applicationId);
  if (data.first_name || data.last_name) {
    const relationship = typeof data.relationship === 'string' ? data.relationship : null;
    await client.from('application_co_makers').insert({
      application_id: applicationId,
      first_name: data.first_name ?? null,
      last_name: data.last_name ?? null,
      relationship: normalizeRelationship(relationship),
      phone_number: data.phone_number ?? data.contact_number ?? null,
      date_of_birth: data.date_of_birth ?? data.birthday ?? null,
      address: data.address ?? null,
    });
  }
}

// ── [moved from functions/in-office-save-step/index.ts] ─────────────────────
async function saveStep5(applicationId: string, data: Record<string, unknown>) {
  const client = db();
  await client.from('application_documents').delete().eq('application_id', applicationId);
  const documents = Array.isArray(data.documents) ? data.documents : [];
  if (documents.length > 0) {
    await client.from('application_documents').insert(
      documents.map((d) => ({
        application_id: applicationId,
        document_type: normalizeDocumentType(d.document_type ?? null),
        file_path: d.file_url ?? d.file_path ?? null,
        file_name: d.file_name ?? 'document',
        mime_type: d.mime_type ?? 'application/octet-stream',
      }))
    );
  }
  if (data.borrower_signature) {
    await client.from('in_office_applications').update({
      borrower_signature: data.borrower_signature,
    }).eq('id', applicationId);
  }
}