// supabase/functions/_shared/notification_types.test.ts
//
// Guards the notifications.type FK.
//
// notifications.type REFERENCES notification_types(code), kaya ang bawat type
// na ipinapadala ng Edge Functions (`sendPushNotification` / `notifyStaff`)
// ay DAPAT may naka-seed na code sa ilang migration. Kapag wala, ang insert
// ay nabibigo sa FK violation at tahimik lang itong naka-log
// ("Notification insert failed") — kaya WALANG notification na nakakarating
// sa user (in-app man o FCM push).
//
// Nangyari na ito nang dalawang beses sa production:
//   • 'payment_due'                 → naayos sa 00151
//   • 'account_upgrade_rejected' /  → naayos sa 00173
//     'account_upgrade_verified'
//
// Ang test na ito ay nag-scan ng lahat ng notification types na aktwal na
// ipinapadala ng functions at ine-verify na naka-seed ang lahat.

import {
  assert,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { join, fromFileUrl } from "https://deno.land/std@0.168.0/path/mod.ts";

const HERE = fromFileUrl(new URL(".", import.meta.url)); // .../supabase/functions/_shared/
const REPO_ROOT = join(HERE, "../../../"); // repo root
const FUNCTIONS_DIR = join(REPO_ROOT, "supabase/functions");
const MIGRATIONS_DIR = join(REPO_ROOT, "supabase/migrations");

// ── Source scanning ─────────────────────────────────────────────────────────

function listTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of Deno.readDirSync(dir)) {
    const full = join(dir, entry.name);
    if (entry.isDirectory) out.push(...listTsFiles(full));
    else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      out.push(full);
    }
  }
  return out;
}

/** Skips a quoted string / template literal starting at [i]; returns the
 *  index just past its closing quote. Braces inside `${...}` are ignored on
 *  purpose — hindi sila nagbabago ng brace depth ng object literal. */
function skipString(src: string, i: number): number {
  const quote = src[i];
  i++;
  while (i < src.length) {
    const ch = src[i];
    if (ch === "\\") {
      i += 2;
      continue;
    }
    if (ch === quote) return i + 1;
    i++;
  }
  return i;
}

/** The argument object literal of every `callee({ ... })` call in [src]. */
function callBlocks(src: string, callee: string): string[] {
  const blocks: string[] = [];
  const marker = `${callee}(`;
  let idx = 0;
  while ((idx = src.indexOf(marker, idx)) !== -1) {
    let i = idx + marker.length;
    while (i < src.length && /\s/.test(src[i])) i++;
    if (src[i] !== "{") {
      idx = i;
      continue;
    }
    const start = i;
    let depth = 0;
    while (i < src.length) {
      const ch = src[i];
      if (ch === "'" || ch === '"' || ch === "`") {
        i = skipString(src, i);
        continue;
      }
      if (ch === "/" && src[i + 1] === "/") {
        const nl = src.indexOf("\n", i);
        i = nl === -1 ? src.length : nl;
        continue;
      }
      if (ch === "/" && src[i + 1] === "*") {
        const end = src.indexOf("*/", i);
        i = end === -1 ? src.length : end + 2;
        continue;
      }
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) {
          i++;
          break;
        }
      }
      i++;
    }
    blocks.push(src.slice(start, i));
    idx = i;
  }
  return blocks;
}

/** The notification types named by the `type:` property of an argument block.
 *  Handles ternaries (`type: cond ? 'a' : 'b'`), multi-line included, and
 *  ignores the literals used in the condition (`action === 'verified'`). */
function typesInBlock(block: string): string[] {
  const found: string[] = [];
  const re = /\btype\s*:/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(block)) !== null) {
    // Statement runs to the closing comma of the property.
    let i = m.index + m[0].length;
    let depth = 0;
    const start = i;
    while (i < block.length) {
      const ch = block[i];
      if (ch === "'" || ch === '"' || ch === "`") {
        i = skipString(block, i);
        continue;
      }
      if (ch === "(" || ch === "[") depth++;
      else if (ch === ")" || ch === "]") depth--;
      else if (ch === "," && depth === 0) break;
      i++;
    }
    const statement = block.slice(start, i).replace(/[=!]==?\s*'[^']*'/g, "");
    for (const lit of statement.matchAll(/'([^']*)'/g)) {
      if (/^[a-z][a-z_]*$/.test(lit[1])) found.push(lit[1]);
    }
    re.lastIndex = i;
  }
  return found;
}

/** Types pushed by the Edge Functions, with the file that sends them. */
function pushedTypes(): Map<string, string[]> {
  const used = new Map<string, string[]>();
  for (const file of listTsFiles(FUNCTIONS_DIR)) {
    const src = Deno.readTextFileSync(file);
    for (const callee of ["sendPushNotification", "notifyStaff"]) {
      for (const block of callBlocks(src, callee)) {
        for (const type of typesInBlock(block)) {
          const files = used.get(type) ?? [];
          const rel = file.slice(REPO_ROOT.length);
          if (!files.includes(rel)) files.push(rel);
          used.set(type, files);
        }
      }
    }
  }
  return used;
}

/** Codes seeded into notification_types by the migrations (incl. renames). */
function seededTypes(): Set<string> {
  const codes = new Set<string>();
  for (const entry of Deno.readDirSync(MIGRATIONS_DIR)) {
    if (!entry.name.endsWith(".sql")) continue;
    const src = Deno.readTextFileSync(join(MIGRATIONS_DIR, entry.name));

    // INSERT INTO notification_types ... VALUES ('code', 'Label', n), ...
    for (const block of src.matchAll(/insert\s+into\s+notification_types[\s\S]*?;/gi)) {
      for (const row of block[0].matchAll(/\(\s*'([a-z_]+)'\s*,\s*'/g)) {
        codes.add(row[1]);
      }
    }

    // 00008 renamed the legacy kyc_* codes in place.
    for (const block of src.matchAll(/update\s+notification_types[\s\S]*?;/gi)) {
      for (const row of block[0].matchAll(/set\s+code\s*=\s*'([a-z_]+)'/gi)) {
        codes.add(row[1]);
      }
    }
  }
  return codes;
}

// ── Tests ───────────────────────────────────────────────────────────────────

Deno.test("every pushed notification type is seeded in notification_types", () => {
  const seeded = seededTypes();
  const missing = [...pushedTypes()]
    .filter(([type]) => !seeded.has(type))
    .map(([type, files]) => `${type} (${files.join(", ")})`);

  assert(
    missing.length === 0,
    `Notification types sent without a notification_types row — the INSERT ` +
      `will fail the FK and the user gets nothing (in-app + push):\n  ` +
      missing.sort().join("\n  "),
  );
});

Deno.test("the account-upgrade verify outcomes are seeded", () => {
  const seeded = seededTypes();
  for (const type of [
    "account_upgrade_verified",
    "account_upgrade_rejected",
    "account_upgrade_required",
    "account_upgrade_submitted",
    "account_upgrade_update",
  ]) {
    assert(seeded.has(type), `'${type}' is not seeded in any migration`);
  }
});

// Sanity check: kung biglang walang makitang type ang scanner, mabibigo rin
// ito — para hindi tahimik na "pumapasa" ang test na walang sinusuri.
Deno.test("the scanner actually finds the notification calls", () => {
  const used = pushedTypes();
  assert(
    used.size >= 20,
    `Only ${used.size} pushed types detected — the scanner may be broken`,
  );
  assert(used.has("account_upgrade_rejected"));
});
