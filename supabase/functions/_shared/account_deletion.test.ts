// supabase/functions/_shared/account_deletion.test.ts
// Walang network/DB: pure policy helpers lang ang sinusuri dito.
import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  buildDeletionReference,
  cancellableLoanStatuses,
  hashDeletionIdentifier,
  isDeletionReference,
  maskIdentifier,
  normalizeDeletionIdentifier,
  outstandingLoanStatuses,
  sanitizeDeletionReason,
  summarizeDeletionResult,
} from './account_deletion.ts';

Deno.test('outstandingLoanStatuses: active/overdue lang ang humaharang', () => {
  assertEquals(
    outstandingLoanStatuses([
      { status: 'completed' },
      { status: 'pending' },
      { status: 'overdue' },
      { status: 'ACTIVE' },
      { status: 'rejected' },
    ]),
    ['active', 'overdue'],
  );
});

Deno.test('cancellableLoanStatuses: walang perang lumabas, hindi kasama ang overdue', () => {
  assertEquals(
    cancellableLoanStatuses([
      { status: 'pending' },
      { status: 'approved' },
      { status: 'under_review' },
      { status: 'pending' },
      { status: 'completed' },
      { status: 'active' },
      { status: 'overdue' },
      { status: 'rejected' },
      { status: 'cancelled' },
    ]),
    ['approved', 'pending', 'under_review'],
  );
});

Deno.test('normalizeDeletionIdentifier: lahat ng PH mobile forms', () => {
  for (const input of ['09171234567', '+639171234567', '639171234567', '9171234567']) {
    assertEquals(normalizeDeletionIdentifier(input), {
      type: 'phone',
      value: '09171234567',
      e164: '+639171234567',
    });
  }
});

Deno.test('normalizeDeletionIdentifier: tinatanggihan ang landline / blangko', () => {
  assertEquals(normalizeDeletionIdentifier('0281234567'), null);
  assertEquals(normalizeDeletionIdentifier(''), null);
  assertEquals(normalizeDeletionIdentifier('not-an-email'), null);
  assertEquals(normalizeDeletionIdentifier('a@b'), null);
  assertEquals(normalizeDeletionIdentifier(12345), null);
});

Deno.test('normalizeDeletionIdentifier: lowercase email', () => {
  assertEquals(normalizeDeletionIdentifier('  Juan.DelaCruz@Gmail.com '), {
    type: 'email',
    value: 'juan.delacruz@gmail.com',
  });
});

Deno.test('maskIdentifier: hindi ibinabalik ang buong PII', () => {
  assertEquals(maskIdentifier('phone', '09171234567'), '09*****4567');
  assertEquals(maskIdentifier('email', 'juan.delacruz@gmail.com'), 'ju**@gmail.com');
  assert(!maskIdentifier('phone', '09171234567').includes('123'));
});

Deno.test('buildDeletionReference: stable format', () => {
  assertEquals(
    buildDeletionReference(new Uint8Array([0x01, 0x02, 0x03, 0x04, 0x05])),
    'DEL-0102030405',
  );
  assert(isDeletionReference(buildDeletionReference()));
  assert(!isDeletionReference('DEL-xyz'));
  assert(!isDeletionReference('del-0102030405'));
});

Deno.test('sanitizeDeletionReason: control chars, trim, 500 cap', () => {
  assertEquals(sanitizeDeletionReason('  I\u0000 moved\u001f abroad  '), 'I moved abroad');
  assertEquals(sanitizeDeletionReason('x'.repeat(600)).length, 500);
  assertEquals(sanitizeDeletionReason(null), '');
});

Deno.test('hashDeletionIdentifier: deterministic at 64 hex chars', async () => {
  const a = await hashDeletionIdentifier('pepper', '09171234567');
  const b = await hashDeletionIdentifier('pepper', '09171234567');
  const c = await hashDeletionIdentifier('other', '09171234567');
  assertEquals(a, b);
  assert(a !== c);
  assert(/^[0-9a-f]{64}$/.test(a));
});

Deno.test('summarizeDeletionResult: safe defaults', () => {
  assertEquals(summarizeDeletionResult(null), {
    anonymized_email: '',
    cancelled_loans: 0,
    removed: [],
    retained: [],
  });
  assertEquals(
    summarizeDeletionResult({
      anonymized_email: 'deleted+x@deleted.invalid',
      cancelled_loans: 2,
      removed: ['notifications'],
      retained: ['loans', 123],
    }),
    {
      anonymized_email: 'deleted+x@deleted.invalid',
      cancelled_loans: 2,
      removed: ['notifications'],
      retained: ['loans'],
    },
  );
});
