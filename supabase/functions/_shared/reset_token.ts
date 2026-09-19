// supabase/functions/_shared/reset_token.ts
// ─────────────────────────────────────────────────────────────────────────────
// Opaque password-reset flow token.
//
// WHY: the reset screen used to put the account email in the URL
// (`/reset-password?email=kyl@gmail.com`). Query strings are not private — they
// land in browser history, server/proxy access logs, analytics and the Referer
// header of every third-party request, and they show up in screenshots.
//
// Instead, `auth-password?fn=forgot-password` mints a 256-bit random token and
// hands it to the client once. The client puts THAT in the URL:
//
//   /reset-password?t=3f9c…  (64 hex chars — a hash-like, non-guessable handle)
//
// Only the SHA-256 hash of the token is stored, so even a database leak cannot
// be replayed against the API. The server resolves the token back to the email
// internally, which means the email never has to travel in the URL at all.
// ─────────────────────────────────────────────────────────────────────────────

const HEX_TOKEN = /^[0-9a-f]{64}$/;

/** 256-bit random token, hex encoded. Unguessable and non-reversible. */
export function generateResetToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** SHA-256 hex of the token — the only form that is ever persisted. */
export async function hashResetToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Shape check so obviously bogus values never reach the database. */
export function isResetToken(value: unknown): value is string {
  return typeof value === "string" && HEX_TOKEN.test(value);
}
