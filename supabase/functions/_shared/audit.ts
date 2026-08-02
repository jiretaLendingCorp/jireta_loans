// supabase/functions/_shared/audit.ts
import { getAdminClient } from './db.ts';

export async function writeAuditLog(params: {
  performedBy: string;
  action: string;
  tableName: string;
  recordId: string;
  oldValues?: Record<string, unknown> | null;
  newValues?: Record<string, unknown> | null;
  ipAddress?: string;
}): Promise<void> {
  try {
    const db = getAdminClient();
    await db.from('audit_logs').insert({
      performed_by: params.performedBy,
      action: params.action,
      table_name: params.tableName,
      record_id: params.recordId,
      old_values: params.oldValues ?? null,
      new_values: params.newValues ?? null,
      ip_address: params.ipAddress ?? null,
    });
  } catch (err) {
    console.error('Audit log write failed:', err);
  }
}