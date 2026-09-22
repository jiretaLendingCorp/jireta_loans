// supabase/functions/_shared/validators.ts
export function sanitizeString(input: unknown): string {
  if (typeof input !== 'string') return '';
  return input.trim().replace(/[<>'"]/g, '');
}

// `rider_profiles.vehicle_type` FK-references `vehicle_types(code)`, whose rows
// are Title-cased ("Motorcycle", "Car", "Tricycle"). The app submits lowercase
// ("motorcycle", "tricycle", "car") so map/canonicalize to the stored codes.
export function normalizeVehicleType(value: unknown): string | null {
  const raw = sanitizeString(value);
  if (!raw) return null;
  const lower = raw.toLowerCase().replace(/\s+/g, '');
  switch (lower) {
    case 'motorcycle':
    case 'motorbike':
      return 'Motorcycle';
    case 'bicycle':
    case 'bike':
      return 'Bicycle';
    case 'tricycle':
      return 'Tricycle';
    case 'car':
    case 'van':
      return 'Car';
    default:
      return raw.charAt(0).toUpperCase() + raw.slice(1);
  }
}

export function validatePhone(phone: string): boolean {
  return /^09\d{9}$/.test(phone);
}

export function validateEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** Totoong email-format ba (pareho ang rules sa [validateEmail])? */
export function isEmailFormat(value: string): boolean {
  return validateEmail((value ?? '').trim().toLowerCase());
}

/**
 * Ang email na isusulat sa **GoTrue** (`auth.users.email`) para sa isang
 * identifier.
 *
 * Bakit kailangan: ang HEAD MANAGER ay puwedeng mag-login gamit ang simpleng
 * identifier — hal. pangalan lang ("juan") — kaya walang @gmail.com / format
 * validation para sa kanila. Pero ang GoTrue ay may SARILING email-format
 * validation: tatanggi ito sa `createUser({ email: 'juan' })`. Kaya ang nasa
 * auth.users ay ang `${slug}@jireta.temp`, at ang TOTOONG identifier pa rin
 * ang naka-save sa `public.users.email` (iyon ang hinahanap ng login).
 *
 * Ang `auth-login` at `users-manage` (email edit) ay gumagamit din nito, para
 * iisa lang ang katumbas na credential sa lahat ng dako.
 */
export function credentialEmailFor(identifier: string): string {
  const clean = (identifier ?? '').trim().toLowerCase();
  if (isEmailFormat(clean)) return clean;
  const slug = clean
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^[.-]+|[.-]+$/g, '');
  return `${slug || 'hm'}@jireta.temp`;
}

export function validateLoanAmount(amount: number): boolean {
  return amount >= 3000 && amount <= 500000;
}

export function validateFrequency(freq: string): boolean {
  return ['daily', 'weekly', 'monthly'].includes(freq);
}

export function validatePasswordComplexity(password: string): { valid: boolean; message?: string } {
  if (password.length < 8) return { valid: false, message: 'Password must be at least 8 characters' };
  if (!/[A-Z]/.test(password)) return { valid: false, message: 'Password must contain an uppercase letter' };
  if (!/[a-z]/.test(password)) return { valid: false, message: 'Password must contain a lowercase letter' };
  if (!/\d/.test(password)) return { valid: false, message: 'Password must contain a number' };
  return { valid: true };
}

export function validateUUID(id: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
}

export function validatePagination(page: unknown, limit: unknown): { page: number; limit: number } {
  const p = Math.max(1, parseInt(String(page)) || 1);
  const l = Math.min(100, Math.max(1, parseInt(String(limit)) || 20));
  return { page: p, limit: l };
}