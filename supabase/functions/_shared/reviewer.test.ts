// supabase/functions/_shared/reviewer.test.ts
// Security policy tests para sa Google Play reviewer access. Walang network:
// ang configuration ay galing sa isang in-memory env map at ang guard ay
// sinusuri sa response lamang.
import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  constantTimeEqual,
  isReviewerAuthUser,
  isReviewerPhone,
  maskedReviewerPhone,
  parseReviewerConfig,
  requireNonReviewer,
  reviewerAccountFor,
  reviewerLoginFailedResponse,
  reviewerPasswordMatches,
} from './reviewer.ts';

const LENDER_PASSWORD = 'rev-lender-pass-2026';
const RIDER_PASSWORD = 'rev-rider-pass-2026';

function envWith(overrides: Record<string, string | undefined> = {}) {
  const values: Record<string, string | undefined> = {
    REVIEWER_LOGIN_ENABLED: 'true',
    REVIEWER_LENDER_PHONE: '09000000101',
    REVIEWER_LENDER_PASSWORD: LENDER_PASSWORD,
    REVIEWER_RIDER_PHONE: '09000000102',
    REVIEWER_RIDER_PASSWORD: RIDER_PASSWORD,
    ...overrides,
  };
  return (name: string) => values[name];
}

Deno.test('reviewer login is DISABLED unless the env flag is explicitly true', () => {
  assertEquals(parseReviewerConfig(envWith()).enabled, true);

  for (const off of ['', 'false', '0', 'yes', 'TRUE ']) {
    const config = parseReviewerConfig(
      envWith({ REVIEWER_LOGIN_ENABLED: off }),
    );
    // Tanging exact na "true" (trimmed, case-insensitive) ang nagpapagana.
    assertEquals(
      config.enabled,
      off.trim().toLowerCase() === 'true',
      `flag=${JSON.stringify(off)}`,
    );
  }
});

Deno.test('missing or short secrets produce no account (fail closed)', () => {
  assertEquals(
    parseReviewerConfig(
      envWith({ REVIEWER_LENDER_PASSWORD: undefined }),
    ).accounts.length,
    1,
  );
  assertEquals(
    parseReviewerConfig(envWith({ REVIEWER_LENDER_PASSWORD: 'short' }))
      .accounts.length,
    1,
  );
  assertEquals(
    parseReviewerConfig(
      envWith({ REVIEWER_LENDER_PHONE: undefined, REVIEWER_RIDER_PHONE: undefined }),
    ).accounts.length,
    0,
  );
  assertEquals(
    parseReviewerConfig(
      envWith({
        REVIEWER_LENDER_PASSWORD: undefined,
        REVIEWER_RIDER_PASSWORD: undefined,
      }),
    ).enabled,
    false,
  );
});

Deno.test('phones are normalized and duplicates cannot be reused for both roles', () => {
  const config = parseReviewerConfig(
    envWith({
      REVIEWER_LENDER_PHONE: '+63 900 000 0101',
      REVIEWER_RIDER_PHONE: '09000000101',
    }),
  );
  assertEquals(config.accounts.length, 1);
  assertEquals(config.accounts[0].role, 'lender');
  assertEquals(config.accounts[0].phone, '09000000101');
});

Deno.test('only allowlisted reviewer phones resolve to an account', () => {
  const config = parseReviewerConfig(envWith());

  assertEquals(reviewerAccountFor(config, '09000000101')?.role, 'lender');
  assertEquals(reviewerAccountFor(config, '+639000000102')?.role, 'rider');
  assertEquals(reviewerAccountFor(config, '09171234567'), null);
  assertEquals(reviewerAccountFor(config, ''), null);
  assertEquals(isReviewerPhone(config, '09171234567'), false);
});

Deno.test('reviewer password must match the server secret exactly', () => {
  const config = parseReviewerConfig(envWith());
  const account = reviewerAccountFor(config, '09000000101');

  assertEquals(reviewerPasswordMatches(account, LENDER_PASSWORD), true);
  assertEquals(reviewerPasswordMatches(account, ` ${LENDER_PASSWORD} `), true);
  assertEquals(reviewerPasswordMatches(account, RIDER_PASSWORD), false);
  assertEquals(reviewerPasswordMatches(account, ''), false);
  assertEquals(reviewerPasswordMatches(null, LENDER_PASSWORD), false);
});

Deno.test('constant-time comparison still compares content and length', () => {
  assertEquals(constantTimeEqual('abc', 'abc'), true);
  assertEquals(constantTimeEqual('abc', 'abd'), false);
  assertEquals(constantTimeEqual('abc', 'abcd'), false);
  assertEquals(constantTimeEqual('', ''), true);
  assertEquals(constantTimeEqual('', 'x'), false);
});

Deno.test('reviewer flag comes from the server-side session, not the client', () => {
  assertEquals(isReviewerAuthUser({ isReviewer: true }), true);
  assertEquals(isReviewerAuthUser({ isReviewer: false }), false);
  assertEquals(isReviewerAuthUser(null), false);
  assertEquals(isReviewerAuthUser(undefined), false);
});

Deno.test('financial guard blocks reviewer sessions with 403 REVIEWER_NOT_ALLOWED', async () => {
  const normal = requireNonReviewer({
    id: 'user-1',
    role: 'lender',
    sessionIdentifier: 's1',
    isReviewer: false,
  });
  assertEquals(normal, null);

  const blocked = requireNonReviewer({
    id: 'reviewer-1',
    role: 'lender',
    sessionIdentifier: 's1',
    isReviewer: true,
  });
  assertEquals(blocked instanceof Response, true);
  assertEquals(blocked!.status, 403);
  const body = await blocked!.json();
  assertEquals(body.error.code, 'REVIEWER_NOT_ALLOWED');
});

Deno.test('a failed reviewer login never reveals whether the account exists', async () => {
  const response = reviewerLoginFailedResponse();
  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.error.code, 'REVIEWER_LOGIN_FAILED');
  assertEquals(body.error.message, 'Invalid reviewer credentials.');
});

Deno.test('reviewer phones are masked in logs', () => {
  assertEquals(maskedReviewerPhone('09000000101'), '0900****01');
  assertEquals(maskedReviewerPhone('+639000000102'), '0900****02');
  assertEquals(maskedReviewerPhone('not-a-phone'), 'invalid');
});
