// test/lender_term_default_pause_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Guards para sa escalation rule:
//   "Kapag IKAWALANG loan ng lender na natapos ang term na may natitirang
//    utang (hindi nakabayad base sa term na kinuha niya), i-pause ang
//    account at harangin siya sa app gamit ang AccountPausedOverlay."
//
// Mga tinatakpan:
//   • 00152 — 2nd term default → users.account_status = 'paused'
//   • 00163 — term default kapag tapos na ang huling due date at kulang ang
//             verified payments bago/sa araw ng term end (kahit magbayad
//             later, default pa rin)
//   • 00185 — active/overdue/completed lang ang binibilang; HINDI kasama ang
//             rejected/pending/cancelled applications na may schedule rows
//             mula sa application time (bug na nagdulot ng maling pause)
//   • app.dart — global blocking modal para sa paused na lender
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

/// Mirror ng `loan_was_term_default()` (00163 + 00185).
///
/// `termEnd` = huling due date, `today` = (now_manila())::date.
/// `paidByTermEnd` = verified payments na binayad bago/sa araw ng term end.
bool wasTermDefault({
  required String status,
  required DateTime termEnd,
  required double paidByTermEnd,
  required double expected,
  required DateTime today,
}) {
  return const {'active', 'overdue', 'completed'}.contains(status) &&
      termEnd.isBefore(today) &&
      paidByTermEnd < expected;
}

/// Mirror ng escalation: pangalawa (o higit) → paused.
bool shouldPause(int termDefaults) => termDefaults >= 2;

void main() {
  final today = DateTime(2026, 10, 19);

  group('Term default — base sa term na kinuha ng lender', () {
    test('tapos na ang term at may utang → default', () {
      expect(
        wasTermDefault(
          status: 'active',
          termEnd: DateTime(2026, 10, 1),
          paidByTermEnd: 2000,
          expected: 3600,
          today: today,
        ),
        isTrue,
      );
    });

    test('hindi pa tapos ang term → HINDI default (kahit overdue mid-term)',
        () {
      expect(
        wasTermDefault(
          status: 'overdue',
          termEnd: DateTime(2026, 10, 25),
          paidByTermEnd: 0,
          expected: 3600,
          today: today,
        ),
        isFalse,
      );
    });

    test('bayad na bago matapos ang term → HINDI default', () {
      expect(
        wasTermDefault(
          status: 'completed',
          termEnd: DateTime(2026, 10, 1),
          paidByTermEnd: 3600,
          expected: 3600,
          today: today,
        ),
        isFalse,
      );
    });

    test('nagbayad LATER pero kulang noong term end → default pa rin', () {
      // Ang `paidByTermEnd` ay para lang sa bayad bago/sa term end.
      expect(
        wasTermDefault(
          status: 'overdue',
          termEnd: DateTime(2026, 10, 1),
          paidByTermEnd: 0,
          expected: 3600,
          today: today,
        ),
        isTrue,
      );
    });

    test('unreleased applications → HINDI default kahit may schedule rows',
        () {
      for (final status in ['pending', 'approved', 'rejected', 'cancelled']) {
        expect(
          wasTermDefault(
            status: status,
            termEnd: DateTime(2026, 9, 1),
            paidByTermEnd: 0,
            expected: 3600,
            today: today,
          ),
          isFalse,
          reason: '$status ay hindi dapat mag-count as term default (00185)',
        );
      }
    });
  });

  group('Escalation — pangalawa lang ang nagpa-pause', () {
    test('isang term default → active pa rin', () {
      expect(shouldPause(1), isFalse);
    });

    test('pangalawang term default → paused', () {
      expect(shouldPause(2), isTrue);
      expect(shouldPause(3), isTrue);
    });

    test('dalawang rejected application ay hindi umabot sa pause', () {
      final defaults = [
        wasTermDefault(
          status: 'rejected',
          termEnd: DateTime(2026, 8, 1),
          paidByTermEnd: 0,
          expected: 3600,
          today: today,
        ),
        wasTermDefault(
          status: 'pending',
          termEnd: DateTime(2026, 8, 15),
          paidByTermEnd: 0,
          expected: 3600,
          today: today,
        ),
      ].where((e) => e).length;
      expect(shouldPause(defaults), isFalse);
    });
  });

  group('Source guards', () {
    test('00152: 2nd term default → account_status = paused', () {
      final src =
          _squash(_read('supabase/migrations/00152_pause_on_second_term_default.sql'));
      expect(src, contains('term_default_count'));
      expect(src, contains('IF v_defaults IS NOT NULL AND v_defaults >= 2'));
      expect(src, contains("SET account_status = 'paused'"));
    });

    test('00163: term-end + paid-by-term-end ang basehan', () {
      final src =
          _squash(_read('supabase/migrations/00163_recount_lender_term_defaults.sql'));
      expect(src, contains('loan_was_term_default'));
      expect(src, contains('term_end < (now_manila())::date'));
      expect(src, contains('paid_by_term_end'));
    });

    test('00185: active/overdue/completed lang ang binibilang', () {
      final src = _squash(
          _read('supabase/migrations/00185_term_default_exclude_unreleased_loans.sql'));
      expect(
        src,
        contains("AND l.status IN ('active', 'overdue', 'completed')"),
        reason: 'hindi dapat mabilang ang rejected/pending applications',
      );
      expect(src, contains('recount_lender_term_defaults'));
    });

    test('app.dart: global AccountPausedOverlay para harangin ang lender', () {
      final src = _read('lib/app.dart');
      expect(src, contains('AccountPausedOverlay'));
      expect(src, contains('builder:'));
    });

    test('overlay: lender-only, hindi dismissible, logout lang ang labasan',
        () {
      final src = _read(
          'lib/presentation/shared/widgets/account_paused_overlay.dart');
      expect(src, contains('RoleConstants.lender'));
      expect(src, contains('dismissible: false'));
      expect(src, contains('Contact Our Services'));
      expect(src, contains('Log Out'));
    });
  });
}
