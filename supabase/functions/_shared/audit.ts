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
 * Normalize a raw `x-forwarded-for` header into a value the `ip_address` INET
 * column will accept (or null to store NULL).
 *
 * Callers commonly fall back to the string `"unknown"` when the header is
 * missing, and proxies chain addresses ("client, proxy1, proxy2"). Postgres
 * rejects both on an INET column, which used to make every audit write throw
 * and (because the write is best-effort) silently drop the row — so actions
 * like creating riders/lenders never appeared in the Head Manager's audit.
 *
 * Take the first hop, trim it, and only keep it when it looks like an IP
 * literal (IPv4 or IPv6). Anything else becomes NULL.
 */
export function sanitizeIpAddress(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const candidate = String(raw).split(",")[0]?.trim();
  if (!candidate) return null;
  if (candidate.toLowerCase() === "unknown") return null;
  if (candidate.includes(":")) {
    // IPv6 literal, including IPv4-mapped forms like ::ffff:203.0.113.7.
    // Keep hex digits, colons and dots only.
    return /^[0-9a-fA-F:.]+$/.test(candidate) ? candidate : null;
  }
  const octets = candidate.split(".");
  if (
    octets.length === 4 &&
    octets.every((o) => /^\d{1,3}$/.test(o) && Number(o) <= 255)
  ) {
    return candidate;
  }
  return null;
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
      ip_address: sanitizeIpAddress(params.ipAddress) ?? null,
    });
  } catch (err) {
    console.error("Audit log write failed:", err);
  }
}
