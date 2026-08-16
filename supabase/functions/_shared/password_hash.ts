// supabase/functions/_shared/password_hash.ts
//
// Password history hashing. The `password_history.password_hash` column must
// NEVER hold a plaintext password — it is not a GoTrue password (those live
// hashed in auth.users) but a fingerprint for the "cannot reuse last N
// passwords" rule. We store a salted SHA-256 digest of the value.
//
// The per-user salt is the user's id itself, which is stable, not derivable
// from the password, and differs per account. Because the stored value is a
// one-way digest, a leaked history row cannot be replayed as a login
// credential.

const enc = new TextEncoder();

export async function hashPassword(userId: string, password: string): Promise<string> {
  const data = enc.encode(`jireta::${userId}::${password}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `sha256$${hex}`;
}

// Compares a candidate password against a stored history entry. Legacy rows
// written before hashing was introduced may hold the raw value; those are
// still matched (they are only ever compared, never stored going forward).
export async function matchesPasswordHistory(
  userId: string,
  candidate: string,
  stored: string | null | undefined,
): Promise<boolean> {
  if (!stored) return false;
  if (stored.startsWith('sha256$')) {
    return (await hashPassword(userId, candidate)) === stored;
  }
  return stored === candidate;
}