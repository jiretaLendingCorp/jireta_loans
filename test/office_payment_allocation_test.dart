// test/office_payment_allocation_test.dart
//
// BUSINESS RULE: kapag nag-record ng bayad para sa isang PARTIKULAR na
// installment (hal. ang "Pay in Office" button sa isang row ng Payment
// Schedule), ang installment na IYON ang unang binabayaran — dapat maging
// `paid` agad ang row na pinindot.
//
// Dati: `allocatePayment(db, loanId, amount)` ay laging oldest-first, kaya ang
// pinindot na row (hal. #3) ay nananatiling `pending` habang ang pera ay
// napupunta sa #1 — kahit matagumpay na na-record ang bayad.
//
// Sinasalamin dito ang allocation rule ng
// `supabase/functions/_shared/loan_financials.ts`, at tinitiyak na ipinapasa
// ng `payments-manage?fn=record-office` ang pinindot na installment
// (`loan_schedule_id`) at na verified agad ang naitalang office payment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef Sched = ({String id, double due, double paid});
typedef Alloc = ({String id, double amount});

/// Mirror ng `allocatePayment`: `preferScheduleId` muna, tapos ang natitirang
/// unpaid sa installment-number order (oldest first).
List<Alloc> allocate(
  List<Sched> schedules,
  double amount, {
  String? preferScheduleId,
}) {
  final ordered = preferScheduleId == null
      ? schedules
      : [
          ...schedules.where((s) => s.id == preferScheduleId),
          ...schedules.where((s) => s.id != preferScheduleId),
        ];
  final out = <Alloc>[];
  var left = amount;
  for (final s in ordered) {
    if (left <= 0) break;
    final remaining = s.due - s.paid;
    if (remaining <= 0) continue;
    final applied = remaining < left ? remaining : left;
    out.add((id: s.id, amount: applied));
    left -= applied;
  }
  return out;
}

/// Read a repo file and normalize line endings (Windows checkouts use CRLF).
String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  const fresh = <Sched>[
    (id: 's1', due: 600, paid: 0),
    (id: 's2', due: 600, paid: 0),
    (id: 's3', due: 600, paid: 0),
  ];

  group('Allocation rule — ang pinindot na installment ang unang bayad', () {
    test('pinindot ang #3 habang unpaid pa ang #1-#2 → #3 ang PAID', () {
      final a = allocate(fresh, 600, preferScheduleId: 's3');
      expect(a.length, 1);
      expect(a.single.id, 's3');
      expect(a.single.amount, 600);
    });

    test('walang prefer → oldest-first pa rin (koleksyon / GCash flow)', () {
      final a = allocate(fresh, 600);
      expect(a.single.id, 's1');
      expect(a.single.amount, 600);
    });

    test('sobrang halaga → pinindot muna, tapos pinaka-lumang unpaid', () {
      final a = allocate(fresh, 1800, preferScheduleId: 's2');
      expect(a.map((x) => x.id).toList(), ['s2', 's1', 's3']);
    });

    test('bayad nang installment → hindi na kasama (imposible ang doble)', () {
      final rows = <Sched>[
        (id: 's1', due: 600, paid: 600),
        (id: 's2', due: 600, paid: 300),
      ];
      final a = allocate(rows, 300, preferScheduleId: 's1');
      expect(a.single.id, 's2');
      expect(a.single.amount, 300);
    });
  });

  group('Backend wiring — naka-wire ang pinindot na installment', () {
    test('allocatePayment ay may `preferScheduleId` at inuuna ito', () {
      final src =
          readNormalized('supabase/functions/_shared/loan_financials.ts');
      expect(src, contains('preferScheduleId?: string'));
      expect(src, contains('s.id === preferScheduleId'));
      expect(src, contains('...all.filter((s) => s.id !== preferScheduleId)'));
    });

    test('record-office ay ipinapasa ang `loan_schedule_id`', () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      expect(
          src,
          contains('allocatePayment(\n'
              '    db,\n'
              '    loan_id,\n'
              '    Number(amount),\n'
              '    loan_schedule_id,'));
    });

    test('verified agad ang office payment → PAID ang schedule row', () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      expect(src, contains("payment_method: 'office_cash'"));
      expect(src, contains("status: 'verified'"));
      // KRITIKAL: ang `payments.status_id` ay may DEFAULT (pending) at ang
      // `sync_payments_lookup_ids` trigger ay nag-o-overwrite ng `status` mula
      // sa `status_id` kapag `status_id IS DISTINCT FROM OLD.status_id` (NULL
      // sa INSERT). Kung walang `status_id: null`,
      // ang `verified` ay nagiging `pending` → `amount_paid = 0` → Pending pa
      // rin ang installment kahit naka-record na ang pera.
      expect(src, contains('status_id: null'));
    });

    test('isinasara ang bukas pang request/rider assignment kapag buo ang bayad',
        () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      // Tinitingnan ang LAHAT ng bukas pang status (requested … pending_approval)
      // para sa mismong installment na nabayaran...
      expect(
          src,
          contains("['requested', 'assigned', 'accepted', 'in_progress', "
              "'pending_approval']"));
      expect(src, contains("select('id, rider_id, assigned_by, loan_schedule_id')"));
      // ...at isa-isang isinasara.
      expect(src, contains(".update(patch).eq('id', id)"));
    });

    test('walang-rider na request → declined, HINDI completed (CHECK)', () {
      // CHECK constraint (00033_schema_audit_fixes.sql):
      //   status IN ('requested','declined') OR (rider_id IS NOT NULL AND assigned_by IS NOT NULL)
      // Kaya ang row na walang rider ay HINDI pwedeng maging 'completed' —
      // tahimik na nabibigo (Postgres 23514) ang update at mananatiling
      // Requested ang row sa Collections kahit PAID na ang installment.
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      expect(src, contains('a.rider_id && a.assigned_by'));
      expect(
          src,
          contains("? { status: 'completed', completed_at: closedAt, "
              'amount_collected: a.collected }'));
      expect(src, contains("status: 'declined',"));
      expect(src, contains('response_at: closedAt,'));
      // Kapag 'completed', required ang completed_at (CHECK); ang 'declined'
      // ay wala sa OPEN_COLLECTION_STATUSES ng collections-view → nawawala sa
      // pending list ng Collections.
      expect(src, contains('completed_at: closedAt'));
    });

    test('ang notification sa lender ay nagsasabing SA OFFICE siya nagbayad',
        () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      // Hindi sapat na "Payment Recorded" — dapat malinaw sa lender na ang
      // channel ay office (hindi rider collection o GCash).
      expect(src, contains("title: 'Paid in Office'"));
      expect(src, contains('was recorded at the office.'));
      // Pareho pa ring type, kaya hindi nababago ang emoji/deep link ng app.
      expect(src, contains("type: 'payment_recorded'"));
    });

    test('ang request na pinindot ng staff ay natugunan kahit partial', () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      expect(src, contains('a.id !== assignment_id'));
      expect(src, contains('if (assignment_id && !toClose.has(assignment_id))'));
    });

    test('HINDI isinasara ang request kapag partial pa ang bayad', () {
      final src =
          readNormalized('supabase/functions/payments-manage/index.ts');
      expect(src, contains('if (collected < Number(s.amount_due)) continue;'));
    });
  });
}
