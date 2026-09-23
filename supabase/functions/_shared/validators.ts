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

/**
 * Ang E.164 (`+639XXXXXXXXX`) na katumbas ng isang Philippine mobile number —
 * ito ang format na tinatanggap ng GoTrue sa `auth.users.phone`.
 *
 * Tinatanggap ang `09171234567` (local) at `639171234567` / `+639171234567`.
 * `''` ang ibinabalik kapag hindi mobile number ang hugis, para hindi kailanman
 * mailipat ang login credential sa bogus na numero.
 */
export function phoneToE164(phone: string | null | undefined): string {
  const digits = (phone ?? '').replace(/\D/g, '');
  if (/^09\d{9}$/.test(digits)) return `+63${digits.slice(1)}`;
  if (/^639\d{9}$/.test(digits)) return `+${digits}`;
  return '';
}

export function validateEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/**
 * Ang credential email na dapat nakatali sa isang numero sa GoTrue kapag WALANG
 * totoong email ang account (`''` kapag hindi ito dapat galawin).
 *
 * Bakit: ang OTP login (`auth-otp?fn=verify-otp`) ay pumapasok gamit ang
 * `signInWithPassword({ email: `${phone}@jireta.temp`, password })` — lalo na
 * kapag NAKA-DISABLE ang Phone provider ng project ("Phone logins are
 * disabled"), kung saan ang email lang ang tanging paraan ng pagpasok. Kapag
 * binago ang numero sa `public.users.phone_number` at nanatili ang LUMANG
 * `${oldPhone}@jireta.temp` sa credential, «Invalid login credentials» ang
 * isasagot ng GoTrue at hindi na makakapasok ang lender.
 *
 * Hindi ginagalaw ang TOTOONG email (`juan@gmail.com`) ng account.
 */
export function phoneCredentialEmail(
  phone: string | null | undefined,
  currentEmail: string | null | undefined,
  hasIncomingEmail = false,
): string {
  const cleanPhone = (phone ?? '').trim();
  if (!cleanPhone || hasIncomingEmail) return '';
  const email = (currentEmail ?? '').trim().toLowerCase();
  if (email !== '' && !email.endsWith('@jireta.temp')) return '';
  return `${cleanPhone}@jireta.temp`;
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