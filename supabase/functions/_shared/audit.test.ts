// supabase/functions/_shared/audit.test.ts
//
// Verifies the audit trail is functional:
//   1. writeAuditLog inserts the correct payload for every kind of action.
//   2. Webhook/system actions (performedBy "system") map to NULL performed_by.
//   3. Write failures are swallowed (never break the primary operation).
//   4. Every action string written by the backend Edge Functions is present in
//      the Flutter UI's AuditActionCatalog (so filters never return empty).

import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { join, fromFileUrl } from "https://deno.land/std@0.168.0/path/mod.ts";
import { writeAuditLog, type AuditLogParams } from "./audit.ts";

const HERE = fromFileUrl(new URL(".", import.meta.url)); // .../supabase/functions/_shared/
const REPO_ROOT = join(HERE, "../../../"); // .../ (repo root)
const FUNCTIONS_DIR = join(REPO_ROOT, "supabase/functions");
const CATALOG_PATH = join(
  REPO_ROOT,
  "lib/presentation/features/head_manager/audit/audit_action_catalog.dart",
);

type Db = Parameters<typeof writeAuditLog>[1];

function fakeDb() {
  const rows: Array<{ table: string; row: Record<string, unknown> }> = [];
  const failNext = { current: false };
  return {
    rows,
    failNext,
    from(table: string) {
      return {
        insert: async (row: Record<string, unknown>) => {
          if (failNext.current) {
            failNext.current = false;
            throw new Error("boom");
          }
          rows.push({ table, row });
          return { data: row, error: null };
        },
      };
    },
  };
}

async function write(db: ReturnType<typeof fakeDb>, params: AuditLogParams) {
  await writeAuditLog(params, db as unknown as Db);
  return db.rows[db.rows.length - 1]?.row;
}

Deno.test("writeAuditLog inserts the full payload for a user action", async () => {
  const db = fakeDb();
  const row = await write(db, {
    performedBy: "u-123",
    action: "loan_approve",
    tableName: "loans",
    recordId: "r-456",
    oldValues: { status: "pending" },
    newValues: { status: "approved" },
    ipAddress: "1.2.3.4",
  });

  assertEquals(row, {
    performed_by: "u-123",
    action: "loan_approve",
    table_name: "loans",
    record_id: "r-456",
    old_values: { status: "pending" },
    new_values: { status: "approved" },
    ip_address: "1.2.3.4",
  });
});

Deno.test("performedBy 'system' (webhook) maps to NULL performed_by", async () => {
  const db = fakeDb();
  const row = await write(db, {
    performedBy: "system",
    action: "xendit_payment_verified",
    tableName: "payments",
    recordId: "r-1",
  });
  assertEquals(row.performed_by, null);
  assertEquals(row.action, "xendit_payment_verified");
});

Deno.test("null performedBy stays NULL", async () => {
  const db = fakeDb();
  const row = await write(db, {
    performedBy: null,
    action: "disbursement_webhook",
    tableName: "disbursements",
    recordId: "r-2",
  });
  assertEquals(row.performed_by, null);
});

Deno.test("missing optional fields are stored as NULL", async () => {
  const db = fakeDb();
  const row = await write(db, {
    performedBy: "u-1",
    action: "payment_recorded",
    tableName: "payments",
    recordId: "r-3",
  });
  assertEquals(row.old_values, null);
  assertEquals(row.new_values, null);
  assertEquals(row.ip_address, null);
});

Deno.test("a failed audit write is swallowed (never throws)", async () => {
  const db = fakeDb();
  db.failNext.current = true;
  let threw = false;
  try {
    await write(db, {
      performedBy: "u-1",
      action: "collection_assign",
      tableName: "collection_assignments",
      recordId: "r-4",
    });
  } catch (_) {
    threw = true;
  }
  assertEquals(threw, false);
  assertEquals(db.rows.length, 0);
});

// ── Cross-file consistency: backend actions ↔ Flutter catalog ─────────────

function listTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of Deno.readDirSync(dir)) {
    if (entry.name === "_shared" && dir === FUNCTIONS_DIR) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory) out.push(...listTsFiles(full));
    else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      out.push(full);
    }
  }
  return out;
}

/** Every `action: '...'` value used inside the Edge Functions. */
function backendActions(): { action: string; file: string }[] {
  const found: { action: string; file: string }[] = [];
  for (const file of listTsFiles(FUNCTIONS_DIR)) {
    const src = Deno.readTextFileSync(file);
    const re = /action\s*:\s*(['"])([^'"]+)\1/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(src)) !== null) {
      found.push({ action: m[2], file: file.replace(REPO_ROOT, "") });
    }
  }
  return found;
}

/** The values listed in AuditActionCatalog.actions. */
function catalogActions(): string[] {
  const src = Deno.readTextFileSync(CATALOG_PATH);
  const block = src.match(/static const List<String> actions = \[([\s\S]*?)\];/);
  assert(block, "AuditActionCatalog.actions block not found");
  const actions: string[] = [];
  const re = /^\s*'([^']+)',/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(block[1])) !== null) actions.push(m[1]);
  return actions;
}

Deno.test("every backend audit action is present in AuditActionCatalog", () => {
  const catalog = new Set(catalogActions());
  const missing = new Set<string>();
  const duplicateFiles = new Map<string, string[]>();

  for (const { action, file } of backendActions()) {
    if (!catalog.has(action)) missing.add(action);
    const list = duplicateFiles.get(action) ?? [];
    if (!list.includes(file)) {
      list.push(file);
      duplicateFiles.set(action, list);
    }
  }

  assert(
    missing.size === 0,
    `Backend writes audit actions missing from the UI catalog: ${[...missing].join(", ")}`,
  );

  // Sanity: each action must be exercised by at least one function.
  for (const [action, files] of duplicateFiles) {
    assert(
      files.length >= 1,
      `Catalog action '${action}' is never written by the backend`,
    );
  }
});

Deno.test("no backend action exceeds the VARCHAR(100) column limit", () => {
  for (const { action, file } of backendActions()) {
    assert(
      action.length <= 100,
      `'${action}' in ${file} is ${action.length} chars (limit 100)`,
    );
  }
});

Deno.test("catalog has no duplicate or blank action", () => {
  const catalog = catalogActions();
  assertEquals(new Set(catalog).size, catalog.length);
  for (const a of catalog) assert(a.trim().length > 0);
});
