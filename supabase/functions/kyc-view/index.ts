// supabase/functions/kyc-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   kyc-verify       →  ?fn=verify
//   kyc-get-list     →  ?fn=get-list
//   kyc-get-status   →  ?fn=get-status
//   kyc-get-details  →  ?fn=get-details
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getLenderAddressBatch, getLenderAddress } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';
import { computeSchedule } from '../_shared/schedule.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'verify';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'verify':
        // ── [moved from functions/kyc-verify/index.ts] ───────────────────
        return await handleVerify(req);
      case 'get-list':
        // ── [moved from functions/kyc-get-list/index.ts] ─────────────────
        return await handleGetList(req);
      case 'get-status':
        // ── [moved from functions/kyc-get-status/index.ts] ───────────────
        return await handleGetStatus(req);
      case 'get-details':
        // ── [moved from functions/kyc-get-details/index.ts] ──────────────
        return await handleGetDetails(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('kyc-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/kyc-verify/index.ts] ──────────────────────────────
async function handleVerify(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { account_upgrade_doc_id, lender_id, action, rejection_notes } = body;
    if (!['verified', 'rejected'].includes(action)) {
      return errorResponse('action (verified|rejected) is required', 400, 'VALIDATION_ERROR');
    }
    // Reject requires NO reason — simple Yes / No confirm from staff UI.
    // rejection_notes is optional and may be omitted entirely.
    if (!account_upgrade_doc_id && !lender_id) {
      return errorResponse('account_upgrade_doc_id or lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const now = new Date().toISOString();

    // Resolve the lender_id: direct lender_id, or from a single document id.
    let targetLenderId = lender_id as string | null;
    let singleDocId: string | null = null;
    if (account_upgrade_doc_id) {
      const { data: doc } = await db.from('account_upgrade_documents').select('id, lender_id, status').eq('id', account_upgrade_doc_id).single();
      if (!doc) return errorResponse('Account Upgrade document not found', 404, 'NOT_FOUND');
      targetLenderId = doc?.lender_id;
      singleDocId = account_upgrade_doc_id;
    }

    // When lender_id is given, verify/reject ALL non-final docs for that lender
    // in a single operation. When account_upgrade_doc_id is given, only that doc is updated.
    let query = db.from('account_upgrade_documents').update({
      status: action,
      reviewed_by: user.id,
      reviewed_at: now,
      rejection_notes: rejection_notes ?? null,
    }).eq('lender_id', targetLenderId);
    if (singleDocId) query = query.eq('id', singleDocId);
    const { error: updateError } = await query;
    if (updateError) return errorResponse('Failed to update Account Upgrade documents', 500, 'DB_ERROR');

    const { data: allDocs } = await db.from('account_upgrade_documents').select('status').eq('lender_id', targetLenderId);
    const anyRejected = allDocs?.some((d) => d.status === 'rejected');
    const allVerified = allDocs?.every((d) => d.status === 'verified');

    let newAccountUpgradeStatus = 'submitted';
    if (anyRejected) newAccountUpgradeStatus = 'rejected';
    else if (allVerified) newAccountUpgradeStatus = 'verified';

    // Track rejection time via updated_at so the 1-month resubmit cooldown
    // can be enforced in kyc-submit / kyc-get-status without a migration.
    // rejection_notes stays optional (null when staff rejects via Yes/No).
    await db.from('lender_profiles').update({
      account_upgrade_status: newAccountUpgradeStatus,
      updated_at: now,
      account_upgrade_rejection_notes:
        action === 'rejected' ? (rejection_notes ?? null) : null,
    }).eq('id', targetLenderId);

    // ── AUTO-CONVERT pending Walk-in (in_office) to Loan after verification ──────
    // Business rule: in-office application STOPPED at account creation until KYC verified.
    // Once staff verifies, any in_office_applications with that lender_id and status='submitted'
    // (pending upgrade) must be automatically converted into a real loan so the lender can proceed
    // without re-entering data — parity with lender self-apply where verified lender can immediately apply.
    let autoConvertedLoanId: string | null = null;
    if (newAccountUpgradeStatus === 'verified' && targetLenderId) {
      try {
        const { data: pendingApps } = await db.from('in_office_applications').select('id').eq('lender_id', targetLenderId).eq('status', 'submitted');
        for (const app of (pendingApps ?? [])) {
          const appId = (app as any).id;
          // Load stored wizard data
          const [pRes, eRes, aRes, ecRes, lRes, cmRes, dRes] = await Promise.all([
            db.from('application_personal_info').select('*').eq('application_id', appId).maybeSingle(),
            db.from('application_employment_info').select('*').eq('application_id', appId).maybeSingle(),
            db.from('application_addresses').select('*').eq('application_id', appId),
            db.from('application_emergency_contacts').select('*').eq('application_id', appId),
            db.from('application_loan_details').select('*').eq('application_id', appId).maybeSingle(),
            db.from('application_co_makers').select('*').eq('application_id', appId),
            db.from('application_documents').select('*').eq('application_id', appId),
          ]);
          const loanDet = (lRes as any).data;
          if (!loanDet || !loanDet.principal_amount) continue;
          const principalAmount = Number(String(loanDet.principal_amount).replace(/,/g, ''));
          if (Number.isNaN(principalAmount) || principalAmount < 3000) continue;
          const rawFreq = String(loanDet.payment_frequency ?? loanDet.frequency ?? 'monthly').toLowerCase();
          const frequency = ['daily','weekly','monthly'].includes(rawFreq) ? rawFreq : 'monthly';
          let periodsOverride: number | undefined;
          if (loanDet.term_periods != null && String(loanDet.term_periods).trim() !== '') {
            const parsed = Number(String(loanDet.term_periods).replace(/,/g, '').trim());
            periodsOverride = Number.isNaN(parsed) ? undefined : parsed;
          }
          const sched = computeSchedule(principalAmount, frequency, new Date(), periodsOverride);
          const year = new Date().getFullYear();
          const seq = Math.floor(Math.random() * 900000 + 100000);
          const loanNumber = `LN-${year}-${seq}`;
          const { data: newLoan, error: loanErr } = await db.from('loans').insert({
            lender_id: targetLenderId,
            in_office_application_id: appId,
            loan_number: loanNumber,
            principal_amount: principalAmount,
            interest_rate: 20,
            payment_frequency: frequency,
            term_days: sched.termDays,
            term_periods: sched.installments,
            installment_amount: sched.installmentAmount,
            status: 'pending',
            purpose: loanDet.purpose ?? 'Walk-in loan',
          }).select().single();
          if (loanErr || !newLoan) {
            console.error('kyc-verify auto-convert loan insert failed', { appId, loanErr });
            continue;
          }
          const scheduleRows = sched.dueDates.map((due: string, i: number) => ({
            loan_id: newLoan.id,
            installment_number: i + 1,
            due_date: due,
            amount_due: (sched.amounts as number[])[i],
          }));
          await db.from('loan_schedules').insert(scheduleRows);
          const coMakers = (cmRes as any).data ?? [];
          for (const cm of coMakers) {
            const { data: person } = await db.from('co_makers').insert({
              first_name: cm.first_name,
              last_name: cm.last_name,
              phone_number: cm.phone_number,
              date_of_birth: cm.date_of_birth,
              address: cm.address,
            }).select().single();
            if (person) {
              const relSet = new Set(['Spouse','Parent','Sibling','Child','Relative','Friend','Colleague','Employer','Other']);
              const rel = relSet.has(cm.relationship) ? cm.relationship : 'Other';
              await db.from('loan_co_makers').insert({ loan_id: newLoan.id, co_maker_id: person.id, relationship: rel });
            }
          }
          const docs = (dRes as any).data ?? [];
          if (docs.length > 0) {
            const docSet = new Set(['valid_id','proof_of_income','barangay_clearance','pay_slip','selfie','proof_of_billing','certificate_of_employment','itr','business_registration','co_maker','ci_photo','evidence','site_photo','neighbor_interview','proof_of_residence','other']);
            const docRows = docs.map((d: any) => ({
              loan_id: newLoan.id,
              document_type: docSet.has(d.document_type) ? d.document_type : 'other',
              file_path: d.file_path ?? d.file_url,
              file_name: d.file_name ?? 'document',
              mime_type: d.mime_type ?? 'application/octet-stream',
              uploaded_by: user.id,
            }));
            await db.from('loan_documents').insert(docRows);
          }
          await db.from('in_office_applications').update({ status: 'converted', wizard_step: 5, updated_at: new Date().toISOString() }).eq('id', appId);
          autoConvertedLoanId = newLoan.id;
          await writeAuditLog({
            performedBy: user.id,
            action: 'in_office_auto_converted_after_kyc_verified',
            tableName: 'in_office_applications',
            recordId: appId,
            newValues: { loan_id: newLoan.id, lender_id: targetLenderId, loan_number: loanNumber },
            ipAddress: ip,
          });
          await sendPushNotification({
            userId: targetLenderId,
            title: 'Walk-in Loan Now Ready',
            body: `Your Walk-in loan ${loanNumber} (₱${principalAmount.toLocaleString()}) is now submitted and pending approval. Track it in My Loans.`,
            type: 'loan_applied',
            referenceId: newLoan.id,
          });
          // Convert only the oldest pending app per verification to avoid duplicate loans if multiple drafts
          break;
        }
      } catch (e) {
        console.error('kyc-verify auto-convert error', e);
      }
    }

    await writeAuditLog({
      performedBy: user.id,
      action: singleDocId ? `account_upgrade_doc_${action}` : `account_upgrade_all_${action}`,
      tableName: 'account_upgrade_documents',
      recordId: singleDocId ?? targetLenderId ?? account_upgrade_doc_id ?? '',
      ipAddress: ip,
    });
    await sendPushNotification({
      userId: targetLenderId ?? account_upgrade_doc_id ?? '',
      title: action === 'verified' ? 'Account Upgrade Verified' : 'Account Upgrade Rejected',
      body: action === 'verified'
        ? 'All of your Account Upgrade documents have been verified.'
        : (rejection_notes
            ? `Account Upgrade rejected: ${rejection_notes}`
            : 'Account Upgrade rejected. You may resubmit after 1 month.'),
      type: 'account_upgrade_update',
      referenceId: singleDocId ?? targetLenderId ?? '',
      sentBy: user.id,
    });

    // 1-month cooldown anchors on this rejection timestamp.
    const rejectedAt = newAccountUpgradeStatus === 'rejected' ? now : null;
    const resubmitAfter = rejectedAt
      ? new Date(new Date(rejectedAt).getTime() + 30 * 24 * 60 * 60 * 1000).toISOString()
      : null;

    return jsonResponse({
      message: singleDocId ? `Document ${action}` : `All documents ${action}`,
      account_upgrade_status: newAccountUpgradeStatus,
      lender_id: targetLenderId,
      rejected_at: rejectedAt,
      resubmit_after: resubmitAfter,
      auto_converted_loan_id: autoConvertedLoanId,
    });
}

// ── [moved from functions/kyc-get-list/index.ts] ────────────────────────────
async function handleGetList(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    // Accept both spellings used by the app.
    const search = url.searchParams.get('search') ?? url.searchParams.get('lender_name');
    const offset = (page - 1) * limit;

    const db = getAdminClient();

    let query = db.from('lender_profiles')
      .select(`
        id, account_upgrade_status, updated_at,
        source_of_funds, gender, civil_status, date_of_birth, employment_type,
        employer_name, monthly_income, gcash_number,
        users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, suffix, phone_number, email, account_status, profile_photo_url),
        account_upgrade_documents(id, document_type, file_path, status, uploaded_at, rejection_notes, reviewed_by, reviewed_at),
        emergency_contacts(id, name, relationship, phone_number, address)
      `, { count: 'exact' })
      .neq('account_upgrade_status', 'not_submitted');

    if (status) query = query.eq('account_upgrade_status', status);
    if (search) query = query.or(`users.first_name.ilike.%${search}%,users.last_name.ilike.%${search}%,users.middle_name.ilike.%${search}%`);

    const { data, error, count } = await query
      .order('updated_at', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) return errorResponse(`Failed to fetch Account Upgrade list: ${error.message}`, 500, 'SERVER_ERROR');

    const rows = data ?? [];
    const lenderIds = rows.map((r) => r.id);
    const addressMap = await getLenderAddressBatch(db, lenderIds);

    // One row per lender (NOT one per document). Staff should see a single
    // submission per borrower with a document count; document-level review
    // happens inside kyc-get-details / kyc-verify. `id` is the lender id so
    // the client can navigate straight to the lender's KYC details.
    const mapped = (rows ?? []).map((row) => {
      const address = addressMap[row.id] ?? null;
      const users = embedAsObject(row.users);
      const lender = {
        id: users?.id ?? row.id,
        first_name: users?.first_name,
        middle_name: users?.middle_name,
        last_name: users?.last_name,
        suffix: users?.suffix,
        phone_number: users?.phone_number,
        email: users?.email,
        account_status: users?.account_status,
        profile_photo_url: users?.profile_photo_url,
        account_upgrade_status: row.account_upgrade_status,
        street_address: address?.street ?? null,
        barangay: address?.barangay ?? null,
        city: address?.city ?? null,
        province: address?.province ?? null,
        zip_code: address?.zip_code ?? null,
        source_of_funds: row.source_of_funds,
        gender: row.gender,
        civil_status: row.civil_status,
        date_of_birth: row.date_of_birth,
        employment_type: row.employment_type,
        employer_name: row.employer_name,
        monthly_income: row.monthly_income,
        gcash_number: row.gcash_number,
      };

      const docs = row.account_upgrade_documents ?? [];
      const docTypes = [...new Set(docs.map((d) => d.document_type))];
      const latestUpload = docs.length
        ? docs.reduce((a, b) =>
            (a.uploaded_at ?? '') > (b.uploaded_at ?? '') ? a : b)
        : null;

      return {
        id: row.id,
        lender_id: row.id,
        document_type: 'submission',
        document_count: docs.length,
        document_types: docTypes,
        file_url: null,
        status: row.account_upgrade_status ?? (docs.length ? 'submitted' : 'not_submitted'),
        created_at: latestUpload?.uploaded_at ?? row.updated_at ?? new Date().toISOString(),
        lender,
        emergency_contacts: row.emergency_contacts ?? [],
      };
    });

    return jsonResponse({
      data: mapped,
      total: count ?? mapped.length,
      page,
      limit,
      totalPages: limit > 0 ? Math.ceil((count ?? mapped.length) / limit) : 1,
    });
}

// ── [moved from functions/kyc-get-status/index.ts] ──────────────────────────
async function handleGetStatus(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.LENDER, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const requestedLenderId = url.searchParams.get('lender_id');

    // Lenders may only ever inspect their own Account Upgrade; ignore any lender_id they send.
    let lenderId = user.id;
    if (user.role !== ROLES.LENDER) {
      if (requestedLenderId) {
        const roleCheck2 = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
        if (roleCheck2) return roleCheck2;
        lenderId = requestedLenderId;
      }
    }

    const db = getAdminClient();
    const { data: profile } = await db.from('lender_profiles').select('*').eq('id', lenderId).single();
    const { data: docs } = await db.from('account_upgrade_documents')
      .select('id, lender_id, document_type, file_path, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
      .eq('lender_id', lenderId)
      .order('uploaded_at', { ascending: false });
    const { data: emergencyContacts } = await db.from('emergency_contacts')
      .select('id, name, relationship, phone_number, address')
      .eq('lender_id', lenderId);

    const address = await getLenderAddress(db, lenderId);

    const lender = profile
      ? {
          ...profile,
          street_address: address?.street ?? null,
          barangay: address?.barangay ?? null,
          city: address?.city ?? null,
          province: address?.province ?? null,
          zip_code: address?.zip_code ?? null,
        }
      : null;

    const documents = (docs ?? []).map((d) => ({
      ...d,
      file_url: d.file_path,
      created_at: d.uploaded_at,
    }));

    // Walk-in origin: did this lender get created via in-office application?
    let inOfficeApplication: Record<string, unknown> | null = null;
    try {
      const { data: ioApp } = await db.from('in_office_applications')
        .select('id, status, wizard_step, created_at, created_by, lender_id, users!in_office_applications_created_by_fkey(first_name,last_name)')
        .eq('lender_id', lenderId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (ioApp) inOfficeApplication = ioApp as unknown as Record<string, unknown>;
      // Fallback: if lender_id not set yet (old data) but phone matches walk-in draft, try via personal info phone
      if (!inOfficeApplication && profile) {
        // Check phone match with any submitted in-office draft that has same phone and created by staff
        const phone = lender?.phone_number ?? profile?.phone_number;
        if (phone) {
          const { data: phoneMatch } = await db.from('application_personal_info')
            .select('application_id, phone_number, in_office_applications!inner(id,status,created_at,created_by,lender_id,users!in_office_applications_created_by_fkey(first_name,last_name))')
            .eq('phone_number', phone)
            .limit(1)
            .maybeSingle();
          if (phoneMatch) {
            const app = (phoneMatch as any).in_office_applications;
            if (app && app.status === 'submitted') inOfficeApplication = app;
          }
        }
      }
    } catch (_) { /* ignore */ }

    // 1-month resubmit cooldown after rejection (anchored on latest
    // rejected reviewed_at, fallback to profile updated_at).
    let rejectedAt: string | null = null;
    let resubmitAfter: string | null = null;
    let daysRemaining: number | null = null;
    let canResubmit = true;
    if ((profile?.account_upgrade_status ?? 'not_submitted') === 'rejected') {
      const rejReviewed = (docs ?? [])
        .filter((d: any) => d.status === 'rejected' && d.reviewed_at)
        .map((d: any) => new Date(d.reviewed_at).getTime())
        .filter((t: number) => !Number.isNaN(t));
      const anchorMs = rejReviewed.length
        ? Math.max(...rejReviewed)
        : (profile?.updated_at ? new Date(profile.updated_at).getTime() : NaN);
      if (!Number.isNaN(anchorMs)) {
        rejectedAt = new Date(anchorMs).toISOString();
        const afterMs = anchorMs + 30 * 24 * 60 * 60 * 1000;
        resubmitAfter = new Date(afterMs).toISOString();
        const remaining = Math.ceil((afterMs - Date.now()) / (24 * 60 * 60 * 1000));
        daysRemaining = remaining > 0 ? remaining : 0;
        canResubmit = Date.now() >= afterMs;
      } else {
        // No timestamp available — allow resubmit to avoid locking lenders out.
        canResubmit = true;
      }
    }

    return jsonResponse({
      account_upgrade_status: profile?.account_upgrade_status ?? 'not_submitted',
      lender_id: lenderId,
      lender,
      documents,
      emergency_contacts: emergencyContacts ?? [],
      in_office_application: inOfficeApplication,
      is_walk_in: inOfficeApplication != null,
      rejected_at: rejectedAt,
      resubmit_after: resubmitAfter,
      days_remaining: daysRemaining,
      can_resubmit: canResubmit,
    });
}

// ── [moved from functions/kyc-get-details/index.ts] ─────────────────────────
async function handleGetDetails(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const accountUpgradeDocId = url.searchParams.get('account_upgrade_doc_id');
    const lenderId = url.searchParams.get('lender_id');

    if (!accountUpgradeDocId && !lenderId) {
      return errorResponse('account_upgrade_doc_id or lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    // Resolve the lender_id from either the document id or a direct lender id.
    let targetLenderId = lenderId;
    let document: Record<string, unknown> | null = null;
    if (accountUpgradeDocId) {
      const { data: raw, error } = await db
        .from('account_upgrade_documents')
        .select('id, lender_id, document_type, file_path, file_name, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
        .eq('id', accountUpgradeDocId)
        .single();
      if (error || !raw) return errorResponse('Account Upgrade document not found', 404, 'NOT_FOUND');
      targetLenderId = raw?.lender_id;
      document = {
        id: raw.id,
        lender_id: raw.lender_id,
        document_type: raw.document_type,
        file_url: raw.file_path,
        file_name: raw.file_name,
        status: raw.status,
        created_at: raw.uploaded_at,
        rejection_notes: raw.rejection_notes,
        reviewed_by: raw.reviewed_by,
        reviewed_at: raw.reviewed_at,
      };
    }

    // lender_id points at lender_profiles.id which equals the users.id PK.
    const { data: userRow } = await db
      .from('users')
      .select('id, first_name, middle_name, last_name, suffix, phone_number, email, account_status, profile_photo_url, created_at')
      .eq('id', targetLenderId!)
      .single();

    const { data: lenderProfile } = await db
      .from('lender_profiles')
      .select('*')
      .eq('id', targetLenderId!)
      .single();

    const { data: docs } = await db
      .from('account_upgrade_documents')
      .select('id, lender_id, document_type, file_path, file_name, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
      .eq('lender_id', targetLenderId!)
      .order('uploaded_at', { ascending: false });

    // account-upgrade-documents is a private bucket with an owner-scoped RLS policy
    // (only the lender who uploaded a file may read it). Staff review Account Upgrade
    // with their own JWT, so a client-side signed URL lookup would be blocked
    // by RLS and fail with "object not found". Resolve signed URLs here with
    // the service-role client so reviewers can open lender documents.
    const ACCOUNT_UPGRADE_BUCKET = 'account-upgrade-documents';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const signOne = async (path: string) => {
      const { data } = await db.storage
        .from(ACCOUNT_UPGRADE_BUCKET)
        .createSignedUrl(path, 3600);
      // createSignedUrl already returns an absolute URL (e.g.
      // http://localhost:8000/storage/v1/object/sign/...). Only prefix with the
      // storage base URL when the SDK returns a bare relative path so we never
      // produce a doubled URL like .../storage/v1http://.../storage/v1/object.
      const signedPath = data?.signedUrl as string | null ?? null;
      if (!signedPath) return null;
      return signedPath.startsWith('http')
        ? signedPath
        : `${supabaseUrl}/storage/v1${signedPath}`;
    };
    const signedUrls = new Map<string, string | null>();
    for (const d of (docs ?? [])) {
      const p = d.file_path as string;
      if (p) signedUrls.set(d.id, await signOne(p));
    }

    const { data: emergencyContacts } = await db
      .from('emergency_contacts')
      .select('id, name, relationship, phone_number, address')
      .eq('lender_id', targetLenderId!);

    const address = await getLenderAddress(db, targetLenderId!);

    const lender = {
      id: userRow?.id ?? targetLenderId,
      first_name: userRow?.first_name,
      middle_name: userRow?.middle_name,
      last_name: userRow?.last_name,
      suffix: userRow?.suffix,
      phone_number: userRow?.phone_number,
      email: userRow?.email,
      account_status: userRow?.account_status,
      profile_photo_url: userRow?.profile_photo_url,
      created_at: userRow?.created_at,
      ...(lenderProfile ?? {}),
      street_address: address?.street ?? null,
      barangay: address?.barangay ?? null,
      city: address?.city ?? null,
      province: address?.province ?? null,
      zip_code: address?.zip_code ?? null,
    };

    const documents = (docs ?? []).map((d) => ({
      id: d.id,
      lender_id: d.lender_id,
      document_type: d.document_type,
      file_url: d.file_path,
      file_name: d.file_name,
      status: d.status,
      created_at: d.uploaded_at,
      rejection_notes: d.rejection_notes,
      reviewed_by: d.reviewed_by,
      reviewed_at: d.reviewed_at,
      signed_url: signedUrls.get(d.id) ?? null,
    }));

    // Cooldown anchors for staff view (same 30-day rule as get-status).
    let rejectedAt: string | null = null;
    let resubmitAfter: string | null = null;
    if ((lenderProfile?.account_upgrade_status ?? '') === 'rejected') {
      const times = (docs ?? [])
        .filter((d: any) => d.status === 'rejected' && d.reviewed_at)
        .map((d: any) => new Date(d.reviewed_at).getTime())
        .filter((t: number) => !Number.isNaN(t));
      const anchor = times.length
        ? Math.max(...times)
        : (lenderProfile?.updated_at
            ? new Date(lenderProfile.updated_at).getTime()
            : NaN);
      if (!Number.isNaN(anchor)) {
        rejectedAt = new Date(anchor).toISOString();
        resubmitAfter = new Date(
          anchor + 30 * 24 * 60 * 60 * 1000,
        ).toISOString();
      }
    }

    return jsonResponse({
      document,
      lender_id: targetLenderId,
      account_upgrade_status: lenderProfile?.account_upgrade_status ?? 'not_submitted',
      lender,
      documents,
      emergency_contacts: emergencyContacts ?? [],
      rejected_at: rejectedAt,
      resubmit_after: resubmitAfter,
    });
}