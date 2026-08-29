// supabase/functions/audit-get-logs/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

// Escape LIKE wildcards so user input (e.g. "100%" or "a_b") is matched
// literally instead of acting as a pattern.
function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get('page') ?? '1');
    const limit = parseInt(url.searchParams.get('limit') ?? '50');
    const action = url.searchParams.get('action');
    const performedBy = url.searchParams.get('performed_by');
    const performedByName = url.searchParams.get('performed_by_name');
    const tableName = url.searchParams.get('table_name');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    let query = db
      .from('audit_logs')
      .select(
        `id, action, table_name, record_id, old_values, new_values,
         ip_address, created_at, performed_by,
         performed_by_user:users!audit_logs_performed_by_fkey(
           id, first_name, last_name, email, phone_number, roles(name)
         )`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (action) query = query.eq('action', action);
    // performed_by filters by the raw user UUID (kept for API compat).
    if (performedBy) query = query.eq('performed_by', performedBy);
    // performed_by_name is what the audit UI's search box sends — a human name
    // matched against users.first_name / users.last_name via ilike on the
    // joined users row (aliased performed_by_user).
    if (performedByName) {
      // postgREST embedded `.or()` filters are unreliable (they can return
      // unfiltered rows), so resolve the matching user ids up front and
      // filter on the FK column directly.
      const term = String(performedByName).replace(/[(),.%*[\].]/g, '');
      const q = escapeLike(term);
      const { data: matchingUsers, error: usersErr } = await db
        .from('users')
        .select('id')
        .or(`first_name.ilike.%${q}%,last_name.ilike.%${q}%,email.ilike.%${q}%,phone_number.ilike.%${q}%`);
      if (usersErr) {
        console.error('audit-get-logs name search users query failed:', usersErr.message);
        return errorResponse('Failed to search audit logs by name', 500, 'DB_ERROR');
      }
      const ids = (matchingUsers ?? []).map((u) => u.id);
      if (ids.length === 0) {
        return jsonResponse({
          data: [],
          meta: { page, limit, total: 0, total_pages: 0 },
        });
      }
      query = query.in('performed_by', ids);
    }
    if (tableName) query = query.eq('table_name', tableName);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) {
      console.error('audit-get-logs DB error:', error.message, error.details, error.hint);
      return errorResponse('Failed to fetch audit logs', 500, 'DB_ERROR');
    }

    return jsonResponse({
      data,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('audit-get-logs error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});