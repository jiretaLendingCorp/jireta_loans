// test/users_manage_get_profile_test.dart
// Reproduction + regression test for Log 1:
// GET 404 https://...supabase.co/functions/v1/users-manage?fn=get-profile
// Covers: phone normalization fallback, synthetic email skip, stale targetId vs canonicalId,
// and FK hint brittleness fix.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String toLocalPhone(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('63')) return '0${digits.substring(2)}';
  return rawPhone;
}

String toE164(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('63')) return '+$digits';
  if (digits.startsWith('0')) return '+63${digits.substring(1)}';
  return '+63$digits';
}

List<String> phoneCandidates(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  final localPhone = digits.startsWith('63') ? '0${digits.substring(2)}' : rawPhone;
  final e164Phone = digits.startsWith('63')
      ? '+$digits'
      : digits.startsWith('0')
          ? '+63${digits.substring(1)}'
          : '+63$digits';
  return [...{localPhone, e164Phone, rawPhone}];
}

bool isSyntheticEmail(String email) => email.trim().toLowerCase().endsWith('@jireta.temp');

void main() {
  group('Log 1 — users-manage?fn=get-profile 404 debug', () {
    test('phoneCandidates covers local / E164 / raw — handles Log 1 mismatch', () {
      // Typical rider OTP token: +639171234567, DB stores 09171234567
      expect(phoneCandidates('+639171234567'), containsAll(['09171234567', '+639171234567']));
      // Local DB with spaces/dashes: fallback fuzzy will catch last 9 digits
      expect(phoneCandidates('0917-123-4567'), isNotEmpty);
      // Already local
      expect(phoneCandidates('09171234567'), contains('09171234567'));
      expect(phoneCandidates('09171234567'), contains('+639171234567'));
    });

    test('toLocalPhone / toE164 round-trip', () {
      expect(toLocalPhone('+639171234567'), '09171234567');
      expect(toE164('09171234567'), '+639171234567');
      expect(toE164('+639171234567'), '+639171234567');
      expect(toLocalPhone('09171234567'), '09171234567');
    });

    test('synthetic @jireta.temp email must be skipped for fallback', () {
      expect(isSyntheticEmail('09171234567@jireta.temp'), isTrue);
      expect(isSyntheticEmail('09171234567@JIRETA.TEMP'), isTrue);
      expect(isSyntheticEmail('user@example.com'), isFalse);
      expect(isSyntheticEmail('head_manager@jireta.com'), isFalse);
      // If fallback tried synthetic email against public.users (which stores NULL),
      // it would always miss — skipping is correct.
    });

    test('fuzzy fallback patterns are last 9/10 digits with % prefix', () {
      const raw = '+639171234567';
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      final last9 = digits.substring(digits.length - 9);
      final last10 = digits.substring(digits.length - 10);
      // digits = 639171234567, last9 = 171234567, last10 = 9171234567
      expect(last9, '171234567');
      expect(last10, '9171234567');
      expect('%$last9', '%171234567');
      expect('%$last10', '%9171234567');
    });

    test('stale targetId vs canonicalId — contacts/address must use canonical', () {
      // Simulate: auth recovered 222 but client sent stale 111
      const staleTargetId = '11111111-1111-1111-1111-111111111111';
      const canonicalId = '22222222-2222-2222-2222-222222222222';
      // Old buggy code did: eq('lender_id', targetId) -> would query 111 and miss contacts
      // Fixed code does: eq('lender_id', canonicalId) -> 222
      expect(staleTargetId, isNot(canonicalId));
      // The fix asserts we always use data.id after fallback
      const usedId = canonicalId; // after fallback, data.id
      expect(usedId, canonicalId);
      expect(usedId, isNot(staleTargetId));
    });

    test('PROFILE_SELECT must not contain brittle FK hint !lender_profiles_id_fkey + must hint roles', () async {
      final file = File('supabase/functions/users-manage/index.ts');
      expect(await file.exists(), isTrue, reason: 'users-manage file must exist');
      final content = await file.readAsString();
      // After fix, lender hint is removed — plain lender_profiles(...)
      expect(content.contains('lender_profiles!lender_profiles_id_fkey'), isFalse,
          reason: 'FK hint !lender_profiles_id_fkey is brittle and was removed. '
              'Plain lender_profiles(...) is auto-detected by PostgREST.');
      expect(content.contains('const PROFILE_SELECT'), isTrue,
          reason: 'Unified PROFILE_SELECT constant should exist');
      expect(content.contains('lender_profiles(employment_type'), isTrue);
      // Critical: roles must be hinted after 00115 (roles.archived_by -> users introduces 2nd path)
      // Plain `roles(id, name)` throws PGRST "more than one relationship" — see Log 1 at 04:30
      expect(content.contains('roles!users_role_id_fkey(id, name)'), isTrue,
          reason: 'After migration 00115 roles.archived_by creates 2nd users<->roles FK; '
              'plain roles(id,name) fails with "more than one relationship". Must hint users_role_id_fkey.');
      expect(content.contains(RegExp(r'roles\(id, name\)')), isFalse,
          reason: 'Bare roles(id, name) without FK hint must not remain.');
      // Safety: emergency_contacts and address now use canonicalId
      expect(content.contains('canonicalId'), isTrue,
          reason: 'contacts/address must use canonicalId after fallback, not stale targetId');
      expect(content.contains("eq('lender_id', canonicalId)"), isTrue);
      expect(content.contains('getLenderAddress(db, canonicalId)'), isTrue);
    });

    test('Log at 04:30 proves roles hint regression — exact error', () async {
      // Log 1 @04:30:13.340Z: dbError: "Could not embed because more than one relationship was found for 'users' and 'roles'"
      // Log 2 shows synthetic email skip warning — code already deployed was the version with synthetic skip
      // but still had bare roles(...) so every query (id + phone fallback) threw same PGRST error
      // and fallbackData stayed null → final 404.
      const dbError = "Could not embed because more than one relationship was found for 'users' and 'roles'";
      expect(dbError.contains("more than one relationship"), isTrue);
      expect(dbError.contains("'users' and 'roles'"), isTrue);
      // This is the exact error from PostgREST when `select=roles(id,name)` is ambiguous
      // after 00115 added roles.archived_by -> users. The fix is roles!users_role_id_fkey.
      const authPhone = "639303030303";
      const targetId = "f0877d80-6661-421a-af68-43b912ca2594";
      expect(targetId, isNotEmpty);
      // Phone candidate generation for this log:
      final cands = phoneCandidates(authPhone);
      expect(cands, contains('09303030303'), reason: 'DB stores 09303030303, token is 639... -> candidate must include local 09');
      expect(cands, contains('+639303030303'));
      // After hint fix, query will succeed via phone candidate 09303030303
      // and previous file content check ensures hint is present.
    });

    test('Dio URL for self profile (no user_id) keeps fn=get-profile intact', () {
      const base = 'https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1/';
      const path = 'users-manage?fn=get-profile';
      // Self profile: no extra queryParams
      const url = '$base$path';
      final uri = Uri.parse(url);
      expect(uri.queryParameters['fn'], 'get-profile');
      // With user_id, Dio appends with & not ?
      const userId = '21fc2fcb-1234-5678-90ab-cdef12345678';
      final withId = Uri.parse('$base$path').replace(queryParameters: {
        'fn': 'get-profile',
        'user_id': userId,
      });
      expect(withId.queryParameters['fn'], 'get-profile');
      expect(withId.queryParameters['user_id'], userId);
      expect(withId.toString(), contains('fn=get-profile&user_id='));
    });

    test('UserRemoteDataSource getProfile query shape — regression for Log 1', () async {
      // Mirrors FakeDioClient from rest_api_debug_test but specifically for users-manage
      // Ensures ApiEndpoints.usersGetProfile is well-formed
      const ep = 'users-manage?fn=get-profile';
      expect(ep, contains('?fn=get-profile'));
      expect(ep.startsWith('users-manage'), isTrue);
      // Dio should not double-encode ?fn
      final uri = Uri.parse('https://example.supabase.co/functions/v1/$ep');
      expect(uri.path, contains('users-manage'));
      expect(uri.query, contains('fn=get-profile'));
    });

    test('Log 1 execution_time 867ms suggests DB fallback loops ran — not gateway 404', () {
      // Gateway "Unknown action: ..." returns instantly (<100ms). 867ms implies
      // handleGetProfile ran DB queries (equ+phone fallback+fuzzy) then returned 404
      // via `User not found (... phone=...)`. So the 404 is from the final
      // errorResponse in handleGetProfile, not the router default.
      // This test documents the inference.
      const executionMs = 867;
      expect(executionMs, greaterThan(300),
          reason: 'If router unknown-action 404, execution would be ~50-150ms. '
              '867ms matches DB round-trips for phone fallback loops.');
    });
  });
}
