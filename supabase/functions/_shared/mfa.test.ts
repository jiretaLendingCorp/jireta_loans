// supabase/functions/_shared/mfa.test.ts
//
// Server-side na patakaran ng MFA (aal2). Ito ang tunay na hangganan ng
// seguridad: kahit baguhin ng client ang anumang flag nito, ang `aal` claim ng
// NAKAPIRMANG token at ang factor state sa GoTrue (service-role) ang sinusuri
// ng mga sensitibong handler.
//
// Patakbuhin:  cd supabase && deno task test
import {
  assert,
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.168.0/testing/asserts.ts';

import {
  decodeJwtPayload,
  fetchUserMfaState,
  hasVerifiedTotpFactor,
  mfaRequiredForSensitiveOp,
  requireMfaIfEnrolled,
  sanitizeFactors,
  tokenAal,
  tokenAmr,
} from './mfa.ts';

/** Gumagawa ng JWT (hindi pinirmahan) na may ibinigay na payload. */
function fakeJwt(payload: Record<string, unknown>): string {
  const encode = (value: Record<string, unknown>) =>
    btoa(JSON.stringify(value))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode(payload)}.signature`;
}

type FakeFactors = Array<Record<string, unknown>>;

type MfaAdminClient = Parameters<typeof fetchUserMfaState>[0];

function fakeDb(options: {
  factors?: FakeFactors;
  listThrows?: boolean;
  getUserByIdFails?: boolean;
  onlyGetUserById?: boolean;
}): MfaAdminClient {
  const factors = options.factors ?? [];
  const db = {
    auth: {
      admin: {
        mfa: options.onlyGetUserById
          ? undefined
          : {
            listFactors: (_params: { userId: string }) => {
              if (options.listThrows) throw new Error('boom');
              return Promise.resolve({ data: { factors }, error: null });
            },
          },
        getUserById: (_userId: string) =>
          Promise.resolve({
            data: { user: { factors } },
            error: options.getUserByIdFails ? { message: 'nope' } : null,
          }),
      },
    },
  };
  return db as unknown as MfaAdminClient;
}

Deno.test('hasVerifiedTotpFactor — verified TOTP lang ang binibilang', () => {
  assert(
    hasVerifiedTotpFactor([
      { factor_type: 'totp', status: 'verified' },
    ]),
  );
  assert(
    !hasVerifiedTotpFactor([
      { factor_type: 'totp', status: 'unverified' },
    ]),
    'Ang hindi pa na-verify na factor ay hindi 2FA',
  );
  assert(
    !hasVerifiedTotpFactor([
      { factor_type: 'phone', status: 'verified' },
    ]),
    'TOTP lang ang itinatakda ng feature na ito',
  );
  assert(!hasVerifiedTotpFactor([]));
  assert(!hasVerifiedTotpFactor(null));
  assert(!hasVerifiedTotpFactor(undefined));
});

Deno.test('decodeJwtPayload / tokenAal / tokenAmr', () => {
  const token = fakeJwt({
    sub: 'user-1',
    aal: 'aal2',
    amr: [{ method: 'password' }, { method: 'totp' }],
  });
  assertEquals(decodeJwtPayload(token)?.['sub'], 'user-1');
  assertEquals(tokenAal(token), 'aal2');
  assertEquals(tokenAmr(token), ['password', 'totp']);

  const aal1 = fakeJwt({ aal: 'aal1' });
  assertEquals(tokenAal(aal1), 'aal1');

  assertEquals(tokenAal(null), null);
  assertEquals(tokenAal('not-a-jwt'), null);
  assertEquals(tokenAal('a.b'), null, 'Sirang payload → null, hindi pag-hulog');
  assertEquals(tokenAmr('a.b'), []);
  assertEquals(tokenAal(undefined), null);
});

Deno.test('sanitizeFactors — walang secret na lumalabas', () => {
  const factors = sanitizeFactors([
    {
      id: 'f1',
      friendly_name: 'Authenticator',
      factor_type: 'totp',
      status: 'verified',
      created_at: '2026-10-16T00:00:00Z',
      // Hindi dapat ito makalusot sa response ng Edge Function.
      secret: 'JBSWY3DPEHPK3PXP',
      totp: { secret: 'JBSWY3DPEHPK3PXP', qr_code: '<svg/>' },
      phone: '+639171234567',
    },
    { friendly_name: 'walang id' },
    null,
    'garbage',
  ]);

  assertEquals(factors.length, 1);
  const serialized = JSON.stringify(factors);
  assert(!serialized.includes('JBSWY3DPEHPK3PXP'), 'TOTP secret leaked');
  assert(!serialized.includes('qr_code'));
  assert(!serialized.includes('+639171234567'));
  assertEquals(factors[0].id, 'f1');
  assertEquals(factors[0].status, 'verified');
});

Deno.test('sanitizeFactors — hindi array → walang laman', () => {
  assertEquals(sanitizeFactors(null), []);
  assertEquals(sanitizeFactors('garbage'), []);
  assertEquals(sanitizeFactors({ id: 'f1' }), []);
});

Deno.test('fetchUserMfaState — admin.mfa.listFactors ang unang daan', async () => {
  const state = await fetchUserMfaState(
    fakeDb({ factors: [{ id: 'f1', factor_type: 'totp', status: 'verified' }] }),
    'user-1',
  );
  assert(state.ok);
  assert(state.enrolled);
});

Deno.test('fetchUserMfaState — fallback sa getUserById', async () => {
  const state = await fetchUserMfaState(
    fakeDb({
      factors: [{ id: 'f1', factor_type: 'totp', status: 'verified' }],
      onlyGetUserById: true,
    }),
    'user-1',
  );
  assert(state.ok);
  assert(state.enrolled);
});

Deno.test('fetchUserMfaState — walang factor → ok pero hindi enrolled', async () => {
  const state = await fetchUserMfaState(fakeDb({ factors: [] }), 'user-1');
  assert(state.ok);
  assert(!state.enrolled);
});

Deno.test('fetchUserMfaState — infra error → ok=false (fail-closed)', async () => {
  const state = await fetchUserMfaState(
    fakeDb({ onlyGetUserById: true, getUserByIdFails: true }),
    'user-1',
  );
  assert(!state.ok, 'Hindi dapat mag-claim ng \"walang 2FA\" kapag hindi matukoy');
  assert(!state.enrolled);
});

Deno.test('fetchUserMfaState — walang userId → ok=false', async () => {
  const state = await fetchUserMfaState(fakeDb({}), '');
  assert(!state.ok);
});

Deno.test('mfaRequiredForSensitiveOp — aal2 kung naka-enroll lang', () => {
  // Naka-2FA: kailangan ang authenticator code.
  assert(mfaRequiredForSensitiveOp('aal1', true));
  assert(mfaRequiredForSensitiveOp(null, true));
  assert(!mfaRequiredForSensitiveOp('aal2', true));

  // WALANG 2FA: hindi hinaharang (walang paraan para umabot sa aal2).
  assert(!mfaRequiredForSensitiveOp('aal1', false));
});

Deno.test('requireMfaIfEnrolled — aal2 ay lumalampas (walang extra call)', async () => {
  let listed = 0;
  const db = fakeDb({ factors: [] });
  db.auth.admin.mfa.listFactors = ((_p: { userId: string }) => {
    listed += 1;
    return Promise.resolve({ data: { factors: [] }, error: null });
  }) as unknown as typeof db.auth.admin.mfa.listFactors;
  const result = await requireMfaIfEnrolled(db, { id: 'user-1', aal: 'aal2' });
  assertStrictEquals(result, null);
  assertEquals(listed, 0);
});

Deno.test('requireMfaIfEnrolled — aal1 + naka-enroll → 403 MFA_REQUIRED', async () => {
  const db = fakeDb({
    factors: [{ id: 'f1', factor_type: 'totp', status: 'verified' }],
  });
  const result = await requireMfaIfEnrolled(db, { id: 'user-1', aal: 'aal1' });
  assert(result instanceof Response);
  assertEquals(result.status, 403);
  const body = await result.json();
  assertEquals(body.error.code, 'MFA_REQUIRED');
  assertEquals(body.error.current_level, 'aal1');
  assertEquals(body.error.next_level, 'aal2');
});

Deno.test('requireMfaIfEnrolled — aal1 na WALANG 2FA → pinapayagan', async () => {
  const db = fakeDb({ factors: [{ id: 'f1', factor_type: 'totp', status: 'unverified' }] });
  const result = await requireMfaIfEnrolled(db, { id: 'user-1', aal: 'aal1' });
  assertStrictEquals(result, null, 'Hindi pa naka-enroll → walang aal2 na kailangan');
});

Deno.test('requireMfaIfEnrolled — hindi matukoy ang state → 503 (fail-closed)', async () => {
  const db = fakeDb({ onlyGetUserById: true, getUserByIdFails: true });
  const result = await requireMfaIfEnrolled(db, { id: 'user-1', aal: 'aal1' });
  assert(result instanceof Response);
  assertEquals(result.status, 503);
  const body = await result.json();
  assertEquals(body.error.code, 'MFA_CHECK_FAILED');
});

Deno.test('requireMfaIfEnrolled — walang aal claim sa token = aal1', async () => {
  const db = fakeDb({
    factors: [{ id: 'f1', factor_type: 'totp', status: 'verified' }],
  });
  const result = await requireMfaIfEnrolled(db, { id: 'user-1' });
  assert(result instanceof Response);
  assertEquals(result.status, 403);
});
