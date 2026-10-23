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

// ─────────────────────────────────────────────────────────────────────────────
// MPIN hashing
// ─────────────────────────────────────────────────────────────────────────────
//
// Ang MPIN ay 4 na digit lang, kaya ang one-round SHA-256 (dating format) ay
// napakabilis i-brute-force kapag na-leak ang `user_mpins` row (10,000 lang ang
// posibleng kombinasyon). Para sa mga BAGONG MPIN, PBKDF2-HMAC-SHA256 na may
// per-row random salt ang gamit.
//
// Backwards compatible: sinusuportahan pa rin ang lumang `sha256$<hex>` para
// makapasok ang existing na MPIN; awtomatiko itong ina-upgrade sa PBKDF2 sa
// unang matagumpay na verification (tingnan ang `auth-mpin`).

const MPIN_ALGORITHM = 'pbkdf2';
const MPIN_DEFAULT_ITERATIONS = 150_000;
const MPIN_SALT_BYTES = 16;
const MPIN_HASH_BITS = 256;

export function isLegacyMpinHash(stored: string | null | undefined): boolean {
  return !!stored && stored.startsWith('sha256$');
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array {
  const clean = hex.length % 2 === 0 ? hex : `0${hex}`;
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

async function deriveMpin(
  userId: string,
  mpin: string,
  salt: Uint8Array,
  iterations: number,
): Promise<string> {
  const material = enc.encode(`jireta::${userId}::${mpin}`);
  const key = await crypto.subtle.importKey(
    'raw',
    material,
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  // Explicit ArrayBuffer copy — ang `Uint8Array` ng `fromHex` ay maaaring
  // naka-isa sa `SharedArrayBuffer`, na hindi tinatanggap ng WebCrypto types.
  const saltBuffer = salt.buffer.slice(
    salt.byteOffset,
    salt.byteOffset + salt.byteLength,
  ) as ArrayBuffer;
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: saltBuffer, iterations, hash: 'SHA-256' },
    key,
    MPIN_HASH_BITS,
  );
  return toHex(new Uint8Array(bits));
}

/** Compare nang constant-time para hindi mabasa ang hash sa timing. */
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * `pbkdf2$<iterations>$<saltHex>$<hashHex>` — random salt bawat hash, kaya
 * magkaiba ang hash ng dalawang user na pareho ang MPIN.
 */
export async function hashMpin(userId: string, mpin: string): Promise<string> {
  const salt = new Uint8Array(MPIN_SALT_BYTES);
  crypto.getRandomValues(salt);
  const digest = await deriveMpin(userId, mpin, salt, MPIN_DEFAULT_ITERATIONS);
  return `${MPIN_ALGORITHM}$${MPIN_DEFAULT_ITERATIONS}$${toHex(salt)}$${digest}`;
}

/**
 * Sinusuri ang MPIN laban sa naka-store na hash.
 *
 * Suportado ang PBKDF2 (bago) at ang legacy na `sha256$<hex>` (luma). Ang
 * legacy ay one-round SHA-256 ng `jireta::<user_id>::<mpin>`.
 */
export async function verifyMpinHash(
  userId: string,
  mpin: string,
  stored: string | null | undefined,
): Promise<boolean> {
  if (!stored) return false;

  if (stored.startsWith(`${MPIN_ALGORITHM}$`)) {
    const parts = stored.split('$');
    if (parts.length !== 4) return false;
    const iterations = parseInt(parts[1], 10);
    if (!Number.isFinite(iterations) || iterations <= 0) return false;
    const salt = fromHex(parts[2]);
    const expected = parts[3];
    if (salt.length === 0 || !/^[0-9a-f]{64}$/i.test(expected)) return false;
    const actual = await deriveMpin(userId, mpin, salt, iterations);
    return constantTimeEqual(actual, expected.toLowerCase());
  }

  if (isLegacyMpinHash(stored)) {
    return (await hashPassword(userId, mpin)) === stored;
  }

  return false;
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