// supabase/functions/_shared/auth_identity.test.ts
//
// Coverage para sa GoTrue identity sync (`auth.users.email` + display metadata).
//
// Ang bug na ito: ang self-registered lender ay may sintetikong
// `${phone}@jireta.temp` na credential sa GoTrue. Kapag na-verify na niya ang
// totoong email sa app (`auth-email-verify?fn=confirm`), `public.users.email`
// lang ang dating naisusulat — kaya TEMP pa rin ang nakikita sa Authentication
// → Users, `-` ang Display name, at hindi siya makapasok sa Google sign-in.
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  type AuthIdentitySync,
  authDisplayMetadata,
  syncAuthUserIdentity,
} from "./auth.ts";

type AdminClient = Parameters<typeof syncAuthUserIdentity>[0];

interface StubOptions {
  /** Kasalukuyang `auth.users.email`. */
  email?: string | null;
  /** Kasalukuyang `raw_user_meta_data` (para ma-test ang merge). */
  metadata?: Record<string, unknown>;
  /** Kapag pinasa, ibabalik itong error ng `updateUserById`. */
  updateError?: string;
}

function stubDb(opts: StubOptions = {}) {
  const updates: Record<string, unknown>[] = [];
  let getCalls = 0;
  const db = {
    auth: {
      admin: {
        getUserById: (_id: string) => {
          getCalls += 1;
          return Promise.resolve({
            data: {
              user: {
                email: opts.email ?? null,
                user_metadata: opts.metadata ?? {},
              },
            },
            error: null,
          });
        },
        updateUserById: (_id: string, attrs: Record<string, unknown>) => {
          updates.push(attrs);
          return Promise.resolve({
            data: { user: null },
            error: opts.updateError ? { message: opts.updateError } : null,
          });
        },
      },
    },
  };
  return {
    db: db as unknown as AdminClient,
    updates,
    getCalls: () => getCalls,
  };
}

// ── authDisplayMetadata ────────────────────────────────────────────────────

Deno.test("authDisplayMetadata writes every key Studio can read as a name", () => {
  assertEquals(authDisplayMetadata({ firstName: "Juan", lastName: "Dela Cruz", phone: "09171234567" }), {
    display_name: "Juan Dela Cruz",
    name: "Juan Dela Cruz",
    full_name: "Juan Dela Cruz",
    first_name: "Juan",
    last_name: "Dela Cruz",
    phone: "09171234567",
  });
});

Deno.test("authDisplayMetadata trims and omits blank values", () => {
  assertEquals(authDisplayMetadata({ firstName: "  Maria ", lastName: "   " }), {
    display_name: "Maria",
    name: "Maria",
    full_name: "Maria",
    first_name: "Maria",
  });
});

Deno.test("authDisplayMetadata with no name keeps only the phone", () => {
  // Self-registered lender: walang pangalan pa sa DB (makukuha sa Account
  // Upgrade), kaya hindi tayo dapat mag-imbento ng pangalan.
  assertEquals(authDisplayMetadata({ phone: "09171234567" }), {
    phone: "09171234567",
  });
});

Deno.test("authDisplayMetadata returns nothing for empty input", () => {
  assertEquals(authDisplayMetadata({}), {});
  assertEquals(authDisplayMetadata({ firstName: "", lastName: "", phone: "" }), {});
});

// ── syncAuthUserIdentity ───────────────────────────────────────────────────

Deno.test("syncAuthUserIdentity pushes the verified email and confirms it", async () => {
  const stub = stubDb({ email: "09171234567@jireta.temp" });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {
    email: "Juan@Example.com",
  });

  assertEquals(result.ok, true);
  assertEquals(result.duplicate, false);
  assertEquals(result.previousEmail, "09171234567@jireta.temp");
  assertEquals(stub.updates.length, 1);
  // lowercase ang canonical form (tugma sa `uq_users_email_lower`)
  assertEquals(stub.updates[0].email, "juan@example.com");
  assertEquals(stub.updates[0].email_confirm, true);
});

Deno.test("syncAuthUserIdentity reports the previous email for rollback", async () => {
  const stub = stubDb({ email: "old@example.com" });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {
    email: "new@example.com",
  });
  assertEquals(result.previousEmail, "old@example.com");
});

Deno.test("syncAuthUserIdentity skips the write when the email already matches (case-insensitive)", async () => {
  const stub = stubDb({ email: "juan@example.com" });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {
    email: "Juan@Example.COM",
  });

  assertEquals(result.ok, true);
  assertEquals(result.previousEmail, "juan@example.com");
  assertEquals(stub.updates.length, 0);
});

Deno.test("syncAuthUserIdentity flags a duplicate email instead of overwriting", async () => {
  const stub = stubDb({
    email: "09171234567@jireta.temp",
    updateError: "A user with this email address has already been registered",
  });
  const result: AuthIdentitySync = await syncAuthUserIdentity(stub.db, "user-1", {
    email: "taken@example.com",
  });

  assertEquals(result.ok, false);
  assertEquals(result.duplicate, true);
  assertEquals(result.previousEmail, "09171234567@jireta.temp");
});

Deno.test("syncAuthUserIdentity treats non-duplicate errors as non-fatal failures", async () => {
  const stub = stubDb({ email: null, updateError: "Database error saving new user" });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {
    email: "juan@example.com",
  });

  assertEquals(result.ok, false);
  assertEquals(result.duplicate, false);
  assert(result.error?.includes("Database error"));
});

Deno.test("syncAuthUserIdentity merges metadata so OAuth keys survive", async () => {
  const stub = stubDb({
    email: "juan@gmail.com",
    metadata: { avatar_url: "https://lh3.googleusercontent.com/a/x", name: "Juan (Google)" },
  });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {
    firstName: "Juan",
    lastName: "Dela Cruz",
    phone: "09171234567",
  });

  assertEquals(result.ok, true);
  const meta = stub.updates[0].user_metadata as Record<string, unknown>;
  assertEquals(meta.avatar_url, "https://lh3.googleusercontent.com/a/x");
  assertEquals(meta.display_name, "Juan Dela Cruz");
  assertEquals(meta.phone, "09171234567");
});

Deno.test("syncAuthUserIdentity with no patch does not touch GoTrue", async () => {
  const stub = stubDb({ email: "juan@example.com" });
  const result = await syncAuthUserIdentity(stub.db, "user-1", {});

  assertEquals(result.ok, true);
  assertEquals(stub.updates.length, 0);
});
