// test/email_verify_saves_email_test.dart
//
// "SA LENDER ROLE, SA FILL IN INFORMATION, HINDI NAG-SAVE ANG EMAIL SA DATABASE"
//
// ROOT CAUSE: ang link verification (`auth-email-verify?fn=confirm`) ay
// `users.email_verified_at` lang ang isinusulat — HINDI ang `users.email`. Ang
// tanging nag-i-save ng email ay ang app-side na `update-profile` na tawag, kaya
// kapag nabigo iyon (409 DUPLICATE / GoTrue email sync / stale auth row) ay NULL
// pa rin ang email sa database kahit "Successfully Verified" na ang link.
//
// Sunod-sunod pa: ang `?fn=status` ay `email: null` ang isinasagot, at ang
// `alreadyVerified()` ay LAGING false kapag NULL ang `users.email` — kaya ang
// muling pag-tap sa link (o ang auto-visit ng Gmail/Outlook scanner) ay
// nagsasabing "Link already used" kahit matagumpay ang verification.
//
// Ang mga test na ito ay nagbabantay sa server-side fix sa
// `supabase/functions/auth-email-verify/index.ts`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFn(String name) =>
    File('supabase/functions/$name/index.ts').readAsStringSync();

void main() {
  group('auth-email-verify?fn=confirm — dapat ma-save ang VERIFIED email', () {
    late String src;

    setUpAll(() {
      src = _readFn('auth-email-verify');
    });

    test('isinusulat ang users.email kasabay ng email_verified_at', () {
      expect(
        src.contains('update({ email: row.email, email_verified_at: nowIso })'),
        isTrue,
        reason: 'Ang confirm ay dapat mag-save ng VERIFIED email sa public.users, '
            'hindi lang email_verified_at — kung hindi ay "hindi nag-save ang '
            'email" kahit verified na.',
      );
    });

    test('hindi hinaharang ng duplicate email ang verification stamp', () {
      expect(
        src.contains("code === '23505'"),
        isTrue,
        reason: 'Kapag may ibang account nang gumagamit ng address (23505), '
            'i-stamp pa rin ang email_verified_at at ipaliwanag ito.',
      );
      expect(
        src.contains('update({ email_verified_at: nowIso })'),
        isTrue,
        reason: 'Kailangang may fallback na stamp kapag hindi maisulat ang email.',
      );
    });

    test('alreadyVerified ay hindi na umaasa sa users.email (NULL-safe)', () {
      expect(
        src.contains(
            "return stored === '' || stored === email.trim().toLowerCase();"),
        isTrue,
        reason: 'Kapag NULL pa ang users.email, verified pa rin dapat ang link '
            '(dating laging "Link already used" ang resulta).',
      );
    });
  });
}
