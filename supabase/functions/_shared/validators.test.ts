// supabase/functions/_shared/validators.test.ts
//
// Coverage para sa identifier → GoTrue credential mapping.
//
// Ang requirement: sa HEAD MANAGER role lang, WALANG email-format validation —
// puwedeng kahit pangalan lang (hal. "juan") ang identifier, makakagawa siya ng
// account, at makakapag-login. Pero ang GoTrue (`auth.users.email`) ay may
// sariling email-format validation, kaya:
//
//   * `public.users.email`  = ang hilaw na identifier ("juan")
//   * `auth.users.email`    = ang `credentialEmailFor("juan")` → "juan@jireta.temp"
//
// Ang `auth-login` at `users-manage` (email edit) ay parehong gumagamit ng
// helper na ito, kaya kailangang stable ang mapping — kapag nagbago ito,
// hindi na makakapasok ang existing head manager accounts.
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  credentialEmailFor,
  isEmailFormat,
  validateEmail,
} from "./validators.ts";

// ── isEmailFormat ─────────────────────────────────────────────────────────

Deno.test("isEmailFormat matches validateEmail", () => {
  for (const v of ["juan@gmail.com", "a.b+c@sub.example.co", "JUAN@GMAIL.COM"]) {
    assertEquals(isEmailFormat(v), validateEmail(v.trim().toLowerCase()));
    assert(isEmailFormat(v), `${v} should be email-format`);
  }
  for (const v of ["juan", "juan@gmail", "juan dela cruz", "@gmail.com", ""]) {
    assertFalse(isEmailFormat(v), `${v} should NOT be email-format`);
  }
});

// ── credentialEmailFor ────────────────────────────────────────────────────

Deno.test("credentialEmailFor keeps a real email as-is (lowercased)", () => {
  assertEquals(credentialEmailFor("Juan@Gmail.com"), "juan@gmail.com");
  assertEquals(credentialEmailFor("  admin@jireta.com  "), "admin@jireta.com");
});

Deno.test("credentialEmailFor maps a first name to a GoTrue-valid address", () => {
  // Ito ang head-manager case: pangalan lang ang identifier.
  assertEquals(credentialEmailFor("juan"), "juan@jireta.temp");
  assertEquals(credentialEmailFor("JUAN"), "juan@jireta.temp");
  assertEquals(credentialEmailFor("  Maria  "), "maria@jireta.temp");
});

Deno.test("credentialEmailFor is always accepted by validateEmail", () => {
  // Ang tanging punto ng mapping: ang GoTrue ay tumatanggap lang ng email
  // format, kaya lahat ng identifier ay dapat may valid na credential.
  for (const id of ["juan", "juan@gmail", "juan dela cruz", "@@@", "-", ""]) {
    const credential = credentialEmailFor(id);
    assert(validateEmail(credential), `${id} → ${credential} must be valid`);
  }
});

Deno.test("credentialEmailFor sanitises characters GoTrue would reject", () => {
  // Walang space/illegal chars sa credential (ang hilaw na identifier ang
  // naka-save pa rin sa public.users).
  const credential = credentialEmailFor("juan dela cruz");
  assertFalse(credential.includes(" "));
  assertEquals(credential, "juan-dela-cruz@jireta.temp");
});

Deno.test("credentialEmailFor is stable for the same identifier", () => {
  // Kapag nagbago ang mapping na ito, hindi na makakapasok ang mga existing
  // head manager account (naka-save sa auth.users ang lumang anyo).
  assertEquals(credentialEmailFor("juan"), credentialEmailFor("juan"));
  assertEquals(credentialEmailFor("juan"), "juan@jireta.temp");
});
