// supabase/functions/_shared/audit.ts
import { getAdminClient } from "./db.ts";

export interface AuditLogParams {
  performedBy: string | null;
  action: string;
  tableName: string;
  recordId: string;
  oldValues?: Record<string, unknown> | null;
  newValues?: Record<string, unknown> | null;
  ipAddress?: string;
}

/**
 * Insert one row into `audit_logs`. Errors are swallowed by design so a failed
 * audit write never breaks the primary operation (e.g. a payment webhook).
 *
 * The optional second argument is a test seam — callers use the production
 * admin client automatically.
 */
export async function writeAuditLog(
  params: AuditLogParams,
  db: Pick<ReturnType<typeof getAdminClient>, "from"> = getAdminClient(),
): Promise<void> {
  try {
    await db.from("audit_logs").insert({
      // 'system' is the placeholder used by webhook callbacks (no logged-in
      // user); it maps to NULL now that performed_by is nullable.
      performed_by: params.performedBy === "system" ? null : params.performedBy,
      action: params.action,
      table_name: params.tableName,
      record_id: params.recordId,
      old_values: params.oldValues ?? null,
      new_values: params.newValues ?? null,
      ip_address: params.ipAddress ?? null,
    });
  } catch (err) {
    console.error("Audit log write failed:", err);
  }
}
